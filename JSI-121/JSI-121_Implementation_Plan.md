# JSI-121 — Pending Transactions (QuickBooks holding area) — Implementation Plan

> **Status:** PLAN — decisions D1–D11 settled by Jason 2026-09-16; D12 has a working default. **No build yet.**
> **Author:** Jason Ott · **Date:** 2026-09-16
> **Jira:** **JSI-121** *"Sync CRM with Director of Finance's QBO accounts"* (confirmed by Jason
> 2026-09-16; To Do, epic JSI-13). Story snapshot: `JSI-121_User_Story.md`. Its DoD reads: *link QBO account info with Salesforce · daily feed
> from QBO to NPSP · **allow for review process before posting into NPSP***. This design is that review
> process. Related: JSI-16, JSI-39, JSI-81, JSI-88 (finance reconciliation), JSI-80 (Gift Entry, built).

---

## 1. What we're building (from the dictation)

ACH and wire gifts land in the bank → Finance records them in QuickBooks → they sync into Salesforce
into a **holding area**, not straight into gifts. Staff then work them in **one clean LWC screen**:

1. See everything waiting.
2. Edit anything on a transaction — including the **donor (Contact / Account)**.
3. Decide what it is: a **new gift (Opportunity)** or a **payment on an existing pledge**. When a donor
   is set, the screen detects their **open pledges** and lets the user pick one.
4. **Commit** one at a time or a selected batch.
5. On a successful commit the holding record is **deleted**, so the holding area never grows.

Sleek, modern, fast to enter data.

### In scope (proposed)
- Holding object, conversion engine (new gift / pledge payment), the LWC console + tab, security, tests.
- A manual **"Add transaction"** form so rows can go into the holding area **without** QuickBooks —
  the screen is usable and testable before the sync exists. (CSV import **not** in v1 — D7.)

### Out of scope / later phase (proposed — see decision D1)
- The **QuickBooks → Salesforce sync itself**. No QuickBooks connector is installed in the org today
  (verified: `sf package installed list`), and we don't yet know which QuickBooks records Finance uses
  for ACH/wire. The holding object is designed so the sync only has to insert rows.

---

## 2. Decisions

| # | Question | Options |
|---|---|---|
| **D1** ✅ | QuickBooks sync — this build or next? | **DECIDED (Jason, 2026-09-16): next phase.** Build holding area + screen + conversion now, with manual entry; sync once Finance confirms the QBO data shape. |
| **D2** ✅ | A payment amount that doesn't match a pledge installment | **DECIDED (Jason, 2026-09-16)** — see §4.3 *Installment rules*: apply to the **oldest unpaid installment**. **Short** → that installment is marked paid at the received amount and a **new payment is created for the remainder**. **More** → that installment's amount is raised to the received amount and the **extra is removed from the LAST payment** on the pledge. You can never pay **more than the pledge's total outstanding**. |
| **D3** ✅ | Which gifts count as "open" for applying a payment | **DECIDED (Jason, 2026-09-16): Pledges and Grants** with an unpaid balance. |
| **D4** ✅ | Audit trail once the holding record is deleted | **DECIDED (Jason, 2026-09-16): stamp whichever record we create** — the **Opportunity** for a new gift, the **Payment** for a pledge payment. The stamp is also the **duplicate guard** (checked on both objects). |
| D5 ✅ | Who can see / commit | **DECIDED: JCRC - Fundraising + JCRC - Development** (plus System Administrator). Profile-based, per our standard. |
| D6 ✅ | New donors | **DECIDED: yes** — create the Contact (and its household) inline from the screen. |
| D7 ✅ | Bulk edit / CSV | **DECIDED: bulk-set Campaign / Fund / Approach / Record Type = yes. CSV import = not in v1.** |
| D8 ✅ | "Wire" | **REVISED (Jason, 2026-09-16): keep the combined `ACH/Wire` value — no picklist change.** The earlier "only ACH exists" note was wrong: Opportunity stores `ACH/Wire`, Payment stores `ACH` labelled *ACH/Wire*, and `PaymentMethodService` translates between them. |
| D9 ✅ | One deposit, several purposes | **DECIDED: no splits in v1** — one transaction = one gift or one payment. |
| D10 ✅ | Volume | **DECIDED: low volume** (a handful to a few dozen a week) → commit runs synchronously; no background path in v1. |
| D11 ✅ | Overage bigger than the last installment | **DECIDED: work backwards** — delete L, take the rest off the next-to-last, and so on. |
| D12 ⏳ | Scheduled date of the remainder payment | **Working default:** the new unpaid remainder keeps O's original scheduled date. Confirm in UAT. |

