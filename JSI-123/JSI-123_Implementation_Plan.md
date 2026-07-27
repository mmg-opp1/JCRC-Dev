# JSI-123 — Board Tracking — Implementation Plan

> **Story:** [JSI-123 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-123) (epic JSI-9
> Contact Management). Companion to [`JSI-123_User_Story.md`](./JSI-123_User_Story.md) and
> [`JSI-123_StoryDictationNotes.MD`](./JSI-123_StoryDictationNotes.MD).
> **Author:** Jason Ott · **Drafted:** 2026-07-27 · **Status:** PLAN / spec-for-review — **NO BUILD yet.**
>
> This is a **spec to gather client feedback** (the Jira story is a stub with no client-reviewed DoD).
> The architecture below is a **recommendation with explicit forks**; nothing is deployed until the plan
> is reviewed and the forks are settled (workflow Step 5 → 6). Author = "Jason Ott" in all metadata.

---

## 1. Scope

### In scope (this story — recommended build)
1. **Board membership + terms** — record which contacts serve on the board, their board-level role, term
   **start / end (expiration)**, term status, and **roll-off** signaling when a term ends.
2. **Committees & subcommittees, by year** — record which committees/subcommittees each member sits on and
   their **role within each**, tracked per **board (fiscal) year**.
3. **Annual fiscal commitment + fulfillment** — a per-member, per-fiscal-year giving commitment, with the
   member's giving **allocated toward it** and **progress** (committed / given / remaining / % met) — built
   by **extending JSI-90's `Annual_Giving_Summary__c`** (decision locked 2026-07-27).
4. **Reporting + dashboard** — current roster, upcoming expirations, committee participation, and commitment
   fulfillment; an at-a-glance **Board dashboard**.
5. **Contact-page board visibility** — board status/role/term surfaced on the Contact record (tab + banner).
6. **Board management surface** — a place in the **Development app navigation** to see all board members,
   drill into each, and reach the dashboard.
7. **Built to extend** — configurable roles/committees; grain that can later widen (e.g., household/org boards).

### Out of scope / deferred (candidate — confirm)
- **Attendance / meeting minutes** tracking (not in dictation; a likely future add-on).
- **Board document management** (agendas, packets) — not requested.
- **Automated roll-off enforcement** beyond signaling (e.g., removing security access) — governance decision.
- **Prospective-board pipeline / nominations** workflow — could be a later story.
- **Multi-board support** (>1 governing board) — design leaves room; build for the single JCRC board now.

---

## 2. Decisions to confirm

> **(J)** = Jason / design fork (settle in Step 5). **(C)** = client input needed (Jason relays).
> **Locked** items were settled 2026-07-27.

| # | Decision | Recommendation | Owner |
|---|----------|----------------|-------|
| D1 | Giving-commitment model | **Reuse/extend JSI-90 `Annual_Giving_Summary__c`** | **Locked** |
| D2 | Push DoD to Jira now? | **Hold** until client review | **Locked** |
| D3 | Board-membership grain | **Custom `Board_Term__c` spine** (not raw NPSP Affiliations) | **Locked ✓ 2026-07-27** |
| D4 | Committee model | **`Committee__c` config + `Committee_Assignment__c` (per year)** | **Locked ✓ 2026-07-27** |
| D5 | Term length & renewals | Fixed length? consecutive terms allowed? | C |
| D6 | Roll-off behavior on expiration | **Signal** (status formula + report/task), not hard enforcement | J/C |
| D7 | Commitment shape | **Dollar amount per FY** (optional gift-count) | C |
| D8 | What counts toward commitment | **All hard + soft credit for the FY** (= `Total_Giving__c`) | C/J |
| D9 | Board year == fiscal year Jul 1–Jun 30 | **Yes** (matches dictation + org) | C confirm |
| D10 | Board surface implementation | **`Board_Members` LWC on a custom tab + Board Dashboard** | **Locked ✓ 2026-07-27** |
| D11 | Also set NPSP **Primary Affiliation** for board members? | **Yes, optional additive automation** (keeps native "is-board" niceties) | J |
| D12 | Security placement | **JCRC\* profiles** (org standard, not perm sets) | J confirm |
| D13 | "Board" side of `Board_Term__c` | **No `Board__c` — single board.** `Board_Term__c` is a Contact-child; current board = `Is_Current__c=TRUE`. Board-level defaults in **`Board_Setting__mdt`**; leave a clean slot to add `Board__c` later if a 2nd governing body appears. | **Locked ✓ 2026-07-27** |

