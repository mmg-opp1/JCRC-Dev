# JSI-109 — Implementation Plan: Email engagement metrics at contact level

> **Story:** [JSI-109](https://missionmattersgroup.atlassian.net/browse/JSI-109) · Epic JSI-3 Email Marketing · Sprint 2 · Feature Owner **Communications**.
> **Author:** Jason Ott · **Drafted:** 2026-07-20 · Status: **PLAN — awaiting fork decisions (Step 5), no build yet.**
> Third Constant Contact story. Extends the JSI-107 hybrid integration (poller + `Integration_Log__c` + Contact CC fields) and the JSI-108 Campaign(`CC List`)/CampaignMember model. Per Jason's dictation, this replaces JSI-107's "many summary fields" approach with a **relational engagement model** built from CC's per-campaign activity data.

---

## 1. Scope

**In scope:**
- A **relational email-engagement model** in Salesforce fed by the existing scheduled CC poller:
  - **`CC_Email__c`** — one record per email the client sends in Constant Contact.
  - **`CC_Email_Activity__c`** — one **summary** record per Contact per email (opened?/clicked?/counts/dates), kept current each poll (not one row per event).
- **Recent activity + rolled-up engagement visible on the Contact** (DoD #1/#2): related list of the contact's `CC_Email_Activity__c`; 90-day opens/clicks metrics.
- **Reports** for highly-engaged and disengaged constituents (DoD #3).
- **Daily+ refresh** via the existing poller (DoD #4) — already hourly.
- **Privacy considerations documented** (DoD #5).

**Out of scope / deferred:**
- Composing/sending emails (Communications does that in CC).
- Real-time engagement (CC has no account-level webhooks — polling only, per JSI-107 Appendix A).
- Per-event history (one click = one row). Dictation is explicit: **summary per contact per email**, not an event log.
- SMS / other JSI-3 stories.

---

## 2. How this changes JSI-107
JSI-107 §4 chose **Option A (Contact summary fields) now, Option B (engagement child object) held open.** JSI-109 **builds Option B** — the child-object model — because Communications needs per-email detail and cross-email reporting that flat summary fields can't give. The JSI-107 Contact fields are **kept** and repurposed as poller-maintained rolling metrics (see §4.3); nothing is thrown away.

---

## 3. Verified org context (JCRC-Dev, 2026-07-20)

- **Existing (JSI-107/108), reused here:** Contact `CC_Contact_Id__c` (Ext ID), `CC_Salesforce_Id__c` (formula CASESAFEID), `CC_Subscription_Status__c`, native `HasOptedOutOfEmail`, `Email_Hard_Bounce__c`, `Email_Last_Bounce_Date__c`, `Email_Last_Open__c`, `Email_Last_Click__c`, `Email_Opens_Last_90_Days__c`; Campaign `CC_List_Id__c` (Ext ID) + `CC List` record type; CampaignMember Subscribed/Unsubscribed; `Integration_Log__c` (Operation picklist already includes **Engagement**). 
- **Apex framework to extend:** `ConstantContactClient` (CC v3 calls over the `Constant_Contact` Named Credential; clean `getJson`/cursor/DTO pattern), `ConstantContactSyncService` (applier), `ConstantContactSyncQueueable(operation)`, `ConstantContactSyncSchedulable` (hourly). All `with sharing`; tests currently 10/10.
- **Net-new confirmed:** no `CC_Email__c` / `CC_Email_Activity__c` today (standard `EmailMessage` is unrelated — SF's own email object, not CC). 
- **External blocker (shared with 107/108):** the CC OAuth **Authenticate** is still pending the CC **Account Owner**. As with 107/108, we **build + mock-test now**; live verification waits on that authorize.

---

## 4. Data model (proposed)

### 4.1 `CC_Email__c` — one per Constant Contact email
| Field | Type | Purpose |
|---|---|---|
| `Name` | Text (or auto) | The email name from CC |
| `CC_Campaign_Activity_Id__c` | Text (**External ID, unique**) | CC `campaign_activity_id` — the stable key for upsert/dedupe |
| `Subject__c` | Text | Email subject line |
| `Sent_Date__c` | DateTime | When CC sent it |
| `CC_List__c` | **Lookup → Campaign** (`CC List` RT) | The audience/list it was sent to (the JSI-108 CC-List Campaign) — **"email list" lookup** |
| `Campaign__c` | **Lookup → Campaign** | Link to a marketing/appeal Campaign for attribution — the **"campaign out of Constant Contact"** lookup (D1 ✅) |
| `Total_Sends__c` / `Total_Opens__c` / `Total_Clicks__c` / `Total_Bounces__c` | Number (DLRS targets) | Per-email totals — **populated by DLRS** (Jason wires the rollups from `CC_Email_Activity__c`; D2) |

### 4.2 `CC_Email_Activity__c` — one per Contact per email (the summary)
| Field | Type | Purpose |
|---|---|---|
| `CC_Email__c` | **Master-Detail → `CC_Email__c`** | Parent email (enables per-email rollups) |
| `Contact__c` | **Lookup → Contact** *(D2)* | The recipient |
| `Activity_Key__c` | Text (**unique**) | `{CC_Campaign_Activity_Id}|{CC_Contact_Id}` — idempotent upsert key |
| `Status__c` | Picklist | Sent / Opened / Clicked / Bounced / Unsubscribed (highest reached) |
| `Opened__c` / `Clicked__c` / `Bounced__c` | Checkbox | Quick flags for filtering/rollups |
| `Open_Count__c` / `Click_Count__c` | Number | Per-recipient totals for this email |
| `First_Open_Date__c` / `Last_Open_Date__c` / `Last_Click_Date__c` | DateTime | Engagement timing |

**§4.2 relationship fork (D2):** `Contact__c` as **Lookup** (recommended) + Contact 90-day metrics maintained by the poller/DLRS, **vs.** making `CC_Email_Activity__c` a **junction** (master-detail to *both* `CC_Email__c` and `Contact`) for native Contact rollups. Recommendation = **Lookup**, because native roll-up summaries **cannot express a rolling "last 90 days" window** anyway (RUS can't filter on TODAY()-based formulas), so the 90-day counters must be poller- or DLRS-maintained regardless — and a lookup avoids the Contact-as-master ownership/mass-delete implications. Per-email rollups (§4.1) still work via the `CC_Email__c` master-detail.

### 4.3 Contact fields — keep JSI-107's, add one
Repurpose the JSI-107 Contact fields as **poller-maintained rolling metrics** (they solve the 90-day window RUS can't): `Email_Last_Open__c`, `Email_Last_Click__c`, `Email_Opens_Last_90_Days__c` (+ **add** `Email_Clicks_Last_90_Days__c`). "Last 5 sends/opens/clicks visible on the Contact" (DoD #1) = a **related list of `CC_Email_Activity__c`** on the Contact page (sorted by email Sent Date), which Jason places in App Builder.

### 4.4 Naming fork (D3)
Proposed API names use the established **`CC_` prefix** (`CC_Email__c`, `CC_Email_Activity__c`) to match `CC_List_Id__c` / `CC_Subscription_Status__c` and avoid confusion with the standard `EmailMessage` object. Dictation said "Email object / Email Activity" generically — confirm the prefix.

---

## 5. Poller extension (CC → SF)

**Chosen shape: campaign-centric** (far fewer API calls than iterating every contact):
1. `ConstantContactClient.getEmailCampaigns(since)` — list CC email campaign activities updated since the cursor → upsert a `CC_Email__c` per campaign (by `CC_Campaign_Activity_Id__c`), resolving `CC_List__c` from the campaign's list ids via `Campaign.CC_List_Id__c` (JSI-108 mapping).
2. `ConstantContactClient.getCampaignTracking(campaignActivityId)` — `GET /reports/email_reports/{caId}/tracking/{sends|opens|clicks|bounces}` (cursor-paginated); each row carries `contact_id` → aggregate per contact into a `CC_Email_Activity__c` DTO (open/click counts + dates + status), resolving the SF Contact via the pushed **Salesforce Id** (reuse `resolveSalesforceId`) / `CC_Contact_Id__c` / email fallback.
3. `ConstantContactSyncService.applyEmailActivity(...)` — upsert `CC_Email__c` + `CC_Email_Activity__c` by their unique keys (idempotent; re-poll updates the same rows), then **refresh the Contact 90-day counters** (`Email_Opens/Clicks_Last_90_Days__c`, last open/click). One `Integration_Log__c` row per run, **Operation = Engagement**.
4. `ConstantContactSyncQueueable('ENGAGEMENT')` + schedule (daily is enough per DoD; can ride the existing hourly cadence). Incremental by cursor; back-pull history once on first run.

**Alternative (documented):** contact-centric `GET /contacts/{contact_id}/activities?start=&end=` gives per-contact/per-campaign summaries directly — simpler mapping but one call per contact (heavy at scale). Keep as a fallback / for on-demand single-contact refresh.

> **VERIFY-AGAINST-LIVE (same as JSI-107):** exact tracking response shapes + pagination are grounded in CC v3 docs (`/contacts/{id}/activities` confirmed via the developer portal; `/reports/email_reports/{caId}/tracking/*` per JSI-107 research — that page is JS-gated/403 to automated fetch). Confirm field names against a real payload once the CC authorize clears. The applier stays CC-agnostic (DTOs), so wire-format tweaks are localized to the client.

---

## 6. Requirement → mechanism (DoD map)

| DoD | Mechanism |
|---|---|
| #1 Recent activity (last 5 sends/opens/clicks) on Contact | `CC_Email_Activity__c` related list on the Contact page (Jason places it) |
| #2 Rolled-up opens/clicks last 90 days | Poller-maintained Contact counters (`Email_Opens/Clicks_Last_90_Days__c`); per-email totals via `CC_Email__c` rollups |
| #3 Reports: engaged / disengaged | Custom report type on `CC_Email_Activity__c` (+ Contact); 2 reports (engaged ≥ threshold; disengaged = 0 opens/90d among subscribed) |
| #4 Refresh ≥ daily | Existing scheduled poller (`ENGAGEMENT` op) — hourly ≫ daily |
| #5 Privacy documented | §9 privacy note (stored vs inferred, retention, opt-out respected) |

## 7. Security & FLS
Per org standard (**profiles, not perm sets** — `feedback-security-at-profile-not-permsets`): object + FLS for `CC_Email__c` / `CC_Email_Activity__c` + the new Contact field on **Admin + JCRC Development/Fundraising/Marketing/Volunteering** via the additive minimal-profile technique. Engagement data OWD: **Private or Public Read-Only** (D4 — it's donor behavioral data; recommend Public Read-Only within staff, no external). Apex class access on the same profiles.

## 8. Phased build plan
- **Phase 1 — schema [Claude]:** `CC_Email__c` + `CC_Email_Activity__c` (+ fields, unique keys, rollups) + `Email_Clicks_Last_90_Days__c` on Contact + FLS on 5 profiles. Deploy + anon-Apex verify (savepoint→rollback).
- **Phase 2 — poller [Claude]:** extend `ConstantContactClient` (getEmailCampaigns / getCampaignTracking + DTOs), `ConstantContactSyncService.applyEmailActivity`, `ConstantContactSyncQueueable('ENGAGEMENT')`; `HttpCalloutMock` tests ≥90%.
- **Phase 3 — reporting [Claude]:** report type + engaged/disengaged reports (folder reuse "Constant Contact Reports").
- **Phase 4 — UI [Jason]:** place the `CC_Email_Activity__c` related list on the Contact page + a `CC_Email__c` record page/related lists; assign as needed.
- **Phase 5 — live verify [blocked]:** once CC authorize clears — first run backfills history; confirm counts vs CC; schedule.

## 9. Privacy considerations (DoD #5 — draft)
- **Stored (fact):** per-email, per-contact **aggregate** engagement — sent/opened/clicked flags, open/click **counts**, and **dates**; email subject/name/send date. No message body, no per-keystroke/geo/device tracking beyond what CC returns.
- **Inferred:** "engaged" / "disengaged" is a **derived** label from counts over a rolling 90 days — not a CC field; documented as inferred.
- **Retention:** mirrors CC (source of truth); if a contact is deleted or opts out, activity rolls off with the Contact (lookup) / can be purged. Opt-out (`HasOptedOutOfEmail`) is always respected — engagement data never drives re-sending.
- **Access:** staff-only (OWD Private/Read-Only), FLS on JCRC profiles; not surfaced externally.

## 10. Open decisions — ✅ SETTLED (Jason, 2026-07-20)
- **D1 — ✅ TWO lookups on `CC_Email__c`:** `CC_List__c` (→ CC List / audience Campaign) **and** `Campaign__c` (→ a marketing/appeal Campaign for attribution). Both built now.
- **D2 — ✅ LOOKUPS, not master-detail:** `CC_Email_Activity__c` has a **Lookup** to both `CC_Email__c` and `Contact`. **Rollups via DLRS** (Jason builds them) — matches the org's DLRS pattern. The poller still maintains the Contact **90-day** counters (reliable rolling window DLRS/RUS can't express); Jason can add DLRS rollups for all-time/per-email totals.
- **D3 — ✅ `CC_` prefix:** `CC_Email__c` / `CC_Email_Activity__c`.
- **D4 — engagement OWD:** **Public Read-Only** (`Read`) for staff — donor behavioral data, staff-visible, not external.
- **D5 — poller cadence:** ride the existing hourly job (≫ the daily SLA) with a new `ENGAGEMENT` operation.

## 11. Sources
- CC v3 **Contact Activity Reporting** (confirmed via portal): `GET /contacts/{contact_id}/activities` (per-campaign summary: sends/opens/clicks/bounces/optouts/forwards; 200/page), `/activity_details`, `/open_and_click_rates` — https://developer.constantcontact.com/api_guide/contact_reporting_overview.html
- CC v3 **Campaign Tracking** (opens/clicks/sends/bounces per campaign_activity_id) — https://developer.constantcontact.com/docs/campaign-tracking/email-campaign-tracking-.html *(JS-gated/403 to automated fetch; corroborated by JSI-107 research)*
- JSI-107 Implementation Plan (the hybrid poller this extends) — `../JSI-107/JSI-107_Implementation_Plan.md`
- JSI-108 Implementation Plan (Campaign `CC List` + CampaignMember model) — `../JSI-108/JSI-108_Implementation_Plan.md`

## 12. Build Log

**Phase 1 — schema — ✅ BUILT, DEPLOYED & VERIFIED 2026-07-20 (not committed).**
- **`CC_Email__c`** (OWD Public Read-Only, Text name "Email Name") + 9 fields: `CC_Campaign_Activity_Id__c` (Text 50, External ID, unique), `Subject__c` (Text 255), `Sent_Date__c` (DateTime), `CC_List__c` (Lookup→Campaign, "CC Emails (by List)"), `Campaign__c` (Lookup→Campaign, "CC Emails"), `Total_Sends/Opens/Clicks/Bounces__c` (Number 18,0 — DLRS targets for Jason).
- **`CC_Email_Activity__c`** (OWD Public Read-Only, AutoNumber `EA-{000000}`) + 12 fields: `CC_Email__c` (Lookup→CC_Email__c), `Contact__c` (Lookup→Contact), `Activity_Key__c` (Text 120, External ID, unique = `{caId}|{ccContactId}`), `Status__c` (restricted picklist Sent/Opened/Clicked/Bounced/Unsubscribed), `Opened/Clicked/Bounced__c` (Checkbox), `Open_Count/Click_Count__c` (Number 8,0), `First_Open_Date/Last_Open_Date/First_Click_Date/Last_Click_Date__c` (DateTime — `First_Click_Date__c` added 2026-07-20 for symmetry with First Open). Both relationships **Lookup** (D2); rollups via DLRS (Jason).
- **Contact:** added `Email_Clicks_Last_90_Days__c` (Number 6,0) — companion to the JSI-107 `Email_Opens_Last_90_Days__c`.
- Deploy: **24/24 components, 0 errors.**
- **FLS via additive minimal-profile technique** (5 profiles, 5/5): all fields readable on **Admin + 4 JCRC**; Admin editable on all + full object CRUD; JCRC read/create/edit objects (no delete), editable only on `CC_List__c`/`Campaign__c` (attribution), rest read-only (poller/DLRS-maintained).
- **Verified** via anon Apex (savepoint→rollback): inserted `CC_Email__c` + `CC_Email_Activity__c` linked to a live Contact; cross-object lookup (`CC_Email__r.Subject__c`) resolved; 3/3 asserts passed; rolled back (no data persisted).
- **⏳ Follow-up:** sync the repo full profiles to document the new FLS/object perms (additive deploy grants in-org; version-control catch-up).

**Phase 2 — engagement poller — ✅ BUILT, DEPLOYED & TESTED (mocked) 2026-07-20 (not committed).**
- **`ConstantContactSyncService.applyEmailActivity(List<EmailCampaignDTO>)`** — the CC-agnostic core: upserts `CC_Email__c` by `CC_Campaign_Activity_Id__c` (resolving `CC_List__c` from the sent-to CC list ids via `Campaign.CC_List_Id__c`), upserts one `CC_Email_Activity__c` per recipient by `Activity_Key__c` (status = highest of Clicked/Opened/Bounced/Sent; flags + counts + dates), then **recomputes each affected Contact's rolling 90-day counters** (`Email_Opens/Clicks_Last_90_Days__c`) + last open/click dates via an aggregate over activities whose parent `Sent_Date__c` ≥ now−90. System-mode DML; partial-success; one `Integration_Log__c` ('Engagement Sync'). + 2 DTOs (`EmailCampaignDTO`, `ContactActivityDTO`).
- **`ConstantContactClient.getEmailCampaigns(since)`** — lists `/emails`, finds each `primary_email` activity, loads `/emails/activities/{caId}` (subject + `contact_list_ids`), merges the four `/reports/email_reports/{caId}/tracking/{sends|opens|clicks|bounces}` reports into one `ContactActivityDTO` per recipient (opens/clicks aggregated, first/last dates). Parsing isolated here; **VERIFY-AGAINST-LIVE** (shapes documented, not yet confirmed against a real payload — CC authorize pending).
- **`ConstantContactSyncQueueable('ENGAGEMENT')`** + `runEngagementSync()` (incremental cursor from the last Engagement Sync log; logs a Failed run on callout error).
- **`ConstantContactEngagementTest`** — 4 tests: direct applier (email+activity+CC_List+Contact counters), idempotent re-run + unmatched recipient, full poller path via `HttpCalloutMock`, callout-failure logging.
- **Deploy 4/4; tests 14/14 pass** (4 new + 10 existing unbroken); coverage Service 94% / Client 93% / Queueable 93% / Schedulable 100%.

**Phase 3 — reporting — ✅ BUILT & DEPLOYED 2026-07-20 (not committed).**
- **3 cross-object formula fields** on `CC_Email_Activity__c` (report types here can't dot-walk parent lookups — JSI-122 pattern): `Contact_Name__c` (`TRIM(BLANKVALUE(Contact__r.FirstName,"") & " " & Contact__r.LastName)` — note `Contact__r.Name` compound isn't formula-accessible cross-object), `Email_Subject__c` (`CC_Email__r.Subject__c`), `Email_Sent_Date__c` (`CC_Email__r.Sent_Date__c`); read-only FLS on 5 profiles.
- **Custom report type `CC_Email_Engagement`** ("CC Email Engagement") on `CC_Email_Activity__c`.
- **3 reports** in the existing **Constant Contact Reports** folder: **"Highly Engaged Constituents"** (ContactList, `Email_Opens_Last_90_Days__c` ≥ 3, sorted desc) + **"Disengaged Constituents (Subscribed)"** (ContactList, opens = 0 AND not opted-out AND Subscribed) — DoD #3 — plus **"Email Engagement by Contact"** (custom type, Summary grouped by email subject) showing who opened/clicked each send.
- Deploy: fields 3/3, FLS 5/5, report type 1/1, reports 3/3 — all clean (report type deployed before the reports referencing it).

**Repo full-profile FLS sync — ✅ DONE 2026-07-20:** the new field/object permissions inserted into all 5 full profile files (contiguous, XML-validated) so source matches the org.

**Phase 4 — UI (Jason, App Builder) — ✅ DONE + RETRIEVED 2026-07-20 (not committed).** Jason built the record pages; retrieved to source: **`Contact_Record_Page`** (added a dynamic related list on `CC_Email_Activities__r` — the constituent's recent email activity, DoD #1); new **`CC_Email_Record_Page`** (`CC_Email__c` — highlights + fields + Email Activities related list); new **`CC_Email_Activity_Record_Page`** (`CC_Email_Activity__c` — highlights + fields). Page→record-type assignments are App-Builder activation (not source-tracked), Jason's. **⏳ DLRS rollups** (`Total_*` on `CC_Email__c`) still Jason's to wire.

**Remaining:** DLRS rollups (Jason) · Phase 5 live verify + schedule (blocked on the shared CC authorize) · commit + push.