**Needs Finance (for the sync phase):** how does Simcha record ACH/wire in QuickBooks — **Deposit**,
**Sales Receipt**, or **Receive Payment**? Which QBO field carries the **donor** (Customer / Received
From / memo), the **fund** (Class? Location? Item?), and anything campaign-like? Is there a stable
QBO customer id we could link to the Salesforce Account (JSI-121 / JSI-81)?

---

## 3. Verified org context (JCRC-Dev, 2026-09-16)

| Fact | Evidence |
|---|---|
| NPSP Payments **enabled**; Account model = **Household Account** | `npe01__Contacts_And_Orgs_Settings__c` |
| Pledges carry **scheduled unpaid installments** (e.g. $50,000 pledge → 12 × ~$4,166.67, 1 paid) | pledge + payment query |
| Payment has what we need: amount, payment date, scheduled date, paid, method, check/reference #, `npsp__Batch_Number__c`, `npsp__Origin_ID__c` / `Origin_Name__c` / `Origin_Type__c`, `npsp__Gateway_Payment_ID__c` (External ID) | FieldDefinition on `npe01__OppPayment__c` |
| Payment Method: combined **ACH/Wire** value on both objects (Opportunity API `ACH/Wire`; Payment API `ACH`, label *ACH/Wire*), plus Cash, Check, Credit Card, PayPal, Stock/Securities/Crypto, DAF, Benevity | field metadata + PicklistValueInfo |
| `Opportunity.Payment_Method__c` exists and **flows down to payments** (`PaymentMethodService`, commit `51297e4`) | describe + repo |
| `Opportunity.Approach__c` values: Online, Other, Direct Mail, Phone, Major Gift, In Person, Event | PicklistValueInfo |
| Opportunity record types: Standard Donation (NPSP_Default), Major Gift, Pledge, Grant, Matching Gift, In-Kind, Securities, Event Registration | RecordType |
| Stages: pledges sit at **Pledged**; `Opportunity_FullyPaidPledgeToPosted` flips a fully-paid pledge/grant to **Posted** — so paying off a pledge through this screen closes it out automatically | flow + stages |
| Funds are **NPSP GAUs**: General Fund, Israel Fund, Gala Fund. Default allocations **on** (default GAU set); payment allocations **off** | `npsp__Allocations_Settings__c`, GAU query |
| Won gifts with an unpaid balance: Pledge 24, Grant 1, Standard Donation 223, Major Gift 121, Matching Gift 31 | aggregate query — the non-pledge counts look like seed data (D3) |
| On gift creation, our automation already runs: Gift Allocations + giving levels (JSI-90), acknowledgment router (JSI-87), payment method sync | flows / triggers in repo |
| NPSP Data Import engine is present (`npsp.BDI_DataImport_API`, `npsp__DataImport__c` with `DonationImported__c` / `PaymentImported__c`); **0** DataImport rows; Donation matching = *Do Not Match* | ApexClass + FieldDefinition + settings |
| **JCRC - Development, Marketing and Volunteering hold the *Modify All Data* system permission** → Salesforce grants them full CRUD + View/Modify All on every object automatically (incl. `Pending_Transaction__c`). Object access therefore can't be limited to D5's profiles without removing that permission; FLS still limits Marketing/Volunteering (no field access granted). Fundraising does not have it. | `Profile.PermissionsModifyAllData` + `ObjectPermissions` |
| Proven house pattern for exactly this shape: **Website Donations** — staging object → processor → contact match rules → replay | `WebDonation*` classes |

---

## 4. Approach and why

### 4.1 Custom holding object + our own converter (recommended) — vs. NPSP Data Import
NPSP's Data Import object is itself a staging table and can target an existing payment. Considered and
**not recommended** here:
- `npsp__DataImport__c` is already the Gift Entry batch table (JSI-80); QuickBooks rows would show up in
  and tangle with Gift Entry batches.
