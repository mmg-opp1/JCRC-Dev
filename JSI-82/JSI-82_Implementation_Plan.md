# JSI-82 — Implementation Game Plan: Track Pledges Separately from One-Time Gifts

> **Status:** Plan only — no build yet.
> **Author:** Jason Ott · **Date:** 2026-06-20 (**rev. 4** — Partially Posted reconciliation set to Option B; flagged for client confirmation)
> **Related:** `JSI-82_User_Story.md`, `JSI-82_Dictation.md`, `NPSP_PledgeDocumentation.md`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-82
> **🚩 NEEDS CLIENT CONFIRMATION:** the **Partially Posted** "Amount vs. write-off" reconciliation is set to **Option B** (§6.3) **for now** — confirm with the client before go-live, since it overwrites the Opportunity `Amount` to the collected total and records the uncollected remainder in a custom field rather than NPSP's native write-off.

---

## 1. Scope

**IN scope:** Configure NPSP so the Development team tracks **pledges** (multi-payment
commitments) on the **Opportunity** object, distinguished from one-time gifts by a dedicated
**Record Type**, with installments on the standard **NPSP Payment** object
(`npe01__OppPayment__c`); full pledge **lifecycle** (commitment → fully/partially paid →
written off); per-pledge control over auto-payment creation; the financial fields (total
pledged, received, remaining balance, **amount due to date**); pledge reports; documented
write-off process.

Also (decision #6) stands up the **Opportunity Record Type set** (Donation, Pledge, Grant,
In-Kind Gift, Major Gift, Matching Gift, Securities Gift) plus the **Donation stewardship
pipeline** and **Pledge lifecycle** stages, since the Pledge type can't be defined coherently
without them. Deep per-type build-out (their own layouts/automation) follows in later stories.

**Recognition policy (decided):**
- **Pledges → accrual:** recognized at **commitment** (books as a receivable). §5.2.
- **One-time donations → recognized when collected:** they move through a **stewardship
  pipeline** (Prospecting → Cultivating → **Posted**) and are *not* auto-closed. §5.2, §5.5.

**OUT of scope:** DAF/soft-credit handling; deep per-record-type build-out beyond
record-type/visibility/stages/payment behavior.

---

## 2. Architectural decision — **Accrual model: Opportunity + Payments** ✅

| Model | Mechanism | Verdict |
|-------|-----------|---------|
| **Option #1 — Accrual** ✅ | One Opportunity = full pledge; installments are **Payment** records; full amount counts when the Opp is **Won**. | **CHOSEN** — matches the dictation (Opportunity + standard Payments) and decision #1 (recognize at commitment → receivable). |
| **Option #2 — Cash (Recurring Donations)** ❌ | RD = pledge; each installment is its own Opp. | **REJECTED** by the dictation and by decision #1. |

