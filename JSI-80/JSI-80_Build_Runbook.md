# JSI-80 — Build Runbook (remaining UI-gated steps)

> **Author:** Jason Ott · **Date:** 2026-06-19 · Org: **JCRC-Dev (sandbox)**
> Everything that can be deployed from source is already done (see
> `JSI-80_Implementation_Plan.md` §10). The two items below are **NPSP managed
> features** whose records (Advanced Mapping CMT, Form Template JSON) are gated to
> the NPSP UI — direct metadata deploys are rejected by the package
> (Advanced Mapping CMT deploy returns `UNKNOWN_EXCEPTION`). After completing these,
> retrieve them into the repo to keep git in sync.

## Prerequisite status ✅
- Advanced Mapping = **Data Import Field Mapping** (enabled) — verified.
- Gift Entry = **Enabled** — verified.

---

## Step 1 — Map the Approach field (Advanced Mapping)

Makes the new `Approach__c` flow from a gift into the Opportunity on processing.

1. **NPSP Settings** tab → **System Tools** → **Advanced Mapping for Data Import & Gift Entry**.
2. Click **Configure Advanced Mapping**.
3. Open the **Opportunity** object group → **View Field Mappings**.
4. **Create New Field Mapping**:
   - **Source Field** (on NPSP Data Import): **Approach** (`Approach__c`)
   - **Target Field** (on Opportunity): **Approach** (`Approach__c`)
   - Required: **No**
5. Save.

*(Reference for the record this creates — set `Migrated_Custom_Field_Mapping_Set`,
object mapping `Opportunity_ce8a6ed7b`, source `Approach__c`, target `Approach__c`.)*

---

## Step 2 — Build the 3 Gift Entry Form Templates (Template Builder)

App Launcher → **Gift Entry** → **Templates** subtab → **Create Template** (repeat ×3).

### Common to all three templates
**Gift fields:**
- Donor: **Donor Type** + **Account1**/**Contact1** (existing donor lookup)
- **Donation Amount**
- **Donation Date**
- **Payment Method** (default differs per template — below)
- **GAU Allocation 1: General Accounting Unit** + **GAU Allocation 1: Amount**  (= the "Fund")
- **Primary Campaign Source** (Campaign)
- **Approach**  *(available after Step 1)*

**Batch Settings (on each template):**
- **Require Expected Totals Match** = ON
- **Contact Matching Rule** = `Firstname, Lastname, Email`
- **Donation Matching Behavior** = **Do Not Match**  *(contacts only; every gift creates its own Opportunity)*

### Per-template specifics
| Template name | Payment Method default | Extra field |
|---------------|------------------------|-------------|
| **Checks** | Check | **Check/Reference Number** |
| **ACH/Wire** | ACH/Wire | — |
| **Stock/Securities/Crypto** | Stock/Securities/Crypto | (add valuation/shares fields later if needed) |

---

## Step 3 — Batch reconciliation fields (page layout)

The custom batch fields **Bank Deposit Reference** (`Bank_Deposit_Reference__c`) and
**Deposit Date** (`Deposit_Date__c`) are deployed on **NPSP Data Import Batch**. Add them
to the NPSP Data Import Batch page layout so they're captured per batch for finance
reconciliation. (Gift Entry's batch header also natively offers Expected Count / Expected
Total Amount.)

---

## Step 4 — Users
Assign the **JCRC – Fundraising** profile (already deployed; includes the Gift Entry tab +
FLS on the new fields) to the fundraising users.

---

## Step 5 — Capture back into git
After Steps 1–2, retrieve the new managed-feature records so the repo matches the org:
```powershell
# Form templates are records; export via data, or retrieve the Advanced Mapping CMT:
sf project retrieve start -o JCRC-Dev -m "CustomMetadata"
sf data export tree -o JCRC-Dev -q "SELECT Name, npsp__Format_Version__c, npsp__Template_JSON__c FROM npsp__Form_Template__c" -d JSI-80/exported-templates
```

## Verify (end-to-end smoke test)
1. Open the **Development** app → **Gift Entry** tab.
2. **New Batch** → pick **Checks** → set Expected Count/Total → enter a test check gift →
   **Dry Run** (donor matches or creates) → **Process Batch**.
3. Confirm the Opportunity/Payment created, **Approach** populated, batch number stamped.
