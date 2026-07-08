# JSI-80 — Implementation Game Plan: Manual Batch Gift Entry (UI)

> **Status:** ✅ Built, deployed & committed (`d81dc04`, 2026-06-22); verified against JCRC-Dev. See §10 for build status. Trivial go-live leftovers only (assign profile to users; surface 2 batch fields on layout; ACH stored-value decision).
> **Author:** Jason Ott · **Date:** 2026-06-18 (rev. 2 — QBO de-scoped; tool selection verified)
> **Related:** `JSI-80_User_Story.md`, `Story_Dictation_Cleaned.md`, `SalesforceHelp_NPSPGiftEntry.txt`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-80

---

## 1. Scope

**IN scope (this story):** The **manual / UI** side — enabling and configuring **NPSP
Gift Entry** so the Development team can create gift **batches** in the app, choose a
**template** per gift type, manually enter/verify/correct gifts, enforce **expected
totals**, and process them into NPSP donations.

**OUT of scope (separate Jira story):** The **QuickBooks (QBO) automated sync** that
fetches reconciled checks by deposit date. Tracked separately. See §2.4 for why
building Gift Entry now is fully compatible with — and does not pre-empt — that future
work.

---

## 2. Tool selection (the critical decision) — **NPSP Gift Entry**

NPSP ships **three** related capabilities that all write to the **same** underlying
objects (`npsp__DataImportBatch__c` + `npsp__DataImport__c`). They are **not** the same
tool. Choosing the wrong one is the main risk this plan exists to eliminate.

| Tool | What it is | Right for | Evidence |
|------|------------|-----------|----------|
| **NPSP Gift Entry** ✅ | Modern Lightning UI: **Form Templates** (Template Builder) + Batches/Single Gift; manual direct entry with Dry Run → Process. | **Manually** entering donations in Salesforce — *"a stack of checks"* — no file prep. **← JSI-80** | "Gift Entry runs on the same engine as NPSP Data Importer, but allows you to enter the data directly into Salesforce manually instead of … a spreadsheet … import." [SF Help: Gift Entry] |
| **NPSP Data Importer** (generic) | Bulk engine: load rows into the `DataImport` object (Data Loader/file), then process the batch. Any object (Accounts/Contacts/Donations). | **Bulk** data from **external sources** / migrations / vendor systems. **← relevant to the separate QBO story, not this one.** | "If you need to import Accounts or Contacts, the NPSP Data Importer is recommended … for bulk data coming from external sources." [SF Help: NPSP Data Importer] |
| **Batch Gift Entry (BGE)** ❌ legacy | Older gift batch tool; config stored in `Active_Fields__c`/`Batch_Table_Columns__c`; **no Form Template**. | Nothing new — **superseded**. | "Gift Entry replaces the older Batch Gift Entry product." / "Gift Entry and Batch Gift Entry … are quite different features" — hide the BGE tab. [SalesforceHelp_NPSPGiftEntry.txt L396, L511] |

### 2.1 Decision
Use **NPSP Gift Entry**. It is purpose-built for the JSI-80 use case (manual entry of
reconciled mailed gifts), is the current/supported tool, and natively provides every
requirement in the de-scoped story (templates per gift type, expected-totals matching,
verify/correct, audit).

### 2.2 Proof from the actual org metadata (not assumed)
The field model in our repo distinguishes the tools concretely:

- `npsp__DataImportBatch__c.npsp__GiftBatch__c` — boolean flag: **true = a Gift Entry
  batch** (vs. a generic Data Import batch).
- `npsp__DataImportBatch__c.npsp__Form_Template__c` — lookup to the Gift Entry **Form
  Template**. Docs: *"If Form Template is blank, the batch was created with the legacy
  Batch Gift Entry tool."*
- `npsp__DataImportBatch__c.npsp__Batch_Gift_Entry_Version__c` — version marker that
  separates legacy BGE from modern Gift Entry.
- `npsp__Form_Template__c.npsp__Template_JSON__c` — the Gift Entry template definition
  (a modern-tool construct; BGE has no Form Template).

### 2.3 Currency / longevity check
- NPSP **3.237** is the latest release (Dec 2025), actively maintained; **no
  deprecation** notice. [NPSP GitHub]
