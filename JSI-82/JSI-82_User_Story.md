# JSI-82 — Track pledges separately from one-time gifts

> **Source:** [JSI-82 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-82)
> Retrieved from Jira on 2026-06-19 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-82 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | Must-Have, US-016 |
| **Feature Owner** | Gift Officer |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-19 |

## User Story

> As a member of the Development team, I want pledges tracked separately from
> one-time gifts, so that we can report on **outstanding pledge balances** and
> **forecast cash flow**.

## Definition of Done

- Pledges entered as Opportunities with a stage of "Pledged" and an expected payment schedule.
- Each pledge payment recorded as a related Opportunity Payment in NPSP.
- Pledge balance calculated as total pledged minus total received.
- Reports show outstanding pledges, pledges due this fiscal year, and overdue pledges.
- Multi-year pledges supported with payments spanning fiscal years.
- Pledge written-off process documented for uncollectible / uncollected commitments.

## Notes & Context

**JCRC Notes**
- How do we count receivables if received outside the pledged fiscal year — counting the
  pledge vs. payments made (reporting; reconciliation)? If this donation is an HRS, when
  does it count against the FY HRS?

**MAF Notes**
- "I'm unclear on what this means. Pledges are also sometimes one-time gifts."

## Outstanding Questions

- **Fiscal-year recognition:** When a payment is received outside the fiscal year in which
  the pledge was made, do we recognize it against the pledge's FY (accrual) or the payment's
  FY (cash)? This drives the reporting and reconciliation model. (See `NPSP_PledgeDocumentation.md`
  §"Accrual vs. cash" — the choice of NPSP pledge model hinges on this.)
- **HRS interaction:** If a pledged donation is an HRS, in which fiscal year does it count
  against the FY HRS total?
- **Scope of "pledge":** Per MAF, clarify the boundary between a *pledge* (multi-payment
  commitment) and a *one-time gift* that is simply promised/paid later — i.e., does a
  single-payment future commitment belong in this story or in JSI-80?
- 🚩 **CLIENT CONFIRMATION NEEDED — Partial-payment reconciliation (Option B):** When a donor
  pays *some* installments and then defaults ("Partially Posted"), the current design
  **overwrites the Opportunity Amount to the collected total** and records the uncollected
  remainder in a **custom** "Pledge Written-Off" field — it does **not** use NPSP's native
  write-off (which would break NPSP's Remaining Balance formula once Amount is reduced). This
  makes donor/campaign totals reflect *collected* dollars, but the **original committed pledge
  amount is no longer shown** on the record. Confirm with the client before go-live whether
  this is acceptable, or whether they need the original commitment preserved (Option C). See
  `JSI-82_Implementation_Plan.md` §6.3.

## Related Reference Material

- [`NPSP_PledgeDocumentation.md`](./NPSP_PledgeDocumentation.md) — Salesforce/NPSP pledge
  documentation (Manage Pledges, accrual vs. cash models) gathered for this story.
