# JSI-55 — Log bulk email sends on constituent record

> **Source:** [JSI-55 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-55)
> Retrieved from Jira on 2026-07-21 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-55 |
| **Type** | Story |
| **Status** | To Do |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-3 — Email Marketing (Constant Contact) |
| **Sprint** | Implementation Sprint 2 |
| **Labels** | Should-Have, US-051 |
| **Feature Owner** | Communications |
| **Reporter** | Jason Ott |

## User Story

> As a Communications staff member, I want all bulk email sends logged on the constituent
> record, so that anyone reaching out to a donor knows what we've recently sent them.

## Definition of Done

- Email send activity appears in the Contact's activity history.
  - Subject line, send date, and engagement (opened/clicked) shown.
  - Activity searchable and filterable.
  - Visibility controlled by security profile for sensitive campaigns.
  - Staff trained on checking activity before personal outreach.

## Notes & Context (dictation — Jason)

- **Verify/close-out story** — "very much the same as JSI-50." Review the docs + DoD against what's **already built** (esp. JSI-109) and Constant Contact functionality; confirm it's accounted for. **If there's nothing to implement, close as "not for implementation."** Only produce an implementation plan if a real gap exists.
- **Explicit scope call:** Constant Contact sends do **NOT** need to appear in the native **Activity timeline** — that DoD item is AI-generated. **The `CC_Email_Activity__c` related list on the Contact (JSI-109) is the intended "log," and it suffices.**

## Outstanding Questions / Gaps (Step 2)

1. **"Activity history" = related list, not native timeline** — confirmed reinterpretation (Jason). Native Task/Activity logging per send is explicitly **out**. (If the client later insists on the native timeline, that's a separate net-new build.)
2. **"Visibility controlled by security profile for sensitive campaigns"** — the engagement object already respects **profile FLS** (staff read; poller-maintained fields read-only). If "sensitive campaigns" means *per-campaign* restricted visibility (some sends hidden from some staff), that is **not built** — needs a client decision on whether that's actually required.

## Related Reference Material

- [`../JSI-109/JSI-109_Implementation_Plan.md`](../JSI-109/JSI-109_Implementation_Plan.md) — the email-engagement model (`CC_Email__c` / `CC_Email_Activity__c`) that delivers this story.
- [`../JSI-50/JSI-50_Implementation_Plan.md`](../JSI-50/JSI-50_Implementation_Plan.md) — the sibling verify/no-build CC story.