- Salesforce **Nonprofit Cloud** exists as a newer *alternative* product, but it is a
  different stack and **not installed** in JCRC-Dev. This org runs **NPSP**, so **NPSP
  Gift Entry is the correct tool today.** (Flag only: any future Nonprofit Cloud
  migration would revisit gift entry — out of scope here.)

### 2.4 Why this does not conflict with the future QBO story
All three tools converge on the **same** `DataImport`/`DataImportBatch` engine. The
separate QBO integration will create `npsp__DataImport__c` rows (programmatically) and
process them through that same engine — optionally even attaching them to a Gift Entry
batch. **Building Gift Entry now lays the shared foundation (Advanced Mapping, matching
rules, target field mappings) that the QBO story will reuse.** No rework.

> Sources: [Configure Gift Entry](https://help.salesforce.com/s/articleView?id=sfdo.NPSP_Gift_Entry.htm&type=5) · [Configure NPSP Data Importer](https://help.salesforce.com/s/articleView?id=sfdo.NPSP_Data_Importer.htm&type=5) · [Batch Gift Entry FAQ (Power of Us)](https://powerofus.force.com/articles/Resource/NPSP-BGE-FAQ) · [NPSP GitHub](https://github.com/SalesforceFoundation/NPSP)

---

## 3. Verified org context (checked against JCRC-Dev)

| Fact | Evidence | Implication |
|------|----------|-------------|
| **NPSP installed** (`npsp` 3.237.0.2) + classic packages | `sf package installed list` | Gift Entry available to configure. |
| Gift Entry objects + 44 `npsp__` objects present **locally** in `force-app` with fields (e.g., `DataImportBatch` = 28 fields, `DataImport` = 175) | repo `objects/` | We can design field-level changes from the repo. |
| **Advanced Mapping is OFF** — `Data_Import_Settings.Field_Mapping_Method = "Help Text"` | SOQL | **Step 1 = enable Advanced Mapping** (required before Gift Entry). |
| **`Gift_Entry_Settings.Enable_Gift_Entry__c`** exists; **0 Form Templates** | repo + SOQL | Gift Entry not yet enabled/used; all templates net-new. |

---

## 4. Requirement → native Gift Entry mechanism

| Story requirement (manual scope) | Native mechanism | Backing field/feature |
|---|---|---|
| "Batch gift entry tab" | **Gift Entry** tab (Batches + Templates subtabs) | `Gift_Entry_Settings.Enable_Gift_Entry__c` |
| "Multiple batch types, each a template" | One **Form Template** per type | `npsp__Form_Template__c` (Paper Check / Stock / ACH-Wire) |
| "Verify & add missing data" | Batch grid + **Dry Run** | `npsp__DataImport__c.npsp__Status__c`, matching fields |
| "Verification totals / batch header match" | **Expected totals + require match** | `npsp__Expected_Count_of_Gifts__c`, `npsp__Expected_Total_Batch_Amount__c`, `npsp__RequireTotalMatch__c` |
| "Track bank deposit / key" | **Batch numbering** + custom field | `npsp__Batch_Number__c` + new `Bank_Deposit_Reference__c` / `Deposit_Date__c` |
| "Corrections post-entry (pre-process)" | Edit unprocessed gifts; re-Dry Run | batch grid |
| "Audit trail (who/when)" | CreatedBy/LastModifiedBy + batch number on Opp/Payment | standard + `npsp__Batch_Number__c` |
| Paper-check specifics | Check reference field | `npsp__DataImport__c.npsp__Payment_Check_Reference_Number__c` |

---

## 5. Phased plan (manual / UI only)

### Phase 1 — Enable the foundation (config)
1. Confirm **My Domain** deployed (prereq).
2. NPSP Settings → System Tools → **Advanced Mapping for Data Import & Gift Entry** →
   enable **Advanced Mapping** (converts existing Help Text mappings — validate nothing
   breaks first, ideally in sandbox).
3. Enable **Gift Entry**.
4. Configure **Batch Numbers for Donations** (stamps Opp/Payment Batch Number for finance traceability).

### Phase 2 — Access & navigation
5. Create permission set **"Gift Entry — JCRC"** per NPSP's documented list (object/field
   access to Form Templates, NPSP Data Import Batches, NPSP Data Imports; the documented
   Apex/VF/custom-setting access). *Note: the official list legitimately includes some
   `npsp.BGE_*` Apex classes — Gift Entry reuses that batch-entry controller under the
   hood; this is expected, not the legacy tool.*
