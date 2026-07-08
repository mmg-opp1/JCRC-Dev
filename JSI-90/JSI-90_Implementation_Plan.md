# JSI-90 — Implementation Game Plan: Major Donor Moves Management

> **Status:** Plan / research — no build yet (framework-first; client is still finalizing levels).
> **Author:** Jason Ott · **Date:** 2026-07-01
> **Related:** `JSI-90_User_Story.md`, `JSI-90_StoryDictationNotes.MD`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-90

---

## 1. Scope

This story has **three distinct builds**. The dictation is the source of intent (it expands well
beyond the Jira DoD).

**IN scope (this story):**
- **A — Engagement Planning (NPSP-native):** enable Engagement Plans, seed **placeholder** templates +
  example tasks, surface Engagement Plans on the record pages, staying close to NPSP standards.
- **B — Giving-Levels engine (custom):** a configurable, fiscal-year giving-tier system —
  `Giving_Level__c` config, `Annual_Giving_Summary__c` per-donor-per-year accumulator,
  `Gift_Allocation__c` junction (hard + soft credit), level inheritance, expiring override, and
  date-achieved tracking. **Framework built now; level values filled by the client later.**
- **C — Gift Officer Assignment (custom):** a `Gift_Officer_Assignment__c` junction (User ↔ Contact)
  with a role (Primary / Backup / Solicitor / Committee).

**OUT of scope (deferred):**
- **Moves-management STAGES — deferred to a client decision (2026-07-01).** The client must first
  decide whether moves management belongs on major **GIFTS** (an Opportunity stage pipeline) or on
  major **DONORS** (a Contact-level cultivation pipeline). We will **not** build a `Major_Gift_Process`
  / new stages until that framing is settled — the two answers are materially different builds. (Was
  briefly started this session, then correctly deferred: the Major Gift Opp currently keeps
  `Donation_Process` unchanged.) See §2 D9.
- Reports (prospects by stage / ask amount / overdue next actions) — Jira DoD #4.
- Dashboard for the development director — Jira DoD #5.
- **Confidential officer-only notes — deferred (2026-07-01, Jason)** — Jira DoD #6.
- The Major Gift record type + Tasks — **already delivered** (JSI-82 record type; native Activities).

**Framework-first principle:** the client has not finalized levels, template content, or role lists.
Everything client-dependent is **data-configurable** (records, picklist values, thresholds) so we
build the engine now and the client populates values without a code change.

---

## 2. Decisions to confirm (design forks)

