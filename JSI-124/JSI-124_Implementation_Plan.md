# JSI-124 — Implementation Game Plan: DAF Acknowledgements

> **Story:** [JSI-124](https://missionmattersgroup.atlassian.net/browse/JSI-124) — DAF Acknowledgements (Epic JSI-8 Fundraising)
> **Author:** Jason Ott · **Written:** 2026-08-17
> **Status:** **PLAN ONLY — no build.** Per the dictation, implementation starts after
> clarifications are settled and this plan is reviewed.
>
> **Change Log:**
> - 2026-08-17 — Jason Ott — Initial plan: Jira pull, dictation reconciliation, org verification, research, design.

---

## 1. Scope

**In scope**

- Route any gift flagged `Opportunity.DAF_Gift__c = true` **away from every standard
  acknowledgment template** and onto a DAF-specific template.
- Add the DAF template(s) themselves as **placeholders**, structured so the client's copy
  drops in later: payment + payment date + campaign present; **amount absent**; **no
  tax-deduction or quid-pro-quo language** anywhere, especially below the signature block.
- Close the re-classification gap so a gift flagged as DAF *after* it was first routed
  cannot keep a standard template (see §7, Risk 1 — this is the story's whole point).

**Out of scope**

- The DAF **data model** — already built by Jason in the UI on 2026-08-17
  (`Opportunity.DAF_Gift__c`, `Account.Fund` record type, `Account.Advisor__c`,
  `DAF_Record_Page`) and retrieved into source the same day. This story consumes it.
- **Final template copy** — client-pending, exactly as with the JSI-87 standard templates.
- Re-opening the JSI-85 soft-credit design or the JSI-90 allocation engine. If Q1 resolves
  toward the fund-as-Account model, the knock-on effects there are a **separate story**.
- Statements / year-end receipting (owned elsewhere).

---

## 2. The mechanism decision — **extend the existing rules engine, do not bolt on a second one**

### 2.1 Decision

Add a **DAF criterion to `Acknowledgment_Rule__mdt`** and one new rule record, rather than
special-casing DAF anywhere in Apex or in a parallel flow.

### 2.2 Why — proof from the actual org metadata, not assumption

`Opportunity_Acknowledgment_Router` (read in full, 314 lines) already does exactly this
shape of work:

- Entry: Opportunity, after-save, `CreateAndUpdate`, entry filter `Acknowledgment_Channel__c IsNull`.
- Skips when `IsWon = false` **or** status is `Acknowledged` / `Do Not Acknowledge`.
- `Get_Rules` pulls all `Active__c = true` rules; `Loop_Rules` walks them; the
  **lowest `Priority__c`** match wins (via `varBestPriority`, per the JSI-87 gotcha that
  CMDT sort order is unreliable in Flow).
- Stamps `Acknowledgment_Channel__c`, `Acknowledgment_Send_Mode__c`,
  `Acknowledgment_Template__c`, and `npsp__Acknowledgment_Status__c = 'To Be Acknowledged'`.

The CMDT already carries `Campaign__c`, `Fund__c`, `Donor_Type__c`, `Record_Type__c`,
`Min_Amount__c`, `Max_Amount__c`, `Channel__c`, `Send_Mode__c`, `Email_Template__c`,
`Template_Flow__c`, `Priority__c`, `Active__c` — the engine was **built to be extended this
way**. One caveat found by reading the router's match formula:

```
formIsMatch =
  AND( OR(ISBLANK(Rule.Record_Type__c), RecordType.DeveloperName = Rule.Record_Type__c),
       OR(ISBLANK(Rule.Min_Amount__c),  Amount >= Rule.Min_Amount__c),
       OR(ISBLANK(Rule.Max_Amount__c),  Amount <= Rule.Max_Amount__c) )
```

**`Campaign__c`, `Fund__c` and `Donor_Type__c` are declared on the CMDT but are never
evaluated.** They are inert placeholders today. So adding a criterion means adding both the
field *and* its clause in `formIsMatch` — no criterion is free.

### 2.3 Why the criterion must be a **picklist, not a checkbox**

The engine's convention is **blank = "don't care"** (every clause is `OR(ISBLANK(...), ...)`).
A checkbox has no blank state — every one of the five existing rules would silently acquire
a hard `false`, changing their meaning. A three-state picklist preserves the convention:

| `DAF_Gift__c` on the rule | Meaning |
|---|---|
| _(blank)_ | Ignore DAF status — matches either. **All five existing rules stay exactly as they are.** |
| `Yes` | Matches **only** DAF gifts |
| `No` | Matches **only** non-DAF gifts |

New clause: `OR( ISBLANK({!Loop_Rules.DAF_Gift__c}), TEXT({!Loop_Rules.DAF_Gift__c}) = IF({!$Record.DAF_Gift__c}, "Yes", "No") )`

### 2.4 Why not simply "Do Not Acknowledge"

Setting `npsp__Acknowledgment_Status__c = 'Do Not Acknowledge'` for DAF gifts would be the
one-line version — and it is **wrong for this story**. The Jira DoD is explicit that the
*donor receives an acknowledgement*; the dictation says the *templates will be different*.
Suppression would satisfy the dictation's headline and fail the DoD. (`Acknowledgment_Channel__c`
does have a `None` value available if a true-suppression option is ever wanted.)

### 2.5 Belt-and-braces: should the standard rules be set to `No`?

Two defensible settings, and it is a real decision (**D3**):

- **Leave them blank** — the DAF rule wins on priority alone. If someone deactivates the
  DAF rule, DAF gifts fall back to a standard template → **a tax letter goes to a DAF donor**.
- **Set the five standard rules to `No`** — if the DAF rule is deactivated, a DAF gift
  matches *nothing* and gets no letter at all. Silent, but harmless.

**Recommendation: set them to `No`.** For a compliance control, failing closed beats failing
into the exact letter the story exists to prevent.

---

## 3. Verified org context (checked against JCRC-Dev, 2026-08-17)

| Fact | Verified value |
|---|---|
| `Opportunity.DAF_Gift__c` | Checkbox, default false. Created 13:32 on 2026-08-17. |
| `Account.Fund` record type | Active. Org description: **"DAFs / Benevity"**. |
| `Account.Advisor__c` | Lookup → Contact, `SetNull`, relationship `Accounts`. |
| Existing Fund accounts | **2**: `Fidelity Charitable` and `Ott Family Fund` — both with `Advisor__c` **blank**. (These are two *different kinds* of thing; see Q2.) |
| DAF opportunities today | **0** — nothing to migrate; clean build. |
| `Acknowledgment_Template__c` | **Text(255)**, not a picklist — a new template name needs **no** picklist value. |
| `Acknowledgment_Channel__c` | Restricted picklist: `Email` / `Print` / `None`. |
| Existing rules | 5: `Major_Gift` (p10), `Donation_Mid_Approval`, `Donation_Small_Auto`, `In_Kind_Gift`, `Default_Fallback` (p100, Print/Approval-Gated/`Ack_General`). |
| Email send flow | `Opportunity_Send_Acknowledgment_Email` — entry `Acknowledgment_Channel__c = 'Email'`; recipient = **`$Record.npsp__Primary_Contact__c`**; template fetched by **DeveloperName** from `Acknowledgment_Template__c`. → **a new email template needs no flow change.** |
| Letter flow | One `Acknowledgment_Letter` screen flow; Pick-Template branches on `Ack_InKind` / `Ack_MajorGift` / `Ack_Recurring` / `Ack_Tribute` + general. → **a DAF print letter = one new outcome + screen.** |
| Email templates | `Ack_Email_General` / `_InKind` / `_MajorGift` / `_Recurring` / `_Tribute` (classic, `email/unfiled$public/`). |
| Campaigns in org | 8. |
| NPSP OCR default role | `Donor` (`npe01__Contacts_And_Orgs_Settings__c`) |
| NPSP soft-credit roles | `Matched Donor;Household Member;Soft Credit` (`npo02__Households_Settings__c`) |
| **Actual OCR on a Fund-account gift** | **`Soft Credit`, IsPrimary = true** — measured, not inferred (§5.2). The settings above would have predicted `Donor`. |
| **Current routing of a DAF gift** | **`Ack_Email_General` / Email / Approval-Gated** — i.e. the standard tax letter, today (§5.2). |
| Still outstanding from JSI-87 | OWEA `development@jcrcny.org` verification + Deliverability = All email. **Live email send stays blocked until those are done** — including DAF email. |

---

## 4. Requirement → mechanism

| DoD / dictation requirement | Mechanism |
|---|---|
| DAF gift gets none of the standard acknowledgements | `DAF_Gift__c = Yes` rule at priority **5** (below `Major_Gift`'s 10) + standard rules set to `No` (D3) |
| Donor still receives an acknowledgement | The DAF rule stamps a real template; status still goes to `To Be Acknowledged` |
| …of the payment and the payment date | Template merge fields — which date is authoritative is **Q4** |
| …for the specific campaign | Campaign name merged into the template — likely needs a formula field, see §5.3 |
| Amount not displayed | Purely template-level: omit `{!Opportunity.Amount}` **and** the JSI-86 deductible/non-deductible fields |
| No tax-deduction reference after the signatures | New template body; the standard closing block is not reused |
| Templates are different | Separate `Ack_Email_DAF` template and/or `Ack_DAF` letter screen |

---

## 5. Design

### 5.1 New metadata

| Component | Type | Notes |
|---|---|---|
| `Acknowledgment_Rule__mdt.DAF_Gift__c` | Picklist (`Yes`/`No`) | Blank = ignore. Per §2.3. |
| `Acknowledgment_Rule.DAF_Gift` | CMDT record | `DAF_Gift__c = Yes`, `Priority__c = 5`, channel/mode per **D2**, template per D2. **Remember the `xmlns:xsd` gotcha** — a CMDT record without it deploys as "0 components" with no error. |
| 5 existing rule records | CMDT edit | Add `DAF_Gift__c = No` (if D3 = fail-closed) |
| `Opportunity_Acknowledgment_Router` | Flow edit | One extra clause in `formIsMatch`. Nothing else changes. |
| `Ack_Email_DAF` | EmailTemplate | Classic, `email/unfiled$public/`, placeholder copy. **This is the D2 template** — the DAF rule sets `Email_Template__c = Ack_Email_DAF`, leaving `Template_Flow__c` blank so the router's `BLANKVALUE(Template_Flow__c, Email_Template__c)` resolves to it. |
| `DAF Gifts Pending Approval` | Report | Per §5.4, in the existing `Acknowledgment Reports` folder |
| ~~`Acknowledgment_Letter` flow edit~~ | — | **Not needed** — D2 chose Email, so no print screen is required. Revisit only if a printed DAF letter is wanted later. |
| `Opportunity_Reset_Ack_On_DAF_Change` | New before-save flow | Closes Risk 1 — see §7 |
| `Opportunity.Campaign_Name__c` | Formula (Text) | **Only if** §5.3 verification shows the campaign can't merge directly |

### 5.2 Recipient — **RESOLVED (D1), no build required**

**Jason, 2026-08-17:** on any DAF gift the **Account is a `Fund`-record-type Account**
(e.g. *Ott Family Fund*) and the **Opportunity's Primary Contact is the donor**. NPSP
soft-credits the donor, which is the accurate treatment, and **the donor receives the
acknowledgement**.

This is the best of the two models I had offered: the fund holds the gift *and*
`npsp__Primary_Contact__c` is populated. Since `Opportunity_Send_Acknowledgment_Email`
already resolves its recipient from `$Record.npsp__Primary_Contact__c`, **no recipient
fallback, no `Account.Advisor__c` chain, and no "unresolvable recipient" error path are
needed.** The original Phase 4 drops entirely.

**Verified in-org, not assumed** (anon Apex, `setSavepoint()` → `rollback()`, 2026-08-17) —
a $1,000 Donation booked to *Ott Family Fund* with Jason Ott as Primary Contact and
`DAF_Gift__c = true`:

| Observation | Result |
|---|---|
| OCR created by NPSP | **exactly one — `Role = Soft Credit`, `IsPrimary = true`** ✔ confirms the expected treatment |
| Acknowledgment channel stamped | `Email` |
| Send mode stamped | `Approval-Gated` |
| **Template stamped** | **`Ack_Email_General`** |
| Status stamped | `To Be Acknowledged` |

**That fourth row is the proof this story is needed.** With today's rules, a DAF gift is
already queued to receive the **standard general acknowledgement** — the tax-language letter
the dictation exists to prevent. It is not a theoretical gap; it is the current behaviour.

Worth noting the org settings alone would have predicted the *wrong* answer here:
`npe01__Opportunity_Contact_Role_Default_role__c` is `Donor` and the soft-credit role list is
`Matched Donor;Household Member;Soft Credit`. NPSP nonetheless assigned `Soft Credit` for the
organisational gift. Reading the settings would have produced a confident wrong conclusion;
running it produced the right one.

### 5.2a Side finding — JSI-90 hard-credits what NPSP soft-credits

The same test showed `GiftAllocationService` creating a **`Hard`** `Gift_Allocation__c` of
$1,000 for the donor, because it takes its hard-credit contact from
`npsp__Primary_Contact__c` without regard to the OCR role. So for a DAF gift the donor is a
**soft credit in NPSP** but a **hard credit in the JSI-90 giving-levels engine** — and the
Fund account separately carries the NPSP account hard credit.

**This does not affect JSI-124** (the acknowledgment recipient is the same either way) and it
may well be the desired behaviour — JSI-90's D5 settled that combined hard + soft qualifies
for a level, and JSI-123's `Board_Commitment_Applied__c` reads `Total_Giving` (hard + soft),
so totals land correctly in both. It only skews the **hard-vs-soft split** on the Annual
Giving Summary. Flagging it because JSI-80's original JCRC notes explicitly asked to
*"make sure the gift isn't double-counted"* — this is where that question comes due.
**Recommend handling it as its own story, not folding it into JSI-124.**

### 5.3 Campaign merge — verify, don't assume

A classic email template merging a **parent lookup's name** is not reliable —
`{!Opportunity.CampaignId}` merges an Id, not a name, and this org already hit a related
wall on JSI-109 (a cross-object formula could not reference a parent's compound `Name`;
it had to be rebuilt from `FirstName`/`LastName`). `Campaign.Name` is a plain text field
rather than a compound one, so it **probably** works in a formula — but that is exactly the
kind of "probably" the No-Guessing tenet forbids.

**Phase 0 verification:** deploy a throwaway formula `Campaign.Name` on a sandbox field and
confirm; if it fails, ship `Opportunity.Campaign_Name__c` as a text formula and merge that.

### 5.4 Approval queue report (D2)

Because the DAF path is **Email / Approval-Gated**, nothing sends until someone ticks
`Acknowledgment_Approved__c`. That makes the approval queue the operational bottleneck, so it
needs its own view rather than being buried in the general pending report.

**New report — "DAF Gifts Pending Approval"** (folder `Acknowledgment Reports`, alongside the
two JSI-87 reports):

| Aspect | Spec |
|---|---|
| Format | Tabular (work queue) |
| Filter | `DAF_Gift__c = true` **AND** `npsp__Acknowledgment_Status__c = To Be Acknowledged` **AND** `Acknowledgment_Send_Mode__c = Approval-Gated` **AND** `Acknowledgment_Approved__c = false` |
| Columns | Opportunity name, Account (the Fund), Primary Contact (the donor — the recipient), Close Date, Campaign, `Acknowledgment_Template__c`, `Acknowledgment_Age_Business_Days__c` |
| Sort | Age descending, so the oldest unapproved sits at the top |

Report gotchas that apply here (from prior stories): report **Name max 40 chars**; the folder
and its reports must deploy **together**; a custom column on the standard Opportunity report
type needs the object-qualified token `Opportunity.DAF_Gift__c`, not the bare API name.

**Dependency to be explicit about:** choosing Email means the DAF acknowledgement **cannot be
verified end-to-end until the two outstanding JSI-87 org settings are done** — the OWEA
`development@jcrcny.org` must be verified, and Setup → Deliverability → *Access to Send Email*
set to **All email** (sending a template to a `recipientId` requires single-email). Routing,
stamping, approval and the report are all fully testable before that; only the actual send is
blocked. See Risk 3.

### 5.5 Security

Per the org standard — **profiles, not permission sets** — via the additive
minimal-profile deploy. The only new field needing FLS is `Campaign_Name__c` (if built);
CMDT fields don't take FLS. Targets: `Admin` + `JCRC - Development / Fundraising /
Marketing / Volunteering`.

---

## 6. Compliance — two findings worth the client's attention

**a) The "no tax language" rule is real, and the research backs the dictation exactly.**
The donor's deduction happened when they funded the DAF, not when the DAF granted to JCRC.
Sector guidance is that the charity should **not** send a tax acknowledgement for a DAF
grant, but **should** thank the advisor for recommending it — commonly phrased *"Thank you
for recommending the generous grant of … that we received on … through your donor advised
fund at [sponsor]."* Note this phrasing **does** name the sponsor (Q9) and **does** state
the amount — which the Jira DoD says to omit. The DoD is the stricter of the two; there is
no compliance problem with omitting the amount, so **follow the DoD**.

**b) Gala tickets paid from a DAF — a live risk, and this story's persona is the gala event
manager.**

*The mechanics.* A gala seat priced at $1,000 against $250 of dinner/entertainment FMV is
$750 deductible + $250 non-deductible — precisely JSI-86's `Deductible_Amount__c` /
`Non_Deductible_Amount__c` split and the Gala build's `Gala_Level__c.Non_Deductible_Amount__c`.
Donors frequently propose **"bifurcation"**: pay the $250 FMV personally and have the DAF
grant the $750. It sounds clean and it is the thing to watch for.

*The rule, stated precisely.* **IRC §4967** taxes a DAF distribution that confers **more than
an incidental benefit** on the donor/advisor — the excise tax falls on **the advisor**
(and potentially fund management), not on JCRC. In **Notice 2017-73** Treasury and the IRS
announced they **are considering proposed regulations** that would treat a DAF distribution
paying for tickets enabling the advisor to attend a charity-sponsored event as more than
incidental — **even where the advisor pays the non-deductible portion out of pocket**.

*Status — the statute is in force. Only one interpretive regulation is outstanding.*
**§4967 is enacted law and has applied to taxable years beginning after 17 August 2006**
(Pension Protection Act of 2006). It is not proposed and not pending. The tax is **125% of the
prohibited benefit**, payable by the donor/advisor who advised the distribution or received the
benefit, plus a separate **10% on any fund manager** who knowingly agreed to it.

What is *not* final is only the **regulation** that would codify how the more-than-incidental
test applies to this particular fact pattern: Notice 2017-73 announced Treasury's intent, the
November 2023 proposed regulations addressed **§4966** and left §4967 for later, and §4967
guidance remains on the Priority Guidance Plan.

> **Correction (2026-08-18).** An earlier draft of this section led with "the regulations are
> still not final" and characterised the position as *"announced intent plus sponsor practice,
> not settled regulation."* **That understated it.** The operative statute is settled and
> enforceable, the IRS has stated its position on event tickets, and sponsors apply that
> position today. JCRC reported it as enforced, and JCRC is right. Treat this as a live rule,
> not a forthcoming one.

*How it is enforced in practice — at the sponsor.* The sponsoring organisation is the
enforcement point, because its own fund managers carry §4966/§4967 exposure. Fidelity
Charitable and community foundations decline event-ticket and table grants outright, and
specifically **will not cover any part of a ticket even where part of the price is
deductible** — which is exactly the bifurcation route donors propose. The practical failure
mode is therefore **operational as well as legal**: a donor recommends a grant for a gala
table, the sponsor rejects it, and the seat is already promised.

*The clean pattern* most nonprofits land on: DAF money is accepted only where the donor takes
**no benefit at all** — a sponsorship with the tickets formally declined, i.e. fully
deductible, zero FMV.

**Recommendation:** put Q8 to JCRC as a policy question. If they confirm, add a warning or
validation when `DAF_Gift__c = true` **and** the gift carries a non-deductible/FMV portion
(or uses the `Event_Registration` record type / a `Gala_Level__c` with FMV). **Not building
it without the policy answer** — but it should not be discovered later, and the data model
can already represent the problematic combination today.

---

## 7. Risks

1. **Re-classification gap — the highest-value defect this plan closes.** The router's entry
   filter is `Acknowledgment_Channel__c IsNull`, so it classifies **once and never again**.
   If a gift is saved and won *before* someone ticks the DAF box, it has already been stamped
   with a standard template — and ticking DAF afterwards does **nothing**. The donor gets the
   standard tax letter, which is the precise outcome this story exists to prevent. Given that
   the DAF box is a manual tick, this is the *likely* path, not an edge case.
   **Fix:** a small before-save flow that clears `Acknowledgment_Channel__c` (and Send Mode /
   Template) when `DAF_Gift__c` changes and status is not yet `Acknowledged`. The router then
   re-fires and re-routes on its own — no change to the router's own logic, minimal blast radius.
2. **Already-sent letters can't be recalled.** If the standard acknowledgement was already
   *sent* before the DAF flag went on, no automation can undo it. Mitigation: surface it —
   a report of DAF gifts whose `npsp__Acknowledgment_Date__c` predates the DAF flag.
3. **Email path is still blocked org-wide** by the two outstanding JSI-87 settings (OWEA
   verification + Deliverability). If D2 chooses Email, DAF acknowledgment cannot be
   verified end-to-end until those are done.
4. ~~**`Fund` record-type semantics are unsettled**~~ — **retired 2026-08-17.** D1 settled the
   model and the in-org test confirmed it. `Account.Advisor__c` is **not** on the
   acknowledgment path at all, so nothing here depends on how it gets populated.
5. **CMDT record deploy gotcha** — the `xmlns:xsd` declaration. Omitting it fails silently
   with "0 components" (source) / `UNKNOWN_EXCEPTION` (mdapi).

---

## 8. Phased build (on go-ahead)

| Phase | Work | Gate |
|---|---|---|
| **0** | ~~Confirm credit model~~ **✅ done 2026-08-17** (D1 answered + verified in-org). Remaining: verify campaign merge (§5.3) | — |
| **1** | `DAF_Gift__c` criterion on the CMDT + `formIsMatch` clause + DAF rule record + set standard rules to `No` | D2, D3 |
| **2** | `Ack_Email_DAF` template (placeholder copy, email only per D2) | D2 ✅ |
| **3** | Re-classification reset flow (Risk 1) | — |
| **4** | ~~Recipient fallback~~ — **DROPPED**, not needed (§5.2) | — |
| **5** | `DAF Gifts Pending Approval` report (§5.4) + FLS + record-page visibility for the DAF flag | — |
| **6** | Verify: anon Apex in `setSavepoint()` → `rollback()` for each routing path; confirm a DAF gift never lands on a standard template. **Baseline already captured** (§5.2) — today it lands on `Ack_Email_General`, so the same script re-run after Phase 1 is the pass/fail test | — |

---

## 9. Decisions to settle before build

| # | Decision | Recommendation |
|---|---|---|
| **D1** | ~~Which DAF credit model is in force~~ | **✅ SETTLED 2026-08-17 (Jason):** Account = `Fund` record type, Primary Contact = the donor, NPSP soft-credits the donor, **donor receives the acknowledgement**. Verified in-org. Recipient work drops. |
| **D2** | DAF channel + send mode | **✅ SETTLED 2026-08-17 (Jason): `Email` / `Approval-Gated`**, plus a report so staff can see which DAF gifts are awaiting approval. See §5.4. |
| **D3** | Standard rules blank vs. `No` | **✅ SETTLED 2026-08-17 (Jason): fail closed** — if the DAF rule is deactivated, **no letter goes out**. The five standard rules get `DAF_Gift__c = No`. |
| **D4** | Which date is the payment date (Q4) | Close Date unless the client reconciles from NPSP Payments |
| **D5** | Name the sponsoring fund in the letter (Q9) | Yes — it is the sector-standard phrasing, and JCRC's donors will recognise it |
| **D6** | Build the gala/DAF bifurcation guard (Q8) | Ask the client first; do **not** build blind |

---

## 10. Sources

- IRS **Notice 2017-73** (donor-advised funds; bifurcated event tickets) — <https://www.irs.gov/pub/irs-drop/n-17-73.pdf>
- Fidelity Charitable, *How to Thank Donors Who Use Donor-Advised Funds* — <https://www.fidelitycharitable.org/articles/how-to-thank-donors-who-use-donor-advised-funds.html>
- Little Green Light, *How to acknowledge gifts from donor-advised funds* — <https://www.littlegreenlight.com/blog/donor-advised-funds/>
- National Council of Nonprofits, *Gift Acknowledgments* — <https://www.councilofnonprofits.org/running-nonprofit/fundraising-and-resource-development/gift-acknowledgments-saying-thank-you-donors>
- Community Foundation for Greater Atlanta, *Clarifying the rules: Donor-advised funds and event tickets* — <https://cfgreateratlanta.org/2024/12/06/clarifying-the-rules-donor-advised-funds-and-event-tickets/>
- Soliant Consulting, *How to Track DAF-Paid Donations in Salesforce NPSP* (the Option 1 / Option 2 framing used in JSI-85) — <https://www.soliantconsulting.com/blog/how-track-daf-paid-donations-salesforce-npsp/>
- In-repo: `JSI-87/` (engine), `JSI-85/JSI-85_Implementation_Plan.md` (DAF decision), `JSI-86/` (deductible split), `JSI-80/JSI-80_User_Story.md` (original JCRC DAF questions).

---

## 11. Build Log

### 2026-08-17 — Phases 1, 2, 3, 5 BUILT + DEPLOYED + VERIFIED (JCRC-Dev)

**Deployed**

| Component | Notes |
|---|---|
| `Acknowledgment_Rule__mdt.DAF_Gift__c` | Restricted picklist `Yes`/`No`, DeveloperControlled. Blank = ignore. |
| `Opportunity.Campaign_Name__c` | Text formula `Campaign.Name`, `BlankAsBlank`. **§5.3 verification answered: it deploys and populates.** FLS read-only on Admin + 4 JCRC via additive minimal-profile deploy. |
| `Acknowledgment_Rule.DAF_Gift` | New rule: `DAF_Gift__c=Yes`, Priority **5**, Email / Approval-Gated, `Email_Template__c=Ack_Email_DAF`, no Record Type (applies to every gift type). |
| 5 existing rule records | `DAF_Gift__c = No` added (D3 fail-closed). |
| `Opportunity_Acknowledgment_Router` | `formIsMatch` gained the DAF clause. |
| `Ack_Email_DAF` | Classic EmailTemplate, `email/unfiled$public/`. Placeholder copy: no amount, no tax/goods-and-services language, explicit in-body warning not to add either. |
| `Opportunity_Reset_Ack_On_DAF_Change` | New before-save flow (Phase 3, Risk 1). |
| `DAF Gifts Pending Approval` | Report in `Acknowledgment Reports`. |

**Verified — anon Apex, `setSavepoint()` → `rollback()`, nothing persisted**

| Test | Result |
|---|---|
| T1 — DAF gift routes to the DAF template | **PASS** — `Ack_Email_DAF` / Email / Approval-Gated / not approved / To Be Acknowledged (baseline before this build: `Ack_Email_General`) |
| T1b — campaign merge value | **PASS** — `Campaign_Name__c` = "FY27 Spring Appeal" |
| T2 — non-DAF gift unchanged (regression) | **PASS** — still `Ack_Email_General` |
| T3 — gift routed standard, *then* flagged DAF | **PASS** — re-routes to `Ack_Email_DAF` |
| T3b — approval stripped on re-route | **PASS** — `Acknowledgment_Approved__c` forced back to false |
| T4 — recipient + credit | **PASS** — OCR `Soft Credit`/primary; letter targets the donor (`npsp__Primary_Contact__c`); merges resolve to fund "Ott Family Fund" + campaign "FY27 Spring Appeal" |
| T5 — fail-closed (D3) | **PASS** — with the DAF rule temporarily deployed `Active=false`, a DAF gift routed to **nothing** (channel/template/status all null) rather than falling back to a standard tax letter. Rule restored to active and routing re-confirmed. |

**Gotchas hit**

1. **A CMDT picklist in a Flow formula must be wrapped in `TEXT()`.** `ISBLANK({!Loop.Pick__c})` and a bare `=` comparison fail the deploy with *"Field Loop_Rules is a picklist field. Picklist fields are only supported in certain functions."* Fix: `ISBLANK(TEXT(...))` and `TEXT(...) = "Yes"`.
2. **Report `description` max length is 255** — same 255-char ceiling as a permission set's.

**🔴 NEW FINDING — approving an email acknowledgment currently fails the save outright.**
During T3 the first attempt set `Acknowledgment_Approved__c = true` on its own, and the DML
threw: `CANNOT_EXECUTE_FLOW_TRIGGER … "Opportunity Send Acknowledgment Email" … Org-Wide Email
provided is not valid.` This is **not DAF-specific and not new to JSI-124** — it hits every
approval-gated *email* acknowledgment, including JSI-87's standard path. The unverified OWEA
does not merely stop the send; it makes the record **unsaveable** the moment approval turns on.
**Consequence: the two outstanding JSI-87 settings are now blocking, not deferrable** —
verify OWEA `development@jcrcny.org`, and set Setup → Deliverability → *Access to Send Email*
= **All email**. Routing, re-routing, fail-closed and the report are all verified without them;
only the approve-and-send step is blocked.

**Not built (deliberate)**

- **Gala/DAF bifurcation guard** — held for JCRC's policy answer (Q8 / D6), per §6b.
- Print letter screen — D2 chose Email, so no `Ack_DAF` branch in `Acknowledgment_Letter`.
- Client template copy — pending, same as JSI-87.