6. Add **Gift Entry** tab to the team's Lightning app; add **New Gift** action to
   Contact/Account layouts (remove any old "New Donation" action).
7. Assign permission set to Development team users.
8. Hide the legacy **Batch Gift Entry** tab to avoid confusion.

### Phase 3 — Form Templates per gift type (the "different templates" requirement)
9. Build **Form Templates** (Template Builder): **Paper Check**, **Stock / Securities**,
   **ACH / Wire** — each with appropriate default **Payment Method** and the field set
   (donor, amount, gift date, fund/GAU, campaign, approach/source; Check Reference # on
   the Paper Check template).
10. Confirm/extend the **Payment Method** picklist to cover Check, Stock/Securities,
    ACH/EFT, Wire. *(Exact current values still to be confirmed in build — not assumed.)*
11. Confirm the **"approach / source / channel"** field (existing vs new) and map it on
    each template.

### Phase 4 — Batch verification totals & traceability
12. Standardize batch creation: **Require Expected Totals Match** on; enter Expected
    Count + Expected Total from the bank deposit.
13. Add custom fields on `npsp__DataImportBatch__c`: **`Bank_Deposit_Reference__c`**
    (text) and **`Deposit_Date__c`** (date) for finance reconciliation.

### Phase 5 — Donor/donation matching
14. Configure **NPSP Data Importer** Contact/Account + Donation matching rules to the
    agreed criteria (batch-level fields exist: `npsp__Contact_Matching_Rule__c`,
    `npsp__Donation_Matching_Rule__c`, `npsp__Donation_Matching_Behavior__c`).
15. Define the **reviewer-confirmation** workflow before processing (Jira DoD: fuzzy
    match + reviewer confirmation).

### Phase 6 — Validation, corrections, audit
16. Add import **validation rules** as needed (amount > 0, required fund/campaign) so
    they surface in **Dry Run**.
17. Confirm **audit trail** coverage (CreatedBy/Date on Data Import + Batch Number on
    downstream records); enable field history if required.

### Phase 7 — Test, train, deploy
18. Test each template; expected-totals mismatch; new vs existing donor; correction flow.
19. Short runbook for the team (create batch → enter → dry run → process).
20. Deploy config from sandbox via source; capture in this repo.

---

## 6. Net-new metadata (manual scope only)

| Item | Type | Notes |
|------|------|-------|
| Advanced Mapping + Gift Entry enabled | NPSP setting | Currently "Help Text". |
| Batch number format | NPSP setting | Traceability. |
| Gift Entry — JCRC | PermissionSet | Per NPSP documented access list. |
| Paper Check / Stock / ACH-Wire | `npsp__Form_Template__c` ×3 | "Different templates" requirement. |
| Payment Method values | Picklist values | Confirm current set first. |
| `Bank_Deposit_Reference__c`, `Deposit_Date__c` | Custom fields on `npsp__DataImportBatch__c` | Reconciliation. |
| Approach/source field | Field + picklist (TBD existing vs new) | Mapped on templates. |
| Import validation rules | Validation rules | Surface in Dry Run. |
| Gift Entry tab + New Gift action; hide BGE tab | App/Layout/PermSet | Navigation/access. |

*(No QBO connector, integration, or `DataImport` external-id fields here — those belong to the separate QBO story.)*

---

## 7. Decisions (resolved 2026-06-19)

