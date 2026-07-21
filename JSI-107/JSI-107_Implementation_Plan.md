# JSI-107 — Implementation Plan: Sync Constant Contact lists with NPSP

> **Story:** [JSI-107](https://missionmattersgroup.atlassian.net/browse/JSI-107) · Epic JSI-3 Email Marketing · Must-Have (US-045) · Sprint 2 · Feature Owner **Communications**.
> **Author:** Jason Ott · **Drafted:** 2026-07-19 · Status: **PLAN — awaiting approach decision (Step 5), no build yet.**
> This is the first of the Constant Contact (CC) integration stories. Per Jason's dictation, the priority is a *thorough analysis of standard integration vs. custom API* before building. This plan is research-complete and ends in a decision that Jason (and, on budget, the client) must settle before Step 6.

---

## 1. Scope

**In scope (this story):**
- A working, tested Constant Contact ↔ NPSP integration (DoD #1).
- **SF → CC:** push Salesforce audiences (Reports/Campaigns → CC lists) (DoD #2).
- **CC → SF (the hard part):** engagement (sends/opens/clicks/bounces/unsubscribes) onto NPSP Contacts (DoD #3); **email opt-out synced back within 24h** (DoD #4); **hard bounces flagged** for cleanup (DoD #5).
- Subscription status + basic deliverability stats **visible on the Contact in Salesforce** (dictation).
- **Sync error logging surfaced to System Administrator** (DoD #6).

**Out of scope / deferred:**
- Designing and sending the actual emails/campaigns (Communications does that inside CC).
- Full segmentation strategy and which specific lists sync (needs Communications input — see §10).
- Multi-email-address business rule (open client question — see §10 Q2).
- SMS, advanced automations, and later CC stories under epic JSI-3.

---

## 2. Integration approach — **the critical decision** (build vs. buy vs. native)

### 2.1 The governing finding
**Constant Contact's own native Salesforce integration is ONE-WAY (Salesforce → Constant Contact only).** Verbatim from the vendor doc Jason supplied: *"The sync is one-way, and data, including unsubscribes and contact activity, isn't sent back into your Salesforce account"* (`ConstantContactDocumentation.MD` line 9). Independent sources confirm the native connector does not return engagement, unsubscribes, or preference changes to Salesforce.

Therefore **the native integration alone satisfies only DoD #2** and fails #3, #4, #5 — which are the core of this story and of Jason's "must be bidirectional" dictation. (Note: the *bidirectional* material in the vendor doc is for Constant Contact's **separate** product, *Lead Gen & CRM* / former SharpSpring — a different, heavier platform, not the Email/Digital Marketing product JCRC uses.)

### 2.2 The three real options

| | **A. Native CC↔SF** | **B. Purpose-built middleware** | **C. Custom API integration** |
|---|---|---|---|
| What | CC-hosted connector (configured on CC's side) | Cazoomi **SyncApps** *(NPSP↔Constant Contact)* or Outfunnel | Apex + Named/External Credential (OAuth2) + scheduled polling of CC v3 API |
| Direction | **One-way SF→CC only** | **Bidirectional** | **Bidirectional** (both directions we code) |
| Opt-out CC→SF (#4) | ❌ | ✅ (advertised) | ✅ (poll `optout_after`/updated contacts) |
| Engagement CC→SF (#3) | ❌ | ✅ (opens/clicks/bounces as activities + fields) | ✅ (per-contact Activity Summary API) |
| Hard-bounce flag (#5) | ❌ | ✅ (bounce reason + last-bounce date) | ✅ (bounce report / activity) |
| Audience push SF→CC (#2) | ✅ | ✅ (Campaigns/Reports → lists) | ✅ (add/remove list memberships) |
| Error logging (#6) | vendor dashboard only | vendor dashboard + email alerts | ✅ custom, native (our design) |
| Build effort | Low (config) | **Low–moderate (config/mapping)** | **High (OAuth, polling jobs, mapping, dedupe, error store, tests, maintenance)** |
| Ongoing cost | included | **~$112.50/mo** (Cazoomi, 25% nonprofit off $150) | no per-record SaaS; carries dev + maintenance cost instead |
| Data leaves SF to a 3rd-party processor | CC only | **Yes — middleware vendor (needs DPA review)** | No extra processor (SF↔CC direct) |
| Control / customization | Low | Medium (vendor's mapping model) | **Full** |
| Who maintains it | vendor | vendor | **us (JCRC/MMG)** |

### 2.3 Key technical facts behind the matrix (verified in research)
- **CC v3 API is fully capable** for a custom build: Contacts CRUD; list membership add/remove (`/activities/add|remove_list_memberships`); consent data (`email_optout_date`, `email_optout_reason`, `optout_after` filter, `/contacts/counts`); **per-contact activity reporting** (`em_sends/opens/clicks/bounces`) and an **Activity Summary per contact**; OAuth2 (Auth-Code + PKCE + Device).
- **Webhooks are PARTNER-ONLY** — *"Only authorized technology partners have access to partner endpoints."* A normal JCRC account cannot subscribe to real-time unsubscribe/bounce webhooks. **⇒ a custom build uses scheduled polling, not push.** The DoD's *"within 24 hours"* opt-out SLA is comfortably met by an hourly or a few-times-daily poll.
- No Constant Contact package is installed in JCRC-Dev today (verified) — every option is net-new.

### 2.4 DECISION — **Option D: Hybrid** (Jason, 2026-07-19)
**Chosen approach: native connector for the one-way direction + a targeted custom API reader for the reverse.** Concretely:
- **Outbound (SF→CC), DoD #2:** the **free native Constant Contact connector** (CC-hosted) pushes SF Contacts / Campaign lists → CC lists on a schedule. **Zero Salesforce build.**
- **Inbound (CC→SF), DoD #3/#4/#5:** a **custom, read-only Apex poller** pulls opt-outs, bounces, and engagement from the CC v3 API on a schedule and writes them onto NPSP Contacts.

**Why this wins over B and C:**
- vs **C (full custom):** we don't build or maintain the outbound sync — the native connector does it for free — so the custom scope shrinks to an inbound reader.
- vs **B (middleware):** no recurring SaaS fee and **no third-party data processor** — donor PII flows SF↔CC directly, simplifying the privacy/DPA story.
- vs **A (native only):** adds the reverse sync the native connector structurally cannot do, so the Must-Have DoD is fully met.

**Trade-off accepted:** JCRC/MMG owns and maintains the inbound poller (Apex) + the CC OAuth token health. Moderate, and far smaller than a full two-way custom build.

**On webhooks (Jason's question):** real-time contact-event webhooks are **not available** for this design — CC's webhooks are partner/billing-oriented, not account-level opt-out/bounce events — so the inbound side is **scheduled polling**, which comfortably meets the 24-hour opt-out SLA. Full analysis in **Appendix A**.

---

## 3. Verified org context (checked against JCRC-Dev, 2026-07-19)

- **Edition/API:** Enterprise + NPSP 3.237 → **API access available** (both native connector and custom API need it). ✅
- **No Constant Contact managed package installed.** ✅ (net-new either way)
- **Email fields on Contact today:** `Email`; NPSP `npe01__HomeEmail__c`, `npe01__WorkEmail__c`, `npe01__AlternateEmail__c`, `npe01__Preferred_Email__c` (picklist — which is primary). 
- **Native email opt-out EXISTS:** `HasOptedOutOfEmail` ("Email Opt Out", checkbox) is present with FLS Read+Edit on **System Administrator + all four JCRC profiles** (confirmed via `FieldPermissions` and Jason's direct UI check). `DoNotCall` (phone) exists too. **⇒ reuse `HasOptedOutOfEmail` as the opt-out target for DoD #4 — do not invent a new opt-out field.** *(Correction: earlier `sf` CLI describe/SOQL probes intermittently reported these standard fields as absent — a stale/transient metadata-cache artifact, since Salesforce returns the same "No such column" text for a missing field and for one being edited in Setup. Disregarded in favor of the verified FieldPermissions + UI evidence.)*
- **Other consent/deliverability fields:** `npsp__Do_Not_Contact__c` (boolean, general — not email-specific), `npsp__Undeliverable_Address__c` (boolean, **postal**). The standard SF bounce fields `EmailBouncedReason` / `EmailBouncedDate` / `IsEmailBounced` exist **but only populate from Salesforce's own email sends**, not from an external sender like CC — so CC bounce data still needs its own field(s). No native field holds CC **subscription status** or **engagement** → those are net-new (see §4).
- **Campaign & CampaignMember exist** (CampaignMember queryable; 0 rows today) → pushing **Salesforce Campaigns as CC audiences** is structurally supported.

---

## 4. Data model — new fields to hold CC data (needed for B **and** C)

The org already has the **email opt-out** (`HasOptedOutOfEmail`) — reuse it. It lacks CC **subscription-status, bounce, and engagement** fields, so add a small, vendor-neutral set on **Contact** (names to confirm with Jason):

| Field (proposed) | Type | Purpose / DoD |
|---|---|---|
| *(reuse)* `HasOptedOutOfEmail` | Checkbox (native) | Email opt-out mirrored from CC unsubscribe (DoD #4). No new field. |
| `CC_Subscription_Status__c` | Picklist (Subscribed/Unsubscribed/Pending/Cleaned) | CC permission state, visible in SF (dictation). |
| `Email_Last_Bounce_Date__c` | Date | Last CC bounce (DoD #5). |
| `Email_Hard_Bounce__c` | Checkbox | Hard-bounce flag for list cleanup (DoD #5). |
| `Email_Last_Open__c` / `Email_Last_Click__c` | Date | Basic deliverability visibility (dictation, DoD #3). |
| `CC_Contact_Id__c` | Text (External ID, unique) | Stable link to the CC contact for reliable matching/dedupe. |

**Engagement detail (DoD #3) — DECISION (Jason, 2026-07-19): Option A now, B/C anticipated.**
- **A (build now):** summary fields on Contact — `Email_Last_Open__c`, `Email_Last_Click__c`, `Email_Last_Bounce_Date__c`, optional `Email_Opens_Last_90_Days__c` counter. Satisfies "engagement visible on the Contact" + list-hygiene filtering with minimal build.
- **B (documented, held open):** `Email_Engagement__c` child object — one row per send/open/click/bounce for full per-email history/timeline.
- **C (documented, held open):** map CC emails → **Campaign** + recipients → **CampaignMember** status — the native marketing-analytics model; dovetails with DoD #2's campaign audiences.
- **Likely future need (Jason):** Communications may well want **full email analytics inside Salesforce**, which means adding **B (the engagement log)** and/or **C**. **Design for that now:** (1) keep the poller's engagement write as a **modular "sink" step** so a child-object/CampaignMember writer can be added without re-architecting the poller; (2) persist the **CC campaign/activity identifiers + timestamps** the poller reads (at least the run cursor) so we retain the ability to **backfill** history later; (3) CC retains contact activity, so a future B/C build can also re-pull history from the API. No Phase-1 field choice blocks the upgrade.

---

## 5. Security & FLS
Per org standard (**profile-based, not permission sets** — see the `feedback-security-at-profile-not-permsets` rule): grant FLS for all new fields on **Admin + JCRC Development / Fundraising / Marketing / Volunteering** profiles via the additive minimal-profile technique. If Option C, the **integration/API user** also needs object + field access and API-only setup. No new permission set.

---

## 6. Requirement → mechanism (Hybrid — DoD map)

| DoD | Direction | Mechanism (chosen: Hybrid) |
|---|---|---|
| #1 Integration configured & tested | both | Native connector connected on CC side (integration user) + custom inbound poller via Named/External Credential (OAuth2). Test both directions in sandbox. |
| #2 Push Reports/Campaigns → CC | SF→CC | **Native connector** import: SF Contacts / Campaign lists → CC lists on schedule. **No SF build.** During field mapping, map the **SF 18-char Contact Id into a CC custom field** so the poller can match back reliably. |
| #3 Engagement → NPSP | CC→SF | **Poller:** per-campaign tracking (`/reports/email_reports/{caId}/tracking/opens|clicks`) or per-contact Activity Summary → update Contact summary fields (last open/click) and/or CampaignMember. |
| #4 Opt-out CC→SF ≤24h | CC→SF | **Poller (hourly):** `GET /contacts?optout_after={lastRun}` → set native `HasOptedOutOfEmail=true` on matched Contacts. Hourly ≪ 24h SLA. |
| #5 Hard bounces flagged | CC→SF | **Poller:** campaign/contact bounce activity → set `Email_Hard_Bounce__c` + `Email_Last_Bounce_Date__c` (classify hard vs soft). |
| #6 Errors surfaced to admin | — | Custom `Integration_Log__c` (run status/counts/failures) + list view/report + optional email alert to **System Administrator**. |

**Inbound poller shape:** External Credential + Named Credential (OAuth2 Authorization-Code + refresh token; one-time admin connect) → `Schedulable`/`Queueable` (hourly) reading CC deltas since a stored last-run timestamp → match by `CC_Contact_Id__c`/mapped SF Id (fallback email) → upsert fields → write `Integration_Log__c`. Incremental delta pulls stay well within CC v3 limits (~10k calls/day, ~4/sec).

---

## 7. Phased build plan (Hybrid)

**Phase 0 — Prereqs / access [Jason + client]:** register a CC **API application** (API key + secret; Jason has the keys per dictation); create a dedicated **Salesforce integration user** (least-privilege via profile); confirm CC subscription tier permits API access.
**Phase 1 — Native outbound [Jason, CC-side config]:** connect CC↔SF, create the import(s) (Contacts / Campaign lists → CC lists), and **map the SF Contact Id into a CC custom field** for match-back. Satisfies DoD #2. Verify a list flows SF→CC.
**Phase 2 — SF data model [Claude, CLI]:** deploy §4 Contact fields (`CC_Subscription_Status__c`, `Email_Last_Bounce_Date__c`, `Email_Hard_Bounce__c`, `Email_Last_Open__c/Click__c`, `CC_Contact_Id__c`) + `Integration_Log__c` object + **profile FLS** (additive minimal-profile, 5 profiles). Reuse native `HasOptedOutOfEmail`.
**Phase 3 — Auth [Claude + Jason]:** External Credential + Named Credential for CC OAuth2 (Auth-Code + refresh); one-time admin connect; connectivity test (anon Apex callout in savepoint).
**Phase 4 — Inbound poller [Claude, Apex]:** `Schedulable`/`Queueable` reader — opt-outs (#4), bounces (#5), engagement (#3); match by `CC_Contact_Id__c`/email; upsert; write `Integration_Log__c`; store last-run timestamp. Tests ≥90%, `with sharing`, USER_MODE where writing user data. Verify each path via anon Apex (savepoint→rollback).
**Phase 5 — Error surfacing + reports [Claude]:** admin list view/report on `Integration_Log__c` failures + "Contacts: Opt-Outs / Hard Bounces" report (#6). Optional email alert.
**Phase 6 — Schedule + verify + hand-off:** schedule the poller (hourly); end-to-end sandbox test (unsubscribe in CC → `HasOptedOutOfEmail` within the hour; bounce → flag; engagement → fields); document; confirm lists/segments with Communications (§10).

---

## 8. Net-new metadata (Hybrid)
SF: §4 Contact fields (+ FLS on 5 profiles), `Integration_Log__c` object + fields, External Credential + Named Credential (+ Auth Provider if used), Apex poller classes + tests, scheduled job, admin report/list view. CC side (config, not SF metadata): the API application + the native import with SF-Id mapping.

## 9. Risks & compliance
- **Compliance-critical:** opt-out must round-trip reliably or JCRC risks emailing people who unsubscribed (CAN-SPAM). Test #4 hard before go-live; monitor.
- **Multiple emails per Contact (client Q2):** CC is keyed on a single email; NPSP has up to 4 (`Preferred_Email` picks one). Must define the authoritative email for sync and how opt-out/bounce map when addresses differ — **blocking design input**.
- **Option B:** third-party data processor → review Cazoomi's DPA/security posture with the client (nonprofit donor PII). Recurring cost ownership.
- **Option C:** ongoing maintenance, CC API rate limits (~10k/day) and token-refresh reliability, no vendor support.
- **Duplicates:** without a stable key, CC↔SF matching creates dupes → the `CC_Contact_Id__c` external ID mitigates.
- **"What not to touch" (client Q1):** confirm guardrails before writing to any existing marketing field.

## 10. Open decisions (settle in Step 5)
- **D1 — INTEGRATION APPROACH — ✅ RESOLVED (Jason, 2026-07-19): Hybrid** (native connector SF→CC + custom inbound API poller CC→SF). See §2.4 + Appendix A. Remaining budget-only note: Phase 0 confirms CC tier permits API access (no SaaS fee for this path).
- **D2 (Jason):** confirm opt-out target = native **`HasOptedOutOfEmail`** (recommended; verified present). Optionally also mirror to `npsp__Do_Not_Contact__c` if the client wants a global suppression flag.
- **D3 — ✅ RESOLVED (Jason, 2026-07-19):** Option **A (summary fields)** now; **B (`Email_Engagement__c` log)** and/or **C (Campaigns/CampaignMembers)** documented and **held open** — Communications may want full email analytics in Salesforce, so the poller is built extensibly (modular engagement sink + retained CC activity ids for backfill). See §4.
- **D4 (Client) — answered (Jason, 2026-07-19):** nothing off-limits in email marketing as of now; revisit if Communications later flags something. No build impact.
- **D5 (Client, from Jira comment):** business process for **multiple email addresses per Contact** → which email is authoritative for sync.
- **D6 (Communications):** which lists/segments sync, and initial direction of authority per field.

## 11. Sources
- Vendor doc supplied by Jason: `ConstantContactDocumentation.MD` (native sync = one-way, line 9; Lead Gen & CRM = separate bidirectional product).
- Constant Contact v3 API guide — contacts, list membership, consent, per-contact activity reporting, OAuth2, **partner-only webhooks**: https://developer.constantcontact.com/api_guide/index.html
- Cazoomi SyncApps (NPSP↔Constant Contact) — bidirectional, opt-out + engagement + bounce sync, NPSP support, nonprofit pricing: https://www.cazoomi.com/syncapps/salesforce-nonprofit-success-pack-npsp-to-constant-contact/
- Native connector one-way limitation (independent): massmailer.io Constant Contact–Salesforce integration guides; Outfunnel 2-way sync notes.
- Org verification: `sf sobject describe Contact`, `FieldDefinition` + `FieldPermissions` queries against JCRC_Dev (see §3). *(Note: `HasOptedOutOfEmail`/`DoNotCall` exist — an early CLI describe/SOQL false-negative was a metadata-cache artifact; corrected via FieldPermissions + Jason's UI check.)*
- Partner/webhooks scope (billing-oriented, partner-approval): https://developer.constantcontact.com/api_guide/partner_webhook_overview.html (see Appendix A).

## 12. Build Log

**Phase 2 — SF data model — ✅ BUILT, DEPLOYED & VERIFIED 2026-07-19 (not yet committed).**
- **7 Contact fields** deployed: `CC_Contact_Id__c` (Text 50, External ID, unique), `CC_Subscription_Status__c` (restricted picklist: Subscribed/Unsubscribed/Pending/Cleaned/Not Set), `Email_Hard_Bounce__c` (checkbox), `Email_Last_Bounce_Date__c` (date), `Email_Last_Open__c` (date), `Email_Last_Click__c` (date), `Email_Opens_Last_90_Days__c` (number 4,0). Opt-out reuses native `HasOptedOutOfEmail`.
- **`Integration_Log__c`** object (AutoNumber `IL-{00000}`, Private OWD, admin-only) + 9 fields: `Integration__c`, `Operation__c` (Opt-Out/Bounce/Engagement/Audience Push/Full Sync), `Run_Status__c` (Success/Partial/Failed), `Run_Start__c`, `Run_End__c`, `Records_Processed/Updated/Failed__c`, `Message__c` (long text).
- Deploy: **17/17 components, 0 errors** (via source-dir; this CLI 2.106.6 rejects mixing `-d`+`-m`).
- **FLS via additive minimal-profile technique** (full profiles not source-deployable here): Contact fields → **Admin + 4 JCRC profiles**; `Integration_Log__c` object + fields → **Admin** only. Repo full profiles synced (contiguous insert; +7 FLS each JCRC, +16 FLS + object perm on Admin). *(Gotcha hit: in a Profile, all `<fieldPermissions>` must be contiguous and precede `<objectPermissions>` — split groups → "fieldPermissions is duplicated" deploy error.)*
- **Verified** via anon Apex (savepoint→rollback): Contact wrote opt-out + all CC fields; `Integration_Log__c` IL-00000 created; 4/4 asserts passed; rolled back (no data persisted).
- **Added for Phase 1 outbound match-key:** `CC_Salesforce_Id__c` Contact **formula** field = `CASESAFEID(Id)` (18-char), read-only FLS on all 5 profiles. Exists so the native connector can map a normal field (not the raw record Id, which the connector may not expose) into a CC custom field. Verified returns the 18-char Id. Repo profiles synced (+1 read-only FP each).

**Phase 1 — native connector (Jason, CC-side UI) — walkthrough provided 2026-07-19; in progress.** Create CC custom field "Salesforce ID" → connect CC to the **sandbox** → create import → map `CC_Salesforce_Id__c` → CC "Salesforce ID" (+ confirm Email Opt Out pre-mapped) → Merge, scheduled → verify the Id lands in CC.

**Phase 4 (part 1) — reverse-sync applier — ✅ BUILT, DEPLOYED & TESTED 2026-07-19 (not committed).** `ConstantContactSyncService` (`with sharing`, trusted-backend system-mode DML): takes normalized `ContactUpdate` DTOs and applies opt-out (native `HasOptedOutOfEmail` + `CC_Subscription_Status__c`), hard bounce + date, engagement (last open/click, opens-90), and backfills `CC_Contact_Id__c`; matches by pushed **Salesforce Id (indexed)** with case-insensitive **email fallback**; partial-success DML; writes one `Integration_Log__c` per run. `ConstantContactSyncServiceTest` **2/2 pass, 96% cov**. This core is intentionally **CC-API-agnostic** (no guessing CC's wire format).

**✅ CC AUTHORIZE CLEARED & INTEGRATION LIVE 2026-07-21.** The External Credential principal `CC_Principal` is **Configured** (verified via anon-Apex callouts: `/contacts`, `/contact_custom_fields` [the "Salesforce Id" match field is present], `/emails` all return HTTP 200 with live data). **Root cause of the earlier "authenticated but Not Configured"** was the CC account owner being **already logged into Constant Contact**, so the IdP skipped the scope-consent page and returned without granting scopes → no token stored; **re-authenticating from a session that forced the consent screen** fixed it (see [[reference-sf-metadata-gotchas]]). Scope in use: `contact_data campaign_data offline_access`. **All three inbound syncs (opt-out/preference/engagement) ran clean end-to-end as Queueables and are SCHEDULED HOURLY** via `ConstantContactSyncSchedulable` (`JSI CC Inbound Sync Hourly`, cron `0 0 * * * ?`). First runs logged Success (0 to process — no recent deltas / only a draft campaign; real-data parsing confirms on first live activity).

**Phase 3 — Auth — ✅ RESOLVED 2026-07-21 (was: ⏳ CONFIGURED, BLOCKED ON CC APPROVAL 2026-07-20).** CC API app registered (Client ID `4e149…`, Long-Lived refresh); Salesforce External Credential + Named Credential `Constant_Contact` built; redirect_uri handshake fixed. **Blocker:** the OAuth **Authenticate** step fails with Okta *"You are not allowed to access this app — contact an admin"* for Jason's **Account Manager** role (persists across days + incognito). CC's docs say Account Managers have full v3 API endpoint access but are **silent on who may authorize an OAuth app**, so cause is undocumented. **Resolution (external): the CC Account Owner must complete the one-time Authenticate** (Named Principal → account-level token), or CC support enables the app. Account Owner not currently reachable.

**Phase 4 (part 2) — opt-out poller — ✅ BUILT, DEPLOYED & TESTED (mocked) 2026-07-20 (not committed).**
- `ConstantContactClient.getUnsubscribes(since)` — `GET /contacts?status=all&optout_after={ISO}&include=custom_fields` with cursor pagination; maps `contact_id`/`email_address.{address,opt_out_date}` → `ContactUpdate`; resolves the pushed **Salesforce Id** from `custom_fields` (looks up the "Salesforce ID" custom_field_id via `/contact_custom_fields`).
- `ConstantContactSyncQueueable` (Database.AllowsCallouts) — cursor from last successful `Opt-Out Sync` log (else −25h) → client → applier; logs a **Failed** row on callout/auth error.
- `ConstantContactSyncSchedulable` — hourly; enqueues the worker.
- `ConstantContactPollerTest` (HttpCalloutMock) — **6/6 pass** with the applier test; coverage Client 96%, Queueable 96%, Schedulable 100%, Service 96%.
- ⚠️ **VERIFY-AGAINST-LIVE:** field names + cursor pagination are grounded in the documented v3 contact schema but unconfirmed against a real payload (auth blocked). First live run may need minor parsing tweaks; a sample `/contacts` + `/contact_custom_fields` response would let me confirm.

**Phase 5 — admin visibility — ✅ BUILT & DEPLOYED 2026-07-20 (not committed).**
- Custom report type **`CC_Sync_Logs`** ("Constant Contact Sync Logs") on `Integration_Log__c` (reusable for future integrations).
- Folder **Constant Contact Reports** + 2 reports: **"CC Sync Runs — Errors"** (Integration_Log__c, Run Status ≠ Success — DoD #6) and **"Contacts — Opt-Outs & Hard Bounces"** (ContactList, `HasOptedOutOfEmail` OR `Email_Hard_Bounce__c` — DoD #5).
- `Integration_Log__c` list view **"Failed & Partial Runs"** for at-a-glance admin monitoring.
- *(Gotchas → memory: a custom object's default report type is NOT referenceable by object name — build a **CustomReportType**; a report references it as **`<DevName>__c`** even though the type's own fullName has no `__c`; custom-report-type report columns use `Object$Field` and the auto-number `Name` isn't exposed unless added to the type — omit or add it. Report type + report referencing it must deploy in **separate** transactions.)*

**Remaining:**
- **Phase 4 (part 3) — bounce (#5) + engagement (#3) fetches:** CC **reporting** endpoints (campaign tracking / per-contact activity). Shape-heavier → build once a live/sample reporting payload is available (or after auth clears). Feed the same applier (`Bounce Sync` / `Engagement Sync`).
- **Live smoke test** of the whole inbound path (needs Phase 3 authorize).
- **Phase 6:** `System.schedule` the poller hourly (after authorize); end-to-end sandbox test.
- **Production** go-live: native connector + credential + Owner authorize against prod; re-auth `JCRC-Prod`.
- **D5** (authoritative email) refines the email fallback; primary match is the pushed SF Id, so non-blocking.
- **D6** (Communications): which lists/segments sync.

---

## Appendix A — Webhooks: why the inbound side polls (answering "what does it take?")

**Short answer:** Constant Contact does **not** offer real-time contact-event webhooks (unsubscribe/bounce/opened) to a normal account, so the inbound sync is **scheduled polling**. Pursuing partner status would **not** unlock those events either.

**What the CC webhook surface actually is:**
- CC v3 webhooks live under **`/partner/webhooks/...`** and are **restricted to approved Technology Partners** — specifically partners **reselling the CC "ToolKit" product suite**. They authenticate with **partner basic-auth credentials** (not the account's OAuth2).
- The topics are **billing/account events** (e.g., *billing-tier changes for accounts under the partnership*) — i.e., reseller/account-management notifications, **not** per-contact opt-out or bounce events.
- ⇒ Even a JCRC that became a partner would receive **billing notifications, not "contact X unsubscribed."** Partner webhooks do not solve DoD #4/#5.

**What it would take to get partner status (for completeness):** apply to the **Constant Contact Technology Partner Program** — it's **free but approval-gated**, and oriented to ISVs/resellers distributing solutions to CC customers (and to raising API rate limits). Not a fit for a single nonprofit integrating its own account, and — per above — it wouldn't deliver the contact events we need anyway.

**Therefore — the design uses polling:**
- An hourly (configurable) scheduled Apex job pulls **deltas** since the last run: opt-outs via `optout_after`/updated-contacts, bounces via campaign/contact activity, engagement via tracking/activity-summary.
- **Hourly ≪ the 24-hour opt-out SLA (DoD #4)** — even a few-times-daily cadence satisfies it.
- Delta pulls keep call volume low, well within CC v3 limits (~10k/day, ~4/sec). No public-endpoint/webhook-listener to secure.
- **Revisit only if** CC introduces account-level contact webhooks (would cut latency + API calls, but isn't required to meet this story).

*Caveat: CC's developer portal is partly JS-gated / returned 403 to automated fetch; the above is corroborated across the API guide, the partner-webhook overview, and third-party integration write-ups. Jason has the API keys + guide and can confirm the exact current webhook topic list on the partner overview page if we ever reconsider.*