- The screen needs **live pledge lookup, installment choice and splitting rules** (D2) that are our
  business logic, and they're far easier to own, test and explain in our own Apex than to steer through
  the importer's matching settings and Advanced Mapping.
- Delete-on-commit and a QuickBooks-id duplicate guard are simple with our own object.
- We already run this exact pattern in production-quality form for website donations.

### 4.2 Data model — `Pending_Transaction__c` (label "Pending Transaction"; name TBC)
Autonumber `PT-{00000}`. OWD **Private**-or-Read-per-D5. One row = **one bank transaction line**.

| Group | Field | Type | Notes |
|---|---|---|---|
| Source | `Source__c` | Picklist | QuickBooks · Manual · **Gala Sponsor (Stripe)** (§4.5) |
| | `External_Id__c` | Text(255), **Unique, External ID** | QuickBooks txn id (+ line id). Upsert key for the sync |
| | `External_Type__c` | Text | Deposit / Sales Receipt / Payment (from QBO) |
| | `Payer_Name__c`, `Payer_Email__c`, `Memo__c` | Text / Email / Long Text | Exactly what QuickBooks said — kept read-only so staff can see the original |
| | `Raw_Data__c` | Long Text | Source JSON for troubleshooting (hidden by default) |
| Money | `Amount__c` | Currency, required | |
| | `Transaction_Date__c` | Date, required | becomes Close Date / Payment Date |
| | `Payment_Method__c` | Picklist | ACH · Wire (D8) · Check · … |
| | `Reference_Number__c` | Text | → Payment Check/Reference Number |
| | `Deposit_Date__c`, `Deposit_Reference__c` | Date / Text | bank deposit traceability (JSI-88) → `npsp__Batch_Number__c` |
| Donor | `Contact__c`, `Account__c` | Lookups | set by suggestion or by user |
| | `Match_Status__c` | Picklist | Suggested · Confirmed · No Match · Multiple |
| Routing | `Apply_As__c` | Picklist | **New Gift** · **Pledge Payment** |
| | `Pledge__c` | Lookup(Opportunity) | when Pledge Payment |
| | `Installment__c` | Lookup(Payment) | optional exact installment (D2c) |
| New gift | `Gift_Record_Type__c` | Text (dev name) | default Standard Donation |
| | `Campaign__c`, `Fund__c` (GAU), `Approach__c`, `Gift_Name__c`, `Notes__c` | Lookups / Picklist / Text | |
| Workflow | `Status__c` | Picklist | **Needs Review** · **Ready** · **Error** |
| | `Error_Message__c` | Long Text | last failed commit reason, shown inline |

`Status__c = Ready` is **computed** by the service (donor set, amount/date set, and — for pledge
payments — a pledge chosen and the amount fits), so the screen can show at a glance what's committable.

### 4.3 Conversion engine — `PendingTransactionService` (Apex)
- **Commit(list of ids)** → per row, its own `Savepoint`: validate → convert → stamp → **delete** the
  holding row. Rows succeed or fail **independently**; failures roll back only themselves, land on the
  row as `Error` + message, and the screen shows them in place. Returns a per-row result.
- **New Gift:** insert Opportunity (record type, Account, `npsp__Primary_Contact__c` → NPSP creates the
  donor contact role, Amount, Close Date, stage **Posted**, Campaign, Approach, Payment Method) → NPSP
  auto-creates the paid payment → update that payment with reference #, batch/deposit number, and the
  **audit/dedupe stamp** (D4) → GAU allocation for `Fund__c` if set (else NPSP default GAU applies).
- **Pledge Payment:** lock the pledge's unpaid installments (`FOR UPDATE`), apply the installment rules
  below, set paid / payment date / method / reference / stamp. Pledge rollups recalc natively; the
  existing flow flips a fully paid pledge or grant to Posted.