| # | Fork | Recommendation |
|---|------|----------------|
| D1 | Levels engine: **custom** vs NPSP Levels (`npsp__Level__c`) | **Custom.** NPSP Levels can't do July–June years, per-year records, date-achieved, inheritance, or an expiring override (see §4.1). Use NPSP Levels only as a reference. |
| D2 | Date-achieved: **N date fields on the summary** (admin adds a field per level) vs a child Level-Achievement record | ✅ **DECIDED 2026-07-01 — N date fields on the Annual Giving Summary** (one `Date_Achieved_<Level>__c` per level, per the dictation). **Admin note:** adding a new level requires creating a new date field **and** extending the achievement automation to populate it — documented in the Build Runbook. |
| D3 | Annual Giving Summary grain | **Contact** (design kept extendable to Household Account). |
| D4 | Level config store | **`Giving_Level__c` custom object** (admin-editable records) — fully data-configurable. |
| D5 | Does **soft credit** count toward level qualification? | **Combined hard + soft** qualifies; keep the two totals as separate fields. |
| D6 | Gift Officer Assignment cardinality | **Junction with a Role picklist** (Primary / Backup / Solicitor / Committee) + Active flag — supports the "multiple relationships" ask. |
| D7 | New-year summary creation | **Hybrid:** a **July-1 scheduled batch** creates next-year summaries and links them to the prior year (for inheritance); plus **lazy creation** by the gift-allocation flow if a gift arrives for a donor with no current-year summary. |
| D8 | Confidential notes (Jira DoD #6) | ✅ **DEFERRED (2026-07-01, Jason)** — out of scope this story. |
| D9 | Moves-management **stages**: on major GIFTS (Opportunity stage pipeline) vs on major DONORS (Contact-level pipeline) | 🔜 **DEFERRED TO CLIENT (2026-07-01).** No `Major_Gift_Process`/stage build until the client picks the model. Verified org facts for when it resumes: **0 existing Major Gift opps** (safe to restage); `OpportunityStage` SVS already has **Qualification** + a **Declined** lost path; Major Gift keeps `Donation_Process` for now. If Opportunity-model chosen, also settle the Won/Closed mapping (which stage = gift received/rolls up). |

---

## 3. Verified org context (checked against JCRC-Dev, 2026-07-01)

| Fact | Evidence | Implication |
|------|----------|-------------|
| **Org fiscal year = January** | `Organization.FiscalYearStartMonth = 1` (SOQL) | SF fiscal-year functions ≠ JCRC's July–June giving year. **Do not** rely on them; **do not** change the org FY (breaks reports/forecasting). |
| **NPSP rollups are calendar-based** | `npo02__Use_Fiscal_Year_for_Rollups__c = false` (SOQL) | `npo02__OppAmountThisYear__c` etc. total Jan–Dec — unusable as a July–June level source. |
| **NPSP Levels present** | `objects/npsp__Level__c` (Min/Max Amount, Source_Field, Target, Level_Field, Previous_Level_Field, Engagement_Plan_Template) | Native levels exist but don't fit (see §4.1) — build custom. |
| **NPSP Engagement Plans present, unused** | `npsp__Engagement_Plan__c/_Template__c/_Task__c` in repo; **0 template records** (SOQL); no EP flexipages/layouts | Enable + seed placeholder templates; add UI. |
| **`Major_Gift` Opportunity record type exists + active** | `objects/Opportunity/recordTypes/Major_Gift` (JSI-82) | Reuse; only verify stages. |
| **Only 2 hand-built custom objects today** (`Tag__c`, `Tag_Assignment__c`) | `force-app` scan | JSI-90's custom objects are greenfield — mirror the JSI-122 junction conventions. |
| **No gift-officer / portfolio / moves fields anywhere; 0 custom Contact fields** | `force-app` scan | Net-new; JSI-90 sets the Contact custom-field precedent. |
| **JSI-85 soft-credit infra in place** | `Opportunity_MatchedDonor_SoftCredit` flow; NPSP OCR + soft-credit rollups | The Gift-Allocation flow **reuses OCR/soft-credit** to know who gets soft credit. |

---

## 4. Design

### 4.1 Why custom, not NPSP Levels (the core decision)

NPSP Levels (`npsp__Level__c`) writes a **single current-level** value (+ one previous-level value)
onto Contact/Account from a **source rollup field**, recalculated by a nightly batch. It **cannot**
express five JSI-90 requirements:

| JSI-90 requirement | NPSP Levels | Custom engine |
|---|---|---|
| **July 1–June 30** giving year | ❌ uses org FY (Jan) / calendar | ✅ each gift is allocated to the correct year's summary |
| A **record per donor per year** (history) | ❌ one field on the contact | ✅ `Annual_Giving_Summary__c` per year |
| **Date-achieved** per level | ❌ none | ✅ `Level_Achievement__c` child (or date fields) |
| **Inheritance** (hold level +1 year) | ❌ only "previous level" value | ✅ prior-year self-link + `MAX(earned, prior)` |
| **Expiring override** (not carried forward) | ❌ none | ✅ `Level_Override__c` on the year record only |

> **Key architectural win:** because each gift's credit is written to a `Gift_Allocation__c` that
> points at a **specific** `Annual_Giving_Summary__c` (one July–June year), the yearly totals are just
> a **rollup of that summary's child allocations** — **no fiscal-year date math and no dependence on
> the org's January fiscal setting.** The year is decided once, at allocation time, from the gift's
> Close Date.

### 4.2 Data model (net-new custom objects)

Conventions mirror JSI-122 (`Tag_Assignment__c`): `deploymentStatus=Deployed`, `sharingModel` per
below, `enableReports/Search/BulkApi=true`, AutoNumber name on junction/log objects, every field
`description` ending with `JSI-90 / Jason Ott`.

**1. `Giving_Level__c`** *(config — admin-maintained records)*
| Field | Type | Notes |
|---|---|---|
| Name | Text | e.g. "Congressional", "Senate" |
| `Minimum_Amount__c` | Currency | inclusive `>=` (blank = catch-all bottom) |
| `Maximum_Amount__c` | Currency | exclusive `<` (blank = catch-all top) |
| `Sort_Order__c` | Number | rank low→high for comparisons |
| `Active__c` | Checkbox | |
| `Engagement_Plan_Template__c` | Lookup(`npsp__Engagement_Plan_Template__c`) | *optional* — auto-launch a plan on reaching this level (ties A↔B) |

*Name field = Text (like `Tag__c`). Sharing = ReadOnly public (config data).*

**2. `Annual_Giving_Summary__c` (AGS)** *(per donor, per fiscal year — the accumulator)*
| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber `AGS-{00000}` | |
| `Contact__c` | Lookup(Contact) | the donor (D3: Contact grain) |
| `Fiscal_Year_Label__c` | Text | e.g. "FY2027 (Jul 2026–Jun 2027)" |
| `FY_Start__c` / `FY_End__c` | Date | July 1 / June 30 bounds |
| `Prior_Year_Summary__c` | Lookup(self) | previous year's AGS (inheritance chain) |
| `Total_Hard_Credit__c` | Rollup/Currency | Σ hard `Gift_Allocation__c` |
| `Total_Soft_Credit__c` | Rollup/Currency | Σ soft `Gift_Allocation__c` |
| `Total_Giving__c` | Formula Currency | hard + soft (qualification total, D5) |
| `Earned_Level__c` | Text/Lookup | level earned from `Total_Giving__c` vs `Giving_Level__c` thresholds this year |
| `Prior_Effective_Level__c` | Formula | `Prior_Year_Summary__r.Effective_Level__c` |
| `Effective_Level__c` | Formula/field | **inheritance:** higher rank of Earned vs Prior-Effective (unless overridden) |
| `Level_Override__c` | Lookup/Picklist(`Giving_Level__c`) | manual override (D8: does **not** carry forward) |
| `Override_Reason__c` | Text(255) | |
| `Level_Display__c` | Formula | Override if set, else Effective — the "shown" level |
| `Date_Achieved_<Level>__c` | Date **(one per level)** | **D2 DECIDED — N date fields.** Close Date of the gift that pushed the donor over that level's threshold (e.g. `Date_Achieved_Congressional__c`, `Date_Achieved_Senate__c`). **Adding a level ⇒ add a new field + extend automation** (Runbook). |

**3. `Gift_Allocation__c`** *(junction: Opportunity ↔ AGS — hard & soft credit)*
| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber `GA-{00000}` | |
| `Opportunity__c` | Lookup(Opportunity) `Restrict` delete | the gift |
| `Annual_Giving_Summary__c` | Master-Detail(AGS) | rolls up to the year record |
| `Contact__c` | Lookup(Contact) | credited donor |
| `Credit_Type__c` | Picklist(restricted) | `Hard` / `Soft` |
| `Amount__c` | Currency | credited amount (hard = Opp Amount share; soft = OCR amount) |
| `Allocation_Key__c` | Text unique, ext-id, case-insensitive | `OppId|ContactId|CreditType` dedupe (JSI-122 idiom) |

**4. `Gift_Officer_Assignment__c`** *(junction: Contact ↔ User — the portfolio link; C)*
| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber `GOA-{0000}` | |
| `Contact__c` | Lookup(Contact) `SetNull` | the donor |
| `Gift_Officer__c` | Lookup(User) `SetNull` | internal staff |
| `Role__c` | Picklist(restricted) | Primary Gift Officer / Backup / Solicitor / Committee (D6) |
| `Active__c` | Checkbox | |
| `Assignment_Key__c` | Text unique, ext-id | `ContactId|UserId|Role` dedupe |

### 4.3 Automation

- **Gift Allocation creation** — record-triggered **after-save flow** on Opportunity (Closed Won),
  reusing the JSI-85 OCR/soft-credit pattern:
  1. Resolve the gift's **fiscal year** from Close Date (July–June) → find/create that donor's AGS
     (lazy creation, D7).
  2. Create a **Hard** `Gift_Allocation__c` for the primary contact.
  3. For each **soft-credit OCR** on the Opp, create a **Soft** allocation to that contact's AGS.
  4. Dedupe via `Allocation_Key__c`; recursion-safe (JSI-85/89 pattern).
- **Rollups** — `Total_Hard_Credit__c` / `Total_Soft_Credit__c` on AGS are **native Roll-Up Summary
  fields** (SUM of `Gift_Allocation__c.Amount__c` filtered by `Credit_Type__c` = Hard/Soft). *Chosen
  over DLRS because Gift Allocation is master-detail to AGS* — native RUS is real-time, delete/reparent-
  safe, needs no DLRS trigger artifacts, and is fully version-controlled. *(No fiscal-year filter
  needed — allocations are pre-scoped to the year.)* **Built in Phase 2.**
- **Level assignment + date-achieved** — when `Total_Giving__c` crosses a `Giving_Level__c` threshold,
  set `Earned_Level__c` and stamp that level's **`Date_Achieved_<Level>__c`** field (D2) with the
  crossing gift's Close Date. (Flow or Apex; Apex if the multi-level threshold scan gets heavy.
  Automation must be extended when a new level/date field is added.)
