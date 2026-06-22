# JSI-80 — Upload reconciled snail-mail donations into CRM

> **Source:** [JSI-80 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-80)
> Retrieved from Jira on 2026-06-18 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-80 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | Must-Have, US-013 |
| **Feature Owner** | Development Operations |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-18 |

## User Story

> As a member of the JCRC NY Development team, I want snail mail donations to be
> uploaded into our CRM once they are reconciled in our bank account, recording
> **donor, amount, fund, campaign and approach**, and the **source** of the
> donation.

## Definition of Done

- Standard intake spreadsheet template defined for batch entry of mailed gifts.
- NPSP Gift Entry batch tool configured for bulk entry with required fields enforced.
- Required fields include: donor (matched to existing contact), amount, gift date, fund, campaign, approach (channel).
  - _DM >> TBD if Simcha will capture this information in QBOA. Would be great if he can._
- Donor matching uses fuzzy match with reviewer confirmation before save.
- Reconciliation field captures the bank deposit batch number for finance traceability.
- Acknowledgment status defaults to "Not Acknowledged" so gifts are queued for thank-you processing.
- Audit trail records who entered the gift and when.
- Enable validation of batch upload.
- Enable corrections of data post batch upload.

## Notes & Context

**JCRC Notes**
- Replaces the duplicate version of this story.
- **DM** — define how we want to address payments from DAFs:
  - How are we linking between individuals and DAFs (e.g., JCF)?
  - How can we create a report where information reflects the **donor**, rather than the **payor** (DAF) — setting up soft credits?
  - Make sure the gift isn't double-counted.

## Outstanding Questions

- Some of these gifts will be synced from QBO after they are entered from Simcha.
  - Will somebody be responsible for finding the gift and adding the extra info that Simcha hasn't added?
  - Will there ever be a time when somebody needs to create a gift batch using a spreadsheet or manually that does **not** already pass through Simcha?
- What is the matching criteria for donors? First Name + Last Name + something else?

## Related Reference Material

- [`SalesforceHelp_NPSPGiftEntry.txt`](./SalesforceHelp_NPSPGiftEntry.txt) — Salesforce/NPSP Gift Entry help documentation gathered for this story.