---

## 3. Verified org context (source-of-truth as of 2026-07-27)

Confirmed by reviewing `force-app` + prior-story memory; **final field-level checks at build time via `sf` CLI.**

**JSI-90 giving objects we will extend / reuse:**
- **`Annual_Giving_Summary__c`** — one per Contact per FY (Jul 1–Jun 30). Has `Contact__c` (child rel
  `Annual_Giving_Summaries`), `FY_Start__c`/`FY_End__c` (Date), `Fiscal_Year_Label__c` (Text),
  `Prior_Year_Summary__c` (self-lookup), Earned/Effective/Override `Giving_Level__c` lookups,
  **`Total_Hard_Credit__c`** + **`Total_Soft_Credit__c`** (Rollup SUM over `Gift_Allocation__c.Amount__c`)
  and **`Total_Giving__c`** (formula = hard+soft). **← board commitment/fulfillment attaches here.**
- **`Gift_Allocation__c`** — Master-Detail→AGS (rel `Gift_Allocations`, reparentable), `Opportunity__c`,
  `Contact__c`, `Credit_Type__c` (Hard/Soft), `Amount__c`, unique `Allocation_Key__c`. Giving is already
  allocated to the correct-FY AGS by close date. **← no new giving plumbing needed.**
- **Automation:** `GiftAllocationService` (reconciler, month≥7 → July FY window) + flow
  *"Opportunity – Sync Gift Allocations"*; `AnnualGivingSummaryRollover` (Batchable/Schedulable July-1
  carry-forward). July anchor is **in Apex**, not org fiscal settings — do **not** change org FY.
- `Giving_Level__c` (config: Min/Max/Sort/Active/EP-template); `Gift_Officer_Assignment__c`
  (Contact/User/Role incl. a `Committee` value/Active/Key).

**NPSP relationship objects:** `npe5__Affiliation__c` (Contact/Organization/Role/Status/StartDate/EndDate/
Primary/Description — **managed fields only, no custom fields, no record types**, has `Affiliation_Record_Page`).
`npe4__Relationship__c` similar. Adding fields/record types means editing a **managed** object.

**Contact page:** `Contact_Record_Page` (main) — `maintabs` tabset already has **Relationships**
(`npe4__Relationships__r` + `npe5__Affiliations__r`) and **Moves Management** (`Gift_Officer_Assignments__r`,
`Annual_Giving_Summaries__r`, `npsp__Action_Plans__r`) tabs. Sidebar hosts LWCs `tagManager` +
`contactListSubscriptions`. A **"Board" tab** slots in as a new `flexipage:tab` peer. **No Contact record types.**

**Apps / nav / UI patterns:** `JCRC_Development` app ("Development") = main nav (Home, Contacts, Accounts,
Opportunities, Gift Entry, Recurring Donations, Campaigns, GAU, Reports, Dashboards). Adding a nav tab =
a `CustomTab` file + entry in the app's `<tabs>`. VF + Aura Lightning-Out pattern exists (`AcknowledgmentLetter`
page + `AckLetterOut` `ltng:outApp`, JSI-87); LWC patterns `tagManager`, `contactListSubscriptions`.

---

## 4. Requirement → mechanism

