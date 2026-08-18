# JSI-124 – JSI-127 — Outstanding Issues

> **Written:** 2026-08-17 by Jason Ott
> Everything still open across the four stories built on 2026-08-17. All four are
> **built, deployed to JCRC-Dev, verified by anonymous Apex, and committed**.
> Commits: `f5d1b71` (124), `ec4a1a3` (125), `faafd55` (126), `a9ae9a6` (127).
>
> **Nothing below is a defect in the four stories.** They are external dependencies,
> client decisions, and pre-existing issues surfaced while building them.

---

## 🔴 1. BLOCKING — email sending (affects JSI-124, JSI-125, and JSI-87)

**Status 2026-08-18: ✅ RESOLVED — both settings now in place.** The remaining email problem
is inbox placement, not sending — see section 1b.

| Setting | State | Who |
|---|---|---|
| OWEA `development@jcrcny.org` verified | **✅ DONE** — confirmed in-org, `IsVerified = true` | Jason, done |
| Setup → Email → **Deliverability** → *Access to Send Email* = **All email** | **✅ DONE** — re-probed, single email enabled | Jason, done |

**The second one is not deployable.** `EmailAdministrationSettings` carries no
`sendEmailAccessLevel` field, so it cannot be set from the CLI. It has to be changed in
Setup.

**Verified in-org 2026-08-18, not assumed:**

- Non-sending probe: `Messaging.reserveSingleEmailCapacity(1)` →
  `System.NoAccessException: The organization is not permitted to send email`.
- Re-ran the JSI-125 repro: inserting a **$50 donation still fails outright** —
  `CANNOT_EXECUTE_FLOW_TRIGGER … **Single email is not enabled for your organization or
  profile**`.

The error text **changed** from *"Org-Wide Email provided is not valid"* to *"Single email is
not enabled"*, which is how we know the OWEA half genuinely landed and the deliverability
half is what remains.

**Now verified working (2026-08-18)**

- **Ordinary donations under $100 save again** — a $50 donation inserts cleanly and
  auto-acknowledges (status → Acknowledged, date stamped). This was completely unsaveable
  before.
- **Approving an approval-gated email acknowledgment saves** — a DAF gift routed to
  `Ack_Email_DAF` / Approval-Gated, correctly did **not** send on insert, then sent and
  stamped Acknowledged when approved.
- **Installment and final-payment conditions verified** — paying 1 of 3 gave paid-to-date
  1,000 / remaining 2,000 / last-payment-date stamped; paying the rest took remaining to 0.00
  and flipped the stage to Posted. No notification-flow interviews errored.

**Caveat on what "verified" means here.** These confirm the records save and the flows
complete without error. They do **not** confirm a donor received anything — see 1b. Salesforce
returning `isSuccess = true` is not delivery.

**Note:** JSI-125's notification runs on an **asynchronous after-commit path** specifically so
it can never block a payment save. That protection is working — the failures above are all in
JSI-87's *synchronous* send flow, not in JSI-125.

**Test plan, ready to run the moment deliverability is on** (all of it previously blocked):

| # | Test | Expected |
|---|---|---|
| T1 | Insert a $50 Donation | Saves; auto acknowledgment sends; status → Acknowledged |
| T2 | Insert a DAF gift, then tick `Acknowledgment_Approved__c` | Saves; `Ack_Email_DAF` sends to the donor; no tax language |
| T3 | Pay installment 1 of 3 on a pledge | Async path fires; `Pmt_Email_Installment` with correct running totals |
| T4 | Pay the final installment | `Pmt_Email_Final_Payment` |
| T5 | Confirm negative cases stay silent | Single-payment gift, wrong record type, no primary contact |

⚠️ **T1–T5 send real email.** The only Contact in the sandbox with an address is
`jott326@gmail.com`, so the test messages land in Jason's inbox. T3/T4 also need **committed**
records rather than savepoint/rollback, because an after-commit async path does not fire
inside a rolled-back transaction — those test records get cleaned up afterwards.

---

## 🔴 1b. NEW — donor email lands in SPAM (prod-blocking for every email feature)

**Found 2026-08-18 while testing the now-unblocked send path.**

Email now genuinely leaves the org — but **Gmail files it as spam**. Two plain isolation
emails sent straight from Apex (one from the running user, one from the OWEA
`development@jcrcny.org`) both returned `success=true` and both **arrived in the spam
folder**, not the inbox.

**What this rules in and out**

| Checked | Result |
|---|---|
| Deliverability enabled | ✅ `Messaging.reserveSingleEmailCapacity(1)` succeeds |
| Recipient contact healthy | ✅ not opted out, no bounce date |
| Salesforce dispatches | ✅ `SendEmailResult.isSuccess() = true` |
| OWEA sender works at all | ✅ the OWEA-sent test arrived (in spam) |
| **Inbox placement** | ❌ **both tests spam-foldered** |

