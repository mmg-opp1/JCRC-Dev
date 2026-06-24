# JSI-89 — Implementation Plan: Tribute & Memorial Gifts with Notifications

> **Story:** [JSI-89](https://missionmattersgroup.atlassian.net/browse/JSI-89) — see [`JSI-89_User_Story.md`](./JSI-89_User_Story.md)
> **Author:** Jason Ott · **Drafted:** 2026-06-24
> **Org verified:** `JCRC-Dev` (`jcrcny@missionmattersgroup.com.dev`), NPSP 3.237

---

## 1. Summary & Verdict

**This story is ~80% native NPSP.** NPSP ships a complete **Honoree / Tribute /
Notification-Recipient** field set on the Opportunity, and all of those fields already
exist in this org. The work is therefore **mostly configuration and surfacing**, not
field creation, plus **two net-new pieces** that fall outside standard NPSP:

1. **Per-record-type Lightning record pages** — create dedicated pages for the five
   donation-side record types (today they all share one generic page), surfacing a
   **Tribute & Notification** section on the gift types that need it (see §8).
2. **Online-donation intake → contact-matching automation** — resolve free-text honoree /
   notification names from an online gift into the NPSP Contact lookups (see §5).
3. **Letter generation** (batch, fund/campaign-customized, Hebrew-capable) is **not an NPSP
   capability** and needs a tooling decision (see §6).

Nothing in the story **contradicts** NPSP. The only DoD items NPSP cannot satisfy on its own
are the *letter production* requirements; everything else maps to standard fields/behavior.

---

## 2. NPSP tribute model in this org (single-tribute, inline)

This org does **not** have the `npsp__Tribute__c` object, so it uses NPSP's **single-tribute
inline model**: one honoree + one notification recipient stored directly in fields on the
Opportunity. NPSP's optional **Multiple Tributes** feature (separate Tribute object, many per
gift) is **not enabled**.

- ✅ Sufficient if a gift honors **one** person at a time (the norm for tribute/memorial gifts).
- ❓ **Confirm** JCRC never needs multiple honorees on a single gift. Enabling Multiple
  Tributes later is a settings change but changes the data model and page design, so decide now.

---

## 3. Field mapping — DoD requirement → NPSP field (all already present)

All fields below exist on **Opportunity** today (verified via describe). Picklist values are
the **actual managed-package values** in this org.

