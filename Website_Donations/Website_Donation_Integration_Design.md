# Website Donations — Gravity Forms → Salesforce Integration Design

> **Author:** Jason Ott · **Written:** 2026-08-19
> **Status:** **DESIGN ONLY — nothing built.** For review before any implementation.
>
> **Change Log:**
> - 2026-08-19 — Jason Ott — Initial analysis and recommended approach.
> - 2026-10-28 — Jason Ott — §18: gala gifts go to Pending Transactions instead of becoming gifts (built).

---

## 1. What this solves

The JCRC donate page runs on **Gravity Forms** with the **Stripe** add-on. Gravity Forms ships
a Salesforce integration, but it writes to **standard objects only** with limited field
mapping — which cannot express what this form actually collects. The clearest example: the
**Designation field is multi-select**, so a single payment can be split across several funds,
and no standard-object mapping can represent that.

So the integration is custom: Gravity Forms posts a **webhook** to Salesforce on submission,
and Salesforce parses it and creates the records.

**This document covers the integration itself** — endpoint, authentication, parsing, record
shape, security, retries and monitoring. It deliberately does **not** re-open donor matching
or acknowledgment design, which already exist.

---

## 2. Verified context (checked 2026-08-19)

| Fact | State |
|---|---|
| Gravity Forms Webhooks add-on | POSTs JSON, supports **custom request headers**, fires conditionally. Needs **Elite or Nonprofit** license — assumed available. |
| **GF cannot refresh an OAuth token** | It sends static header values (or merge tags). This is the single biggest constraint on the auth design. |
| Salesforce Sites in org | **None.** No public endpoint exists. |
| Apex REST classes in org | **None.** |
| Custom Connected Apps | **None** (only the CPQ one that ships). |
| Multiple designations | Confirmed by Jason: **one Opportunity with multiple GAU Allocations.** |
| GAUs that exist today | **Only 3** — Gala Fund, General Fund, Israel Fund. The form offers ~11 designations. |
| `npsp__Allocations_Settings__c` | Default Allocations **off**, no default GAU, Payment Allocations **off**. |
| Payment | Stripe add-on. Some submissions are **intent only** — the donor chooses. |
| Acknowledgment timing | Same-day is fine. |

---

## 3. The four decisions, kept separate

Conflating these is what makes this kind of integration go wrong.

| # | Decision | Recommendation |
|---|---|---|
| 1 | **Endpoint** — how the POST reaches Salesforce | Public **Salesforce Site + Apex REST** |
| 2 | **Authentication** — how Salesforce trusts the POST | **Shared secret in a request header**, validated before any work |
| 3 | **Parsing** — JSON to field values | **Apex** deserializes; hand off to Flow later only if admins need to change behavior without a deploy |
| 4 | **Record shape** — what gets written | **One Opportunity + N GAU Allocations**, plus Contact resolution |
| 5 | **Mapping maintenance** — how fields are added later | **Custom Metadata driven by an admin LWC**, so adding a field is configuration, not a deploy (§11) |

---

## 4. Why this endpoint, and not the alternatives

| Option | Verdict |
|---|---|
| **Site + Apex REST** ✅ | No recurring cost, no third party touching donation data, no token lifecycle to break, full control of parsing and errors. Cost: a publicly reachable endpoint, so security must be deliberate (§6). |
| **Streams** (used before) | Gives a stable URL and — the real value — **shapes the payload so Flow can read it**. That shaping is a modest amount of Apex we can own. Paying a vendor for an endpoint plus a parser. |
| **make.com** (used before) | Fastest to stand up and solves OAuth properly. Two costs: a recurring fee, and a **third-party data processor holding donation PII**. Precedent matters — JSI-107 rejected Cazoomi (~$112/mo) partly on those grounds, and that was *marketing* data, less sensitive than this. |
| **OAuth direct from WordPress** ❌ | Possible via the `gform_webhooks_request_headers` filter plus a PHP snippet that caches a token. Makes WordPress a holder of Salesforce credentials and puts token-refresh logic somewhere nobody will maintain. Rule out. |
| **GF native Salesforce add-on** ❌ | The thing being replaced — standard objects, limited mapping, cannot express multi-designation. |