| Dictation / DoD requirement | Mechanism |
|---|---|
| Track board **terms + expiration**, roll off when done | `Board_Term__c` (Contact, role, start/end, status, `Is_Current__c` + `Expiring_Soon__c` formulas) |
| **Board role** | `Board_Term__c.Board_Role__c` (restricted picklist, configurable) |
| **Committees / subcommittees + roles, by year** | `Committee__c` (config, self-lookup for subcommittees) + `Committee_Assignment__c` (Contact + Committee + role + fiscal year) |
| **Annual fiscal commitment ($ / # gifts) per FY** | New fields on **`Annual_Giving_Summary__c`**: `Board_Commitment__c` (+ optional `Board_Gifts_Required__c`) |
| **Allocate giving toward commitment + progress** | Reuse existing Gift_Allocation→AGS rollups; add `Board_Commitment_Met__c` / `_Remaining__c` / `_Pct__c` formulas (+ optional gift-count rollup) |
| Ensure a board member has a year record even before giving | Automation: create/stamp the member's AGS for each covered board year (lazy on term save + July-1 rollover) |
| **Is this contact a board member?** on Contact page | Contact rollup/formula `Current_Board_Member__c` → conditional **banner** + easy filtering |
| **Who's on the board now / at a point in time** | `Board_Term__c` list views + report (Is_Current, or Start≤ / End≥ a date) |
| **Robust reporting** | Custom report types over Board Terms, Committee Assignments, AGS-with-commitment |
| **At-a-glance dashboard** | `Board Dashboard` (roster count, terms expiring, % commitment met, board giving, participation) |
| **Board management surface in nav** | Custom **tab** in the Development app hosting a **Board LWC** (roster + drill-in) + dashboard link |
| **Extensible** | Configurable `Board_Role`/`Committee`/levels; grain isolatable; junction pattern per JSI-122/90 |

---

## 5. Design — objects, fields, automation, pages

### 5.1 New object: `Board_Term__c` (membership spine)
One record per contact per term (a term spans multiple fiscal years). AutoNumber `BT-{00000}`, Private/ReadWrite.

> **D13 — single board, no `Board__c` (locked 2026-07-27).** `Board_Term__c` is a **Contact-child**, not a
> Contact↔Board junction — with one governing board the "board" side is a constant, so it collapses. **"The
> current board" = all `Board_Term__c` where `Is_Current__c = TRUE`.** Board-level defaults (standard term
> length, default annual commitment, "expiring soon" window N) live in a **`Board_Setting__mdt`** custom
> metadata type (admin-configurable, single row). Board-wide totals (total board giving/commitment this FY,
> current headcount) live on the **Board Dashboard**, not on a Board record. **Extension slot:** if JCRC ever
> tracks a second governing body (Advisory/Junior/Regional board), add a `Board__c` object + a `Board__c`
> lookup on `Board_Term__c` (defaulted to the one board) — a small additive change, not a rebuild.

| Field | Type | Notes |
|---|---|---|
| `Contact__c` | Lookup→Contact (required, Restrict) | child rel `Board_Terms` |
| `Board_Role__c` | Picklist (restricted) | Chair, Vice-Chair, Treasurer, Secretary, Member, Emeritus, … (configurable; avoid "/") |
| `Start_Date__c` | Date (required) | term start |
| `End_Date__c` | Date | term expiration (blank = open/indefinite — discouraged) |
| `Status__c` | Picklist (restricted) | Prospective, Active, Rolled Off, On Leave |
| `Term_Number__c` | Number(2,0) | 1st/2nd/… term (optional) |
| `Annual_Commitment_Default__c` | Currency(18,2) | default $ commitment propagated to each year's AGS (override on AGS) |
| `Is_Current__c` | Formula(Checkbox) | `Status__c="Active" && TODAY() ≥ Start && (ISBLANK(End) || TODAY() ≤ End)` |
| `Expiring_Soon__c` | Formula(Checkbox) | `Is_Current && End within N days` (N config, e.g. 90) |
| `Term_Year_Label__c` | Formula(Text) | e.g. "2025–2028" for display |

Validation: `End_After_Start`; (optional) one Active term per contact.

> **D11 option:** on save of an Active `Board_Term__c`, automation also upserts the member's **NPSP Primary
> Affiliation** to a "Board of Directors" Account (role/status/dates mirrored) so native NPSP board reports +
> the "primary affiliation" concept keep working. Cheap, additive, reversible.

### 5.2 New object: `Committee__c` (config)
Admin-maintained list of committees **and** subcommittees. Name = Text.

| Field | Type | Notes |
|---|---|---|
| `Parent_Committee__c` | Lookup→Committee__c (self) | populated ⇒ this row is a **subcommittee** |
| `Type__c` | Formula(Text) | `IF(ISBLANK(Parent_Committee__c),"Committee","Subcommittee")` |
| `Active__c` | Checkbox | default true |
| `Description__c` | Text(255) | |

