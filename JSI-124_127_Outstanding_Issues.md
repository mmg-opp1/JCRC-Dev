# JSI-124 – JSI-127 — Outstanding Issues

> **Written:** 2026-08-17 by Jason Ott
> Everything still open across the four stories built on 2026-08-17. All four are
> **built, deployed to JCRC-Dev, verified by anonymous Apex, and committed**.
> Commits: `f5d1b71` (124), `ec4a1a3` (125), `faafd55` (126), `a9ae9a6` (127).
>
> **Nothing below is a defect in the four stories.** They are external dependencies,
> client decisions, and pre-existing issues surfaced while building them.

---

## 🔴 1. BLOCKING — the org-wide email address (affects JSI-124, JSI-125, and JSI-87)

**Two org settings, both Jason's to do, both UI-only:**

1. **Verify the OWEA `development@jcrcny.org`** — click the confirmation email Salesforce sends.
2. **Setup → Deliverability → *Access to Send Email* = All email** — sending a template to a
   `recipientId` requires single-email to be enabled.

**Why this is now urgent rather than merely outstanding.** It does not just stop email from
sending — it **makes records unsaveable**:

| Discovered in | Symptom |
|---|---|
| JSI-124 | Ticking `Acknowledgment_Approved__c` on any approval-gated **email** acknowledgment throws `CANNOT_EXECUTE_FLOW_TRIGGER … Org-Wide Email provided is not valid` and **the save fails**. |
| JSI-125 | **Inserting an ordinary small donation fails outright.** The `Donation - Small (Auto Email)` rule covers gifts up to **$99.99** on Send Mode **Auto**, so the JSI-87 send flow fires immediately on insert and the record cannot be saved. That is the **highest-volume gift type in the org**. |

Both are pre-existing JSI-87 behaviour, not caused by JSI-124/125.

**What is blocked until it is fixed**

- JSI-124: the DAF acknowledgment email cannot be sent or end-to-end tested.
- JSI-125: the installment/final notification send is **unproven**. Everything upstream —
  trigger, qualification, template selection, merge values — is verified; only the
  `emailSimple` call itself is untested. Exercising it would mean sending real email to a
  real donor address, which was deliberately not done unasked.
- JSI-87: the whole email acknowledgment path.

**Note:** JSI-125's notification deliberately sends on an **asynchronous after-commit path**
precisely so it can never do this to a payment save. That design choice was made *because* of
this finding.

---

## 2. Client decisions still open

| # | Story | Question | Status |
|---|---|---|---|
| C1 | **124** | **Gala tickets paid from a DAF — is this permitted at JCRC?** Under IRC §4967 and IRS Notice 2017-73, a DAF grant that enables event attendance confers *more than incidental benefit* on the advisor, with excise-tax exposure on **them**, even if they pay the non-deductible portion separately. Note the §4967 regulations are **still not final** (Nov 2023 proposed regs covered §4966); this is announced intent plus sponsor practice — Fidelity Charitable and most sponsors refuse event-ticket grants outright. | **Deliberately not built.** Needs JCRC policy before any validation rule or warning. Collides with `Event_Registration`, JSI-86's non-deductible split and the Gala `Gala_Level__c` FMV amounts. |
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