---

## 5. Recommended architecture

```
Gravity Forms (submission)
   |  POST JSON + shared-secret header
   v
Salesforce Site  ->  Apex REST  (@RestResource, guest user)
   |                   1. validate shared secret      <- before ANY work
   |                   2. reject duplicates on GF entry id
   |                   3. deserialize + validate payload
   |                   4. write a staging record      <- durable, always
   |                   5. return 200 fast
   v
Asynchronous processing (Queueable)
   |   resolve/create Contact  ·  create Opportunity
   |   create one GAU Allocation per designation
   |   tribute fields -> JSI-89  ·  write-in -> JSI-127
   v
Integration_Log__c   (reuses the JSI-107 logging object + reports)
```

**Two properties matter more than the details.**

**Accept fast, process later.** The endpoint's only job is to validate, store and return 200.
All record creation happens asynchronously. A slow or failing donor-matching step must never
make the donor's browser hang or Gravity Forms treat the submission as failed.

**The raw payload is stored before anything is interpreted.** If parsing has a bug, the
donation is not lost — it can be reprocessed. Without this, a mapping mistake means a
permanently lost gift, which for a fundraising system is the worst possible failure.

---

## 6. Security model

A public endpoint that creates records needs each of these, not a subset:

1. **Shared secret** in a custom header, compared **before any DML or SOQL**. Rotatable, held
   in Custom Metadata or a protected Custom Setting, never in code.
2. **Guest user least privilege** — create on the staging object and nothing else. No read on
   Contact, Opportunity or anything donor-related. The async job runs in system context and
   does the real work.
3. **Payload ceiling** — reject anything implausibly large before parsing.
4. **No useful error detail in responses.** A public endpoint must not confirm what it stored
   or why something failed. Log detail internally; return a generic failure.
5. **IP allowlist** if the WordPress host has stable IPs — *unconfirmed, so treat as a bonus
   control, never the primary one.*
6. **Never accept card data.** See §7.

Note: guest users cannot own records, so the staging record needs a designated owner.

---

## 7. Payment boundary (non-negotiable)

Stripe processes the card. **The webhook must never carry a card number, CVV or full expiry** —
only the Stripe reference, last four, and payment method. Anything more drags Salesforce into
PCI scope for no benefit. Enforce it by reading only known-safe keys from the payload rather
than accepting whatever arrives.

---

## 8. Two submission paths

The donor chooses whether to pay, so one form produces two shapes:

| Path | Signal | Record |
|---|---|---|
| **Paid** | Stripe transaction present | Gift, closed/won, with the payment reference |
| **Intent** | No transaction | Not a completed gift — a pledge or an open commitment |

Treating these identically would either invent revenue that was never collected, or discard a
genuine commitment. **The webhook must state which it is explicitly** rather than having
Salesforce infer it from a missing field.

---

## 9. Communication policy — settle this early

**Stripe already emails the donor a receipt.** If a website gift also flows through the JSI-87
engine it now produces a **printed, approval-gated letter**, because the email tiers were
replaced. So a $54 online donor gets a Stripe receipt *and* generates a letter for someone to
approve and print.

Options, all needing JCRC's view:

- Website gifts below a threshold → `Do Not Acknowledge` (the Stripe receipt is the thank-you)
- A distinct low-touch acknowledgment for online gifts
- Letters regardless, accepting the volume

This is the same question as "should small gifts get letters", arriving from a second
direction — a good reason to answer it once, properly.

---

## 10. Designation → GAU mapping: a real gap

The form offers roughly **11 designations**; the org has **3 GAUs** (Gala Fund, General Fund,
Israel Fund). The mapping has to be decided and the missing GAUs created before this works end
to end.

Two designations need care rather than a straight mapping:

- **Israel Day on Fifth (Registration/Sponsorship)** vs **(Donation)** — registration carries a
  benefit, so it needs the JSI-86 deductible / non-deductible split, and it is the exact case
  that cannot be paid from a DAF under §4967.
- **Other** → free text, which is precisely what `Other_Campaign_Write_In__c` and the JSI-127
  review queue were built for.

**Recommendation:** hold the mapping in **Custom Metadata** (form value → GAU → campaign), so
adding a designation is configuration rather than a deployment.

---

## 11. Admin-configurable mapping (the LWC)

**Requirement (Jason):** adding a field to the Gravity Forms form, or to Salesforce, must not
require a code change or a deployment.

This is the difference between an integration that ossifies and one that survives a form that
keeps changing. It also removes the most common cause of silent breakage: a form field that
gets added or renamed and is quietly dropped because nothing knew to look for it.

### 11.1 Two mapping tables, not one

| Table | Maps | Example |
|---|---|---|
| **Field mapping** | payload key → object + field | `input_12` → `Contact.MailingPostalCode` |
| **Value mapping** | payload *value* → a record | designation `Israel Affairs` → GAU *Israel Fund* + campaign |

They are genuinely different shapes and squashing them together produces a table that is
awkward for both. §10's designation problem is a **value** mapping; everything else is a
**field** mapping.

### 11.2 Where the mapping lives — a real fork

| | Custom Metadata (`..._mdt`) | Custom Object (`..._c`) |
|---|---|---|
| Travels sandbox → prod in a deploy | **Yes** | No — re-entered or data-loaded |
| Editable by an admin in the UI | Yes | Yes, more naturally |
| Editable from an LWC | Via the Metadata API, **asynchronous** — needs deploy-status polling | Straightforward synchronous DML |
| Version controlled in this repo | **Yes** | No |

**Recommendation: Custom Metadata.** Three reasons, in order of weight:

1. **The mapping is part of the integration contract**, not user data. It should be testable in
   the sandbox and then promoted, not retyped in production where a typo silently misroutes
   donations.
2. **It matches how this org already works** — `Acknowledgment_Rule__mdt`, `Board_Setting__mdt`,
   `Name_Parse_Token__mdt` are all config-as-CMDT.
3. **There is direct precedent in this very org**: NPSP Advanced Mapping — which is enabled
   here — is itself a UI over Data Import Field Mapping CMDT records. The pattern is proven in
   the same codebase.

The cost is honest: writing CMDT from an LWC goes through the Metadata API and is
**asynchronous**, so the component has to handle "saving…" and poll for the result rather than
confirm instantly. That is more work than a custom object, and it is the price of the mapping
being deployable.

### 11.3 What the component has to do

The list-and-edit grid is the obvious part. The parts that earn its keep:

- **Validate the target against a describe.** Picking an object and field from a describe-driven
  picklist rather than typing an API name eliminates the single most common mapping bug. It
  also catches a *type* mismatch at configuration time rather than at 2am when a donation
  fails.
- **Show unmapped payload keys.** Paste a real submission and the component lists every key
  with no mapping. This is how the team learns the form changed, instead of finding out from a
  donor.
- **Dry-run a sample payload.** Paste a real GF submission and show exactly what would be
  written to which fields, *without saving anything*. This turns "we think the mapping is
  right" into "we watched it be right" — the same discipline used everywhere else in this
  project.
- **Flag mappings pointing at fields that no longer exist**, so deleting a Salesforce field
  surfaces immediately rather than at runtime.

### 11.4 Runtime consequence

Apex reads the mapping tables and applies them generically. Adding a field becomes: add a
mapping row, dry-run it, done. No deploy, no release.

The trade to accept knowingly: a generic mapper moves a class of error from **compile time to
run time**. A hard-coded mapping fails when you deploy it; a configured one fails when a
donation arrives. The describe-driven validation and the dry-run in §11.3 exist specifically to
pull those failures back to configuration time, and are not optional extras.

