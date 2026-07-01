# JSI-90 — Track major donor moves management

> **Source:** [JSI-90 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-90)
> Retrieved from Jira on 2026-07-01 by Jason Ott. This is a documentation snapshot — Jira remains
> the system of record. (Story already had a description + DoD in Jira; nothing pushed back.)

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-90 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-15 → 2026-07-10, *active*) |
| **Labels** | Should-Have, US-023 |
| **Feature Owner** | Gift Officer |
| **Reporter** | Jason Ott |
| **Assignee** | Unassigned |
| **Created** | 2026-06-18 |
| **Updated** | 2026-07-01 |

## User Story

> As a **Gift Officer**, I want major donor moves management tracked in the CRM, so that I can see
> **prospect stages, next actions, and assigned officers** for top relationships.

## Definition of Done (from Jira) — with this-story scope annotated

The dictation (`JSI-90_StoryDictationNotes.MD`) **substantially expands** this story beyond the Jira
DoD. Per our workflow, the **dictation is the source of intent**; Jira is the system of record for the
story text. Mapping each Jira DoD item:

1. **Major gift Opportunity record type with prospect stages** (Identification, Qualification,
   Cultivation, Solicitation, Stewardship). → ✅ **MOSTLY ALREADY DONE** — the `Major_Gift`
   Opportunity record type exists (JSI-82). ⚠️ *Verify* the stage set includes the moves-management
   prospect stages (see Outstanding Q1); dictation says "we already have that."
2. **Tasks and activities logged against each major donor record.** → ✅ **STATEMENT OF FACT** — native
   Salesforce Activities; dictation: "we also have tasks so we don't need to worry about that."
3. **Portfolio view by gift officer showing assigned prospects and next action dates.** → ⚠️ **PARTIAL
   — this story builds the *assignment* mechanism** (Gift Officer Assignment); the *view/report* layer
   is deferred (dictation: "ignore the reports … for now").
4. **Reports** (prospects by stage, by ask amount, overdue next actions). → 🔜 **DEFERRED** (dictation:
   "ignore the reports that are part of the definition of done for now").
5. **Dashboard for the development director.** → 🔜 **DEFERRED** (dictation: "ignore the dashboard …
   for now").
6. **Confidential notes restricted to assigned officer and supervisor.** → 🚩 **NOT in the dictation —
   scope unconfirmed** (see Outstanding Q10).

### What the dictation ADDS (the real bulk of this story)

- **A. Engagement Planning (NPSP-native).** Enable NPSP **Engagement Plans**; create **placeholder /
   example templates** with example tasks; surface Engagement Plans on the record pages where they
   belong; keep close to NPSP standards. Client has **not** finalized their templates — build the
   framework so they can design their own.
- **B. Giving Levels / Moves-Management engine (CUSTOM — not NPSP defaults).** A configurable,
   multi-level giving-tier system driven by each donor's giving for the fiscal year:
   - **Configurable levels** (e.g. *Congressional* $5,000–$9,999.99, *Senate* $10,000+, a base tier
     $1–$4,999.99) — names + thresholds **admin-configurable**; levels **not** client-final.
   - A per-donor, **per-fiscal-year accumulator** record (working name **Annual Giving Summary**) that
     keeps a running **hard-credit** total, **soft-credit** total, a combined value, and the donor's
     **level label**.
   - A separate **Gift Allocation** junction linking each Opportunity to the donor's Annual Giving
     Summary, carrying the **hard credit** and enabling **soft credits** to accumulate to the summary.
   - **Level inheritance:** a level earned in a fiscal year is held for the **rest of that year and all
     of the next** fiscal year; if not re-earned, it drops the following year. (Implemented by linking
     each year's summary to the prior year's.)
   - **Manual override** of a donor's level that **does not** carry forward to the next year.
   - **Date-achieved tracking:** capture the date of the gift that pushed the donor over each level
     threshold (a date per level).
- **C. Gift Officer Assignment (CUSTOM).** A junction between a **User** (internal staff) and a
   **Contact** assigning an internal gift officer to a donor. Working name **Gift Officer Assignment /
   Staff Assignment**. The Jira comment asks for **multiple relationships** (primary, back-ups,
   solicitors, committees).

## Notes & Context

**Feature Owner:** Gift Officer.

**JCRC note (from the Jira comment):**
> *DM — track someone over the course of a year — who is in touch, when to be in touch, adding moves
> management details in a calendar, or acknowledgements. Add in multiple relationships — based on
> solicitors, back-ups, committees.*

**MMG note (from the Jira comment):**
> *This seems like a major gift story rather than moves management. Do we want a set of standard tasks
> for major gifts that are automatically created for major gift opportunities? Do we want moves
> management on contacts?*
➡️ The dictation answers both: **yes** to standard tasks (via Engagement Plan templates) and **yes**
to moves management on Contacts (via the Giving-Levels engine + Gift Officer Assignment).

**Research summary (2026-07-01) — see the Implementation Plan for full detail + sources:**
- **NPSP ships a native Levels feature** (`npsp__Level__c`): configurable min/max amount, a source
  (rollup) field, a level field + previous-level field on Contact/Account, and an optional Engagement
  Plan Template that auto-launches when a level is reached — recalculated by the nightly *"NPSP 08 –
  Level Assignment Updates"* batch. **It cannot, however**, produce a July–June giving year, keep a
  per-year record, track a date-achieved, apply a one-year *inheritance* rule, or hold an *expiring
  override* — which is exactly why the dictation calls for a **custom** engine. NPSP Levels is used as
  a **reference model**, not the build.
- **Org fiscal year = January** (`Organization.FiscalYearStartMonth = 1`) and **NPSP rollups are not
  fiscal-year based** (`npo02__Use_Fiscal_Year_for_Rollups__c = false`) → NPSP's "this year" totals
  are **calendar Jan–Dec**, not JCRC's **July 1–June 30** giving year. The custom design resolves this
  by rolling up **Gift Allocations that are pre-assigned to the correct year's summary** (no reliance
  on the org fiscal-year setting).
