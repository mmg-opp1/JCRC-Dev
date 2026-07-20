# JSI-50 — Segmented email lists from NPSP data

> **Source:** [JSI-50 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-50)
> Retrieved from Jira on 2026-07-20 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-50 |
| **Type** | Story |
| **Status** | To Do |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-3 — Email Marketing (Constant Contact) |
| **Sprint** | Implementation Sprint 2 |
| **Labels** | Must-Have, US-046 |
| **Feature Owner** | Communications |
| **Reporter** | Jason Ott |

## User Story

> As a Communications staff member, I want segmented email lists based on donor history,
> event attendance, and program affiliation, so that I can send relevant messages to the
> right audiences.

## Definition of Done

- Salesforce reports define the segments and push to Constant Contact lists.
  - Lists refresh on a schedule (at minimum weekly).
  - Sample segments: lapsed donors, current-year donors, gala attendees, program participants by area.
  - Segment overlap rules defined so a person isn't double-emailed.
  - Communications staff trained on requesting and using segments.

## Notes & Context (dictation — Jason)

- **Research/verify story** — the goal is to confirm this is handled on the **Constant Contact side** + the existing integration, and that **nothing needs to be built in Salesforce.** Only produce an implementation plan **if** there is functionality that must be built.
- **Interpretation:** use the **standard Salesforce ↔ Constant Contact integration** to sync contact lists; the **client configures the source (Jason's lean: list views) + the sync schedule** themselves. Jason **"doesn't see the need to build anything from a report interface when it can be done through the list view."**
- Do the research **very thoroughly** against Constant Contact functionality + the DoD.

## Outstanding Questions / Gaps (Step 2)

1. **Reports vs. list views (the crux):** the DoD says *reports* push to CC lists; Jason plans *list views*. **What does the CC native Salesforce connector actually accept as an audience source** — reports, list views, and/or Campaigns? (Determines whether Jason's list-view approach works as-is or whether segment *reports* are the required mechanism.)
2. **Overlap / no-double-email rules:** where do these live — CC-side (suppression/segment logic) or SF-side (mutually-exclusive segment definitions)? Native connector is add/update, not exclusion-aware.
3. **Does JSI-107 already cover the sync plumbing?** (JSI-107 DoD #2 = "push SF Reports/Campaigns → CC lists" via the native connector.) If so, JSI-50 may be **segment definition + config + training**, not a build.
4. **Sample segments** need NPSP field/criteria definitions (lapsed vs current-year donor thresholds; gala = which Campaign; program participants by area = which field).

## Related Reference Material

- [`../JSI-107/ConstantContactDocumentation.MD`](../JSI-107/ConstantContactDocumentation.MD) — CC integration reference (native connector = one-way SF→CC).
- [`../JSI-107/JSI-107_Implementation_Plan.md`](../JSI-107/JSI-107_Implementation_Plan.md) — the hybrid CC integration (native SF→CC audience push already in scope there).
- [`../JSI-108/JSI-108_Implementation_Plan.md`](../JSI-108/JSI-108_Implementation_Plan.md) — the sibling "verify, little/no SF build" CC story.