- **Inheritance** — `Effective_Level__c = higher rank of (Earned this year, Prior_Effective_Level)`.
  The **July-1 batch** creates each donor's new AGS and sets `Prior_Year_Summary__c`, so next year
  inherits *this* year's effective level; a level not re-earned drops the *following* year. Overrides
  are stored only on the year record and are **not** copied forward.
- **Engagement Plan on level** *(optional, ties A↔B)* — when `Level_Display__c` changes and the level's
  `Engagement_Plan_Template__c` is set, create an `npsp__Engagement_Plan__c` for the Contact.

### 4.4 Engagement Planning (A — NPSP native)

- Enable Engagement Plans (NPSP Settings). Seed **1–2 placeholder templates** (e.g. "Major Gift
  Cultivation") with example `npsp__Engagement_Plan_Task__c` rows across the moves stages
  (Identification → Stewardship) so staff see the mechanics; client redesigns later.
- **Templates are data, not metadata** — seed via `sf data` (documented in the Build Runbook), since
  Engagement Plan Templates aren't source-deployable customMetadata.
- **UI:** add the **Engagement Plans** related list to `Contact_Record_Page` and the `Major_Gift`
  Opportunity page (both `npsp__Engagement_Plan__c` lookups exist). Match the org's page conventions
  (`recordHomeWithSubheaderTemplateDesktop` for Opp; extend the NPSP Contact page).

### 4.5 Record pages (UI)

- **Contact:** add a **"Moves Management"** tab/section surfacing Gift Officer Assignments, the current
  Annual Giving Summary (level + totals), and Engagement Plans. (Contact page = `recordHomeTemplateDesktop`,
  extends `sfa__Contact_rec_L`; the JSI-122 `tagManager` LWC precedent shows how to embed custom UI.)
- **Annual Giving Summary / Gift Allocation / Gift Officer Assignment:** new Lightning record pages
  in the org's standard style; **page→record-type assignment is Jason's in App Builder** (not source).

---

## 5. Security & FLS

- New fields deployed **with FLS** (or invisible to admins, the Apex compiler, and reports — JSI-122
  gotcha). **Security is granted at the PROFILE level, not via a permission set** (JCRC org standard —
  the interim `JSI_90_Moves_Management` perm set was retired 2026-07-08). Object CRUD + FLS + class
  access to `GiftAllocationService`/`AnnualGivingSummaryRollover` are on **Admin (System Administrator)
  + JCRC - Development / Fundraising / Marketing / Volunteering**. Because this org's full profiles
  aren't source-deployable (JSI-86 gotcha — invalid tab settings), the grants were deployed via an
  **additive minimal-profile deploy** (stripped `<Profile>` files carrying only the new
  objectPermissions/fieldPermissions/classAccesses) and documented in the full repo profile files.
- Sharing: config objects (`Giving_Level__c`) public read-only; `Annual_Giving_Summary__c` /
  `Gift_Allocation__c` Public Read/Write initially (revisit if confidential-notes Q10 lands). Apex
  `with sharing` + `USER_MODE`.
- **Confidential notes (Q10)** — if in scope, model as a separate object/field with a **restricted
  sharing model** (Private + sharing to officer + supervisor role) rather than a plain field.

---

## 6. Reporting (deferred — noted only)

Reports (prospects by stage / ask amount / overdue) + the director dashboard are **deferred** per
dictation. The data model is built report-ready: AGS by level, Gift Allocations by year, Gift Officer
Assignments by officer (portfolio), Engagement Plan tasks by due date (overdue queue).

---

## 7. Phased build plan

**Phase 0 — Confirm forks (D1–D8) + client framing** *(this session — no build).*

**Phase 1 — Custom object model (B + C).** `Giving_Level__c`, `Annual_Giving_Summary__c`,
`Level_Achievement__c`, `Gift_Allocation__c`, `Gift_Officer_Assignment__c` + fields + validation
(dedupe keys, XOR where needed) + profile FLS (see §5 — perm set retired). Deploy, verify via anon Apex in a savepoint.

**Phase 2 — Level config + rollups.** Seed example `Giving_Level__c` records (Congressional/Senate +
base). Configure DLRS/Customizable Rollups for hard/soft totals. Verify totals.

**Phase 3 — Allocation + level automation.** After-save Opportunity flow (hard + soft allocations,
lazy AGS creation, dedupe). Level-assignment + date-achieved + inheritance logic. July-1 scheduled
batch for carry-forward. Verify with anon Apex (savepoint→rollback): gift → allocation → total →
level → achievement date → next-year inheritance → override-not-carried.

**Phase 4 — Gift Officer Assignment UI + Engagement Plans (A).** Enable Engagement Plans; seed
placeholder templates/tasks; add EP related lists + Moves Management section to Contact/Major Gift
pages; new record pages for the custom objects.

**Phase 5 — Verify, document, commit.** Build Log; update `project-jcrc-story-pipeline` +
`reference-sf-metadata-gotchas` memories. Commit **only JSI-90 files**; push on request.

---

## 8. Net-new metadata (anticipated)

**4** custom objects (`Giving_Level__c`, `Annual_Giving_Summary__c`, `Gift_Allocation__c`,
`Gift_Officer_Assignment__c` — no separate achievement object per D2) (+ ~30 fields incl. the N
`Date_Achieved_<Level>__c` fields), 3–4 validation rules, 3 restricted picklists, 1–2 record-triggered
flows (+ 1 scheduled flow/Apex), possibly 1 Apex class + test (level-threshold scan) — **JCRC's Apex
pattern reuse from JSI-89**, DLRS rollup configs (Jason), 1 permission set, 3–4 flexipages, seeded
`Giving_Level__c` + Engagement Plan template data.

---

## 9. Risks & watch-outs

- **Scope creep / client unknowns** — mitigated by framework-first + data-config. Don't hard-code
  level names/thresholds.
- **Fiscal-year confusion** — the whole engine is July–June; never use SF `FISCAL_YEAR()` or NPSP
  "this year" fields. Allocations carry the year.
- **Double-counting** — dedupe via `Allocation_Key__c`; hard vs soft kept distinct; reuse JSI-85 OCR
  de-dupe learnings.
- **Date-achieved on backdated/edited gifts** — recompute achievement dates when allocations change;
  define "the gift that crossed the threshold" deterministically (earliest Close Date reaching the
  cumulative total).
- **Inheritance vs override interaction** — override applies to the display for its year only; the
  *earned* level (not the override) is what the next year inherits. Nail this in tests.
- **Engagement Plan templates are data** — not in source control; document the seed in the Runbook.
- **DLRS on a new object** — auto-generates a trigger + test (like `dlrs_npe01_OppPayment*`); expect
  new managed artifacts on retrieve.

---

## 10. Sources

- NPSP Levels mechanics — [npcrowd: Configure & Use NPSP Levels](https://npcrowd.com/npsp-levels-configure-use/)
  (nightly *NPSP 08 – Level Assignment Updates* batch; Min `>=` / Max `<`; Source/Target/Level/Previous-Level fields; optional Engagement Plan).
- NPSP Engagement Plans + Levels for moves management —
  [Trailhead: Engagement Plans and Levels (NPSP)](https://trailhead.salesforce.com/content/learn/modules/engagement-plans-and-levels-npsp/create-and-manage-engagement-plans) ·
  [Cloud4Good](https://cloud4good.com/announcements/npsp-engagement-plans-levels/) ·
  [Idealist Consulting: Step it up — NPSP Levels for moves management](https://idealistconsulting.com/blog/step-it-how-use-npsp-levels-moves-management).
- Moves-management architecture (custom Engagement Profile / stage + engagement plans) —
  [Soliant Consulting: NPSP Donor Moves Management](https://www.soliantconsulting.com/blog/salesforce-npsp-donor-moves-management/).
- Levels as annual-giving tiers (Bronze/Silver/Gold example) —
  [DNL OmniMedia: NPSP Ultimate Guide](https://www.dnlomnimedia.com/resources/salesforce-nonprofit-success-pack/) ·
  [Soapbox Engage: Create Levels](https://www.soapboxengage.com/blog/1559-create-levels-to-track-and-cultivate-sustaining-donors-in-the-salesforce-nonprofit-success-pack).
- Org verification (2026-07-01): `Organization.FiscalYearStartMonth=1`,
  `npo02__Households_Settings__c.npo02__Use_Fiscal_Year_for_Rollups__c=false`, `npsp__Level__c` present,
  0 Engagement Plan Templates, `Major_Gift` record type active — all via `sf data query` on JCRC-Dev.

---

## 11. Build Log

*(filled as we deploy — Phase, component, deploy result, verification.)*
- 2026-07-01 — Plan + User Story authored; org research complete.
- 2026-07-01 — **Forks settled (Jason):** D1 = **custom engine**; D2 = **N date fields on the summary**
  (admin adds a field + extends automation per new level); D3 = **Contact grain**; D5 = **combined
  hard + soft qualifies** (Total Hard / Total Soft kept separate). D4/D6/D7 proceeding on the
  recommended options (Giving_Level__c config object; Gift Officer junction w/ Role picklist; hybrid
  July-1 batch + lazy AGS creation).
- 2026-07-01 — **D8 confidential notes = DEFERRED** (Jason). **D9 moves-management stages = DEFERRED
  TO CLIENT** — reframed as *major GIFTS vs major DONORS* moves management; briefly explored a
  `Major_Gift_Process` (5 story stages + Won/Closed mapping) but pulled back pending the client's
  model choice. Verified: 0 Major Gift opps, `OpportunityStage` already has Qualification + Declined,
  Major Gift stays on `Donation_Process`. **No stage metadata built.**
- Ready to build the Phase-1 custom-object model (Giving-Levels engine + Gift Officer Assignment) on
  go-ahead. Client-side open: D9 stage model, final level values (Q8), EP template content (Q9).
- 2026-07-01 — **PHASE 1 BUILT, DEPLOYED & VERIFIED to JCRC-Dev.** 4 custom objects + 28 fields + 4
  validation rules + `JSI_90_Moves_Management` perm set (41 components). Verified via anon Apex
  (savepoint→rollback): `Total_Giving` formula = 6000; `Level_Display` = Effective (Congressional)
  then Override (Senate); hard+soft Gift Allocations; Gift Officer Assignment; and all 5 negative
  checks blocked (unique `Allocation_Key`, `Max_After_Min`, `Valid_Fiscal_Dates`, `Amount_Not_Negative`,
  `Officer_Required`). Nothing persisted.
  **Deploy learnings (→ gotchas memory):** (1) a **Lookup to `User` can't be a *required* foreign key** —
  it rejects both cascade/Restrict *and* required-without-a-constraint; made `Gift_Officer__c` optional
  + enforced by an `Officer_Required` validation rule. (2) A deployed **permission set must be
  *assigned* to the running user** before anon-Apex will compile against the new fields (FLS gotcha) —
  assigned `JSI_90_Moves_Management` to the admin to verify.
  **⏳ Carryover:** Phase 3 (allocation + level automation); Phase 4 (UI + Engagement Plans).
  Perm set still to be assigned to the actual moves-management users.
- 2026-07-01 — **PHASE 2 BUILT, DEPLOYED & VERIFIED.** (1) Converted `Total_Hard_Credit__c` /
  `Total_Soft_Credit__c` from plain Currency to **native Roll-Up Summary** fields (SUM of Gift
  Allocation Amount filtered by Credit Type) — since the type can't change in place, deleted the two
  fields + the dependent `Total_Giving__c` formula, then recreated all three (rollups + formula);
  perm set updated so the rollups are read-only. (2) Seeded 3 example `Giving_Level__c` records: **Base**
  (0–4,999.99), **Congressional** (5,000–9,999.99), **Senate** (10,000+) — inclusive min / exclusive
  max, admin-editable, values are placeholders pending the client. Verified via anon Apex
  (savepoint→rollback): hard 5000 + soft 1000 → Total Hard=5000, Soft=1000, Total Giving=6000; after
  deleting the soft allocation → Soft=0, Total Giving=5000 (rollups are delete-safe). **Learning:** a
  field type **cannot be converted to Roll-Up Summary in place** ("Cannot update a field to a Summary
  from something else") — delete + recreate, removing dependent formulas first.
  **Seed data note:** the 3 `Giving_Level__c` records live in the org as data (not source metadata),
  like Engagement Plan templates — re-seed with the CLI commands in this log if refreshing a new org.
- 2026-07-01 — **PHASE 3 BUILT, DEPLOYED & VERIFIED (the automation core).**
  - **`GiftAllocationService`** (invocable Apex, `with sharing`, system-mode DML per JSI-89 precedent) —
    on a Closed/Won opp: resolves the July–June fiscal year from Close Date, finds/creates the donor's
    Annual Giving Summary (lazy, links prior year), creates a **Hard** allocation for the primary
    contact + a **Soft** allocation for each OCR in the JSI-85 soft set (Soft Credit / Household Member
    / Matched Donor), **excludes In-Kind**, dedupes via upsert on `Allocation_Key__c`, then sets
    Earned/Effective level (inheritance = higher rank of earned vs prior-year effective) and stamps the
    dynamic `Date_Achieved_<Level>__c` field for each level reached. **7/7 tests, 99% coverage.**
  - **`Opportunity_Create_Gift_Allocations`** record-triggered flow (after-save, `IsWon=true`,
    `doesRequireRecordChangedToMeetCriteria=false` so re-saves re-run idempotently) → calls the service.
  - **`AnnualGivingSummaryRollover`** (Batchable + Schedulable) — July-1 carry-forward: creates each
    prior-year donor's new-year summary with the inherited Effective Level (idempotent). **2/2 tests,
    100% coverage.**
  - Verified end-to-end (savepoint→rollback): real gift-entry path (opp inserted Posted) → hard+soft
    allocations, level, and **Date Achieved = the gift's Close Date**.
  - **Org behavior noted (not a bug):** moving an opp from an OPEN stage to a closed stage makes the org
    reset `CloseDate` to *today*; inserting directly as Posted (real gift entry) preserves the gift
    date. The date-achieved therefore reflects the true gift date in normal use.
  **⏳ Carryover:** schedule the rollover for July 1 (`System.schedule('JSI-90 AGS Rollover','0 0 1 1 7 ?',
  new AnnualGivingSummaryRollover())` — Jason/one-time); soft credits added by automation in a *later*
  transaction than the gift's save are picked up on the next save of the won opp (or by re-running the
  service) — consider a periodic reconcile if needed. Phase 4 (UI + Engagement Plans) next.
- 2026-07-01 — **PHASE 3b — GIFT-CHANGE / DELETE RECONCILIATION (Jason flagged the gap).** Reworked
  the create-only engine into a full **reconciler** so allocations track the gift's current state and
  bad/stale credits are removed. **Decisions (Jason):** disqualified gifts (deleted / un-won / →In-Kind
  / amount 0) → **remove allocations + recompute level from new totals**; soft-credit OCR add/remove →
  **reconcile on next gift save** (opp-triggered now; OCR trigger a later option).
  - `GiftAllocationService` rewritten: computes the *desired* allocation set per opp, then inserts /
    updates / **reparents** (fiscal-year move) / **deletes** to match, and recomputes Earned/Effective
    level + date-achieved (stamp when reached, **clear when no longer reached**). Single invocable
    `syncGiftAllocations` with an `isDelete` flag. `Annual_Giving_Summary__c` MD on Gift Allocation set
    **`reparentableMasterDetail=true`** so a Close-Date change moves the credit to the right year.
  - Flows: `Opportunity_Create_Gift_Allocations` repurposed → **Opportunity - Sync Gift Allocations**
    (after-save; entry formula fires on create or when Stage/Amount/CloseDate/RecordType/Primary Contact
    changes). New **Opportunity - Remove Gift Allocations** (before-delete) removes allocations so the
    gift can delete despite the `Restrict` lookup.
  - **12/12 tests, 99% coverage.** Verified every scenario (savepoint→rollback): amount change
    (down-levels + clears date), Close-Date fiscal-year move (reparents; old year emptied), donor
    change (old removed / new credited), un-win (removed), delete (before-delete flow removes
    allocations then the gift deletes; donor zeroed), soft-OCR removal (removed on resync).
  - **Gotchas (→ memory):** `map`/`into` are **reserved** Apex identifiers; escape an apostrophe in an
    annotation string with `\'` (NOT `''`, which silently splits the string and derails the parse); a
    `RecordBeforeDelete` flow also requires `<recordTriggerType>Delete</recordTriggerType>`; a
    `Restrict` child lookup does **not** block the parent delete if a **before-delete** flow removes the
    children first.
- 2026-07-01 — **PHASE 4 — UI + ENGAGEMENT PLANS (partial; placement items handed to Jason).**
  Delivered (version-controlled + data): (1) seeded an example **Engagement Plan Template** "Major Gift
  Cultivation (Example)" + **5 example tasks** across the moves stages (Identification→Stewardship) —
  data, not source metadata; re-seed via the CLI/anon-Apex in this log. (2) **`Annual_Giving_Summary_Record_Page`**
  flexipage (Giving Level + Totals/Dates-Achieved sections + Gift Allocations related list; modeled on
  `Relationship_Record_Page`). (3) Added a **"Moves Management" tab** to `Contact_Record_Page` with
  three related lists — **Gift Officer Assignments**, **Annual Giving Summaries**, and **Engagement
  Plans** (the EP child relationship on Contact is `npsp__Action_Plans__r`). (4) **Scheduled the July-1
  rollover** (`CronTrigger` "JSI-90 Annual Giving Summary Rollover", `0 0 0 1 7 ?`, WAITING → next fire
  2027-07-01). **✅ DONE BY JASON (App Builder):** Annual Giving Summary record page set as org default;
  Gift Allocations + Engagement Plans related lists placed on the gift pages (committed `944dc15`);
  Engagement Plans already active. **Story-level remaining:** client to finalize level names/thresholds
  and Engagement Plan content; the deferred **D9 moves-management stage model** (major gifts vs donors)
  and **D8 confidential notes**.
- 2026-07-08 — **SECURITY MIGRATED FROM PERM SET → PROFILES (JCRC org standard).** Moved all grants
  off the interim `JSI_90_Moves_Management` perm set onto **Admin (System Administrator) + JCRC -
  Development / Fundraising / Marketing / Volunteering**: 4 objectPermissions + 25 fieldPermissions
  (verbatim from the perm set, rollups/formulas read-only) + classAccesses for `GiftAllocationService`
  and `AnnualGivingSummaryRollover`. Deployed via the **additive minimal-profile technique** (JSI-86
  gotcha — full profiles aren't source-deployable), then documented in the full repo profile files
  (4 objects + 25 fields + 2 classes each; XML validated). **Verified in org:** 20 object perms, 125
  FLS (25×5), 10 class accesses. Unassigned the perm set from the admin user and **deleted it from the
  org + repo** (`sf project delete source`; org query returns 0). No more perm set to assign — profile
  membership grants access automatically.
</content>
