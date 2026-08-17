# JSI-126 — Installation Payment Reports

> **Source:** [JSI-126 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-126)
> Retrieved from Jira on 2026-08-17 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-126 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Medium |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | _None assigned_ |
| **Labels** | _None_ |
| **Feature Owner** | _Not stated (no comments on the issue)_ |
| **Reporter** | Jason Ott |
| **Assignee** | Jason Ott |
| **Created** | 2026-08-17 |
| **Updated** | 2026-08-17 |

## User Story

> As a member of the development team, I want to be able to accept and report on
> installation payments.

## Definition of Done

> - Receive monthly reports when there is an existing installment payment
> - When the plan is complete, send a final letter
> - When a check or ACH has been received, an acknowledgement that it has been recorded,
>   that we have received a certain total, and there is X remaining balance

**Annotated with this-story scope:**

| DoD item | Scope call |
|---|---|
| 1. **Monthly reports on existing installment payments** | **The only real build in this story.** See the gap analysis below — the org has eight pledge reports and *none* of them does this. |
| 2. When the plan is complete, send a final letter | **✅ Already delivered by JSI-125** — `Pmt_Email_Final_Payment`, fired by `Payment_Notify_Donor_On_Paid` when the remaining balance reaches zero, with the same record-type + multiple-payment filtering Jason asked for here. |
| 3. Acknowledgement that a check/ACH was recorded, with total received and remaining balance | **✅ Already delivered by JSI-125** — `Pmt_Email_Installment` carries exactly that: payment received, payment date, total paid to date, remaining balance, total commitment. |

## Notes & Context

**From Jason's dictation** (`JSI-126_StoryDictationNotes.MD`):

- "Most of the story should be accomplished by JSI-125" — confirmed; items 2 and 3 are done.
- The focus here is **the reports**: comb through every report already in the system and
  check whether a **monthly report for existing installments, paid and unpaid**, actually
  exists.
- The final-notification piece must carry **the same filtering as JSI-125** — multiple
  payments only, and only Pledge / Major Gift / Grant. Even on those record types, a
  single-payment gift is excluded. *(This is exactly how JSI-125 was built and verified.)*
- "The last Definition of Done item we should have already accomplished via JSI-125" — confirmed.

## Gap analysis — all 8 existing pledge reports reviewed

The org has a `Pledge and Grant Reports` folder built during JSI-82. Every report in it was
read, not just listed:

| Report | What it actually filters | Shows paid installments? |
|---|---|---|
| Pledge Payment Schedule (Remaining) | `Paid = 0`, `Written_Off = 0`, Stage = Pledged | **No** |
| Pledge Payments Due This Fiscal Year | `Paid = 0`, `Written_Off = 0`, Stage = Pledged | **No** |
| Pledge Payment Aging | `Days Past Due > 0`, Stage = Pledged | **No** |
| Overdue Pledges | overdue receivables | **No** |
| Outstanding Pledges | Opportunity-level balances, Stage = Pledged | Rollup totals only, not per installment |
| New Pledges This Fiscal Year | Opportunity level | n/a |
| Pledge Write-Offs (Bad Debt) | written off | n/a |
| Pledges by Lifecycle Stage | Opportunity level | n/a |

**Three findings:**

1. **Nothing reports on PAID installments.** Every payment-level report filters
   `npe01__Paid__c = 0`. They are all forecast / receivables views. The "paid and unpaid"
   report Jason asked about does not exist.
2. **Every one of them filters `StageName = 'Pledged'`.** When a plan is completed the
   JSI-82 automation flips the stage to **Posted** — at which point the pledge and all its
   installments **disappear from every report in the folder**. Completed installment plans
   are currently invisible.
3. **Major Gift installment plans are excluded entirely.** Major Gift sits on
   `Donation_Process`, which has no "Pledged" stage, so the `StageName = 'Pledged'` filter
   silently excludes every Major Gift — even though this story and JSI-125 both treat Major
   Gift as a valid installment record type.

So DoD #1 is a genuine, and slightly larger, gap than "we might already have this".

## Outstanding Questions

**For Jason:**

1. **One report or two?** Paid installments carry a *Payment Date*; unpaid ones only have a
   *Scheduled Date*, so a single monthly grouping has to pick one. The plan proposes **one**
   report grouped by **scheduled month** with a paid/unpaid sub-grouping — every installment
   has a scheduled date, so nothing is hidden, and the month-by-month view shows what was
   collected against what was expected. The alternative is two reports, one grouped by
   payment month and one by scheduled month.
2. **Date range.** The plan proposes **no date restriction**, so a multi-year plan shows its
   completed past and its scheduled future in one view. The existing JSI-82 reports use
   current-FY windows, which would hide the later years of a 3-year pledge.
3. **Should the three existing "Stage = Pledged" reports be widened** to stop losing
   completed plans and Major Gifts (finding 2 and 3)? That is a fix to JSI-82's reports
   rather than new JSI-126 work, so it is *not* in the plan's build — flagging it as a
   separate call.

## Related Reference Material

- [`JSI-126_StoryDictationNotes.MD`](./JSI-126_StoryDictationNotes.MD) — Jason's dictation, the intent source.
- `JSI-125/JSI-125_Implementation_Plan.md` — delivers DoD #2 and #3.
- `JSI-82/JSI-82_Implementation_Plan.md` — built the pledge reports and the `Pledges_with_Payments__c` report type this story extends.