- **Installment rules (D2, Jason 2026-09-16).** Received amount **R**; unpaid installments ordered by
  scheduled date; oldest = **O**, last = **L**; pledge outstanding = **B**.
  1. **R > B → blocked** ("This pledge has $B outstanding; this transaction is $R").
  2. **R = O** → O marked paid.
  3. **R < O** → O amount set to R and marked paid; a **new unpaid payment** of (O − R) is created.
  4. **R > O** → O amount set to R and marked paid; the extra (R − O) is **taken off L**. If the extra is
     bigger than L, **L is deleted and the rest comes off the next-to-last, working backwards** (D11).
  Worked example — $15,000 pledge, 4 × $3,750 unpaid, ACH of $5,000: installment 1 becomes $5,000 paid;
  installment 4 drops to $2,500. Total still $15,000, outstanding $10,000.
  Second example — same pledge, ACH of $10,000: installment 1 → $10,000 paid; extra $6,250 deletes
  installment 4 ($3,750) and takes $2,500 off installment 3 ($3,750 → $1,250). Remainder date → D12.
- **Stamp (D4):** new `QuickBooks_Transaction_Id__c` (+ source / deposit reference) on **Opportunity**
  (new gift) or **Payment** (pledge payment).
- **Duplicate guard:** before insert (sync) and before commit, refuse any `External_Id__c` already stamped
  on an Opportunity or a Payment.
- **Open pledges for a donor:** pledges (per D3) where `npe01__Amount_Outstanding__c > 0` for the chosen
  Account, **or** where the chosen Contact is primary contact — returns outstanding balance, pledged
  amount, next unpaid installment(s) with dates, campaign.
- **Donor suggestion** on insert: reuse the Website Donations matching approach (email first, then name;
  `Datacloud.FindDuplicates` as on Gala guests) → sets Contact/Account + `Match_Status__c`. Never auto-
  commits; the user always confirms.
- Bulk-safe (no SOQL/DML in loops), `with sharing` reads in `USER_MODE`; the gift/payment writes follow
  the house gotcha about system-stamped fields (see memory: USER_MODE + read-only FLS). Low volume (D10) → commits run
  synchronously, with a per-click cap (e.g. 50) enforced in the service.
- **Storage note:** most Salesforce records count a flat 2 KB regardless of content. Whether deleted rows
  sitting in the Recycle Bin still count needs a check at build time; if so, the service can hard-delete
  (`Database.emptyRecycleBin`).

### 4.4 The screen — `pendingTransactions` LWC on a **Pending Transactions** tab
Pattern reused from the Board Management console (LWC as a tab, `lightning__Tab`).

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│ Pending Transactions                                              [+ Add]  [↻]     │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │
│ │ 18 waiting   │ │ $142,350     │ │ 11 ready ✓   │ │ 2 errors !   │                │
│ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘                │
│ [Search payer, memo, ref…]  Status ▾  Source ▾  Date ▾                             │
├──────────────────────────────────────────┬─────────────────────────────────────────┤
│ ☐  Date   Payer (QBO)   Donor    Amount  │  PT-00042 · ACH · Sep 12   ● Ready      │
│ ☐  9/12   R. Cohen      Rachel…  $5,000 ●│  QuickBooks said: "COHEN R PLEDGE PMT"  │
│ ☑  9/12   Levy Fdn      —        $2,500 ◌│                                         │
│ ☑  9/11   D Kaplan      David K… $3,750 ●│  DONOR   [Contact picker ▾] [Account ▾] │
│ ☐  9/10   Wire 88213    —       $25,000 !│          Suggested: David Kaplan  ✓     │
│                                          │  AMOUNT  [$3,750.00]  DATE [09/11/2026] │
│                                          │  METHOD  [ACH ▾]      REF  [88213    ]  │
│                                          │                                         │
│                                          │  APPLY AS  ( New gift | ■ Pledge pmt )  │
│                                          │  ┌ Open pledges for David Kaplan ─────┐ │
│                                          │  │ ◉ $15,000 Pledge 07/01/2026         │ │
│                                          │  │   $15,000 outstanding ▓░░░░ 0%      │ │
│                                          │  │   Next: $3,750 due 07/01/2026       │ │
│                                          │  └─────────────────────────────────────┘ │
│                                          │  → Marks installment 1 of 4 paid        │
│                                          │                     [Save]  [Commit ▸]  │
├──────────────────────────────────────────┴─────────────────────────────────────────┤
│ 2 selected · $6,250    [Set campaign/fund…]   [Commit selected ▸]                  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

- **List + detail split view**: the list stays visible while you work a row; arrow keys / next button
  move through rows so a stack can be worked top to bottom without leaving the keyboard.