### 5.3 New object: `Committee_Assignment__c` (per contact / committee / year)
The "committee & subcommittee roles **by year**" junction.

| Field | Type | Notes |
|---|---|---|
| `Contact__c` | Lookup→Contact (required, Restrict) | child rel `Committee_Assignments` |
| `Committee__c` | Lookup→Committee__c (required) | |
| `Committee_Role__c` | Picklist (restricted) | Chair, Vice-Chair, Member, Advisor, … |
| `Fiscal_Year_Label__c` | Text(40) | matches AGS labels (e.g. "FY2027 (Jul 2026–Jun 2027)") — the "by year" key |
| `FY_Start__c` | Date | July 1 anchor (for point-in-time / date filtering) |
| `Active__c` | Checkbox | default true |
| `Assignment_Key__c` | Text(255) | **unique, externalId**, `Contact\|Committee\|FYLabel` (dedupe) |

> Keying committee participation to `Fiscal_Year_Label__c` (same labels JSI-90 uses) unifies board-year
> reporting across giving + committees without a hard dependency between the objects.

### 5.4 Extend `Annual_Giving_Summary__c` (commitment + fulfillment) — **JSI-90 reuse**
Additive fields only (no change to existing giving rollups):

| Field | Type | Notes |
|---|---|---|
| `Board_Commitment__c` | Currency(18,2) | required board giving for that FY (blank/0 = none) |
| `Is_Board_Year__c` | Formula(Checkbox) | `Board_Commitment__c > 0` (or a stamped flag from active Board_Term) |
| `Board_Commitment_Remaining__c` | Formula(Currency) | `MAX(Board_Commitment__c − BLANKVALUE(Total_Giving__c,0), 0)` |
| `Board_Commitment_Met__c` | Formula(Checkbox) | `Total_Giving__c ≥ Board_Commitment__c && Board_Commitment__c > 0` |
| `Board_Commitment_Pct__c` | Formula(Percent) | `Total_Giving__c / Board_Commitment__c` (guard divide-by-zero) |
| `Board_Gifts_Required__c` | Number(3,0) | *(optional, D7)* required # of gifts |
| `Board_Gifts_Count__c` | Rollup Summary (COUNT) | *(optional)* count of child `Gift_Allocation__c` (Hard) |