| # | Topic | Decision | Verified note |
|---|-------|----------|---------------|
| 1 | Donor (Contact) matching | **First + Last + Email** | NPSP **Contact Matching Rule = `Firstname,Lastname,Email`** — native default (confirmed in `npsp__Contact_Matching_Rule__c` metadata). Find existing Contact or create new. |
| 1b | Donation matching | **Do NOT match donations** | Every gift creates its own Opportunity → **Donation Matching Behavior = `Do Not Match`**. (We are not de-duping donations/pledges in this story — contact matching only.) |
| 2 | Who enriches/confirms | Multiple roles; **create one profile now: clone *System Administrator* → "JCRC – Fundraising"** | ⚠️ Cloning System Administrator grants broad access (Modify All Data, etc.). Acceptable to unblock; least-privilege tightening recommended as a follow-up (§10). |
| 3 | Approach / source | **Net-new field `Approach__c`** (Opportunity + DataImport source) | ✅ **Deployed to sandbox 2026-06-19.** Values: Direct Mail, Online, Event, Major Gift, Phone, In Person, Other. |
| 4 | Payment Method | **Modify picklist:** keep **Check**; relabel **ACH → "ACH/Wire"**; add **"Stock/Securities/Crypto"** | UI lane (managed `npe01` field). **0 existing Payment records**, so the ACH relabel strands no data. Now every template has a valid default. |
| 5 | DAF / soft credits | **Separate story** (not JSI-80) | — |
| 6 | Templates in first pass | **3 templates: Checks, ACH/Wire, Stock/Securities/Crypto** | — |
| 7 | Fund model | **GAU Allocation** (standard NPSP) | Map Fund → GAU Allocation on templates. |

## 8. Environment (confirmed)

`JCRC-Dev` is a **sandbox** (`IsSandbox = true`, Enterprise Edition — *Jewish Community
Relations Council of New York*). Safe to build here directly; capture all changes in this
repo and deploy onward via source.

---

## 9. Concrete build spec (Phases 1–4)

Two execution lanes. **[CLI]** = metadata I can author and `sf project deploy` to the
sandbox. **[UI]** = NPSP-managed toggles / Template Builder / Advanced Mapping that can
only be done in the org, then retrieved back into the repo.

### A. Foundation — **[UI, NPSP Settings]** *(must be first; blocks everything else)*
1. Enable **Advanced Mapping** (NPSP Settings → System Tools → *Advanced Mapping for Data
   Import & Gift Entry*). Converts existing Help-Text mappings — verify after.
2. Enable **Gift Entry** (same page, second section).
3. (Optional) Configure **Batch Numbers for Donations** for finance traceability.

### B. Profile — **[UI clone, then retrieve]**
4. Setup → Profiles → clone **System Administrator** → **"JCRC – Fundraising"**; then I
   retrieve it into the repo.

### C. Permission set "Gift Entry – JCRC" — **[CLI]** (+ assignment [UI])
5. Object CRUD + FLS on **Form Templates**, **NPSP Data Import Batches**, **NPSP Data
   Imports** (all fields), and the documented target-object fields (Opportunity, Payment,
   Contact, Account, Address, Campaign, GAU Allocation, GAU). Apex class access to the
   documented `npsp.GE_*` / `npsp.BGE_*` / `npsp.BDI_*` classes; VF pages; custom settings.
   Tab visibility for **Gift Entry**. *(BGE_ classes are reused by Gift Entry — expected.)*

### D. Custom fields — **[CLI] ✅ DEPLOYED 2026-06-19**
| Field | Object | Type | Status |
|-------|--------|------|--------|
| `Approach__c` | **Opportunity** (target) | Picklist (restricted): Direct Mail, Online, Event, Major Gift, Phone, In Person, Other | ✅ Created |
| `Approach__c` | **`npsp__DataImport__c`** (source) | Text(255) → maps to Opportunity.Approach__c | ✅ Created |
| `Bank_Deposit_Reference__c` | **`npsp__DataImportBatch__c`** | Text(255) | ✅ Created |
| `Deposit_Date__c` | **`npsp__DataImportBatch__c`** | Date | ✅ Created |

*(Custom non-namespaced fields on managed npsp objects are additive/supported. FLS to be
granted via the Gift Entry – JCRC permission set, §C.)*

### D2. Payment Method picklist — **[UI, Object Manager]** *(managed `npe01` field)*
On `npe01__OppPayment__c` → **Payment Method**:
- Relabel **`ACH` → `ACH/Wire`** (0 existing Payment records, so no value-replace needed).
- Add **`Stock/Securities/Crypto`**.
- Keep **Check**, Cash, Credit Card, PayPal.
Then retrieve the updated field into the repo. *(Managed-field picklist edits aren't
reliably deployable from source, so this is a UI step.)*

### E. Advanced Mapping for Approach — **[UI, after A], then retrieve**
6. Advanced Mapping → **Donation (Opportunity)** object group → **Create New Field
   Mapping**: source `npsp__DataImport__c.Approach__c` → target `Opportunity.Approach__c`.
   Generates a `npsp__Data_Import_Field_Mapping__mdt` record — retrieve to repo.