- **Status dots** (Ready / Needs review / Error) with the reason on hover and inline in the panel.
- **Donor pickers** (`lightning-record-picker`) with the suggestion shown as a one-click confirm, plus
  **"New contact"** inline (D6).
- **Apply as** segmented toggle. Choosing *Pledge payment* instantly loads the donor's open pledges as
  cards (outstanding, progress bar, next installment) and a plain-English **preview** of what commit will
  do ("Marks installment 1 of 4 paid", "Pays $2,000 of the $4,166.67 installment and reschedules the
  rest").
- **Commit** confirms with a summary (count, total, how many new gifts vs payments), then shows per-row
  results; converted rows animate out, failed rows stay with their error.
- Save as you go (draft edits persist on the holding row), non-cacheable data calls (house gotcha:
  cacheable + imperative = stale), explicit refresh, SLDS styling, works at narrower widths.

### 4.5 Interaction: Gala sponsorship page (separate work — recorded here so the model fits it)
Jason, 2026-09-16: `https://jcrcnygala.org/sponsor/` (Stripe) will also send webhooks to Salesforce, and
they are handled **differently from the website donation form** (`WebDonation*`, which turns paid
submissions straight into gifts):

| Sponsor chooses | What Salesforce does | Touches JSI-121? |
|---|---|---|
| **Pay Now** (card via Stripe, completed) | Row lands in **this holding table** for review and commit | **Yes** — a second intake source |
| **Pay Later** (check, wire, DAF) | A **Pledge** Opportunity is created directly | **Yes, later** — when that check/wire reaches the bank → QuickBooks → holding table, staff apply it as a **Pledge Payment** to that pledge (D3 already includes Pledges) |

The intake itself (webhook endpoint, parsing, pledge creation) is **built separately**. What JSI-121 must
leave room for, so that work only has to insert rows:
- `Source__c` value **Gala Sponsor (Stripe)**; `External_Id__c` holds the **Stripe payment id** (same
  duplicate guard and Opportunity/Payment stamp as QuickBooks ids).
- Room for gala context on the holding row so commit can build a proper gala gift: **Gala Level**
  (`Gala_Level__c`, the existing config object — its price, seats and non-deductible amount drive the
  existing `GalaAutomationService`), Campaign, listing/anonymous preference, honoree/tribute, and guest
  names. Exact fields are settled in the sponsor work; `Raw_Data__c` keeps the full submission meanwhile.
- **Processing fee:** the page lets donors cover the Stripe fee (2.9% + $0.30). Keep gross amount and
  donor-covered fee separately (NPSP Payment has `npsp__Donor_Cover_Amount__c`).

**No double-count (Jason, 2026-09-16).** The QuickBooks feed will pull **only ACH and wire**
transactions, never Stripe / credit-card money, so a card sponsorship (or website donation) can't arrive
a second time as a Stripe payout. Phase 5 must filter the feed to ACH and wire.

The page itself (fetched 2026-09-16) lists 13 levels from Presenting Sponsor $136,000 to Supporter $500,
$250 non-deductible per attendee, and pay options card / check / wire / DAF — useful for seeding
`Gala_Level__c`, which is still waiting on client data (Gala design doc).

### 4.6 Security (profile-based, per JCRC standard — no permission sets)
Object CRUD + FLS on `Pending_Transaction__c`, Apex class access for the controller, tab visibility —
added to the D5 profiles with the additive minimal-profile deploy. Delete permission is not needed by
users; the service deletes on commit.

### 4.7 Reporting
Holding records are transient, so reporting lives on the results: gifts/payments carrying the QuickBooks
stamp (source, deposit reference) — feeds JSI-39/JSI-88 reconciliation. Optional list view / report of
what's waiting and how old it is.

---

## 5. Phased build

| Phase | Deliverable | Verifiable outcome |
|---|---|---|
| **1 — Model** | Object, fields, picklists (+ Wire on Opp + Payment), `QuickBooks_Transaction_Id__c` stamp on Opp + Payment, FLS on Admin + Fundraising + Development, tab | Admin can create a pending transaction record |
| **2 — Engine** | `PendingTransactionService` + tests (new gift, pledge payment exact / short / over / multi-installment, duplicate guard, per-row failure isolation, delete-on-commit, donor suggestion) | Anonymous Apex in savepoint→rollback converts rows correctly in JCRC-Dev |
| **3 — Screen** | `pendingTransactions` LWC + controller + tab | User works a stack end-to-end in the browser |
| **4 — Intake without QBO** | "Add transaction" form (CSV not in v1) | Rows can be entered for UAT |
| **5 — QuickBooks sync** (D1) | QBO OAuth via External/Named Credential (same pattern as Constant Contact) + scheduled pull → upsert on `External_Id__c` | Yesterday's ACH/wire appear automatically |

---

## 6. Risks
- **Unknown QBO data shape** — biggest unknown; isolated to Phase 5 by design.
- **Installment splitting** (D2) edits NPSP payment schedules; must not fight NPSP's own schedule logic —
  verify with rollups and the Posted flow in-org.
- **Automation fan-out on commit** (allocations, giving levels, acknowledgments, payment sync) — batch
  commits must stay inside CPU/DML limits; test at the D10 volume.
- **Duplicates** if a converted transaction is re-synced — mitigated by the Payment stamp (D4).
- **Seed data** shows unpaid balances on 344 non-pledge gifts (D3) — would clutter "open pledges" if we
  choose option (b).

## 7. Sources
- Org verification queries listed in §3 (JCRC-Dev, 2026-09-16).
- Jira JSI-121, JSI-81, JSI-88, JSI-16, JSI-39 (pulled 2026-09-16).
- Repo precedent: `WebDonation*` classes, `PaymentMethodService`, `GiftAllocationService`,
  `Opportunity_FullyPaidPledgeToPosted` flow, JSI-80 plan §2.4, JSI-123 board console (LWC tab pattern).

## 8. Build log

### Phase 1 — Model ✅ deployed + verified in JCRC-Dev (2026-09-16)
**Deployed** (32 components, 0 errors, confirmed via Tooling API `CustomObject`/`CustomField`):
- `Pending_Transaction__c` — autonumber `PT-{00000}`, OWD **Public Read/Write** (it's a shared work queue;
  rows are created by the sync/integration user), reports + search on, 26 fields, `All` list view,
  **Pending Transaction Layout** (Information · Donor · Pledge Payment · New Gift · Notes · Source · Raw
  Data), object tab (Bank icon).
- `Source_Transaction_Id__c` (Text 255, **Unique**, case-insensitive, External ID) on **Opportunity** and
  **Payment** — the D4 stamp + duplicate guard. Named generically (not "QuickBooks…") because gala Pay Now
  rows will stamp Stripe ids into it too.
- **Profile access** (additive minimal-profile deploy, 3 components): Admin = full object + edit on all
  fields + tab DefaultOn; **JCRC - Fundraising / Development** = Read/Create/Edit, edit on user fields,
  **read-only** on the system-maintained fields (Status, Error Message, Match Status, Source, External
  ID/Type, Raw Data) and on both stamp fields, tab DefaultOff (their entry point is the Phase 3 screen),
  layout assigned. Repo profiles updated **insert-only** (491 added lines, nothing reordered);
  Marketing/Volunteering repo files record the automatic Modify-All-Data object grant.

**Deviations from §4.2 (build-time):**
- `Installment__c` **dropped** — D2 applies to the oldest unpaid installment automatically, so there's no
  user-picked installment.
- `Amount__c` / `Transaction_Date__c` are **not required at field level** — the screen saves drafts, and
  required fields can't carry FLS; "Ready" status enforces them instead.
- Holding `Payment_Method__c` uses the **Opportunity** values (default `ACH/Wire`), so a new gift copies it
  straight across; payments go through the existing translation.
- Gala-specific fields (level, tribute, guests, fee cover) **not added** — left to the separate sponsor
  intake work (§4.5).

**Verified** (anonymous Apex, savepoint → rollback, 0 rows left): insert with every lookup (Contact,
Account, Pledge, GAU) ✓ · defaults Status = Needs Review, Apply As = New Gift, Method = ACH/Wire ✓ ·
duplicate `External_Id__c` blocked case-insensitively (`DUPLICATE_VALUE`) ✓ · duplicate
`Source_Transaction_Id__c` blocked on Payment ✓ and on Opportunity ✓ · object/field permissions confirmed
via `ObjectPermissions` / `FieldPermissions` ✓.

### Phase 2 — Engine ✅ deployed + verified in JCRC-Dev (2026-09-16)
**Deployed:** `PendingTransactionService` (+ test), `PendingTransactionTrigger` (before insert/update),
`PaymentMethodService.toPaymentValue` made public (reused, not copied). **45/45 tests pass**
(`PendingTransactionServiceTest` 25 + `PaymentMethodServiceTest` + `WebDonationProcessorTest` as
regression). Coverage: service **92.2%**, trigger 100%.

**What the engine does**
- **Status on every save** (trigger): Ready or Needs Review, with plain-English reasons from `problems()` —
  amount, date, donor, *confirm the suggested donor*, pledge chosen / is a Pledge or Grant / not closed /
  has an outstanding balance / amount fits, gift record type active and not In-Kind, source id not already
  committed. A user edit clears a previous commit Error.
- **Donor suggestion** on arrival: payer email (all four NPSP email fields) → exact Account name → the
  org's Contact duplicate rules (fuzzy first + last). One hit = *Suggested* (not Ready until confirmed via
  `confirmDonors`), several = *Multiple Matches* (left blank), none = *No Match*. A donor set by a person =
  *Confirmed*. Account is filled from the Contact only when blank (organization gifts keep their org).
  Note: Accounts have **no active duplicate rule**, so account matching is exact-name only.