### 11.5 Security — this is a privileged screen

Whoever can edit the mapping can change what an **unauthenticated public endpoint writes**, and
where. That is a genuine privilege-escalation surface, not an admin convenience screen.

- Restrict the tab and the Apex to admins; do not hand it to the whole development team.
- Keep a **deny list** of fields the mapper may never target, regardless of configuration —
  ownership, record type, conversion and audit fields at minimum.
- Log every mapping change with who and when. `Integration_Log__c` already exists and can carry
  it.

---

## 12. What this reuses rather than rebuilds

| Need | Already exists |
|---|---|
| Write-in campaign capture + staff review queue | JSI-127 |
| Tribute / in-honor / notification recipient, with fuzzy contact matching | JSI-89 (`TributeContactResolver`) |
| Deductible vs non-deductible split | JSI-86 |
| Parade campaign letter | JSI-87 (routes on a campaign name containing "Parade") |
| Integration run logging + reports | JSI-107 (`Integration_Log__c`) |

---

## 13. Phased build (on approval)

| Phase | Work |
|---|---|
| **0** | Confirm GF license; agree the payload contract with whoever owns the form |
| **1** | Staging object + Apex REST endpoint + shared secret + Site with a least-privilege guest user. Prove a POST lands and returns 200. |
| **2** | Async processing: Contact resolution, Opportunity, GAU Allocations |
| **3** | Mapping tables (field + value) in Custom Metadata, and the Apex that applies them generically |
| **3b** | **Mapping admin LWC** — describe-driven pickers, unmapped-key detection, dry-run (§11) |
| **3c** | Designation → GAU value mappings; create the missing GAUs |
| **4** | Tribute, write-in and deductible handling wired to the existing stories |
| **5** | Logging, failure reports, replay of a failed payload |
| **6** | Communication policy applied (§9) |

---

## 14. Decisions to settle

| # | Decision | Recommendation |
|---|---|---|
| D1 | Endpoint + auth | Site + Apex REST, shared secret header |
| D2 | Parsing | Apex, with a Flow hand-off only if admins need to change behavior |
| D3 | Designation → GAU mapping, and the missing GAUs | Custom Metadata; JCRC owns the mapping |
| D4 | Acknowledgment policy for website gifts (§9) | JCRC — likely suppress for small online gifts |
| D5 | Processing fee — part of the gift, or tracked separately? | JCRC / finance |
| D6 | Intent submissions — pledge, or something else? | JCRC |
| D7 | IP allowlisting | Only if the host has stable IPs |
| D8 | Mapping storage — Custom Metadata or custom object? | **Custom Metadata** — deployable, matches org precedent, mirrors NPSP Advanced Mapping (§11.2) |
| D9 | Who may edit mappings? | Admins only — it controls what a public endpoint writes (§11.5) |

---

## 15. Risks

1. **A public endpoint is a public endpoint.** The controls in §6 are the mitigation; skipping
   any one of them materially weakens it.
2. **Silent data loss is the worst outcome.** Storing the raw payload before interpretation is
   what prevents it — do not optimize this away.
3. **Gravity Forms will retry.** Without idempotency on the GF entry id, retries create
   duplicate gifts. This must exist from phase 1, not be added later.
4. **The form can change without warning.** A new designation or a renamed field should degrade
   gracefully — store the payload, flag for review — rather than fail silently.
5. **Over-communication** (§9) is a donor-facing risk, not a technical one, and is the most
   likely thing for the client to notice.
6. **A configurable mapper moves errors from compile time to run time.** Mitigated by
   describe-driven validation and the dry-run (§11.3), which are load-bearing rather than
   nice-to-have.
7. **The mapping screen is a privilege-escalation surface** — it decides what an
   unauthenticated endpoint can write. Admin-only, with a field deny list (§11.5).

---

## 16. Open, not yet analyzed

