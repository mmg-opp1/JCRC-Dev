# JSI-126 — Implementation Game Plan: Installation Payment Reports

> **Story:** [JSI-126](https://missionmattersgroup.atlassian.net/browse/JSI-126) — Installation Payment Reports (Epic JSI-8 Fundraising)
> **Author:** Jason Ott · **Written:** 2026-08-17
> **Status:** **PLAN ONLY — no build.** Per the dictation, implementation starts after
> clarifications are settled and this plan is reviewed.
>
> **Change Log:**
> - 2026-08-17 — Jason Ott — Initial plan: Jira pull, dictation reconciliation, full report audit, design.

---

## 1. Scope

**In scope**

- A **monthly installment report covering paid *and* unpaid installments** (DoD #1) —
  the one genuine gap, confirmed by reading all eight existing pledge reports (§3).
- Extending the existing `Pledges_with_Payments__c` report type with the few Opportunity
  fields the report needs but which it does not currently expose.

**Out of scope — already delivered**

- **DoD #2 (final letter)** — JSI-125's `Pmt_Email_Final_Payment`.
- **DoD #3 (payment recorded, total received, remaining balance)** — JSI-125's
  `Pmt_Email_Installment`.
- Both already carry the filtering Jason restated in this dictation (Pledge / Major Gift /
  Grant, more than one payment), built and verified on 2026-08-17.

**Deliberately not in this story**

- Widening JSI-82's three `Stage = Pledged` reports (§3 findings 2 and 3). That is a fix to
  existing reports, not new installment reporting — raised as Q3 for a separate call.

---

## 2. The decision — extend the existing report type, add one report

### 2.1 Decision

Add the missing Opportunity columns to **`Pledges_with_Payments__c`** and build **one**
Summary report, rather than creating a second report type or a custom object.

### 2.2 Why

`Pledges_with_Payments__c` (JSI-82) is already an Opportunity → `npe01__OppPayment__r` join
and already exposes the payment-side fields this needs — **Payment Amount, Scheduled Date,
Payment Date, Paid, Written Off, Days Past Due, Aging Bucket**. It is the right base and it
is already trusted by four live reports.

What it does **not** expose, and what the new report needs:

| Missing field | Needed for |
|---|---|
| `Opportunity.RecordTypeId` | the Pledge / Major Gift / Grant filter |
| `Opportunity.npe01__Number_of_Payments__c` | the "more than one payment" filter |
| `Opportunity.npe01__Payments_Made__c` | total paid to date, per DoD #3 wording |
| `Opportunity.AccountId` | who the plan belongs to |

Adding columns to a report type is **additive** — the four existing reports are unaffected,
because a report only breaks if a column it *uses* disappears.

---

## 3. Verified org context — the full report audit (2026-08-17)

Every report in the org was enumerated from the live org (`SELECT FolderName, Name,
DeveloperName, Format FROM Report`), and each of the eight in `Pledge and Grant Reports`
was **read in full**, not judged by its name.

| Report | Real filters | Paid installments? |
|---|---|---|
| Pledge Payment Schedule (Remaining) | `Paid = 0` AND `Written_Off = 0` AND Stage = Pledged; grouped by Scheduled Date | **No** |
| Pledge Payments Due This Fiscal Year | `Paid = 0` AND `Written_Off = 0` AND Stage = Pledged; current FY | **No** |
| Pledge Payment Aging | `Days Past Due > 0` AND Stage = Pledged; grouped by Aging Bucket | **No** |
| Outstanding Pledges | Stage = Pledged AND `Amount_Outstanding > 0`; Opportunity grain | Totals only |
| Overdue Pledges / New Pledges This FY / Write-Offs / By Lifecycle Stage | Opportunity grain | n/a |

**Finding 1 — nothing reports paid installments.** All four payment-level reports filter
`npe01__Paid__c = 0`. They are forecast and receivables views by design (JSI-82's purpose).
The paid-and-unpaid monthly view does not exist. **DoD #1 is a real gap.**

**Finding 2 — completed plans vanish.** Every one of these filters `StageName = 'Pledged'`.
When a plan completes, JSI-82's `Opportunity_FullyPaidPledgeToPosted` flips the stage to
**Posted**, and the pledge plus all of its installments drop out of every report in the
folder. A finished installment plan is currently invisible in reporting.

**Finding 3 — Major Gift is silently excluded.** Major Gift runs on `Donation_Process`,
which has no "Pledged" stage at all, so the same filter excludes every Major Gift
installment plan — even though JSI-125 and this story both treat Major Gift as a valid
installment record type.

**The new report therefore must not filter on StageName at all.** It keys off the payment
data and the record type instead, which is both more correct and immune to the stage
automation.

Other verified facts:

| Fact | Value |
|---|---|
| Report type | `Pledges_with_Payments__c`, base Opportunity, inner join `npe01__OppPayment__r`, 12 exposed columns |
| Payment-side fields already exposed | Payment Amount, Scheduled Date, **Payment Date**, Paid, Written Off, Days Past Due, Aging Bucket |
| Report folder | `Pledge and Grant Reports` (JSI-82) — the new report belongs here |
| Record types | Pledge `012iI0000000Dq9QAE`, Major Gift `012iI0000000Dq7QAE`, Grant `012iI0000000Dq5QAE` |

---

## 4. Requirement → mechanism

| Requirement | Mechanism |
|---|---|
| Monthly view of installments | Summary report grouped by **Scheduled Date**, month granularity |
| Paid **and** unpaid in one view | **No `Paid` filter**; `Paid` becomes a sub-grouping so each month splits into collected vs outstanding |
| Only installment plans | `npe01__Number_of_Payments__c > 1` |
| Only Pledge / Major Gift / Grant | Record-type filter (§5.2) |
| Exclude write-offs | `npe01__Written_Off__c = false` |
| Total received / remaining | `npe01__Payments_Made__c` and `npe01__Amount_Outstanding__c` as columns |
| Must not hide completed plans | **No StageName filter** (§3, findings 2–3) |

---

## 5. Design

### 5.1 New / changed metadata

| Component | Change |
|---|---|
| `Pledges_with_Payments__c` | **Extend** — add `RecordTypeId`, `npe01__Number_of_Payments__c`, `npe01__Payments_Made__c`, `AccountId` to the Opportunities section |
| `Installment Payments by Month` | **New** Summary report in `Pledge and Grant Reports` |

No fields, no Apex, no flows. Nothing existing is modified beyond additive report-type columns.

### 5.2 The record-type filter — the one thing to verify at build

The documented gotcha for a **standard** report type is column `RECORDTYPE` with an
object-qualified DeveloperName (`Opportunity.Pledge,Opportunity.Major_Gift`). Whether a
**custom** report type accepts the same form is **not established** in this org — no existing
custom-report-type report filters on record type.

**Build approach:** try the object-qualified `RECORDTYPE` form first and let the deploy
adjudicate (deploy-error-driven, as with the JSI-124 `TEXT()` fix). If the platform rejects
it, the fallback is a text formula field on Opportunity exposing the record-type
DeveloperName, filtered as a normal text column. **Do not assume either way.**

### 5.3 Report specification — `Outstanding Installments by Month`

**Revised 2026-08-17 after Jason's steer.** The original spec listed paid *and* unpaid
installments as rows. Jason corrected the grain: *"I don't think we need to report
specifically on payments that are already paid. I believe the client is just interested in
opportunities that have outstanding payments. On that report they may want to know how
much/how many payments have been made, but that should be accessible through
Payment → Opportunity."*

So the rows are **outstanding installments only**, and the paid-to-date context arrives as
**Opportunity columns** through the report type's existing Payment → Opportunity join —
no paid-payment rows at all. This is both what the client wants and a shorter report.

| Aspect | Spec |
|---|---|
| Report type | `Pledges_with_Payments__c` |
| Format | Summary |
| Grouping | `npe01__Scheduled_Date__c`, **month** granularity, ascending |
| Filters | `Paid = false`, `Written_Off = false`, `Number_of_Payments > 1`, record type in (Pledge, Major Gift, Grant) |
| Stage filter | **None** — deliberately (§3, findings 2–3) |
| Date range | **None** (§5.4) |
| Row columns | Opportunity Name, Account, Stage, Payment Amount (Sum), Days Past Due |
| Opportunity context columns | Amount, **Payments Made** (how much), **Payments Made (Count)** (how many), Number of Payments, Amount Outstanding |

### 5.3a "How many payments have been made" needed a new field

`npe01__Payments_Made__c` answers *how much* (SUM of paid payments — verified). Nothing
answered *how many*: **`npe01__Number_of_Payments__c` counts every payment including unpaid
scheduled ones** (verified — three unpaid installments read 3), so it cannot be used for
"payments made".

Added **`Opportunity.Payments_Made_Count__c`** — native Roll-Up Summary, COUNT of payments
where `Paid = true`. Same pattern as JSI-125's `Last_Payment_Date__c`: Payment is a
master-detail child, so this is real-time and needs no DML.

### 5.4 Why no date window

Every comparable JSI-82 report uses a current-FY or current-period window. That is right for
a cash-flow forecast and wrong here: a three-year pledge would show only the middle year,
hiding both the installments already collected and those still to come. The point of this
report is the **whole plan, paid and unpaid**, so it ships unwindowed and grouped by month;
anyone who wants a single month filters the grouping.

### 5.5 Security

None required. Reports inherit folder access, and every field used is already readable on
the relevant profiles from JSI-82 and JSI-125.

---

## 6. Research

NPSP ships no installment-plan report of this shape — its payment reporting is the
Opportunity-with-Payments join that JSI-82 already turned into `Pledges_with_Payments__c`.
There is no managed report or package component to reuse, so a custom report on that
existing report type is the platform-standard answer.

Worth stating plainly: **most of this story was already built.** JSI-125 delivered DoD #2 and
#3 in full, with the exact filtering restated here. The remaining work is one report, and the
audit that proved it was missing is a larger part of the value than the build.

---

## 7. Risks

1. **Record-type filter syntax on a custom report type is unverified** (§5.2). Mitigated by
   trying it and having a concrete fallback.
2. **Report deploys are transactional** — the folder and report deploy together, and a bad
   column rolls the whole thing back. Known from JSI-84/85.
3. **Findings 2 and 3 remain live** unless Q3 is actioned: completed plans and Major Gift
   plans stay missing from JSI-82's four existing reports. The new report is not affected,
   but the old ones still mislead.

---

## 8. Phased build (on go-ahead)

| Phase | Work | Gate |
|---|---|---|
| **1** | Extend `Pledges_with_Payments__c` with the four Opportunity columns | — |
| **2** | Build `Installment Payments by Month`; resolve the record-type filter syntax | Q1, Q2 |
| **3** | Verify against real data — seed a multi-installment pledge and a Major Gift plan in a savepoint, confirm both appear and that paid + unpaid both show | — |
| **4** | *(only if Q3 = yes)* widen JSI-82's `Stage = Pledged` reports | Q3 |

---

## 9. Decisions to settle before build

| # | Decision | Recommendation |
|---|---|---|
| **D1** | One report grouped by scheduled month, or two (paid-by-payment-month + unpaid-by-scheduled-month)? | **One** — every installment has a scheduled date, so nothing is hidden and the month shows expected vs collected |
| **D2** | Date window? | **None** — show the whole plan (§5.4) |
| **D3** | Widen JSI-82's existing Stage = Pledged reports? | Jason's call — it is a fix to prior work, not this story |

---

## 10. Sources

- Live org report inventory + full read of all 8 `Pledge and Grant Reports` definitions, 2026-08-17.
- In-repo: `JSI-82/` (report type + existing reports), `JSI-125/` (DoD #2 and #3).

---

## 11. Build Log

### 2026-08-17 — BUILT + DEPLOYED + VERIFIED (JCRC-Dev)

**Deployed**

| Component | Notes |
|---|---|
| `Opportunity.Payments_Made_Count__c` | Native RUS, COUNT of payments where `Paid = true` (§5.3a). FLS read-only on Admin + 4 JCRC; repo profiles documented. |
| `Pledges_with_Payments__c` | **Extended** (additive) with Opportunity `RecordType`, `Account`, `npe01__Number_of_Payments__c`, `npe01__Payments_Made__c`, `Payments_Made_Count__c`. The four existing reports are unaffected. |
| `Outstanding Installments by Month` | New Summary report in `Pledge and Grant Reports`, per §5.3. |

**Verified — anon Apex, `setSavepoint()` → `rollback()`**

Seeded a 3-installment **Pledge** with one paid, a 2-installment **Major Gift** with none
paid, and a single-payment **Donation**, then ran the report's filter criteria as SOQL:

| Expectation | Result |
|---|---|
| Exactly 4 rows | **PASS** — 2 remaining pledge installments + 2 Major Gift installments |
| Single-payment $250 Donation excluded | **PASS** — absent |
| Paid installment not listed as a row | **PASS** — the paid one does not appear |
| Paid context carried on the Opportunity | **PASS** — pledge rows show `paidSoFar=1000.00`, `pmtsMade=1`, `ofTotal=3`, `outstanding=2000.00` |
| Major Gift plans included | **PASS** — and the same query proved **2 Major Gift installments are invisible to the existing `Stage = Pledged` reports**, confirming finding 3 with real data rather than by inspection |

**Gotchas hit — three, all new**

1. **Report-type columns use `RecordType`, not `RecordTypeId`** — `RecordTypeId` fails
   *"Could not find field RecordTypeId in table Opportunity."*
2. **And `Account`, not `AccountId`**, for the parent account column — same failure shape.
3. **The record-type filter VALUE still needs the object-qualified DeveloperName**, exactly
   as for standard report types: `Opportunity.Pledge,Opportunity.Major_Gift,Opportunity.Grant`.
   Plain labels fail *"no RecordType named Pledge found."* **This resolves the §5.2 open
   question: a custom report type takes the same value form as a standard one, but a
   different column name.** No formula-field fallback was needed.
4. Re-confirmed the known rule: **a grouped field cannot also be a column**
   (*"You can't include groupings in the selected columns list"*) — Scheduled Date is the
   grouping, so it was removed from the column list.

**Not built (deliberate)**

- **Widening JSI-82's four `Stage = Pledged` reports** (findings 2–3). Still open as D3 —
  it is a fix to prior work, and the new report already covers the gap for outstanding
  installments. Those reports remain misleading for completed plans and Major Gifts.
