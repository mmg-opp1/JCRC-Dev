# JSI-123 — Board Tracking — Status & Resume

> **Paused 2026-07-31** to switch to other work. This is the single "where we left off" doc — read it
> first when resuming. Full detail lives in `JSI-123_User_Story.md`, `JSI-123_Implementation_Plan.md`
> (Build Log), and the two dictations. **`main` @ `b464f96`, pushed, in sync with origin.**

## TL;DR
Board Tracking is **functionally complete and deployed to JCRC-Dev**: the data model, all automation, and
a 4-tab **Board Management console** (Meetings & Attendance, Committees, Roster, native Dashboard). It is a
**working draft for client feedback** — the Jira story is a stub (no client-approved DoD), and a handful of
client questions + a dashboard tailoring pass remain. Nothing here is in production.

## What's built, deployed & pushed (all in JCRC-Dev)

**Data model (single board; member TYPES, not multiple boards):**
- `Board_Member_Type__c` (config, seeded **JCRC Recruited** 6yr/$5k · **UJA Appointed** 6yr/$5k · **UJA Observer** 1yr/$1.8k).
- `Board_Term__c` — Contact + `Member_Type__c` + Start/End + Status; formulas `Is_Current__c`, `Expiring_Soon__c`, `Term_Year_Label__c`, `Board_Years_Served__c` (roll-up of started non-officer years), `Must_Roll_Off__c` (≥ term length).
- `Board_Membership_Year__c` (MD child of term) — one per fiscal year: `Role__c`, `Is_Officer_Year__c`, stored `Counts_Toward_Limit__c`, `Meetings_Attended__c` roll-up, `Meeting_Requirement_Met__c` (≥3 of 4), `Annual_Giving_Summary__c` link.
- `Board_Meeting__c` + `Board_Meeting_Attendance__c` (MD child of the per-year record → 3-of-4 roll-up).
- `Committee__c` (self-lookup subcommittees + `Category__c` + `Is_Executive_Committee__c`) + `Committee_Assignment__c` (Chair/Co-Chair/Member, per FY). **9 committees seeded** (Executive flagged).
- `Annual_Giving_Summary__c` (JSI-90) extended: `Board_Commitment__c` + `Applied`/`Remaining`/`Met`/`%`/`Is_Board_Year` + `Board_Commitment_Override__c`.

**Automation (Apex triggers/services):**
- **`BoardTermTrigger`/`BoardTermService`** — on save, auto-fill End Date = Start + type term length, and **pre-create one Board Membership Year per fiscal year** (idempotent, capped at End Date). Auto-links each year to its Annual Giving Summary.
- **`BoardCommitmentService`** (+ `BoardMembershipYearTrigger`, `CommitteeAssignmentTrigger`) — stamps keys/`Counts_Toward_Limit` (started years only); **auto-derives commitment** = $0 honorary/Past-President else MAX(member-type base, **$10k** if committee chair/co-chair OR Exec Committee member); stamps AGS unless overridden.
- **`AnnualGivingSummaryTrigger`** — links a new AGS back to its Board Membership Year (board-member-scoped; no work for ordinary donors).
- **`BoardYearAdvance`** (Schedulable, scheduled **July 1** = CronTrigger "JSI-123 Board Year Advance") — flips `Counts_Toward_Limit` as each fiscal year begins.

**UI — Board Management console** (`boardManagement` LWC on the **Board Management** tab in the Development app):
- **Meetings & Attendance** — create a meeting; live checkboxes to mark who attended → feeds the 3-of-4 roll-up. (Save was hardened: payload passed as a JSON string, keys derived server-side.)
- **Committees** — create/edit committees; add/remove members (role + FY).
- **Roster** (`boardMembers` LWC) — current members with type, term, **Must Roll Off**, commitment %; **New Board Member** button (creates the term + years) and **End Term** row action (sets End Date + deletes future years).
- **Dashboard** — native SF **Board Dashboard** (report types `Board_Terms__c`/`Board_Commitments__c`; reports Current Board Roster, Roll-Off Watch, Commitment Fulfillment). **Default metrics — to be tailored to Marc's FRD.**

**Security:** FLS/CRUD + Apex class access + tab visibility on **Admin + JCRC Development/Fundraising/Marketing/Volunteering** profiles (repo profiles synced). No permission sets (org standard).

**Verified:** all Apex tests green; end-to-end anon-Apex checks for auto-gen, commitment tiers, roll-off, meeting roll-up, AGS↔year linking; **attendance save confirmed working in-browser by Jason.**

## ⏳ Open when we resume

**Client TBD (Jason to confirm with JCRC):**
- Do **gala-ticket deductible portions** count toward the commitment? (would change `Board_Commitment_Applied__c`, currently = Total Giving.)
- Confirm **honorary/Past Presidents carry no commitment** (currently $0).
- **Confidential board data / sharing** — any fields needing restricted access beyond profile FLS.

**Deferred build (agreed, not started):**
- **Board Dashboard tailoring** — needs **Marc's FRD** as the reference (the current dashboard is a sensible default). ← likely the highest-value next step.
- The **1-year-off re-eligibility** enforcement (roll off → must sit out ≥1 yr) — data is tracked; auto-enforcement deferred.
- Custom record pages for the newer objects (`Board_Member_Type__c`, `Board_Membership_Year__c`, `Board_Meeting__c`, `Board_Meeting_Attendance__c`) — auto-generated pages work today.
- **eTapestry historical import** (board/committee membership by FY) — out of this story's scope; the per-year model accommodates it.
- **Personal/cultivation info** (birthdays, children, life facts) — flagged as its **own future story**.

**Jason's UI/config items (App Builder — not in source):**
- Confirm the **Board Management** tab placement in the Development app nav; assign the record pages if desired.
- Optionally set the Board Dashboard running user / add it to the console.

**Story admin:**
- Jira JSI-123 is a **stub** — the proposed outcome-based **DoD is held local** (`JSI-123_User_Story.md`), **not pushed to Jira**, pending client review. Push + re-pull (JSI-122 pattern) once approved.

## Where to resume
1. If Marc's FRD is available → tailor the **Board Dashboard** (report types/reports already exist).
2. Otherwise → take the **client TBD** questions to JCRC, then adjust the commitment swap point / honorary rules as answered.
3. Then optionally: record pages for the new objects, re-eligibility rule, push DoD to Jira.

## Key references
- **Commits:** `65a8d39` (model correction) → `f0e894a`/`4888e7f`/`e18b42f` (console 1-3) → `5c8fc1f` (refinements) → `45dec66`/`2deb35b`/`b464f96` (attendance-save fixes). Earlier: `e258124`/`9a4e261` (Phase 1/2 — later corrected).
- **Org:** JCRC-Dev sandbox (`jcrcny@missionmattersgroup.com.dev`). Board year = **July 1–June 30** (derived in Apex; org FY is January — do NOT change it). Reuses JSI-90's `Annual_Giving_Summary__c`/`Gift_Allocation__c`.
- **Gotchas learned** (in the `reference-sf-metadata-gotchas` memory): typed inner-class `@AuraEnabled` params can deserialize empty → pass JSON string; USER_MODE DML setting a read-only field fails; self-lookup can't be Restrict/Cascade; MD-detail Sharing/Bulk/Streaming must match; custom report-type ref needs `__c` suffix; `commit` is a reserved Apex word.