- The **exact field list** — the inventory gathered from the public donate page came from a
  summarizing fetch of rendered HTML and is indicative only. It should be confirmed against
  the form definition in Gravity Forms admin before the payload contract is fixed.
- **Recurring donations** — not visible on the public page, and not discussed. If the form
  offers them, that is a materially different record shape (NPSP Recurring Donations) and
  needs its own analysis.

---

## 17. Sources

- Gravity Forms Webhooks add-on — capabilities and license tier:
  <https://www.gravityforms.com/feature/webhooks/>,
  <https://docs.gravityforms.com/gform_webhooks_request_headers/>
- Salesforce public Apex REST via Sites: <https://www.salesforceben.com/salesforce-webhooks-deep-dive/>
- Live org verification 2026-08-19 — Sites, Apex REST, Connected Apps, GAUs, Allocations settings.
- In-repo: `JSI-127/` (write-in), `JSI-89/` (tribute matching), `JSI-86/` (deductible split),
  `JSI-87/` (acknowledgments), `JSI-107/` (integration logging).

---

## 18. Gala gifts go to Pending Transactions ✅ built 2026-10-28

**Decision (Jason, 2026-10-28):** a website gift whose "What is this for" answers contain the word **Gala**
is **not** created as a gift. It goes to the **Gala tab of Pending Transactions** instead, Source
**JCRC Website - Gala**, so staff link the Event Registration, choose the fund and commit it like any other
gala row. Gala plus another designation goes there too, with the fund left to staff.

- **Configurable** on Web Donation Mapping > Donor & account > *Gala gifts* (stored on
  `Web_Donation_Setting__mdt`): **Send gala gifts to Pending Transactions** (on), **Gala words**
  (`Gala`; comma-separated, whole words, any capitalization), **Fields to check** (`28, 23` - the form's
  "What is this for" checkboxes, where `28` covers 28.1, 28.2 ..., and the Other write-in).
- **Donor:** matched or created exactly as for a gift (address and phone saved). The row carries the
  donor (Match Status Confirmed).
- **The row:** amount from the same Amount mapping the gift uses, date submitted, Payment Method
  Credit Card, Memo "What is this for: ...", Raw Data = the submission, Campaign from a translation (e.g.
  Other → Website Donation - Other), External ID `gf-<entry id>`.
- **Fund:** set only when the donor ticked exactly one designation and it translates to a fund (gala only →
  Gala Fund). Otherwise blank with the note "Website gift for the gala - choose the fund. The donor ticked: ...".
- **Replays:** a second run finds the waiting row instead of adding another; one already committed (its gift
  carries `gf-<entry id>`) fails with "already committed" instead of counting it twice.
- **Web Donation record:** Processed, no Opportunity, new lookup **Pending Transaction** (on the record page;
  Admin / JCRC - Development / JCRC - Fundraising read+edit). It goes blank once staff commit the row (the
  holding row is deleted on commit).
- **Translations:** the old `Web_Donation_Designation__mdt` table is no longer read by any code - designations
  translate through **Value Maps**. Added: General JCRC-NY → General Fund, 50th Anniversary Gala → Gala Fund,
  Israel Affairs → Israel Fund. Until then those showed as unmapped and NPSP's default allocation put every
  such gift in General Fund.
- **Live test (JCRC-Dev):** WD-00019's real payload replayed as WD-00031 (General + Gala) → **PT-00030**, fund
  blank + note; gala-only copy WD-00032 → **PT-00031**, Gala Fund, gala. Both Saul Zebovitz, $54, Credit Card.
- **Tests:** 57/57 web donation tests; coverage WebDonationProcessor 89.7%, WebDonationMappingController 93.8%,
  WebDonationConfig 96.5% (new `WebDonationMappingControllerTest`, `WebDonationConfigTest`).
- **Deploy note:** the 12 `Web Donation Sweeper` jobs hold the web donation classes (even for a validation) -
  unschedule, deploy, reschedule (`0 m * * * ?` for m = 0..55, `new WebDonationSweeper()`).
