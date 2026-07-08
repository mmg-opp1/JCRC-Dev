# JSI-87 — Implementation Game Plan: Gift Acknowledgment Framework

> **Status:** PLAN — awaiting review; no build yet. Author: Jason Ott · Date: 2026-07-08.
> **Related:** `JSI-87_User_Story.md`, `JSI-87_StoryDictationNotes.MD`, `Examples/` (proven VF-print pattern).
> **Approach:** build the **framework** now (plug-and-play) with **placeholder templates**; the real
> letter content, scenario matrix, routing rules, and SLA policy are **client-pending** (MMG note).

---

## 1. Scope

**In scope (this story — the framework + placeholders):**
- Surface the **native NPSP acknowledgment fields** (`npsp__Acknowledgment_Status__c`,
  `npsp__Acknowledgment_Date__c`) on the gift record pages.
- **Single acknowledgment engine = ours.** Deactivate NPSP's native email-acknowledgment path (see §2/§5).
- **Printed-letter framework:** one reusable, parameterized **Visualforce page** + one **Lightning Out
  Aura app** that renders **any** letter **screen flow** and has a **Print** button.
- **Custom email path:** a flow that sends an acknowledgment **email** using our own **email templates**
  (not NPSP's engine), under the master routing flow's control.
- **Master routing flow:** configurable if/then rules → choose template + channel (print vs. email).
- **Placeholder templates** (screen-flow letters + email templates) for **major / recurring / in-kind /
  tribute** gifts (demo/test content; real content later).
- **Stamp on send:** setting status → **Acknowledged** and auto-stamping **Acknowledgment Date** when the
  user prints or the email sends.
- **Reports:** daily **"pending acknowledgment"** work queue + a **48-hour SLA aging** field & report.

**Out of scope / deferred (client-pending):**
- Final letter **content** and the full **scenario matrix** (board vs. regular, CITI vs. individual vs.
  Mastercard, long-time vs. new donor, per-fund/campaign text — DoD #3, #7).
- Final **routing rules** and **timing** policy (DoD #8) — the flow is built rule-driven but seeded with
  placeholders.
- Exact **48-hour SLA definition** (business days? from gift date or entry date? — DoD #6 policy).
- **Batch letter generation** mechanism (individual first; batch is a fork — see §2).

---

## 2. Decisions

**Settled (Jason, 2026-07-08):**
1. **Email path = custom flow-sent email** using our templates (NOT NPSP's native engine).
2. **Single engine:** NPSP's native email-acknowledgment path is driven by the managed **workflow rule
   `npsp__Opportunity Email Acknowledgment`** (fires on the Acknowledgment Status field → email alert with
   the `NPSP Opportunity Acknowledgment` template). **Verified: that rule is already `active=false`** in
   this org, so it isn't firing. Hardening: (a) keep the rule **inactive** (never activate — it's managed),
   and (b) **deactivate the two `Email Acknowledgment Now` / `Email Acknowledgment Not Sent` picklist
   values** so the native path can never be invoked and the status field stays clean (3 values). Not a
   trigger and not a scheduled batch — no TDTM change.
3. **VF architecture:** ONE reusable, **parameterized** VF page + ONE Lightning Out Aura app; a new
   template = just a new **screen flow** (flow API name passed as a parameter).
4. **Phase-1 breadth:** build **several placeholder templates** (major/recurring/in-kind/tribute) + a
   **master routing flow skeleton**, accepting rework when real content/rules land.
5. **Status/date = native NPSP fields** (`npsp__Acknowledgment_Status__c` / `_Date__c`), values
   **To Be Acknowledged / Acknowledged / Do Not Acknowledge**.
6. **Branded sender = `development@jcrcny.org`** — create an Org-Wide Email Address for it (Jason, Setup +
   email verification — OWEA isn't source-deployable). Domain/SPF validation later.
7. **Send modes (per rule):** **emails** support **two tiers — automated send** *and* **approval-gated
   send**; **all printed letters are approval-gated** (a human reviews, then prints). So every acknowledgment
   is either *auto-email* or *approval-gated* (email or print). Design needs an **approval gate** concept.
8. **Individual only** (no batch this phase). Users work from the **"pending acknowledgment" report**,
   opening each gift to print/send — the report *is* the queue.
9. **SLA = 48 hours in BUSINESS days** (~2 business days; exclude weekends). Aging must count business days.
10. **Rules engine = CMDT `Acknowledgment_Rule__mdt`** (admin-reconfigurable). Each record = one rule: match
    fields (Record Type, Min/Max Amount, Fund, Campaign, Donor Type…) → outputs (`Template_Flow`,
    `Email_Template`, `Channel` = Email/Print, `Send_Mode` = Auto/Approval, `Priority`). The router flow
    loops the **active** rules, picks the **highest-priority match**, and acts. Rule changes = edit records
    in Setup, no flow edit/deploy. Phase-1 seeds placeholder rules (major/mid-email/small-auto/tribute/in-kind).

**Open (client only):**
- The template **scenario matrix** + letter **content** + which gifts are **auto-email vs. approval-gated
  vs. printed** (i.e., the actual `Acknowledgment_Rule__mdt` values). Framework ships with placeholders.

---

## 3. Verified org context (2026-07-08, `sf` CLI)

- **Native ack fields exist:** `npsp__Acknowledgment_Status__c` (Picklist), `npsp__Acknowledgment_Date__c`
  (Date) on Opportunity.
- **Ack Status picklist values (active):** To Be Acknowledged · Acknowledged · Do Not Acknowledge ·
  **Email Acknowledgment Now** · **Email Acknowledgment Not Sent** (last two drive NPSP's native email
  engine — to be deactivated).
- **Native email engine = managed WORKFLOW RULE** `npsp__Opportunity Email Acknowledgment` (→ email alert
  `npsp__Opportunity_Email_Acknowledgment`, template `NPSP Opportunity Acknowledgment`). **Currently
  `active=false`** (retrieved & verified) — so it is NOT firing. (A second managed rule `npsp__Opportunity
  Copy FMV to Amount` is also inactive.) The engine is a workflow rule, **not** a TDTM trigger and **not** a
  scheduled batch — the 12 Opportunity TDTM handlers are OCR/rollup/payment/recurring/matching/allocation
  only, and the 20 scheduled jobs are rollups/data-import/recurring/seasonal + JSI-90 rollover (no ack job).
- **8 gift record types:** Donation (NPSP_Default), Event Registration, Grant, In-Kind Gift, Major Gift,
  Matching Gift, Pledge, Securities Gift.
- **0 Org-Wide Email Addresses** (sender gap for the email path).
- **77 email templates** already in the org (reuse folder/structure conventions).
- **Gift record pages** (from prior stories): Donation, Major_Gift, Matching_Gift, In_Kind_Gift,
  Securities_Gift, Pledge, Grant, Event_Registration record pages exist.

---

## 4. Requirement → mechanism (DoD map)

| DoD | Mechanism |
|-----|-----------|
| #1 status field | **Native** `npsp__Acknowledgment_Status__c`; surface on gift pages; deactivate the 2 email values. |
| #2 templated letters, individual + batch | **Parameterized VF page + Lightning Out app + screen-flow letters** (individual). Batch deferred (§2 fork). |
| #3 template options (major/recurring/in-kind/tribute) | **Placeholder screen-flow letters + email templates** per type; content client-pending. |
| #4 date stamped when sent | Flow/VF action sets status=Acknowledged + stamps `npsp__Acknowledgment_Date__c`. |
| #5 daily pending report | Report: Opportunities where status = To Be Acknowledged (work queue). |
| #6 48h SLA in reports | New **aging formula field** (live `TODAY()` vs. gift date) + report bucket; policy client-pending. |
| #7 text by fund/campaign | Master routing flow selects template by criteria (incl. Fund/Campaign); content client-pending. |
| #8 timing by fund/campaign | Routing/timing rules in the master flow (rule-driven; values client-pending). |

---

## 5. Design

### 5.1 Fields (Opportunity)
- **Reuse native:** `npsp__Acknowledgment_Status__c`, `npsp__Acknowledgment_Date__c`.
- **New:** `Acknowledgment_Age_Business_Days__c` (Number **formula**, live) — **business days** since the
  gift date, excluding weekends (SLA basis = 48h business ≈ 2 business days, decision #9). Business-day
  count in a formula uses the standard weekday-math pattern (`CASE`/`MOD` on the date serial to subtract
  weekends); holidays excluded only if we add a holiday set (note as enhancement). Powers the SLA report.
- **New (routing/approval):** `Acknowledgment_Channel__c` (picklist: Print / Email / None),
  `Acknowledgment_Send_Mode__c` (picklist: Auto / Approval-Gated), and
  `Acknowledgment_Approved__c` (Checkbox) — the reviewer sets Approved for gated items; the auto path skips
  it (decision #7). Optionally `Acknowledgment_Template__c` (which template was used) for reporting.
- **New (audit):** `Acknowledgment_Sent_By__c` (Lookup User) + native date give a light audit trail.

### 5.2 Single-engine hardening (neutralize NPSP native path)
- The managed **workflow rule** `npsp__Opportunity Email Acknowledgment` is already **inactive** — leave it
  that way (never activate). It's the only thing that would send native acknowledgment emails.
- **Deactivate** the `Email Acknowledgment Now` / `Email Acknowledgment Not Sent` picklist values on
  `npsp__Acknowledgment_Status__c` (managed field — confirm metadata-deployable vs. Setup-UI edit by Jason)
  so the value that the rule keys off can't be selected. All stamping goes through our automation.

### 5.3 Print framework (Jason's proven pattern, generalized)
- **Lightning Out Aura app** `AckLetterOut` (`extends="ltng:outApp"`, `access="GLOBAL"`, depends on
  `lightning:flow`) — the `$Lightning.use("c:AckLetterOut")` host.
- **One Visualforce page** `AcknowledgmentLetter` (`standardController="Opportunity"`, `showHeader=false`,
  `sidebar=false`): print CSS (`@media print`, `.noprint`), a `window.print()` **Print** link, and a
  `lightning:flow` embedded via Lightning Out — **flow API name passed as a parameter** (URL param
  `flowName`, default to a router flow) + the Opportunity Id (`recordId`).
- **Screen-flow letters** (one per template): `Get` Opportunity + Contact/Household (name, address,
  greeting), build merge values, render the letter as **DisplayText** rich-HTML fields (per Examples).
  Placeholders: `Ack_Letter_MajorGift`, `Ack_Letter_Recurring`, `Ack_Letter_InKind`, `Ack_Letter_Tribute`,
  `Ack_Letter_General`.
- **Placement:** VF page on the gift record pages (a "Print Acknowledgment" tab/section) — Jason in App
  Builder; or a record action/button. On finish/print → stamp status + date.

### 5.4 Email path (custom)
- **Email templates** (Lightning email templates or classic) mirroring the letter placeholders:
  `Ack_Email_MajorGift`, `_Recurring`, `_InKind`, `_Tribute`, `_General`.
- **Flow** (autolaunched/screen) sends the email (`Send Email` action) from the branded **OWEA**, to the
  gift's primary contact, then sets status=Acknowledged + stamps date.

### 5.5 Master routing flow + approval gate
- `Opportunity_Acknowledgment_Router` — given a gift, resolves **template + channel + send-mode** from the
  rule set (§2 fork; CMDT `Acknowledgment_Rule__mdt` recommended). Then:
  - **Auto-email:** send the email immediately (email path §5.4), stamp Acknowledged + date.
  - **Approval-gated email:** set the gift to await approval (`Send_Mode=Approval`, `Approved=false`); when a
    reviewer sets **`Acknowledgment_Approved__c`=true**, a second flow sends the email + stamps.
  - **Print (always approval-gated, #7):** the gift surfaces in the report queue; a reviewer opens it,
    (optionally approves,) prints via the VF page, which stamps Acknowledged + date.
- **Approval mechanism:** phase-1 = a lightweight **`Acknowledgment_Approved__c` checkbox gate** set by a
  reviewer (simpler than a full Salesforce Approval Process; can upgrade later if the client wants routing/
  notifications). Rules seeded with placeholders.

---

## 6. Security & FLS
- New Opportunity fields → FLS on the **profiles** (JCRC org standard — Admin + 4 JCRC), via the additive
  minimal-profile technique. Formula/aging fields read-only.
- VF page + Aura app: grant access on the relevant profiles.
- Email send respects OWEA "allow all profiles" or per-profile setting.

---

## 7. Reporting
- **"Gifts Pending Acknowledgment"** (daily work queue — this is the queue users work from, decision #8):
  Opportunities, status = To Be Acknowledged, grouped by owner/gift officer; sort by gift date. (DoD #5)
- **"Acknowledgment SLA — Over 48 Business Hours"**: uses `Acknowledgment_Age_Business_Days__c` > 2,
  status = To Be Acknowledged. (DoD #6, business-days basis per #9)
- Folder: `Acknowledgment_Reports`.

---

## 8. Phased build plan
1. **Fields + hardening:** aging/channel fields (+ FLS); deactivate the 2 native email picklist values.
2. **Print framework:** Aura Lightning Out app + parameterized VF page + ONE screen-flow letter
   (General) end-to-end; verify print + status/date stamp.
3. **Templates:** remaining placeholder letters (major/recurring/in-kind/tribute) + email templates.
4. **Routing + email:** master router flow (+ optional `Acknowledgment_Rule__mdt`) + email-send flow +
   OWEA.
5. **Reports:** pending queue + SLA aging (folder + 2 reports).
6. **Pages:** place VF page + native fields on the gift record pages (Jason, App Builder).

---

## 9. Net-new metadata (anticipated)
- Fields (Opportunity): `Acknowledgment_Age_Business_Days__c` (formula), `Acknowledgment_Channel__c`,
  `Acknowledgment_Send_Mode__c`, `Acknowledgment_Approved__c`, `Acknowledgment_Template__c`,
  `Acknowledgment_Sent_By__c`.
- Aura app `AckLetterOut`; VF page `AcknowledgmentLetter`.
- Screen flows: 5 letter flows + `Opportunity_Acknowledgment_Router` + email-send flow + approval-send flow.
- Email templates: 5 placeholders.
- **CMDT `Acknowledgment_Rule__mdt`** (fields: Record_Type, Min_Amount, Max_Amount, Fund, Campaign,
  Donor_Type, Channel, Send_Mode, Template_Flow, Email_Template, Priority, Active) + seed placeholder records.
- Reports folder + 2 reports; profile FLS.
- **Jason/UI:** OWEA `development@jcrcny.org` (create + verify); deactivate the 2 native ack picklist values;
  place VF page + native fields on gift record pages.

---

## 10. Risks
- **Managed picklist values:** deactivating NPSP's 2 email values may not be metadata-deployable → Setup-UI
  edit (Jason). Verify.
- **Lightning Out** requires the Aura app + `apex:includeLightning`; test rendering + print CSS across
  record types.
- **Client-pending content** = the biggest risk to "done" — phase delivers a demoable framework, not final
  letters. Set expectations.
- **OWEA/deliverability** for the email path (SPF/DKIM) — client/IT.
- **Batch generation** unspecified — individual only this phase.

---

## 11. Sources
- Org verification via `sf` CLI (fields, picklist values, TDTM handlers, scheduled jobs, record types, OWEA).
- `JSI-87/Examples/` — Jason's VF-page + Lightning-Out + screen-flow print pattern.
- NPSP acknowledgment behavior (native fields + email engine) — **confirm any SF Help specifics with Jason
  if JS-gated**.
- Reuse `reference-sf-metadata-gotchas` (reports, FLS-on-profiles, flow gotchas, flexipage inserts).

---

## 12. Build Log

### 2026-07-08 — Phase 1, Steps 1–2 BUILT, DEPLOYED & VERIFIED
- **Fields (6 on Opportunity):** `Acknowledgment_Age_Business_Days__c` (Number formula),
  `Acknowledgment_Channel__c` (Email/Print/None), `Acknowledgment_Send_Mode__c` (Auto/Approval-Gated),
  `Acknowledgment_Approved__c` (Checkbox), `Acknowledgment_Template__c` (Text), `Acknowledgment_Sent_By__c`
  (Lookup→User, optional/SetNull). Deployed (6/6).
- **Business-day formula verified** via anon Apex: anchor `DATE(1900,1,8)` confirmed a Monday; Mon→Fri=4,
  Fri→Mon=1, week=5, Saturday caps at 5. Deployed field returns 2 for a Mon gift read on Wed (savepoint→rollback).
- **FLS** on Admin + 4 JCRC via additive minimal-profile deploy (6 fields; aging read-only). Verified; repo
  profiles synced (insert after last `</fieldPermissions>`).
- **CMDT `Acknowledgment_Rule__mdt`** (12 fields: Record_Type, Min/Max_Amount, Fund, Campaign, Donor_Type,
  Channel, Send_Mode, Template_Flow, Email_Template, Priority, Active) deployed (13/13). **5 placeholder
  rules** seeded + verified queryable (Major/In-Kind → Print/Approval; Donation <100 → Email/Auto; Donation
  ≥100 → Email/Approval; Default → Print/Approval). CMDT records carry `xmlns:xsd` (JSI-89 gotcha).
- **NOTE:** working tree has heavy pre-existing untracked `customMetadata` churn (NPSP Data Import mappings,
  Name_Parse_Token, rollups) — commit ONLY the 5 `Acknowledgment_Rule.*` records.
- **Print framework BUILT & DEPLOYED:** `AckLetterOut` Lightning Out Aura app + parameterized
  `AcknowledgmentLetter` VF page (renders any letter flow via `?flow=`, Print button) + **5 letter screen
  flows** (`Ack_General/MajorGift/Recurring/InKind/Tribute`) with placeholder content + merge fields; each
  **stamps** npsp Acknowledgment Status=Acknowledged + Date + Sent By on Finish. Field refs validated on
  deploy. **Visual render + print = browser check (Jason).**
- **Router BUILT, DEPLOYED & VERIFIED:** `Opportunity_Acknowledgment_Router` (after-save) classifies each
  won gift from `Acknowledgment_Rule__mdt` → sets Channel/Send_Mode/Template. Anon-apex verified all 5 paths
  (Major→Print/Approval/Ack_MajorGift; In-Kind→Print/Approval/Ack_InKind; Donation $500→Email/Approval;
  Donation $50→Email/Auto; Grant→fallback Print/Ack_General). **5 record-triggered-flow gotchas hit & fixed
  → memory** (loop-back connector; IsWon not usable in entry; NotEqualTo excludes nulls; RecordType.Dev
  Name doesn't resolve → Get Records; CMDT sort unreliable → best-match-by-priority).
- **REPORTS BUILT & DEPLOYED (2026-07-08):** folder `Acknowledgment Reports` + **Gifts Pending
  Acknowledgment** (Summary, grouped by owner `FULL_NAME`, status=To Be Acknowledged, shows channel/
  template/send-mode/approved/age) + **Acknowledgment SLA Breach (Over 48h)** (Tabular, status=To Be
  Acknowledged AND Age_Business_Days > 2). Deployed 3/3 (folder+reports together). Gotchas: owner grouping
  token = `FULL_NAME` (NOT `OPPORTUNITY_OWNER` — invalid for Opportunity report type); report Name max 40 chars.
### 2026-07-08 — Rev after Jason feedback
- **Consolidated 5 letter flows → ONE `Acknowledgment_Letter` flow** (per the original intent — my split into
  5 was wrong). Internal **Pick Template** decision keys off `Acknowledgment_Template__c` (set by the router)
  → renders Major / Recurring / In-Kind / Tribute / General screen → stamps Acknowledged + date + sent-by on
  finish. VF page now defaults to this one flow. The 5 old flows (`Ack_*`) **deactivated** in org (API won't
  delete flows here — Jason can hard-delete in Setup) and **removed from repo**.
- **Print fix:** VF page now hides the flow footer (Finish button) on print via `@media print` CSS +
  a `beforeprint` JS that walks shadow roots. **VF gotcha:** inline JS operators/`&` break the page XML —
  wrap script in `//<![CDATA[ … //]]>` and never put a bare `&` in a CSS/JS comment.
- **Age formula now FREEZES on acknowledgment** (Jason's Q): end date = Acknowledgment Date if set, else
  TODAY() → becomes "business days to acknowledge." **Gotcha:** required `formulaTreatBlanksAs=BlankAsBlank`
  (with `BlankAsZero`, ISBLANK() always returns false so the freeze never triggered). Verified: 2 while
  pending, frozen at 1 once acknowledged on the next business day.
- **CMDT `Template_Flow__c` relabeled "Template Key"** (it's a decision key for the single flow, not a flow name).
### 2026-07-08 — Email path BUILT & VERIFIED
- **`Opportunity_Send_Acknowledgment_Email`** (after-save, entry Channel=Email): Get primary Contact →
  **Check Send** (`status=To Be Acknowledged AND (Send_Mode=Auto OR Approved=true) AND Contact.Email not
  null`) → **Pick Template** (keys off `Acknowledgment_Template__c`) → sets subject + rich body from 5 in-flow
  **Text Templates** (Major/Recurring/In-Kind/Tribute/General, placeholder content, merge fields) → **Send
  Email** (`emailSimple`) from the **OWEA `development@jcrcny.org`** to the contact → **stamps Acknowledged
  + date + sent-by**. Handles both the auto tier and the approval tier (fires when Approved is checked).
- **Router now also stamps `npsp__Acknowledgment_Status__c = "To Be Acknowledged"`** when it classifies —
  so new won gifts appear in the pending report AND become eligible for the email/approval logic.
- **VERIFIED end-to-end** (anon Apex, savepoint): small Donation → router set Email/Auto → email flow sent →
  Status=Acknowledged, Date stamped. **Gotchas:** `emailSimple` requires `emailBody` even when using
  `richTextBody`+`sendRichBody`; **the OWEA must be VERIFIED** — an unverified OWEA throws "Org-Wide Email
  provided is not valid" (confirmed the flow works with current-user sender; OWEA sender restored for once verified).
- **⏳ JASON:** **verify the OWEA** `development@jcrcny.org` (click the confirmation email) so the OWEA send
  works; confirm email **deliverability = All email** in the sandbox.
### 2026-07-08 — Email uses REAL EmailTemplate records (corrected per Jason)
- **Correction:** the `emailSimple` (Send Email) flow action DOES send template records via its
  **`emailTemplateId`** input (its own error even says so). Rebuilt the email path to use **5 classic
  `EmailTemplate` records** (`Ack_Email_General / MajorGift / Recurring / InKind / Tribute`, type=custom HTML,
  merge fields `{!Contact.…}` / `{!Opportunity.…}`, in `email/unfiled$public/`).
- **`Opportunity_Send_Acknowledgment_Email` rewritten:** Get Contact → **Get EmailTemplate by DeveloperName =
  `Acknowledgment_Template__c`** → Check Send (adds "template found") → **Send Email with `emailTemplateId` =
  the template, `recipientId` = contact (whoId merge), `relatedRecordId` = opp (whatId merge), sender = OWEA**
  → stamp. No more in-flow text templates.
- **Verified structurally:** flow reaches Send Email (template lookup + params accepted); the only remaining
  errors are **org email settings**, not code.
- **⏳ JASON — two Setup actions unblock live sending:** (1) **verify the OWEA** `development@jcrcny.org`;
  (2) **Setup → Deliverability → Access to Send Email = "All email"** (sending a template to a contact via
  `recipientId` needs single-email enabled — currently "Single email is not enabled for your org/profile").
- **PHASE 1 COMPLETE** apart from those 2 org email settings + client real content/rules. **Jason UI:** create+verify OWEA `development@jcrcny.org`;
  deactivate the 2 native `Email Acknowledgment…` picklist values; place VF page + native/new fields on gift
  record pages; assign FLS already done.
- **NOT yet committed to git.** Working tree has heavy non-JSI-87 `customMetadata` churn — stage ONLY JSI-87
  paths (fields, profiles FLS, CMDT type + 5 Acknowledgment_Rule records, aura, page, 6 flows, docs).