> Sources: `NPSP_PledgeDocumentation.md`; [Manage Pledges (SF Help)](https://help.salesforce.com/s/articleView?id=sfdo.Manage_Pledges.htm&type=5)

---

## 3. Verified org context (JCRC-Dev, 2026-06-19 — not assumed)

| Fact | Verified via | Implication |
|------|--------------|-------------|
| NPSP 3.237 + Payments installed; **DLRS v2.25 installed** | `sf package installed list` | Payment model + declarative rollup path available. |
| **Payments ENABLED**, **Max Payments = 12**, **auto-close stage BLANK**, **no RT exclusions** | SOQL on `npe01__Contacts_And_Orgs_Settings__c` | Raise/remove Max Payments (#3); **keep auto-close BLANK** (#4 revised, §5.5); exclude Pledge/Grant/In-Kind from auto-create (#2, R-Q3). |
| **Only `NPSP_Default` RT**; **no Pledged/stewardship stages** | SOQL + `describe` | Build the 7-type set + both stage sets. |
| **`JCRC - Fundraising` profile EXISTS** (+ Development/Marketing/Volunteering) | SOQL on Profile | Assign RT visibility now. |
| **0 Opportunities, 0 Payments** | `COUNT(Id)` | **Greenfield** — safe to repurpose `NPSP_Default`; no migration. |

---

## 4. Requirement → mechanism. **Most "new fields" already exist natively.**

| Dictated requirement | NPSP-native field | Definition (verified) | Build? |
|---|---|---|---|
| Total pledged | **`Amount`** | Full pledge (see §6.3 for partial-default adjustment). | ✅ exists |
| Amount paid | **`npe01__Payments_Made__c`** (*Payment Amount Received*) | SUM of Payments where Paid = true. | ✅ exists |
| Amount outstanding + formula | **`npe01__Amount_Outstanding__c`** (*Remaining Balance*) | `Amount − Payments_Made − Amount_Written_Off`. | ✅ exists |
| Write-offs / count | **`npe01__Amount_Written_Off__c`**, **`npe01__Number_of_Payments__c`** | Rollups. | ✅ exists |
| Auto-create payments or not, per pledge | **`npe01__Do_Not_Automatically_Create_Payment__c`** | Per-record suppression. | ✅ exists |
| **Amount due to date** | — none — | Past-due unpaid expected amount. | ❌ **NET-NEW (§6.1)** |

---

## 5. Native configuration

### 5.1 Record Types (decision #6, R-Q3) — **[CLI]**
Create 7 Opportunity record types; assign all to **System Administrator** + **JCRC –
Fundraising**; **Donation = default for both**.

| Record Type | Payments | Stage process |
|---|---|---|
| **Donation** (default) | Auto-create single payment | **Donation pipeline** (§5.2). Repurpose `NPSP_Default` → "Donation" (relabel; keep DeveloperName so NPSP wiring stays intact). |
| **Pledge** | **Exclude** from auto-create (#2 — manual schedules) | **Pledge lifecycle** (§5.2). |
| **Grant** | **Exclude** (R-Q3 — installment-paid, treat like Pledge) | Pledge lifecycle (confirm any grant-specific stages later). |
| **In-Kind Gift** | **Exclude** (no cash payment) | Simple (Received/Posted) — refine in its own story. |
| **Major Gift** | Auto-create single | Donation pipeline (if pledged, use **Pledge**). |
| **Matching Gift** | Auto-create single | Donation pipeline. |
| **Securities Gift** | Auto-create single | Donation pipeline; aligns with JSI-80 "Stock/Securities/Crypto". |

> **JSI-80 coordination:** Gift Entry templates target **Donation** / **Securities Gift**. Not built yet → no rework.

### 5.2 Stages — two processes — **[CLI]**
`IsWon = true` implies `IsClosed = true`; NPSP rolls committed dollars into donor/campaign
totals only for **Won** opportunities. Hence:

**Donation stewardship pipeline** (recognized when collected):
| Stage | Closed | Won | Meaning |
|---|---|---|---|
| Prospecting | ✗ | ✗ | Identified, open pipeline. |
| Cultivating | ✗ | ✗ | Being worked by a fundraiser. |
| **Posted** | ✅ | ✅ | Collected / done. |
| Declined (Closed Lost) | ✅ | ✗ | Did not materialize. |

**Pledge lifecycle** (accrual — recognized at commitment):
| Stage | Closed | Won | Meaning |
|---|---|---|---|
| **Pledged** | ✅ | ✅ | Committed → full amount recognized (receivable booked); Remaining Balance = outstanding receivable. |
| **Posted** | ✅ | ✅ | **All** installments collected. |
| **Partially Posted** | ✅ | ✅ | Some collected, remainder written off (donor stopped). Final. §6.3. |
| **Written Off / Cancelled** | ✅ | ✗ | Committed but **zero** collected → removed from gift totals. §6.2. |

*"Posted" is shared by both processes (one picklist value, included in both business
processes). Stages are wired to record types via business processes.*

### 5.3 Payment auto-creation (decision #2, R-Q3) — **[UI setting + field]**
Add **Pledge, Grant, In-Kind Gift** to `npsp__Opp_RecTypes_Excluded_for_Payments__c` (no
auto-create). Keep `npe01__Do_Not_Automatically_Create_Payment__c` on the Pledge layout for
per-record exceptions. Pledge/Grant schedules are built **manually** via Schedule Payments.

### 5.4 Payment schedule & Max Payments (decision #3) — **[UI]**
- **No max-payment blocker (#3):** set `npsp__Max_Payments__c` to a very high value (e.g.,
  **250**) so the Schedule Payments wizard supports long multi-year pledges; additional/longer
  schedules can also be entered manually or via data import / Gift Entry.
- ⚠️ **Unverified (research roadblock):** official Salesforce Help ("Configure Opportunity
  Payments") is **JS-protected / didn't render**, and the mirror had a TLS error — so I could
  **not** confirm a documented hard ceiling, nor formally confirm the cap is wizard-only.
  Treatment: set generously and **verify the chosen value in-org** during build. (User: "no
  blocker on max payments.")

### 5.5 Fully-paid close — **record-type-specific (decision #4 revised)** — **[Flow]**
- **Leave the global `npsp__Payments_Auto_Close_Stage_Name__c` BLANK** — it is a single
  org-wide setting, so using it would wrongly auto-close one-time **Donations** (which must be
  worked manually through Prospecting → Cultivating → Posted).
- **Pledge auto-close via Flow:** record-triggered Flow — when a **Pledge** is fully collected
  (`Remaining Balance = 0` AND `Amount Written Off = 0` AND `Payment Amount Received > 0`) →
  set Stage = **Posted**. (Pledge is already Closed/Won at Pledged; this is a stage move.)
- **Donations:** no auto-close; fundraiser sets **Posted** manually when collected.

### 5.6 Write-off & lifecycle automation — **[Flow + Docs]**
- **Written Off / Cancelled** (zero collected): fundraiser sets the stage → Flow writes off
  all payments; stage is **Closed/not-Won**, removing the pledge from gift totals.
- **Partially Posted** (some collected): fundraiser sets the stage → Flow performs the §6.3
  reconciliation (per the chosen Option).
- Runbook documents both, plus native single/all write-off (Jira DoD).

---

## 6. Financial fields & the partial-payment model

### 6.1 "Amount Due To Date" (decision #5) — **DLRS net-new field**
**Definition (worked example #5):** today 6/19; 6 × $1,000 due by 6/15; $5,000 paid → **Amount
Due = $1,000** = the expected-to-date amount still unpaid.

- `Opportunity.Amount_Due_To_Date__c` (Currency) =
  **SUM `npe01__Payment_Amount__c`** where
  **`npe01__Paid__c = false` AND `npe01__Written_Off__c = false` AND `npe01__Scheduled_Date__c <= TODAY`**
  (DLRS: child `npe01__OppPayment__c` → parent via `npe01__Opportunity__c`).
- Verified to yield exactly **$1,000** on example #5; equals "expected-to-date − paid-to-date"
  for discrete installments (the normal case here).

**Why not native:** RSF can't filter on `TODAY` ("No Plans to Implement"); NPSP Customizable
Rollups can't target Opportunity. **DLRS can.**

**Mandatory nightly Full Calculate:** the value changes as installments cross their due date
with no record edit. DLRS rollup = **Realtime** (edits) **+ scheduled nightly Full Calculate**
(date rollover). DLRS docs are explicit that date-relative rollups need this.

### 6.2 Full default → Written Off / Cancelled (zero collected)
Fundraiser sets stage **Written Off / Cancelled** → Flow writes off all payments. Stage is
**not Won** → the pledge drops out of donor/campaign gift totals (you don't credit a gift never
paid). Original `Amount` may remain as historical record (it no longer rolls up).

### 6.3 Partially Posted reconciliation — **Option B (selected) · 🚩 needs client confirmation**
NPSP's managed formula `Remaining Balance = Amount − Payment Amount Received − Amount Written
Off` makes the two requests — **(a)** write off the uncollected remainder *and* **(b)** set
`Amount` = collected total — **mutually exclusive** (doing both drives Balance negative).
Example: $5,000 pledge, $4,000 collected, $1,000 uncollected.

**Selected — Option B** (matches the dictation: Opp `Amount` reads the collected total):
- Flow (on Stage → Partially Posted) sets `Amount = Payment Amount Received` (e.g., $4,000);
  records the uncollected remainder (e.g., $1,000) in a **custom** `Pledge_Written_Off__c`
  field; cancels the unpaid payment so **Remaining Balance = $0**.
- Donor/campaign rollups credit the **collected** amount ($4,000) — accurate.
- **Trade-off (the reason for the flag):** this **does not use NPSP's native write-off field**
  (the native one would force a negative balance once `Amount` is reduced), and it **overwrites
  the original committed `Amount`**, so the original pledge size is no longer visible on the
  record. Consider also storing the original pledge in a custom `Original_Pledge_Amount__c` for
  history.

> 🚩 **CLIENT CONFIRMATION REQUIRED before go-live.** Option B is adopted *for now*. If finance
> needs to **preserve the original committed amount** as history and/or use NPSP's **native**
> write-off, switch to **Option C** (keep `Amount = 5,000`; native write-off; reconfigure
> donor/campaign rollups to sum *paid Payments*). Alternative **A** keeps everything native but
> lets Amount-based rollups overstate giving by the written-off amount.

| Option | Mechanics | Rollup credit | Trade-off |
|---|---|---|---|
| **A** | Keep `Amount = 5,000`; **native** write-off 1,000 → Balance auto 0 | **5,000** (overstates) | All-native; Amount-based rollups overstate giving. |
| **B** ✅ *(selected — pending client confirmation)* | Flow sets `Amount = 4,000`; uncollected 1,000 → **custom** `Pledge_Written_Off__c`; cancel unpaid payment; Balance = 0 | **4,000** (accurate) | No native write-off; original `Amount` overwritten. |
| **C** | Keep `Amount = 5,000`; native write-off 1,000; **rollups sum *paid Payments*** | **4,000** (accurate) | Preserves commitment; larger rollup reconfig. |

---

## 7. Phased build plan

1. **Record types, stages, profiles [CLI]:** repurpose `NPSP_Default`→Donation; create the
   other 6; build Donation pipeline + Pledge lifecycle stages + business processes; assign all
   7 RTs to System Admin + JCRC – Fundraising; Donation default.
2. **Payment behavior [UI]:** exclude Pledge/Grant/In-Kind from auto-create; set Max Payments
   high (verify in-org); **leave global auto-close blank**.
3. **Fields & rollup [CLI + DLRS]:** create `Amount_Due_To_Date__c` (+ `Pledge_Written_Off__c`
   if Option B); DLRS rollup Realtime + **nightly Full Calculate**; Pledge layout shows Amount,
   *Payment Amount Received*, *Remaining Balance*, *Payment Writeoff Amount*, *Amount Due To
   Date*.
4. **Lifecycle automation [Flow]:** fully-paid→Posted (Pledge); Partially Posted reconciliation
   (per §6.3 Option); Written Off/Cancelled write-off-all.
5. **Reporting [UI]:** Outstanding Pledges (Remaining Balance > 0), Pledges Due This Fiscal
   Year, Overdue Pledges (Amount Due To Date > 0); optional dashboard.
6. **Validation, docs, test [CLI/Docs]:** optional validation; runbooks; end-to-end test incl.
   the $1,000 due-to-date example, full pay → Posted, partial default → Partially Posted, zero
   → Written Off/Cancelled, and confirm rollups. Deploy via source; capture in repo.

---

## 8. Decisions — resolved 2026-06-19

| # / R | Decision (locked) |
|---|---|
| 1 | Pledges = **accrual** (recognize at commitment → receivable); Pledged = Closed/**Won**. |
| 2 | Pledges = **manual** schedules → exclude Pledge RT from auto-create. |
| 3 | **No max-payment blocker** → set Max Payments very high (+ manual/import for longer). |
| 4 | Fully-paid pledge → **Posted via Flow**; **one-time donations do NOT auto-close** (stewardship pipeline Prospecting→Cultivating→Posted). |
| 5 | Amount Due = expected-to-date unpaid (DLRS, §6.1). Partial-default handling §6.3. |
| 6 | **7 record types** (Donation default), visible to System Admin + JCRC – Fundraising. |
| R-Q3 | **Grant** treated like Pledge (manual schedule, exclude auto-create). |
| R-Stages | **Written Off / Cancelled** stage (Closed/not-Won) for zero-collected defaults. |
| R-Partial | Partial defaults → **Partially Posted** (Closed/Won); **Option B** selected (§6.3) — 🚩 **needs client confirmation before go-live**. |

**Verify before/at build:** §6.3 Option B with the **client** (it overwrites `Amount` and skips
native write-off); Max Payments value behavior in-org; final custom field names
(`Pledge_Written_Off__c`, optional `Original_Pledge_Amount__c`).

---

## 9. Net-new / changed metadata

| Item | Type |
|------|------|
| Donation, Pledge, Grant, In-Kind, Major, Matching, Securities | Opportunity Record Types (Donation default; repurpose `NPSP_Default`) |
| Donation pipeline (Prospecting, Cultivating, Posted, Declined) + Pledge lifecycle (Pledged, Posted, Partially Posted, Written Off/Cancelled) | Stages + business processes |
| RT visibility + default | Profile updates (System Admin, JCRC – Fundraising) |
| `Amount_Due_To_Date__c` (+ `Pledge_Written_Off__c` if Option B) | Custom field(s) on Opportunity |
| DLRS rollup + **nightly Full Calculate** | DLRS config + scheduled job |
| Fully-paid→Posted; Partially-Posted; Written-Off/Cancelled | Record-triggered Flows |
| Payment exclusions; Max Payments; **auto-close left blank** | NPSP settings |
| Pledge reports (3) + optional dashboard; runbooks | Reports + Docs |

*(Reused, not rebuilt: `Amount`, *Payment Amount Received*, *Remaining Balance*, *Payment
Writeoff Amount*, *Number of Payments*, *Do Not Automatically Create Payment*, Schedule
Payments, native Write Off.)*

---

## 10. Risks

- **R1 — Stage/Won config:** Pledged must be Closed/Won for accrual; verify rollups in sandbox.
- **R2 — Amount Due staleness:** requires the nightly DLRS Full Calculate; monitor/alert.
- **R3 — Partial reconciliation (§6.3):** wrong choice misstates donor giving or balance.
  **Mitigate:** confirm Option A/B/C with finance; test all three lifecycle endings.
- **R4 — Max Payments unverified ceiling:** **Mitigate:** test the chosen value in-org; long
  schedules create many Payment records.
- **R5 — Flow vs. global auto-close:** record-type-specific close depends on the Flow firing
  correctly. **Mitigate:** test Donation (manual) and Pledge (auto) paths.
- **R6 — Record-type sprawl:** 7 RTs introduced; only Pledge/Donation fully specified here.
  Later stories own each type.

---

## 11. Sources

- `NPSP_PledgeDocumentation.md`; [Manage Pledges (SF Help)](https://help.salesforce.com/s/articleView?id=sfdo.Manage_Pledges.htm&type=5)
- [RSF can't use TODAY — SF Ideas](https://ideas.salesforce.com/); [NPSP Customizable Rollups objects (Trailhead)](https://trailhead.salesforce.com/content/learn/modules/opportunity-settings-in-nonprofit-success-pack/enable-customizable-rollups-npsp); [DLRS Docs](https://sfdo-community-sprints.github.io/DLRS-Documentation/)
- **Research roadblock:** Salesforce Help "Configure Opportunity Payments" (Max Payments ceiling / wizard-vs-manual) is JS-protected and didn't render; mirror site TLS error — pending user pull.
- Live org verification (`sf` CLI, 2026-06-19): settings, record types, stages, profiles, counts, packages.
