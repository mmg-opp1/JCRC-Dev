# JSI-125 — Paid Installment Notifications

> **Source:** [JSI-125 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-125)
> Retrieved from Jira on 2026-08-17 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-125 |
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

> As a donor, I want the ability to pay a large donation in installment payments,
> and have the system notify me when a payment goes through.

## Definition of Done

> - Ability for jcrc development team member to enter an installation payment program for a
>   particular donor - corporate, non-profit, grant, individual
> - Donor receives notification that an installment payment has been submitted against an
>   existing pledge
> - Donor receives notification when the last payment has been made against that pledge

**Annotated with this-story scope:**

| DoD item | Scope call |
|---|---|
| 1. Enter an installment payment program | **Already delivered by JSI-82.** NPSP Payments with manual schedules, the Pledge record type, the pledge lifecycle stages and the write-off path all exist and were verified working today (see the Implementation Plan §3). Nothing to build. |
| 2. Notification per installment payment | **The main build**, and the whole subject of the dictation. |
| 3. **Notification when the last payment is made** | **In scope — and it is NOT in the dictation.** Jira asks for a second, distinct message when the pledge is fully satisfied. This is the one substantive gap between the two sources. |

## Notes & Context

**From Jason's dictation** (`JSI-125_StoryDictationNotes.MD`):

- Payment handling itself is **standard NPSP Payments** — not being rebuilt.
- When a payment goes to **Paid**, email the **donor** to say JCRC has received their
  pledge payment.
- The message should include **the amount paid to date**, **the amount still left**, and
  **the entire total**. All three map to native Opportunity fields — no new rollups needed.
- **Volume control is an explicit requirement.** Do not send this for every single donation.
  Only where a single Opportunity has **multiple payments**, and only for the **Pledge**,
  **Major Gift** and **Grant** record types. Jason's example: a one-off $18 online gift must
  not produce both an acknowledgment *and* a payment notification.
- No client template yet — build a reasonable sample, same position as JSI-87 and JSI-124.

## Outstanding Questions

**For Jason (design forks — answers change the build):**

1. **Is the filter `record type` AND `more than one payment`, or record type alone?**
   The dictation reads as both, which is how the plan plans it. Consequence worth confirming:
   a **pledge settled in a single payment sends nothing**. If that pledge should still
   notify, the rule becomes record-type-only.
2. **Should the email name the specific payment** ("we received your payment of $500 on
   17 Aug") or only the running totals? This is a real constraint, not a preference:
   `npe01__OppPayment__c` has **activities disabled** (verified), so it cannot be the
   `whatId` of a classic email template — a template can merge Opportunity fields but
   **not** payment fields. Naming the payment requires either stamping last-payment
   amount/date onto the Opportunity, or building the body in the flow instead of using a
   client-editable template. Full trade-off in the Implementation Plan §5.3.
3. **Confirm DoD #3 (final-payment notification) is in scope** — it is in Jira but absent
   from the dictation. The plan assumes yes, as a second template on the same flow.
4. **Who receives it for a corporate / foundation / grant pledge?** DoD #1 explicitly covers
   *corporate, non-profit, grant, individual*. The notification targets
   `Opportunity.npsp__Primary_Contact__c` (the same field the acknowledgment engine uses).
   For an organisational pledge that field may be blank, in which case nothing sends.
   Should there be a fallback, or is "no primary contact means no notification" acceptable?
5. **Written-off payments** — a written-off installment must presumably never notify.
   The plan excludes `npe01__Written_Off__c = true`. Confirm.

**For the client (JCRC):**

6. **Template copy** for both messages — the per-installment notification and the
   final-payment thank-you.
7. **Should these notifications carry any tax or receipt language?** The plan assumes **no**
   — they are payment notifications, not receipts; the tax acknowledgment is JSI-87's job
   and would otherwise double up. Worth confirming with whoever owns donor communications.

## Related Reference Material

- [`JSI-125_StoryDictationNotes.MD`](./JSI-125_StoryDictationNotes.MD) — Jason's dictation, the intent source.
- `JSI-82/JSI-82_Implementation_Plan.md` — the pledge + NPSP Payments model this story sits on (DoD #1).
- `JSI-87/` — the acknowledgment engine; shares the email-sending pattern and the OWEA dependency.
- `JSI-124/JSI-124_Implementation_Plan.md` — where the OWEA blocking behaviour was discovered.