- **`getOpenPledges(contact, account)`** and **`previewPledgePayment(pledge, amount)`** for the screen.
- **`planPledgePayment`** — the D2/D11 rules as pure logic (no DML).
- **`commitTransactions(ids)`** — max **20** per call; per-row savepoint; new gift = Opportunity (stage
  Posted, NPSP naming, typed Gift Name restored, Source Transaction ID stamped) + reference/deposit onto
  NPSP's auto-created payment + 100% fund allocation; pledge payment = installment changes + the paid
  installment stamped; then the holding row is deleted and emptied from the Recycle Bin. Failures roll
  back alone, set Status = Error + message, and are logged with a stack trace.

**Verified NPSP behavior (probe, rolled back):** NPSP renames a new gift on insert; auto-creates one paid
payment dated the close date with `ACH/Wire` → `ACH`; creates Donor + Household Member contact roles; a
100% GAU allocation **replaces** the default General Fund allocation. `npe01__Amount_Outstanding__c` =
Amount − paid (− written off), so editing the unpaid schedule does not move it.

**Live check against real data (rolled back, nothing left behind):** $10,000 wire against the Ilana
Newman $50,000 pledge (11 unpaid × ~$4,166.67) → installment due 10/8/2026 paid at $10,000 (ACH, WIRE-555,
stamped), the 8/8/2027 installment removed, 7/8/2027 reduced to $2,499.99; schedule still totals $50,000,
outstanding $48,000 → $38,000. A $2,500 gift row to Israel Fund in the same commit → gift created.
Two rows: 22 SOQL, 1.7 s CPU, 15 DML.

**Security changes found during the build (profile, JCRC - Fundraising, Pending Transactions only)**
- **Delete** granted — commit deletes the holding row and Apex enforces the object permission (it also
  lets staff discard a row that isn't a donation).
- **View All + Modify All** granted — deleting a row someone else owns (the QuickBooks sync user, a
  colleague) is refused otherwise, even from `without sharing` code. JCRC - Development already has this
  through Modify All Data.
- Commit writes run in an inner **`without sharing` Writer**: Opportunity sharing is Read org-wide, so a
  Fundraising user could not otherwise update installments on a pledge someone else owns. Reads stay
  `with sharing`. Covered by a `runAs` JCRC - Fundraising test on an admin-owned pledge.

**Build-time notes**
- `emptyRecycleBin` succeeds, but Salesforce purges in the background: an `ALL ROWS` query still returns the
  row (IsDeleted = true) well after the call — not asserted in tests.
- Gotchas hit: `when` is reserved (again); `FOR UPDATE` can't be combined with `ORDER BY` (lock, then read
  in order); updating a queried payment that still carries its master-detail parent fails — write through
  fresh records holding only changed fields.

