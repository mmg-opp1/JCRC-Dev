# JSI-125 — Implementation Game Plan: Paid Installment Notifications

> **Story:** [JSI-125](https://missionmattersgroup.atlassian.net/browse/JSI-125) — Paid Installment Notifications (Epic JSI-8 Fundraising)
> **Author:** Jason Ott · **Written:** 2026-08-17
> **Status:** **PLAN ONLY — no build.** Per the dictation, implementation starts after
> clarifications are settled and this plan is reviewed.
>
> **Change Log:**
> - 2026-08-17 — Jason Ott — Initial plan: Jira pull, dictation reconciliation, org verification, research, design.

---

## 1. Scope

**In scope**

- Email the donor when an installment **Payment** is marked **Paid**, carrying the amount
  paid to date, the amount still outstanding, and the total commitment.
- Restrict it so ordinary single-payment gifts never trigger it: **Pledge / Major Gift /
  Grant record types**, and only where the Opportunity actually has **multiple payments**.
- A **second, distinct message when the final payment lands** (DoD #3).
- Placeholder copy for both, structured for the client's wording to drop in.

**Out of scope**

- **The installment payment program itself (DoD #1) — already built by JSI-82** and verified
  still working today (§3). Nothing to do.
- Rebuilding any part of NPSP Payments.
- Tax receipting / acknowledgments — JSI-87 owns those. These are notifications.

---

## 2. The architectural decision — **send on the flow's asynchronous path**

### 2.1 Decision

Trigger a record-triggered flow on `npe01__OppPayment__c` when it becomes Paid, but do the
**email send on an asynchronous (after-commit) path**, not in the synchronous transaction.

### 2.2 Why this is the important call in the story

JSI-124 established, by hitting it, that a failing email send inside a record-triggered flow
does not merely fail to send — it throws `CANNOT_EXECUTE_FLOW_TRIGGER` and **rolls back the
save**. With the org-wide email address still unverified, that is live today.

If this notification were sent synchronously, the consequence would be far worse than a
missing email: **marking a payment as Paid would fail**. That is core finance processing —
deposits, reconciliation, the pledge lifecycle, and the JSI-82 stage automation all hang off
it. A donor-communication feature must never be able to block a payment from being recorded.

Running the send on an **after-commit asynchronous path** means:

- the payment save commits first and cannot be rolled back by an email failure;
- all roll-up summaries are final by the time the body is built (no in-transaction
  recalculation questions at all);
- an OWEA/deliverability problem surfaces as a failed async job, not a blocked user.

This costs nothing and removes the only way this story could damage day-to-day operations.

### 2.3 Why a Payment-triggered flow rather than an Opportunity-triggered one

The event is "a payment went to Paid", which is a Payment-level fact. An Opportunity-level
trigger would have to infer which payment changed, and would fire on unrelated Opportunity
edits. Payment-triggered matches the dictation literally.

---

## 3. Verified org context (checked against JCRC-Dev, 2026-08-17)

Everything the notification needs already exists natively. **Verified by anon Apex**
(`setSavepoint()` → `rollback()`) — a 3,000 pledge with three 1,000 installments:

| Step | `npe01__Number_of_Payments__c` | `npe01__Payments_Made__c` | `npe01__Amount_Outstanding__c` | Stage |
|---|---|---|---|---|
| Pledge inserted | 0 | 0.00 | 3000.00 | Pledged |
| 3 installments scheduled | **3** | 0.00 | 3000.00 | Pledged |
| 1st marked Paid | 3 | **1000.00** | **2000.00** | Pledged |
| all 3 Paid | 3 | 3000.00 | **0.00** | **Posted** |

Reading off that table:

| Requirement | Native field — no build needed |
|---|---|
| Amount paid to date | `npe01__Payments_Made__c` (RUS SUM, label *Payment Amount Received*) |
| Amount still left | `npe01__Amount_Outstanding__c` (formula, label *Remaining Balance*) |
| Entire total | `Opportunity.Amount` |
| "Multiple payments" test | `npe01__Number_of_Payments__c` (RUS COUNT) — **counts scheduled as well as paid**, so a 3-installment pledge reads 3 from the moment the schedule is created, which is what we want |
| **Final payment detected** | `npe01__Amount_Outstanding__c = 0` — and the JSI-82 flow independently flips the stage to **Posted**, so either signal works |

Other verified facts:

| Fact | Value |
|---|---|
| `npe01__OppPayment__c` `enableActivities` | **false** → the Payment **cannot be a `whatId`**, so a classic email template cannot merge payment fields. Drives §5.3. |
| Opportunity record type Ids | Grant `012iI0000000Dq5QAE`, Major Gift `012iI0000000Dq7QAE`, Pledge `012iI0000000Dq9QAE` |
| Existing payment-aware flows | `Opportunity_FullyPaidPledgeToPosted`, `Opportunity_HandlePartiallyPostedPledge`, `Opportunity_HandlePledgeWriteOff` |
| Payment write-off field | `npe01__Written_Off__c` |
| JSI-82 carryover confirmed | `Opportunity_FullyPaidPledgeToPosted` **hardcodes record-type Ids** (Grant + Pledge only — Major Gift is absent). Pre-existing; called out again in §7 Risk 4. |
| Email infrastructure | `emailSimple` + `emailTemplateId` + `recipientId` + OWEA, per JSI-87. **OWEA `development@jcrcny.org` still unverified; Deliverability not yet "All email".** |

---

## 4. Requirement → mechanism

| Requirement | Mechanism |
|---|---|
| Fire when an installment is paid | Record-triggered flow on `npe01__OppPayment__c`, after-save, entry `npe01__Paid__c = true` + `ISCHANGED` |
| Don't fire for single-payment gifts | Decision: `npe01__Number_of_Payments__c > 1` |
| Only Pledge / Major Gift / Grant | Decision on the parent's record type — via a **Get Records on RecordType** (a record-triggered flow cannot resolve `$Record.RecordType.DeveloperName`, JSI-87 gotcha) and matched on **DeveloperName, never a hardcoded Id** |
| Email the donor | `emailSimple` → `recipientId` = `Opportunity.npsp__Primary_Contact__c`, `relatedRecordId` = the Opportunity |
| Paid to date / remaining / total | Opportunity merge fields (§3) |
| Final-payment message (DoD #3) | Decision on `npe01__Amount_Outstanding__c = 0` → the final template instead of the installment one |
| Never block a payment save | The send sits on the **async after-commit path** (§2) |
| Skip write-offs | Decision excludes `npe01__Written_Off__c = true` |

---

## 5. Design

### 5.1 Flow shape — `Payment_Notify_Donor_On_Paid`

```
START  npe01__OppPayment__c, after-save, Create+Update
       entry: npe01__Paid__c = true  (formula also requires ISCHANGED on update)
  └─ ASYNC AFTER-COMMIT PATH
       Get Opportunity (Id = $Record.npe01__Opportunity__c)
       Get RecordType   (Id = Opportunity.RecordTypeId)      <- DeveloperName, not Id
       Decision "Should Notify?"
         - RecordType.DeveloperName IN (Pledge, Major_Gift, Grant)
         - AND Number_of_Payments > 1
         - AND Written_Off = false
         - AND Primary Contact != null
         -> else END (no message)
       Decision "Final Payment?"
         - Amount_Outstanding = 0  -> Get template Pmt_Email_Final_Payment
         - else                    -> Get template Pmt_Email_Installment
       Send Email (emailSimple: emailTemplateId, recipientId=Primary Contact,
                   relatedRecordId=Opportunity, OWEA sender)
```

### 5.2 New metadata

| Component | Type | Notes |
|---|---|---|
| `Payment_Notify_Donor_On_Paid` | Flow | Per §5.1, with the async path |
| `Pmt_Email_Installment` | EmailTemplate | Classic, `email/unfiled$public/`, placeholder copy |
| `Pmt_Email_Final_Payment` | EmailTemplate | Classic, placeholder copy — the "pledge complete" message |
| `Opportunity.Last_Payment_Amount__c` / `Last_Payment_Date__c` | Fields | **Only if D2 says the email should name the specific payment** — see §5.3 |

No new rollups, no Apex, no changes to any existing flow.

### 5.3 The template fork (D2) — a real constraint, not a preference

`npe01__OppPayment__c` has **activities disabled**, so it cannot be an email template's
`whatId`. A classic template on this send can merge `{!Opportunity.*}` and `{!Contact.*}`
only — **there is no way to merge the triggering payment's amount or date into it**.

| Option | Gets "your payment of $500 on 17 Aug"? | Copy editable by client/admin? | Cost |
|---|---|---|---|
| **A. Template, Opportunity fields only** | No — totals only | **Yes**, a real EmailTemplate record | none |
| **B. Stamp `Last_Payment_Amount__c` / `Last_Payment_Date__c` onto the Opportunity, then template** | Yes | **Yes** | 2 fields + FLS; values are "last payment", so they are only meaningful in this context |
| **C. Build the body in the flow with text templates** | Yes | **No** — copy changes mean editing the flow | none, but loses client-editability |

**Recommendation: B.** It satisfies the natural wording of the notification while keeping the
copy in a real EmailTemplate record — which is the pattern Jason corrected JSI-87 toward.
Note the dictation's *stated* content requirements (paid to date, remaining, total) are all
Opportunity-level, so **A alone technically satisfies the story** if we want the smallest build.

### 5.3a How D2 was actually resolved — a native roll-up, not a stamped field

D2 said "don't name the payment, but **do** give the date". The date is still a Payment
value, and Payment fields are not mergeable (activities disabled). But
`npe01__OppPayment__c` is a **master-detail child of Opportunity** (verified), so the date
can come from a **native Roll-Up Summary** instead of Option B's flow-stamped field:

**`Opportunity.Last_Payment_Date__c` = MAX(`npe01__Payment_Date__c`) WHERE `npe01__Paid__c` = true**

This is strictly better than the stamped field the plan originally recommended: real-time,
no DML, delete-safe, no bulk race, and reportable in its own right. Same precedent as JSI-90,
which chose a native RUS over DLRS for a master-detail child.

*Edge case, accepted:* if a back-dated payment is marked Paid **after** a later-dated one,
the roll-up shows the later date rather than the one just processed. Only reachable by
out-of-order back-dating; the alternative (stamping the triggering payment) costs a DML per
payment and a bulk race, which is the worse trade.

### 5.6 Overlap with JSI-126 (found while settling D3)

JSI-126 *"Installation Payment Reports"* restates two of this story's requirements in its DoD:

| JSI-126 DoD item | Status after JSI-125 |
|---|---|
| "when the plan is complete, send a final letter" | **Delivered here** — `Pmt_Email_Final_Payment` |
| "when a check or ACH has been received, an acknowledgement that it has been recorded, that we have received a certain total, and there is X remaining balance" | **Delivered here** — `Pmt_Email_Installment` carries exactly that: received, total paid to date, remaining balance |
| "Receive monthly reports when there is an existing installment payment" | **Not built** — the genuine remainder of JSI-126 |

**So JSI-126 reduces to the monthly report.** Same pattern as JSI-50 / JSI-55, where research
collapsed the story to a fraction of its DoD. Worth confirming when that story is picked up.

### 5.4 Interaction with the JSI-87 acknowledgment engine

The dictation's worry — donors getting an acknowledgment *and* a notification for the same
gift — is worth being precise about, because for pledges **both will legitimately happen**:

- A pledge reaches "Pledged", which JSI-82 made a **Closed/Won** stage, so the JSI-87 router
  acknowledges the *commitment* once.
- Each installment then produces a *payment notification* from this story.

Those are different messages about different events, which is the intent. The case the
dictation actually wants to prevent — a single $18 online donation generating both — is
prevented by the record-type + multiple-payment filter. **No change to JSI-87 is needed**,
and the router will not re-fire on the pledge (its entry filter is `Channel IsNull`, already
stamped).

### 5.5 Security

Profiles, not permission sets, via the additive minimal-profile deploy — **only if** D2 = B
(the two new fields need FLS on Admin + the four JCRC profiles). Otherwise no security change.

---

## 6. Research — how NPSP expects this to be done

NPSP ships **no native per-payment donor notification**. It provides the payment *data model*
(Payments with `npe01__Paid__c`, scheduling, write-offs, and the Opportunity roll-ups above)
and a native **acknowledgment** feature for the gift itself — which this org has deliberately
turned off in favour of the JSI-87 custom engine. So a payment-received notification is
correctly a custom build, and the platform-standard way to build it is a record-triggered
flow plus an email template, which is what this plan does.

The one NPSP-specific trap worth stating: **`npe01__Number_of_Payments__c` counts scheduled
payments, not just paid ones** (verified in §3). That is what makes it a usable
"is this an installment plan?" test at the moment the first payment lands — a
paid-payments-only count would read 1 on the first installment and wrongly suppress the
first notification of every pledge.

---

## 7. Risks

1. **OWEA is still unverified** — no email from this story will actually send until
   `development@jcrcny.org` is verified and Deliverability is set to *All email*. The async
   path (§2) means this degrades to a failed background job rather than a blocked payment,
   but the feature is not live until those are done.
2. **Organisational pledges may have no primary contact** (Q4). The flow ends quietly in that
   case. Quiet is safe, but it is also invisible — consider a report of paid installments on
   qualifying record types with no primary contact, so silent non-delivery is noticeable.
3. **Bulk payment updates.** Marking many payments Paid at once (a deposit batch) will
   generate one email per payment. That is correct per donor, but worth sanity-checking
   against the async path's bulk behaviour during build.
4. **Pre-existing: `Opportunity_FullyPaidPledgeToPosted` hardcodes record-type Ids** and
   covers only Grant + Pledge, not Major Gift. Not caused by this story and not in its scope,
   but it means a fully-paid **Major Gift** does not auto-flip to Posted — so if DoD #3 keyed
   off the *stage* it would miss Major Gifts. **This plan keys off
   `npe01__Amount_Outstanding__c = 0` instead, which is record-type agnostic** and sidesteps
   the defect. Worth fixing separately (JSI-82 carryover).
5. **Payment edits after the fact.** Un-paying and re-paying a payment would re-notify. Low
   volume, but if it matters the flow can require `ISCHANGED` on the Paid flag (planned).

---

## 8. Phased build (on go-ahead)

| Phase | Work | Gate |
|---|---|---|
| **1** | `Payment_Notify_Donor_On_Paid` flow with the async path + both decisions | D1, D3 |
| **2** | `Pmt_Email_Installment` + `Pmt_Email_Final_Payment` templates (placeholder copy) | D2 |
| **3** | *(only if D2 = B)* `Last_Payment_Amount__c` / `Last_Payment_Date__c` + FLS | D2 |
| **4** | *(optional, Risk 2)* report of qualifying paid installments with no primary contact | Q4 |
| **5** | Verify: anon Apex in `setSavepoint()` → `rollback()` — installment fires, final fires, single-payment gift silent, wrong record type silent, written-off silent | — |

---

## 9. Decisions to settle before build

**All settled by Jason, 2026-08-17.**

| # | Decision | Outcome |
|---|---|---|
| **D1** | Record type **AND** >1 payment, or record type alone? | **✅ Both.** A pledge settled in a single payment sends nothing — accepted trade-off, verified as scenario C2. |
| **D2** | Name the specific payment in the email? | **✅ No.** State that a payment was received, plus **the date**, total paid to date, remaining, and total commitment. Since the date is still required and Payment fields are not mergeable, this became a native **roll-up** rather than a stamped field — see §5.3a. |
| **D3** | Is DoD #3 (final-payment message) in scope? | **✅ Yes** — built as the second template on the same flow. Also restated in **JSI-126** (§5.6). |
| **D4** | Fallback recipient for organisational pledges? | **✅ Quiet no-send is fine.** |
| **D5** | Exclude written-off payments? | **✅ Yes** — though NPSP makes it impossible anyway (§11). |

---

## 10. Sources

- Verified in-org behaviour, JCRC-Dev, 2026-08-17 (anon Apex, savepoint → rollback) — §3.
- In-repo: `JSI-82/` (pledge + payments model, DoD #1), `JSI-87/` (email pattern + OWEA), `JSI-124/` (the save-blocking email finding).

---

## 11. Build Log

### 2026-08-17 — BUILT + DEPLOYED + VERIFIED (JCRC-Dev)

**Deployed**

| Component | Notes |
|---|---|
| `Opportunity.Last_Payment_Date__c` | Native Roll-Up Summary, MAX of `npe01__Payment_Date__c` filtered `npe01__Paid__c = true` (§5.3a). FLS read-only on Admin + 4 JCRC via additive minimal-profile deploy; repo profiles documented. |
| `Pmt_Email_Installment` | Classic EmailTemplate. Payment received + date + paid to date + remaining + total, in a small table. Placeholder copy, with an in-body warning that this is a notification and must not carry tax/receipt language. |
| `Pmt_Email_Final_Payment` | Same shape, "paid in full" wording (DoD #3). |
| `Payment_Notify_Donor_On_Paid` | Record-triggered on `npe01__OppPayment__c`, after-save, entry `npe01__Paid__c = true` with `doesRequireRecordChangedToMeetCriteria = true`. **Send runs on the `AsyncAfterCommit` scheduled path** (§2). Template chosen by formula: remaining `<= 0` → final, else installment. |

No Apex. No changes to any existing flow.

**Verified — anon Apex, `setSavepoint()` → `rollback()`, nothing persisted**

| Scenario | Result |
|---|---|
| A — Pledge, 3 installments, pay 1st | **PASS** — qualifies; paid-to-date 1000, remaining 2000, `Last_Payment_Date__c` = today → **installment** template |
| B — same pledge, pay all 3 | **PASS** — remaining 0.00 → **final** template; roll-up correctly returned the **latest** paid date (2026-08-22), not the first |
| C — single-payment $18 Donation | **PASS** — wrong record type *and* only 1 payment → silent |
| C2 — Pledge settled in **one** payment | **PASS** — silent. This is the D1 trade-off, verified explicitly rather than assumed. |
| D — written-off payment | **PASS by construction** — see finding below |
| E — multi-payment pledge, **no primary contact** | **PASS** — silent (D4); roll-ups still correct, so the gift is fully reportable even though nobody is emailed |

**Findings**

1. **NPSP forbids paid + written-off natively.** Attempting both raises
   *"A Payment can't be both paid and written off."* So D5's exclusion can never actually be
   exercised — a written-off payment cannot reach this flow at all. The condition stays as
   belt-and-braces, but the risk it guarded against does not exist.
2. **🔴 The OWEA problem is worse than JSI-124 recorded.** JSI-124 found that approving an
   acknowledgment fails the save. This story found that **inserting an ordinary small
   donation fails outright**: the `Donation - Small (Auto Email)` rule covers gifts up to
   **$99.99** with Send Mode **Auto**, so the JSI-87 send flow fires immediately on insert,
   the unverified OWEA throws, and the record cannot be saved
   (`CANNOT_EXECUTE_FLOW_TRIGGER`). That is the **highest-volume gift type in the org**.
   It is pre-existing (JSI-87), not caused by JSI-125 — but it makes verifying the OWEA
   urgent rather than merely outstanding. It also validates this story's async-path design:
   JSI-125's own emails cannot do this to a payment save.

**Gotchas hit**

1. **An `AsyncAfterCommit` scheduled path must not carry a `<label>`** — deploy fails
   *"Label, TimeSource, OffsetUnit, OffsetNumber, RecordField, MaxBatchSize cannot be set for
   ScheduledPath of PathType"*. Only `<name>`, `<connector>` and `<pathType>`.
2. **The FLS gotcha bit again** — `Last_Payment_Date__c` deployed fine but anon Apex would not
   compile against it (*"No such column"*) until FLS was granted. A new field is invisible to
   the compiler without it, roll-up or not.

**Not verified — and cannot be until the OWEA is fixed**

The async path's **actual send** has not been exercised. Everything upstream of it is
verified above (trigger, qualification, template selection, merge values), but the
`emailSimple` call itself needs a verified OWEA `development@jcrcny.org` plus Deliverability
= *All email*. Exercising it would mean sending real email to a real address, which is not
something to do unasked. **Treat the send as unproven until those two settings are done.**

**Not built (deliberate)**

- Report of qualifying paid installments with no primary contact (Risk 2 / optional Phase 4).
- Client template copy — pending, same position as JSI-87 and JSI-124.
- JSI-126's monthly report — belongs to that story (§5.6).