**Likely cause — domain authentication, which is a DNS job, not a Salesforce one.**
A verified OWEA only proves somebody at that address clicked a confirmation link. It does
**not** authorise Salesforce to send *as* `jcrcny.org`. Unless the domain's DNS says
Salesforce may do so, receiving servers treat the mail as spoofed. Consistent with the org's
own settings: `enableVerifyEmailDomainByDkim` is **false**.

**What production needs (JCRC IT / whoever holds jcrcny.org DNS):**

1. **DKIM** — generate a key in Setup → Email → DKIM Keys, publish the CNAME/TXT records in
   `jcrcny.org` DNS, then activate the key.
2. **SPF** — add Salesforce to the `jcrcny.org` SPF record (`include:_spf.salesforce.com`).
3. **DMARC** — confirm alignment once SPF and DKIM pass, so the policy does not reject.
4. Re-test inbox placement afterwards, to Gmail **and** to a corporate recipient.

**Why this matters more than a test annoyance.** Every donor-facing email built so far routes
through this address: JSI-87 acknowledgments, JSI-124 DAF acknowledgments, JSI-125 installment
and final-payment notifications. **If it ships unauthenticated, donor acknowledgments go to
spam** — the feature technically works and practically does not. Treat inbox placement, not
`isSuccess = true`, as the definition of done.

**Sandbox note:** spam-foldering in the sandbox is not itself alarming; what matters is that
the same domain authentication gap exists for production and must be closed before go-live.

---

## 2. Client decisions still open

| # | Story | Question | Status |
|---|---|---|---|
| C1 | **124** | **Gala tickets paid from a DAF — how should the system respond?** **IRC §4967 is enforced law** (Pension Protection Act 2006, applying to tax years beginning after 17 Aug 2006): a DAF distribution conferring *more than incidental benefit* on the donor/advisor carries a **125% excise tax** on them, plus 10% on a knowing fund manager. The IRS position (Notice 2017-73) is that paying for event tickets is more than incidental **even if the advisor pays the non-deductible portion separately**, and sponsors enforce it today — they will not cover **any part** of a ticket. Only the interpretive *regulation* for this fact pattern is unfinalised; the statute and sponsor practice are not. **JCRC confirmed it is enforced.** | **Question narrowed 2026-08-18** — it is no longer "is this permitted" but "block or warn?". Still not built pending JCRC's answer. Collides with `Event_Registration`, JSI-86's non-deductible split and the Gala `Gala_Level__c` FMV amounts. |
| C2 | **124** | **DAF letter copy** — real wording for `Ack_Email_DAF`. Must carry no amount and no tax/goods-and-services language. | Placeholder shipped with an in-body warning. |
| C3 | **124** | Should the DAF letter **name the sponsoring fund** ("…through your donor advised fund at Fidelity Charitable")? Recommended yes — sector-standard phrasing. | Template merges `{!Account.Name}`; wording pending. |
| C4 | **125** | **Copy for both payment notifications** — `Pmt_Email_Installment` and `Pmt_Email_Final_Payment`. | Placeholders shipped. |
| C5 | **125** | Should payment notifications carry **any tax or receipt language**? Assumed **no** — they are notifications; JSI-87 owns receipting and it would double up. | Assumption documented, needs confirming with whoever owns donor comms. |
| C6 | **127** | **What platform runs the donate page, and who maps the field?** Salesforce can hold the write-in value but something website-side must send it, and per DoD #2 set the campaign. | **The whole story is inert until this is done.** Same unresolved online-platform question JSI-86 deferred and JSI-89 flagged. |

---

## 3. Pre-existing issues found while building (not caused by these stories)