- **NPSP Engagement Plans** are present (managed objects `npsp__Engagement_Plan__c`,
  `npsp__Engagement_Plan_Template__c`, `npsp__Engagement_Plan_Task__c`) but **no templates exist yet**
  and **no Engagement Plan record pages/layouts** are built.

## Outstanding Questions / Design Decisions (for review before build)

**For Jason (architecture):**
1. 🔜 **Moves-management stages — DEFERRED TO CLIENT (2026-07-01).** Jira DoD #1 calls for prospect
   stages (Identification/Qualification/Cultivation/Solicitation/Stewardship). *Verified:* `Major_Gift`
   currently uses **Donation_Process** (Prospecting/Cultivating/Posted/Declined), not those stages.
   **Open client decision — the key framing:** do they want moves management on major **GIFTS** (a
   stage pipeline on the Major Gift *Opportunity*) or on major **DONORS** (a cultivation
   stage/pipeline at the *Contact*/portfolio level — treating the *person* as the thing moving through
   Identification→Stewardship)? This is exactly the "moves management on contacts?" question MMG raised
   in the Jira comment. The two lead to very different builds (Opportunity business process + stages vs.
   a Contact-level stage field / pipeline). **No stage work is built until the client decides.** If
   Opportunity-stage: also needs the Won/Closed mapping decision (which stage = gift received/rolls up,
   and the lost path).
2. 🚩 **Levels engine: custom vs NPSP Levels.** Recommend **custom** (NPSP Levels can't do per-year
   records / July–June / date-achieved / inheritance / expiring override). Confirm.
3. 🚩 **Date-achieved model.** Dictation suggests **N date fields** on the summary (admin adds a field
   per new level). Recommend instead a **child "Level Achievement" record** (Level + Date) so **no
   schema change is needed** when a level is added. Confirm which.
4. **Annual Giving Summary grain.** Per **Contact**, per **Household Account**, or both? Recommend
   **Contact** (with the design left extendable to Account).
5. **Level configuration mechanism.** Recommend a **`Giving_Level__c` custom object** (admin-editable
   records: name, min, max, sort, active) over a picklist, so levels are fully data-configurable.
6. **Does soft credit count toward level qualification?** Recommend qualification on the **combined
   hard + soft** total, while keeping the two totals separate. Confirm.
7. **Gift Officer Assignment cardinality.** The comment implies **multiple** officers per donor with
   roles (Primary, Backup, Solicitor, Committee). Recommend a junction with a **Role** picklist +
   Active flag. Confirm the role list.

**For the client (can proceed on the framework meanwhile):**
8. **Final level names + thresholds** (Congressional / Senate are examples; base tier assumed
   $1–$4,999.99). Framework is configurable — client fills values later.
9. **Engagement Plan templates + tasks** (client will design; we seed 1–2 examples).
10. 🔜 **Confidential notes (Jira DoD #6) — DEFERRED (2026-07-01, Jason).** Officer/supervisor-only
    notes are out of scope for this story; revisit later (would need a restricted-sharing object/field,
    not a plain field).
11. **Reports & dashboard** (Jira DoD #3–#5) — confirmed **deferred** per dictation.

## Related Reference Material

- [`JSI-90_StoryDictationNotes.MD`](./JSI-90_StoryDictationNotes.MD) — Jason's dictation + the 6-step
  process for this story.
- [`JSI-90_Implementation_Plan.md`](./JSI-90_Implementation_Plan.md) — full design, org research, and
  phased build plan.
</content>
</invoke>
