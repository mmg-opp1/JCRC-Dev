# JSI-121 — Sync CRM with Director of Finance's QBO accounts

> Snapshot of the Jira story pulled 2026-09-16 (one-way — Jira already has a description and DoD, so
> nothing is pushed back). **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-121

## Overview

| | |
|---|---|
| Type | Story |
| Status | To Do |
| Priority | Lowest |
| Labels | Must-Have, US-064 |
| Epic | JSI-13 — Integrations & Data Sync |
| Sprint | Implementation Sprint 2 |
| Reporter | Jason Ott |
| Assignee | — |
| Created / Updated | 2026-06-18 / 2026-07-09 |

## User Story

> As a Development Team member, I want my CRM to be in sync with the Director of Finance's accounts in
> QBO.

## Definition of Done (with this-story scope)

- **Link using QBO account information with Salesforce account information.**
  _Scope: Phase 5 (QuickBooks sync). Design keeps the QBO transaction/customer id on the holding row;
  linking QBO customers to Accounts is settled when the sync is built (overlaps JSI-81)._
- **Daily feed from QBO to NPSP of any updates.**
  _Scope: Phase 5 — next phase per decision D1. Blocked on Finance confirming how ACH/wire is recorded
  in QuickBooks._
- **Allow for review process before posting into NPSP.**
  _Scope: **this build (Phases 1–4)** — the Pending Transactions holding area, the review/commit screen,
  and conversion into gifts or pledge payments._

## Notes & Context

- Dictation (Jason, 2026-09-16): ACH and wire gifts go to the bank first, then QuickBooks, then sync into
  a Salesforce **holding area**. Staff review and edit everything (including donor), choose **new gift**
  or **payment on an open pledge**, and commit one by one or in selected batches. The holding record is
  deleted on commit to keep storage down. Screen must be clean, fast for data entry, sleek and modern.
- Addendum (Jason, 2026-09-16): the **Gala sponsorship page** (`https://jcrcnygala.org/sponsor/`, Stripe)
  will also send webhooks to Salesforce. **Pay Now** submissions go **into this holding table**;
  **Pay Later** submissions create a **Pledge** directly. That intake is built as **separate work** —
  see Implementation Plan §4.7 for where it touches this story.
- Related stories: JSI-81 (reconcile account info NPSP ↔ QBO), JSI-88 (gift batches ↔ bank deposits),
  JSI-39 (finance reconciliation report), JSI-16 (paper checks vs bank records), JSI-80 (Gift Entry).

## Outstanding Questions / Design Decisions

See `JSI-121_Implementation_Plan.md` §2 (D1–D12 settled or defaulted 2026-09-16) and the open questions
for Finance (QuickBooks record type and fields for ACH/wire).

## Related Reference

- `JSI-121_Implementation_Plan.md`
- `Website_Donations/Website_Donation_Integration_Design.md` — the existing webhook → staging pattern
- `Gala_Gifts/Gala_Gifts_Design.md` — Gala Level / Table / Guest model the sponsor intake will use