| # | Issue | Impact | Recommendation |
|---|---|---|---|
| P1 | **JSI-82's four pledge reports all filter `StageName = 'Pledged'`.** When a plan completes, JSI-82's own `Opportunity_FullyPaidPledgeToPosted` flips the stage to **Posted** and the pledge plus all its installments **vanish from every report in the folder**. | Completed installment plans are invisible in the existing reports. | Widen those four reports (was **D3** in the JSI-126 plan — Jason's call, left unbuilt because it changes prior deliverables). JSI-126's new report is unaffected: it has no stage filter. |
| P2 | **Major Gift installment plans are excluded from all four of those reports** — Major Gift runs on `Donation_Process`, which has no "Pledged" stage. **Proven with data:** a seeded 2-installment Major Gift was invisible to the `Stage = Pledged` filter. | A fundraiser looking at "Pledge Payment Schedule (Remaining)" today does not see Major Gift plans at all. | Same fix as P1. |
| P3 | **`Opportunity_FullyPaidPledgeToPosted` hardcodes record-type Ids** (`012iI0000000Dq5QAE` Grant, `012iI0000000Dq9QAE` Pledge) and **omits Major Gift entirely**, so a fully-paid Major Gift never auto-flips to Posted. | Known JSI-82 carryover; also means stage is an unreliable "plan complete" signal. | JSI-125 sidestepped it by keying the final-payment notification off `npe01__Amount_Outstanding__c = 0`, which is record-type agnostic. The hardcoded Ids still need fixing before prod. |
| P4 | **A DAF gift is hard-credited by JSI-90 but soft-credited by NPSP.** `GiftAllocationService` takes its hard-credit contact from `npsp__Primary_Contact__c` regardless of OCR role, so the donor gets a **Hard** `Gift_Allocation__c` while NPSP records a **Soft Credit** OCR, and the Fund account separately carries the NPSP account hard credit. | Totals still land correctly in JSI-90 (D5: combined hard+soft qualifies) and JSI-123 (`Board_Commitment_Applied__c` reads `Total_Giving`). Only the **hard-vs-soft split** on the Annual Giving Summary is skewed. | **Own story, not folded into JSI-124.** JSI-80's original JCRC notes asked to "make sure the gift isn't double-counted" — this is where that comes due. |

---

## 4. Smaller open items

| # | Story | Item |
|---|---|---|
| S1 | **125** | Optional report of qualifying paid installments **with no primary contact** — the flow stays silent by design (D4, "quiet no-send is fine"), but silence is invisible. Organisational pledges are the likely case. |
| S2 | **125** | Bulk behaviour unproven at scale — marking many payments Paid in a deposit batch produces one email per payment. Correct per donor, but worth a sanity check on the async path once email works. |
| S3 | **126** | The report ships **unwindowed** so a multi-year plan shows its whole schedule. If staff prefer a rolling window, it is a one-line change. |
| S4 | **127** | Nothing prevents a gift sitting on the *Website Donation - Other* campaign forever if nobody works the queue — no SLA or reminder was built. |
| S5 | **127** | Should populating the write-in text **auto-set** the campaign to *Website Donation - Other*? Not built — belongs with the platform mapping (D2). |
| S6 | **124** | `Acknowledgment_Letter` print path has **no DAF branch** — D2 chose Email. Only revisit if a printed DAF letter is wanted. |
| S7 | **All** | Record-page placement of the new fields (`DAF_Gift__c` is already placed; `Other_Campaign_Write_In__c`, `Last_Payment_Date__c`, `Payments_Made_Count__c`, `Campaign_Name__c` are **not** on any Lightning page). App Builder is Jason's — say if you want them scripted onto the gift pages instead. |
| S8 | **All** | **Production cutover:** none of this is in `JCRC-Prod`. Report folders, CMDT records, the *Website Donation - Other* campaign and the two seeded example records are **data or UI-managed**, so they do not travel in a metadata deploy. |

---

## 5. New gotchas learned (for `reference-sf-metadata-gotchas`)

1. **A CMDT picklist in a Flow formula must be wrapped in `TEXT()`** — `ISBLANK({!Loop.Pick__c})` and a bare `=` fail the deploy: *"Field … is a picklist field. Picklist fields are only supported in certain functions."* (JSI-124)
2. **Report `description` max length is 255.** (JSI-124)
3. **An `AsyncAfterCommit` scheduled path must not carry a `<label>`** — *"Label, TimeSource, OffsetUnit, OffsetNumber, RecordField, MaxBatchSize cannot be set for ScheduledPath of PathType"*. Only `<name>`, `<connector>`, `<pathType>`. (JSI-125)
4. **Report-type columns use `RecordType` and `Account`, not `RecordTypeId`/`AccountId`** — but the record-type filter **value** still needs the object-qualified DeveloperName (`Opportunity.Pledge,…`), same as a standard report type. Different column name, same value form. (JSI-126)
5. **The standard `Opportunity` report type exposes no native campaign column** a filter can use — both `CAMPAIGN_NAME` and `Opportunity.CampaignId` are rejected. Get the real list from the org: `sf api request rest "/services/data/v60.0/analytics/reportTypes/Opportunity"`. (JSI-127)
6. **NPSP forbids a payment being both Paid and Written Off** ("A Payment can't be both paid and written off"), so a written-off payment can never trigger paid-payment automation. (JSI-125)
7. **`npe01__Number_of_Payments__c` counts every payment including unpaid scheduled ones** (verified: three unpaid reads 3) — it cannot answer "how many payments have been made". (JSI-125/126)
8. **The FLS gotcha keeps biting:** a new field deploys fine but anonymous Apex will not compile against it (*"No such column"*) until FLS is granted — roll-up summaries included. Deploy FLS *with* the field, every time.

---

## 6. What was reused rather than rebuilt

Worth recording, because it kept the build small:

- **JSI-124's `Opportunity.Campaign_Name__c`** (built so the DAF template could merge a campaign
  name) turned out to be the **only** usable campaign filter column for **JSI-127's** review
  queue. Name-based, so also portable to production.
- **JSI-125's native-roll-up approach** (`Last_Payment_Date__c`) was reused for **JSI-126's**
  `Payments_Made_Count__c`.
- **JSI-124 extended JSI-87's existing rules engine** rather than adding a parallel one — one
  CMDT criterion, one formula clause, one rule record.
- **JSI-126 extended JSI-82's existing `Pledges_with_Payments__c` report type** additively; the
  four existing reports were untouched.
- **JSI-127 followed JSI-80's `Approach__c` pattern** for the Data Import source field plus
  advanced field mapping.