**Automation to ensure the year record exists for board members:**
- On `Board_Term__c` insert/update (Active), for each fiscal year the term covers, **find-or-create the AGS**
  (reuse `GiftAllocationService`'s FY logic) and stamp `Board_Commitment__c` from
  `Annual_Commitment_Default__c` (unless already overridden). Idempotent.
- Extend `AnnualGivingSummaryRollover` (July-1) to also create the new-year AGS for **active board members**
  and carry the commitment forward.
- **No change** to gift-side allocation — giving already lands on the right-year AGS.

### 5.5 Contact-level flag
Add `Contact.Current_Board_Member__c` — either a **DLRS/native rollup** (count of `Board_Terms` where
`Is_Current__c`) surfaced as a checkbox/number, or a formula if a single-term assumption holds. Drives:
- a **conditional banner** ("★ Current Board Member — {Role}") on the Contact page (component visibility),
- fast list-view/report filtering of board members.

### 5.6 Pages
- **Contact page (`Contact_Record_Page`):** add a **"Board" tab** (peer of Moves Management) with related lists
  **Board Terms** (`Board_Terms__r`), **Committee Assignments** (`Committee_Assignments__r`), and the member's
  **Annual Giving Summaries** (commitment columns). Add the board-member **banner** at top (visibility-ruled).
- **Record pages:** `Board_Term_Record_Page`, `Committee_Record_Page`, `Committee_Assignment_Record_Page`
  (house format). AGS page already exists (JSI-90) — add the commitment fields to it.
- **Board management surface (D10):** a **`Board_Members` LWC** (roster: name, role, term dates, expiring flag,
  % commitment met; click-through to Contact) hosted on a **custom tab** in the Development app; the **Board
  Dashboard** reachable alongside. VF + Lightning-Out (JSI-87 `AckLetterOut` pattern) is the fallback if a raw
  LWC tab is insufficient.

---

## 6. Security & FLS
Per org standard (**profiles, not permission sets** — see `feedback-security-at-profile-not-permsets`):
grant object CRUD + FLS on the new objects/fields and Apex class access on **`Admin` + `JCRC – Development /
Fundraising / Marketing / Volunteering`**, via the **additive minimal-profile** technique (full profiles aren't
source-deployable here — invalid-tab gotcha). Deploy **FLS with the fields**. Confirm which JCRC profiles should
see board data (some may be read-only). Watch: any **confidential board data** (D-comp, sensitive notes) would
need tighter sharing — flag if the client wants it.

---

## 7. Reporting & dashboard

**Custom report types:**
- *Board Members & Terms* (Board_Term__c, +Contact) — current roster, expirations, roles.
- *Committee Participation by Year* (Committee_Assignment__c, +Contact, +Committee).
- *Board Commitment vs. Giving* (Annual_Giving_Summary__c filtered `Is_Board_Year__c`) — committed / given /
  remaining / % met, by fiscal year.

**Reports (examples):** Current Board Roster; Terms Expiring in Next 90 Days; Committee Rosters by Year;
Board Commitment Fulfillment (current FY); Board Giving Trend (multi-FY).

**`Board Dashboard`:** current board headcount; terms expiring soon; **% of members who met commitment**;
total board giving this FY vs. total committed; participation by committee; giving by member (gauge/bar).
*(Report-type parent dot-walk limits apply — use cross-object formula fields per the JSI-122/109 gotcha.)*

---

## 8. Phased build plan (on go-ahead — NOT yet)
1. **Data model** — `Board_Term__c`, `Committee__c`, `Committee_Assignment__c` + fields + validation; extend
   AGS with commitment fields; Contact flag. Deploy + FLS. Verify (anon Apex savepoint/rollback).
2. **Automation** — ensure-AGS-for-board-year on Board_Term save; extend July-1 rollover; commitment stamping.
   Tests ≥ 90%.
3. **Pages** — Contact "Board" tab + banner; the 3 new record pages; AGS commitment fields on its page.
4. **Reporting** — report types + reports + `Board Dashboard`.
5. **Board surface** — `Board_Members` LWC + custom tab in the Development app (+ dashboard link).
6. **Verify + commit** (this story's files only) + push on request; update Build Log + memories.

## 9. Net-new metadata (anticipated)
3 custom objects (+ ~20 fields), **`Board_Setting__mdt` CMDT (+1 config row)**, ~6 AGS fields, 1 Contact field,
~3 validation rules, 1–2 flows (or Apex extension), extension to `AnnualGivingSummaryRollover`, 4 flexipages
(+ Contact page edit), 3 report types, ~5 reports, 1 dashboard, 1 LWC, 1 CustomTab + app nav entry, profile FLS
on 5 profiles. (Right-sized after forks.) **No `Board__c`** (D13).

## 10. Risks & watch-items
- **Managed-Affiliation coupling (D11):** only *additively* set Primary Affiliation; don't depend on editing
  managed Affiliation fields/record types.
- **AGS dual purpose:** AGS now serves giving-levels **and** board commitment — keep board fields additive and
  clearly named so JSI-90 logic is untouched; regression-test the reconciler.
- **Board-year AGS creation for non-donors:** ensure idempotent find-or-create so we don't spawn duplicate AGS.
- **Report-type parent dot-walk** limitation → cross-object formula fields (JSI-122/109 gotcha).
- **Additive profile deploys only ADD, never revoke** (JSI-122 gotcha) — plan FLS accordingly.
- **Point-in-time roster** correctness (Start/End vs. a chosen date) — validate with report filters.
- **Scope creep:** this is meant to be "one of the most robust features" — resist over-building v1; ship the
  spine + commitment + roster/dashboard, leave attendance/nominations/multi-board for later.

## 11. Sources
- Arkus — *Managing Your Board of Directors in NPSP* (Affiliation pattern, roles, giving checkbox/campaigns).
- Free Like a Puppy — *My Favorite Way to Track Board Members* (Affiliation + status rollup + banner; notes
  point-in-time roster weakness).
- Cloud for Good — *Relationship Tracking in NPSP*; Salesforce Help — *Create an Affiliation with an Organization*.
- Internal: JSI-90 (`Annual_Giving_Summary__c`/`Gift_Allocation__c` architecture), JSI-85 (crediting rules),
  JSI-122 (junction + report-type gotchas), JSI-87 (VF + Lightning-Out surface pattern).

## 12. Build Log

**Phase 1 — data model (BUILT + DEPLOYED + VERIFIED 2026-07-27; NOT yet committed):**
- `Board_Setting__mdt` CMDT (4 fields: Default_Term_Length_Years, Default_Annual_Commitment, Expiring_Soon_Window_Days, Roll_Off_Action) + `Board_Setting.Default` record (3 / $0 / 90 / "Flag Only" — placeholders pending client).
- `Board_Term__c` (Contact, Board_Role [placeholder picklist], Start/End Date, Status, Term_Number, Annual_Commitment_Default; formulas Is_Current, Expiring_Soon [reads `$CustomMetadata.Board_Setting__mdt.Default.Expiring_Soon_Window_Days__c`], Term_Year_Label) + `End_After_Start` VR. `enableHistory=true`.
- `Committee__c` (Parent_Committee self-lookup, Type formula, Active, Description).
- `Committee_Assignment__c` (Contact, Committee, Committee_Role [placeholder], Fiscal_Year_Label, FY_Start, Active, unique Assignment_Key).
- **Extended `Annual_Giving_Summary__c`** (JSI-90) with 6 additive fields: `Board_Commitment__c` (input) + formulas `Board_Commitment_Applied__c` (**SWAP POINT** = Total_Giving; change per client Q11/Q12), `Is_Board_Year__c`, `Board_Commitment_Remaining__c`, `Board_Commitment_Met__c`, `Board_Commitment_Pct__c`.
- **FLS/CRUD** on Admin + 4 JCRC profiles via additive minimal-profile deploy (viewAll/modAll on Admin only). **⏳ TODO before commit: sync the repo full profiles** (additive tmp files live in scratchpad, not repo).
- **Verified** via anon Apex (savepoint/rollback): Board_Term current/expiring/expired/rolled-off formulas; End_After_Start VR; Committee Type formula; Assignment_Key uniqueness; AGS commitment math (6000+1000 → applied 7000, remaining 3000, met false, pct 70%, isBoardYear true).
- **GOTCHAS HIT:** (1) **self-lookup cannot use `deleteConstraint` Restrict/Cascade** ("Cannot add a self-lookup relationship child with cascade or restrict options to the object itself") → use **`SetNull`** (same family as the JSI-90 User-lookup rule). (2) **Percent formula fields already apply ×100** — write the raw fraction (`Applied/Commitment`), not `*100`, or the value is 100× too large (7000 vs 70).

**Phase 1b — client-independent UI (BUILT + DEPLOYED + VERIFIED 2026-07-27; NOT yet committed):**
- **`boardMembers` LWC** (current roster: name→Contact link, role, term, expiring flag, commitment $ + % met) + **`BoardMembersController`** (with sharing, USER_MODE; reads current board year AGS) + **`BoardMembersControllerTest`** (2/2 pass, deployed via RunSpecifiedTests).
- **`Board_Members` CustomTab** (LWC-component tab) added to the **Development app** nav; class access + `DefaultOn` tab visibility on Admin + 4 JCRC profiles (additive deploy).
- **Contact "Board" tab** added to `Contact_Record_Page` (peer of Moves Management) with **Board Terms** + **Committee Assignments** related lists.
- **3 record pages:** `Board_Term_Record_Page`, `Committee_Record_Page` (+ Subcommittees & Committee Assignments related lists), `Committee_Assignment_Record_Page` (simple-view template). **⏳ Jason:** assign each as the object's org-default page in App Builder (page→assignment isn't in source).
- **GOTCHA:** `lst:dynamicRelatedList` **requires `relatedListFieldAliases`** — a related list without it fails deploy "missing required property [relatedListFieldAliases]".

**Deferred to later phases (some pending client answers):** Phase 2 automation (ensure-AGS-for-board-year + commitment stamping + roll-off), Contact "★ Board Member" banner + `Current_Board_Member__c` flag (needs DLRS/flow — no native RUS over a lookup), AGS record-page commitment fields, Phase 4 reports + Board Dashboard, optional App Page hosting the LWC + dashboard together.