| DoD requirement | NPSP field (API) | Type | Notes |
|---|---|---|---|
| Tribute type (in honor of / in memory of) | `npsp__Tribute_Type__c` | Picklist | Values: **Honor, Memorial** — matches DoD intent (label, not "in honor of") |
| Honoree (as contact) | `npsp__Honoree_Contact__c` | Lookup → Contact | Stewardship link (DoD: "retained as related contacts") |
| Honoree (as raw text) | `npsp__Honoree_Name__c` | Text(255) | Online-gift intake target (§5) |
| Honoree extra detail | `npsp__Honoree_Information__c` | Long Text(32768) | Free-form |
| Notification recipient (as contact) | `npsp__Notification_Recipient_Contact__c` | Lookup → Contact | |
| Notification recipient (as raw text) | `npsp__Notification_Recipient_Name__c` | Text(255) | Online-gift intake target (§5) |
| Notification address (differs from donor) | `npsp__Notification_Recipient_Information__c` | Text Area | Mailing address/notes distinct from donor |
| Notification email | `npsp__Notification_Recipient_Email__c` | Email | |
| Notification channel | `npsp__Notification_Preference__c` | Picklist | Values: **Email, Postal Mail, Phone, Do Not Notify** |
| Notification message | `npsp__Notification_Message__c` | Long Text(32768) | |
| Notification status (pending / sent) | `npsp__Tribute_Notification_Status__c` | Picklist | Values: **To Be Notified, Notified** (NPSP's labels for pending/sent) |
| Notification date | `npsp__Tribute_Notification_Date__c` | Date | When notified |

**Field gaps: none.** No custom fields need to be created for the *tracking* portion of the DoD.

> **MMG note answered:** tributes are **both** — a Contact lookup *and* text. This is exactly
> what enables the online-gift pattern in §5.

---

## 4. Notification status & review process

- "Pending / Sent" → `Tribute_Notification_Status__c` = **To Be Notified → Notified**, with
  `Tribute_Notification_Date__c` stamped when sent. No new fields needed.
- ❓ **Review process (JCRC note):** Decide whether a gift officer **reviews/approves**
  tribute notifications before they go out. Options:
  - **Manual:** staff flip status to "Notified" after mailing (simplest; no build).
  - **Review queue:** a report/list view of `To Be Notified` tributes as the work queue
    (recommended, no build — see §7).
  - **Approval flow:** only if a formal sign-off is required (heavier; likely overkill).

---

## 5. Online-donation intake → contact matching (net-new automation)

**Requirement (from dictation):** an online gift won't know the Salesforce Contact. The donor
types honoree/notification **names as text**; those sync into the Opportunity text fields, and
**an after-the-fact process resolves the Contact lookups**.

**Design:**
1. **Intake (text):** online platform maps honoree name → `npsp__Honoree_Name__c` and
   notification name → `npsp__Notification_Recipient_Name__c` (+ email/address into the
   `…_Email__c` / `…_Information__c` fields). These are plain text — no contact required at
   ingest. ✅ supported by existing fields.
2. **Resolution (lookup):** a **record-triggered Flow** (or scheduled batch) on Opportunity
   that, when an honoree/notification **name is present but the Contact lookup is empty**,
   attempts to match an existing Contact by name (and email where available) and populates
   `npsp__Honoree_Contact__c` / `npsp__Notification_Recipient_Contact__c`.
   - **Match found (unique):** set the lookup.
   - **No / ambiguous match:** leave lookup blank and flag for manual review (e.g., a checkbox
     or task), so staff can confirm or create the Contact. Auto-creating Contacts from
     free-text names risks duplicates — **prefer match-or-flag over auto-create**.

🚩 **CLIENT CONFIRMATION:** which **online donation platform** is in use, and how does it pass
honoree/notification data? This determines the field mapping and whether matching can also key
on email (far more reliable than name alone). Until confirmed, the resolution flow is designed
but not built.

> Aligns with [[reference-sf-metadata-gotchas]]: Flow entry conditions take only direct fields
> (no dot notation / formulas) — name-vs-lookup logic goes in a **Decision** element in the
> flow body. Avoid hardcoded IDs.

---

## 6. Letter generation — OUT of native NPSP scope 🚩

NPSP **tracks** tribute notifications; it does **not produce documents**. These DoD items need
a tool, not configuration:

- "Tribute notification letters generated as a **batch process**"
- "Letters **customized** by **fund or campaign**"
- JCRC note: **Hebrew fonts** in letters

**Options (client/tooling decision):**
| Option | Fit | Notes |
|---|---|---|
| **Conga Composer / similar AppExchange merge** | Batch + templated | Paid; mature; handles fonts via Word/PDF templates |
| **Flow + Visualforce/email templates** | Light | Native, but limited layout/font control; Hebrew RTL is fragile |
| **Export → external mail house / Word mail-merge** | Manual batch | No platform build; relies on a report (see §7) as the data source |

**Hebrew fonts** are a *document-template* concern (the merge tool / Word template must embed a
Hebrew font and handle RTL), **not** a Salesforce field concern. Salesforce stores the data as
Unicode regardless.

**Recommendation:** treat letter production as a **separate decision/sub-task**. The
Salesforce side delivers the tracked data + a "ready to notify" report (§7) that feeds whatever
merge tool is chosen. Confirm scope with the client before committing to a tool.

---

## 7. Reports — "gifts by honoree" + notification work queue

Native reporting covers the DoD with no custom report type required (Opportunity standard
report type exposes the tribute fields):

1. **Tribute Gifts by Honoree** — Opportunities grouped by `Honoree_Contact__c` (and/or
   `Honoree_Name__c` for unresolved text), filtered to records where a tribute type is set.
2. **Tributes To Be Notified** (work queue / review list) — filter
   `Tribute_Notification_Status__c = To Be Notified`; this doubles as the §4 review queue and
   the §6 letter-merge data source.
3. *(Optional)* **Memorial vs. Honor split** — grouped by `Tribute_Type__c`.

Deliver as version-controlled `report-meta.xml` in a **Tribute_Gifts_Reports** report folder
("Tribute and Memorial Gift Reports"), following the JSI-82 pattern. Per
[[reference-sf-metadata-gotchas]]: standard `Opportunity` report type → standard fields use
**tokens** (`OPPORTUNITY_NAME`, `ACCOUNT_NAME`, `AMOUNT`, `CLOSE_DATE`); npsp fields use
`Opportunity.<apiName>`; for the honoree grouping, group on the field, don't also list it as a
column.

**Built & deployed 2026-06-24:**
- **Tribute Gifts by Honoree** (Summary) — grouped by `npsp__Honoree_Contact__c`; columns
  Opportunity Name, Account, Tribute Type, Honoree Name, Amount (Σ), Close Date; filtered to
  `npsp__Tribute_Type__c` ≠ blank. Honoree Name column surfaces text-only (unmatched) honorees.
- **Tributes To Be Notified** (Tabular work queue) — filter `Tribute_Type__c` ≠ blank **AND**
  `Tribute_Notification_Status__c` = "To Be Notified" **AND** `Notification_Preference__c` ≠
  "Do Not Notify"; columns include the recipient name/email/info + preference so it doubles as
  the letter-merge data source (§6).

---

## 8. Lightning record page architecture (primary build)

### 8.1 Current state (verified in `force-app`)

Only **two** Opportunity record types have a dedicated Lightning record page; the other five
fall back to the generic page:

| Record Type | Business Process | Current record page | Tribute/Notification today |
|---|---|---|---|
| **Pledge** | Pledge_Process | `Pledge_Record_Page` | ✅ **Full section already present** (all 12 fields) |
| **Grant** | Pledge_Process | `Grant_Record_Page` | — (correct; grants don't take tributes) |
| **NPSP_Default** (Donation) | Donation_Process | *generic* `Opportunity_Record_Page_Three_Column` | ❌ none |
| **Major_Gift** | Donation_Process | *generic* Three-Column | ❌ none |
| **Matching_Gift** | Donation_Process | *generic* Three-Column | ❌ none |
| **In_Kind_Gift** | Donation_Process | *generic* Three-Column | ❌ none |
| **Securities_Gift** | Donation_Process | *generic* Three-Column | ❌ none |

> **Correction to earlier analysis:** the Pledge page already carries the **complete** Tribute
> **and** Notification field set (Honoree contact/name/info, Tribute Type/Status/Date,
> Notification Preference, Recipient contact/name/email/info, Message) under its "Tribute
> Information" section. **No change to the Pledge page is required** — the "add notification
> fields to Pledge" ask is already satisfied. (I'll confirm with Jason before touching it.)

### 8.2 Target — create five dedicated record pages

Extend the established per-type pattern (Pledge_Record_Page / Grant_Record_Page). Build five
new `flexipage-meta.xml` files **in Jason's Pledge/Grant format** — `recordHomeWithSubheader`
template, `dynamicHighlights` header (with the Manage Soft Credits action), path in the
subheader, a **Details** tab of two-column field sections, plus **Accounting** (GAU
Allocations), **Soft Credits**, and **Other Related Information** tabs, and an **Activity**
sidebar. (Payments tab dropped — one-time gifts aren't scheduled.) Differentiated per type:

| New page | For record type | Tribute & Notification section? | Type-specific section |
|---|---|---|---|
| `Donation_Record_Page` | NPSP_Default | ✅ **Yes** | — (standard donation) |
| `Major_Gift_Record_Page` | Major_Gift | ✅ **Yes** | Cultivation: `Approach__c`, `npsp__Gift_Strategy__c`, `npsp__Ask_Date__c`, `npsp__Qualified_Date__c`, `Budget_Confirmed__c`, `Discovery_Completed__c`, `ROI_Analysis_Completed__c`, `Loss_Reason__c` |
| `Matching_Gift_Record_Page` | Matching_Gift | ✅ **Yes** | Matching: `npsp__Matching_Gift_Account__c`, `npsp__Matching_Gift_Employer__c`, `npsp__Matching_Gift_Status__c`, `npsp__Matching_Gift__c` |
| `In_Kind_Gift_Record_Page` | In_Kind_Gift | ❌ **No** | In-Kind: `npsp__In_Kind_Type__c`, `npsp__In_Kind_Description__c`, `npsp__In_Kind_Donor_Declared_Value__c`, `npsp__Fair_Market_Value__c` |
| `Securities_Gift_Record_Page` | Securities_Gift | ❌ **No** | Securities valuation: `npsp__Fair_Market_Value__c` (+ any securities fields confirmed) |

### 8.3 The reusable "Tribute & Notification" section

Mirror the Pledge page's proven two-column section (so all tribute UIs are identical). Added
verbatim to the three "Yes" pages above:

- **Column 1 — Tribute / Honoree:** `npsp__Tribute_Type__c`, `npsp__Honoree_Contact__c`,
  `npsp__Honoree_Name__c`, `npsp__Honoree_Information__c`,
  `npsp__Tribute_Notification_Status__c`, `npsp__Tribute_Notification_Date__c`
- **Column 2 — Notification recipient:** `npsp__Notification_Preference__c`,
  `npsp__Notification_Recipient_Contact__c`, `npsp__Notification_Recipient_Name__c`,
  `npsp__Notification_Recipient_Email__c`, `npsp__Notification_Recipient_Information__c`,
  `npsp__Notification_Message__c`

**Decision (locked 2026-06-24):** section is **always visible** (mirrors the Pledge page) —
no component-visibility filter.

### 8.4 ⚠️ Page-to-record-type assignment is NOT in source metadata

Verified: no metadata file in `force-app` references the existing page names — Lightning page
**assignments are UI-managed** (Lightning App Builder → *Activation*), exactly the JSI-82
carryover lesson. So the build splits cleanly along our normal division of labor:

- **Claude:** author + deploy the five `flexipage-meta.xml` files (version-controlled).
- **Jason (UI):** in App Builder, **assign** each new page to its record type (App default,
  and/or record-type + profile) so the right page loads. Deploying the flexipage alone does
  **not** route any record type to it.

### 8.5 Classic layout (optional)

If any profile still uses the classic page layout (`Opportunity-Opportunity Layout`, which has
no tribute fields), mirror the Tribute & Notification section there too. Lightning is assumed
primary; treat classic as a follow-up only if needed.

---

## 9. Build task summary

| # | Task | Type | Owner | Status |
|---|---|---|---|---|
| 1 | Build `Donation_Record_Page` (+ Tribute & Notification) (§8.2/8.3) | Flexipage | Claude | ✅ **Deployed** 2026-06-24 |
| 2 | Build `Major_Gift_Record_Page` (+ Tribute & Notification + Cultivation) | Flexipage | Claude | ✅ **Deployed** |
| 3 | Build `Matching_Gift_Record_Page` (+ Tribute & Notification + Matching) | Flexipage | Claude | ✅ **Deployed** |
| 4 | Build `In_Kind_Gift_Record_Page` (no tribute; in-kind fields) | Flexipage | Claude | ✅ **Deployed** |
| 5 | Build `Securities_Gift_Record_Page` (no tribute) | Flexipage | Claude | ✅ **Deployed** |
| 6 | **Assign** each new page to its record type in App Builder (§8.4) | UI / Activation | **Jason** | ⏳ **Pending (Jason)** |
| 7 | Pledge page — **no change** (already complete); confirm only (§8.1) | — | Jason | ⏳ confirm |
| 8 | "Tribute Gifts by Honoree" + "To Be Notified" reports (§7) | Metadata | Claude | ✅ **Deployed** 2026-06-24 |
| 9 | Online-gift text→Contact matching flow (§5) | Flow | Claude | ⛔ blocked (#10) |
| 10 | Confirm online platform + field mapping (§5) | Decision | Client | ⛔ open |
| 11 | Notification review process choice (§4) | Decision | Client | ⛔ open |
| 12 | Letter-generation tooling decision + build (§6) | Tooling | Client / TBD | ⛔ open (not NPSP) |
| 13 | Confirm single vs. multiple tributes (§2) | Decision | Client | ⛔ open |

**Done:** #1–#5 (five record pages deployed). **Next:** Jason assigns pages (#6); Claude can
build reports (#8) in parallel. **Blocked on client:** #9–#13.

### 9.1 Build log
- **2026-06-24 (v1)** — Created 5 pages by cloning `Opportunity_Record_Page_Three_Column`
  (deploy `0AfiI0000000rkHSAQ`, 5/5). Superseded — wrong base (generic sales page, not Jason's
  NPSP format).
- **2026-06-24 (v2, current)** — **Rebuilt to match the Pledge/Grant format** (deploy
  `…`, 5/5, 0 errors): `recordHomeWithSubheader` template, `dynamicHighlights` header (Manage
  Soft Credits action), path subheader, Details tab (Opportunity Information + type-specific +
  Tribute & Notification where applicable + System/Description), and Accounting / Soft Credits /
  Other Related Information tabs + Activity sidebar. Payments tab dropped. All field references
  validated against the live schema. **Not yet assigned to record types** — Jason activates in
  App Builder (§8.4). Gotchas: (1) `&` in the "Tribute & Notification" label must be XML-escaped
  (`&amp;`); (2) the generic Three-Column page is the wrong clone base for NPSP donation pages —
  use the Pledge/Grant structure.
- **2026-06-24 (reports)** — Created `Tribute_Gifts_Reports` folder + 2 reports (Tribute Gifts
  by Honoree, Tributes To Be Notified). Deployed 3/3, 0 errors. Standard `Opportunity` report
  type; npsp fields via `Opportunity.<api>`; "not blank" filter via `notEqual` + empty value.

---

## 10. Open / client-confirmation items (carryover)

- 🚩 **Letter generation tool** (§6) — not native NPSP; Hebrew-font + fund/campaign
  customization decision.
- 🚩 **Online donation platform & field mapping** (§5) — drives the matching automation.
- ❓ **Notification review process** (§4) — manual vs. queue vs. approval.
- ❓ **Single vs. multiple tributes** (§2) — confirm before page design is finalized.
- ❓ **Status label mismatch** — DoD says "pending / sent"; NPSP uses "To Be Notified /
  Notified." Confirm staff are fine with NPSP's labels (recommended — don't fork the managed
  picklist) or whether report/letter wording should translate them.
- ⚠️ **Lightning page assignment (Jason, post-deploy)** (§8.4) — the five new pages must be
  assigned to their record types in App Builder; deploying the flexipages does not route any
  record type to them. (Same class of item as the JSI-82 page-assignment carryover.)

**Decisions locked 2026-06-24:** (1) **new** `Donation_Record_Page` for NPSP_Default (don't
edit the shared Three-Column page); (2) each new page includes its **type-specific** field
section; (3) Tribute & Notification section **always visible**.

---

*Change Log*
*2026-06-24 — Jason Ott — Initial plan: NPSP gap analysis, field mapping, online-intake matching design, letter-gen and page-placement decisions.*