### F. Form Templates ×3 — **[UI, Template Builder], then retrieve**
Each template (stored as `npsp__Form_Template__c.Template_JSON__c`) includes the common
gift fields + batch settings, with type-specific defaults:

| Template | Payment Method default | Type-specific fields |
|----------|------------------------|----------------------|
| **Checks** | `Check` | Check/Reference Number (`npsp__Payment_Check_Reference_Number__c`) |
| **ACH/Wire** | `ACH/Wire` (after §D2 relabel) | — |
| **Stock/Securities/Crypto** | `Stock/Securities/Crypto` (after §D2 add) | (consider valuation/shares fields later) |

**Common fields (all templates):** Donor (Contact1 / Account1), Donation Date, Donation
Amount, **Fund → GAU Allocation** (GAU + Amount/Percent), Primary Campaign Source
(Campaign), **Approach**.
**Batch settings:** Require Expected Totals Match = **on**; Contact Matching Rule =
`Firstname,Lastname,Email`; **Donation Matching Behavior = `Do Not Match`** (contact
matching only — every gift creates its own Opportunity).

### G. Validation & audit — **[CLI]** (Phase 6, optional this pass)
7. Validation rule(s) (e.g., Donation Amount > 0; required Fund/Campaign) authored to
   surface in **Dry Run**. Audit trail = standard CreatedBy/Date + Batch Number on Opp/Payment.

---

## 10. Build status & next step

**Done via CLI (2026-06-19) — all deployed to JCRC-Dev sandbox:**
- ✅ §D — 4 custom fields (Opportunity.Approach__c, DataImport.Approach__c,
  DataImportBatch.Bank_Deposit_Reference__c, .Deposit_Date__c).
- ✅ §D2 — Payment Method picklist: **ACH → "ACH/Wire"** (label; stored value stays `ACH`),
  added **"Stock/Securities/Crypto"**. (Managed `npe01` field edited & deployed as XML.)
- ✅ §B+§C — **JCRC – Fundraising** profile created as a **clone of System Administrator**,
  with **FLS for the 4 new fields** and **Gift Entry tab (`npsp__GE_Gift_Entry`) DefaultOn**,
  written directly into the profile XML. *(Replaces the separate permission-set plan — FLS
  is on the profile per direction.)*
- ✅ Tab — **Gift Entry tab added to the `Development` (JCRC_Development) app** navigation,
  after Opportunity. (Fulfills the dictation's "tab in the main application".)

- ✅ §A — **Advanced Mapping + Gift Entry ENABLED** (verified: Field Mapping Method =
  "Data Import Field Mapping"; Enable Gift Entry = true).
- ✅ §E — **Approach Advanced-Mapping entry created** (done in NPSP UI — CLI deploy of the
  CMT is blocked by NPSP's package guard, `UNKNOWN_EXCEPTION`).
- ✅ **FLS granted to System Administrator** profile for all 4 new fields (merge-only
  partial-profile deploy). *(Metadata-deployed fields get no FLS by default — must be
  granted explicitly on every profile that needs them.)*

**Remaining — [UI] (see `JSI-80_Build_Runbook.md`):**
- §F — build the 3 Form Templates in Template Builder (`Template_JSON` is NPSP-internal).
- Surface `Bank_Deposit_Reference__c` / `Deposit_Date__c` on the NPSP Data Import Batch layout.
- Assign the **JCRC – Fundraising** profile to users.

- ✅ **Profile de-admined (least-privilege)** — JCRC – Fundraising hardened: **Modify All
  Data, View All Data, Setup access (ViewSetup), Customize Application, Manage Users,
  Author Apex** and ~38 dependent admin permissions disabled. NPSP Data Import Batch +
  Data Import keep full CRUD (gift entry works).

**Template-edit access control (answered):** Gift Entry has no custom-permission gate; it
keys off **CRUD on `npsp__Form_Template__c`**. Set to **Read-only** on JCRC – Fundraising
→ users can select/use templates and enter gifts but **cannot create/edit/delete
templates**. (This only takes effect because Modify All Data was removed — it had been
overriding object security.) Template management stays with full System Administrators.

**Open items:** decide if "ACH/Wire" should also change the *stored value* (currently `ACH`).
