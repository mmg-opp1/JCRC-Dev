# JSI-124 — DAF Acknowledgements

> **Source:** [JSI-124 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-124)
> Retrieved from Jira on 2026-08-17 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-124 |
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

> As a gala event manager, I want to ensure that the system records the DAF donations
> so that the person does not get the nonprofit acknowledgement.

## Definition of Done

> Donor receives acknowledgement of the payment, the payment date, and for the specific
> 'campaign', while not displaying the amount of the donation in the letter, nor a
> reference to tax deductions after the signatures at the bottom of the letter.

**Annotated with this-story scope:**

| DoD element | Scope call |
|---|---|
| Donor receives an acknowledgement | **In scope** — a DAF gift is acknowledged, just not with a standard template. This is *not* a "suppress the letter entirely" story. |
| …of the payment and the payment date | **In scope** — template content + confirming which date is authoritative (see Q4). |
| …for the specific 'campaign' | **In scope** — requires the campaign to be merge-able into the template (see Q5). |
| Not displaying the amount of the donation | **In scope, and new** — this requirement appears **only in Jira**, not in the dictation. Template-level omission. |
| No tax-deduction reference after the signatures | **In scope** — the central compliance requirement, and the reason the dictation was written. |

## Notes & Context

**From Jason's dictation** (`JSI-124_StoryDictationNotes.MD`):

- The **data-model half of this story is already built** — Jason added it through the UI on
  2026-08-17: `Opportunity.DAF_Gift__c` (checkbox), the `Account.Fund` record type
  (described in the org as *"DAFs / Benevity"*), and `Account.Advisor__c` (Contact lookup).
  Those were retrieved into source on 2026-08-17.
- The part to build here is the **acknowledgment plumbing**: any Opportunity flagged as a
  DAF gift must not receive any of the *standard* acknowledgements.
- **Why:** the donor already took their tax deduction when they funded the donor-advised
  fund. They do **not** get one when the fund grants to the charity. So a DAF letter must
  carry none of the tax-deduction language the standard templates carry.
- The DAF templates will therefore be **different templates**, not the standard ones.
- Actual template copy is **still pending with the client** — same position as JSI-87.
  Jason wants the routing/plumbing built now regardless.

**Prior client context — this question was raised a year of stories ago.** JSI-80's
JCRC notes already asked the org to *"define how we want to address payments from DAFs"*:
how to link individuals to DAFs (naming **JCF** — Jewish Communal Fund), how to report on
the **donor** rather than the **payor**, and how to avoid double-counting. JSI-124 is where
part of that finally gets answered.

**Prior JCRC decision that this story must be reconciled against.** JSI-85 settled DAF
handling as **"DAF as Payment Method"** — hard-credit the individual, treat the DAF as a
reference only. The `Fund` Account record type built on 2026-08-17 points toward the
*other* industry pattern (fund is the Account, individual is soft-credited). Which model is
actually in force decides who receives the DAF letter. See Q1 — this is the one question
that blocks a clean build.

## Outstanding Questions

**For Jason (design forks — answers change the build):**

1. ~~**Which DAF credit model is in force?**~~ **✅ ANSWERED 2026-08-17 (Jason).** On any DAF
   gift the **Account is an Account with record type `Fund`** (example: *Ott Family Fund*),
   and the **Opportunity's Primary Contact is the donor**. NPSP then creates a soft credit
   for the donor, which is the accurate treatment. **The donor — i.e.
   `npsp__Primary_Contact__c` — is who receives the DAF acknowledgement.**
   **Verified in-org the same day** (anon Apex, savepoint → rollback): a gift booked to
   *Ott Family Fund* with Jason Ott as Primary Contact produced exactly one OCR —
   `Role = Soft Credit`, `IsPrimary = true`. Jason's expectation is confirmed by the org's
   real behaviour, not just by the settings. **Build consequence: the existing
   acknowledgment email flow already targets `npsp__Primary_Contact__c`, so no recipient
   work is required — that whole phase drops.**
2. ~~**What is a "Fund" account meant to represent?**~~ **✅ ANSWERED** — a donor's named
   fund (*Ott Family Fund*). (`Fidelity Charitable` also exists in the sandbox as a
   sponsor-style account; the acknowledgment path does not depend on the distinction, since
   the recipient always comes from the Opportunity's Primary Contact.)
3. **Channel and send mode for DAF letters** — Email (auto or approval-gated) or Print
   (approval-gated, as all print is today)? The standard rules use Print/Approval-Gated
   for Major Gift and the fallback.
4. **Which date is "the payment date"** — the Opportunity Close Date, or the NPSP Payment
   record's payment date (`npe01__OppPayment__c`)? JSI-82 built the payment model, so both
   exist.
5. **How should "the specific campaign" be worded** — the Campaign name alone, or a
   friendlier event/appeal label? (Mechanically this likely needs a formula field; see the
   Implementation Plan.)
6. **Should DAF gifts be separated in the acknowledgment work-queue reports**, or just
   flow through the existing "Gifts Pending Acknowledgment" report with a DAF column?

**For the client (JCRC):**

7. **Template copy** — the actual DAF letter/email wording, including the closing block
   that must *not* carry tax-deduction language. (Same blocker as the JSI-87 standard
   templates.)
8. **Gala tickets paid from a DAF — is this permitted at JCRC?** This is a live compliance
   question, not a hypothetical, because the story's own persona is the *gala event
   manager*. Under IRC §4967 and IRS Notice 2017-73, a DAF grant that enables attendance
   at a charity event is treated as conferring **more than an incidental benefit** on the
   advisor — **even if the donor pays the non-deductible portion out of pocket** — which
   exposes the advisor to an excise tax. If JCRC intends to accept DAF payment for gala
   tickets or tables, that needs a policy decision, and the system should arguably block or
   flag the combination. See the Implementation Plan, §Compliance.
9. **Should the DAF acknowledgement name the sponsoring fund** ("…through your donor
   advised fund at Fidelity Charitable")? That is the widely-recommended phrasing, and it
   changes what has to be merge-able into the template.

## Related Reference Material

- [`JSI-124_StoryDictationNotes.MD`](./JSI-124_StoryDictationNotes.MD) — Jason's dictation, the intent source.
- `JSI-87/` — the acknowledgment engine this story extends (router, rules CMDT, letter flow, email flow, templates).
- `JSI-85/JSI-85_Implementation_Plan.md` — where "DAF as Payment Method" was decided.
- `JSI-86/` — the deductible / non-deductible amount split that DAF letters must not surface.
- `Gala_Gifts/Gala_Gifts_Design.md` — the gala workstream referenced by this story's persona.
