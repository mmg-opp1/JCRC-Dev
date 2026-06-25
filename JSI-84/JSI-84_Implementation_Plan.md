# JSI-84 — Implementation Game Plan: Stock & In-Kind Gifts with Valuation

> **Status:** ✅ BUILT & DEPLOYED to JCRC-Dev (securities fields + FLS, Securities page section, 2
> reports) — verified 2026-06-25. **One remaining (Jason, NPSP UI):** the in-kind record-type rollup
> exclusion on the HC + SC filter groups (§5.2). Build Log in §13.
> **Author:** Jason Ott · **Date:** 2026-06-25 (rev. 2 — built)
> **Related:** `JSI-84_User_Story.md`, `JSI-84_StoryDictationNotes.MD`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-84 (Epic JSI-8 — Fundraising; US-017, Should-Have)
> **Org:** JCRC-Dev sandbox · NPSP 3.237 · API v67.0 · **Customizable Rollups ENABLED**

---

## 1. Scope

**Already satisfied by earlier stories (verified — no work here):**
- **Record types** `Securities_Gift` + `In_Kind_Gift` (JSI-82) → DoD #1.
- **In-kind capture fields** — native NPSP `In-Kind Description`, `In-Kind Type`,
  `Fair Market Value`, `In-Kind Donor Declared Value` — already on the In-Kind page (JSI-89) → DoD #3.
- **Tax-deductible** — JSI-86 Tax Information section (`Non_Deductible_Amount__c` +
  `Deductible_Amount__c`) on both pages → DoD #4.

**IN scope (this story):**
1. **Securities valuation fields** (net-new on Opportunity): # shares, ticker, date received, valuation
   method; surfaced in the existing "Securities Gift Details" section. (DoD #2)
2. **Exclude In-Kind gifts from Contact/Account rollups** (NPSP best practice) + the in-kind
   `Amount`-blank convention. (Dictation requirement)
3. **A few simple, industry-standard reports** for securities and in-kind gifts. (DoD #5)
4. **FLS** for the new fields.

**OUT of scope:**
- **Acknowledgment templates** (DoD #6 → separate story).
- **"Cash stock same day"** (DoD #7 → business policy / statement of fact; drives only that securities
  `Amount` = the day-of liquidated value).
- New record types / new in-kind fields (already exist).

**Recognition policy:** **stock = cash once liquidated** → `Amount` = liquidated value, **rolls up
normally**. **In-kind = non-cash** → value in `Fair Market Value`, `Amount` blank, **excluded from
donor rollups**.

---

## 2. Decisions to confirm before build

| # | Decision | Recommendation |
|---|----------|----------------|
| A | **In-kind rollup exclusion mechanism** | **Exclude `In_Kind_Gift` RT from the Hard-Credit (`NPSP_ClosedWon_Opps_HC`) + Soft-Credit (`NPSP_ClosedWon_Opps_SC`) filter groups** via NPSP Customizable Rollups. **Who:** Jason in the NPSP UI (he owns NPSP Settings; 2-min task, exact steps in §5.2) — *or* Claude deploys `npsp__Filter_Rule__mdt`. **+ in-kind `Amount` left blank** (value in FMV). |
| B | **Securities fields** | `Number_of_Shares__c` (Number 16,4 — fractional), `Stock_Ticker_Symbol__c` (Text 10), `Date_Stock_Received__c` (Date, **dedicated** — receipt date can differ from close date), `Stock_Valuation_Method__c` (restricted picklist). |
| C | **Valuation method values** | *Average of High/Low (Publicly Traded)* (IRS default), *Closing Price*, *Qualified Appraisal*, *Donor-Declared*, *Other*. |
| D | **Reports** | **2 core:** "Securities Gifts (This FY)" and "In-Kind Gifts (by Type)". Optional +2 "by donor" variants. |
| E | **FLS** | **Profiles** (Admin + 4 JCRC) via additive minimal-profile deploy — consistent with JSI-86. (Alt: permission set.) |

---

## 3. Verified org context (JCRC-Dev, 2026-06-25 — `sf` CLI)

| Fact | Verified via | Implication |
|------|--------------|-------------|
| In-kind fields native + already on page: `npsp__In_Kind_Description__c` (textarea), `npsp__In_Kind_Type__c` (Goods/Services), `npsp__Fair_Market_Value__c`, `npsp__In_Kind_Donor_Declared_Value__c` | `describe` + flexipage grep | **No in-kind build** — DoD #3 done. |
| **No native stock fields** (shares/ticker/valuation) | `describe Opportunity` | Securities fields **net-new**. |
| `Securities_Gift` page already has an empty-ish **"Securities Gift Details"** section + **Tax Information** (JSI-86) | flexipage grep | Add the 4 stock fields to that section. |
| **Customizable Rollups ENABLED**; HC/SC filter groups filter only `IsWon=true` + `Amount≠null`; **no RT exclusions** anywhere | `npsp__Customizable_Rollup_Settings__c`, `npsp__Filter_Group__mdt`, `npsp__Filter_Rule__mdt` | In-kind **currently would roll up** if Amount set → must add RT exclusion. |
| Filter groups present: `NPSP_ClosedWon_Opps_HC` (hard credit), `NPSP_ClosedWon_Opps_SC` (soft credit), `..._No_RT_Exclusions`, Open, Allocations, Memberships, Payments | `npsp__Filter_Group__mdt` | Exclude In-Kind from **HC + SC**. |

---

## 4. Securities fields (Opportunity) — **[CLI]**
| API name | Label | Type | Notes |
|---|---|---|---|
| `Number_of_Shares__c` | Number of Shares | Number(16,4) | Fractional shares allowed. |
| `Stock_Ticker_Symbol__c` | Stock/Ticker Symbol | Text(10) | e.g., AAPL. |
| `Date_Stock_Received__c` | Date Stock Received | Date | Date shares received (may precede the recorded gift/close date). |
| `Stock_Valuation_Method__c` | Valuation Method | Picklist (restricted) | Values per decision C. |

- `Amount` = **liquidated value** (existing field; no new field). Tax section (JSI-86) already present;
  a stock gift is normally fully deductible (Non-Deductible = 0 → Deductible = Amount).

## 5. In-kind rollup exclusion

### 5.1 `Amount`-blank convention
In-kind value lives in **`npsp__Fair_Market_Value__c`**; **`Amount` left blank** so it can't count as
cash (the HC/SC groups also require `Amount ≠ null`, so blank Amount is a second layer of protection).
In-kind is already excluded from NPSP auto-payment creation (JSI-82).

### 5.2 Exclude the In-Kind record type from rollups (NPSP best practice)
Add a **record-type exclusion** to the **Hard-Credit** and **Soft-Credit** filter groups so in-kind
never rolls up even if an Amount is entered.

**UI steps (Jason — recommended):** Setup → NPSP Settings → **Donations → Customizable Rollups** →
**Filter Groups** → open **"Opps: Won (HC)"** → **New Filter Rule** → Object **Opportunity**, Field
**Record Type**, Operator **Does Not Equal**, Value **In-Kind Gift** → Save. **Repeat for "Opps: Won
(SC)"**. (Optional: also the Allocations group if GAU rollups shouldn't include in-kind.)
*Alternative:* Claude deploys two `npsp__Filter_Rule__mdt` records (RecordTypeId Not-Equals In-Kind) —
pending confirmation of the exact constant format NPSP expects.

> Source: [Trailhead — Customize Rollups to Exclude an Opportunity Record Type](https://trailhead.salesforce.com/content/learn/projects/create-an-opportunity-record-type-for-npsp/customize-rollups-to-exclude-an-opportunity-record-type).

## 6. Page work — **[CLI]**
- **Securities page:** add the 4 fields to the existing **"Securities Gift Details"** field section
  (mirror the JSI-86/89 field-section structure: column Facets + field instances).
- **In-kind page:** **no change** (fields already present).

## 7. Reports — **[CLI]**
Standard **Opportunity** report type (exposes the custom + `npsp__` fields). Record-type filter per the
known gotcha: column `RECORDTYPE`, value `Opportunity.Securities_Gift` / `Opportunity.In_Kind_Gift`.
Folder **"Securities & In-Kind Gift Reports"**.
- **Securities Gifts (This FY)** — Summary; columns Account/Contact, Close Date, Amount (liquidated),
  # Shares, Ticker, Date Received, Valuation Method, Tax-Deductible Amount; sum Amount; `INTERVAL_CURFY`.
- **In-Kind Gifts by Type** — Summary grouped by **In-Kind Type**; columns Account/Contact, Close Date,
  In-Kind Description, Fair Market Value; sum FMV. *(Uses FMV, since in-kind `Amount` is blank.)*
- *(Optional)* "…by Donor" variants of each.

## 8. Security / FLS — **[CLI]**
Deploy FLS for the 4 stock fields to **Admin + the 4 JCRC profiles** via the **additive minimal-profile**
technique (full profiles aren't source-deployable here — JSI-86 lesson). The native `npsp__In_Kind_*`
fields already carry FLS.

## 9. Phased build plan
1. **Fields [CLI]:** 4 securities fields (+ restricted picklist) + FLS (additive profiles).
2. **Page [CLI]:** add the 4 fields to the Securities "Securities Gift Details" section; deploy.
3. **Rollup exclusion:** Jason configures the HC+SC filter-group exclusion (or Claude deploys CMDT);
   confirm in-kind `Amount`-blank convention.
4. **Reports [CLI]:** folder + Securities Gifts + In-Kind Gifts (by Type).
5. **Verify [CLI]:** anon Apex (savepoint) — securities Opp with shares/ticker/method computes &
   rolls up; in-kind Opp (Amount blank, FMV set) does **not** roll up to Contact/Account after the
   exclusion; reports return rows. Commit.

## 10. Net-new / changed metadata
| Item | Type |
|------|------|
| `Number_of_Shares__c`, `Stock_Ticker_Symbol__c`, `Date_Stock_Received__c`, `Stock_Valuation_Method__c` | Opportunity custom fields |
| Securities "Securities Gift Details" section update | FlexiPage |
| 2 (–4) reports + folder | Reports |
| FLS (Admin + 4 JCRC profiles) | Profiles (additive) |
| In-Kind RT exclusion on HC+SC filter groups | NPSP Customizable Rollups (UI by Jason or CMDT) |

## 11. Risks
- **R1 — Rollup exclusion correctness:** wrong/missing exclusion lets in-kind inflate donor totals.
  **Mitigate:** exclude on **both** HC + SC; verify a test in-kind gift rolls to **0**; Amount-blank as backup.
- **R2 — Managed CMDT deploy uncertainty:** filter-rule constant format for record types isn't certain.
  **Mitigate:** prefer the documented **UI** config (Jason), or test the CMDT in sandbox first.
- **R3 — Securities Amount semantics:** Amount must be the **liquidated** value; if a gift isn't yet
  liquidated, Amount may lag. **Mitigate:** document; out of scope to automate (policy = same-day).
- **R4 — FLS omission:** **Mitigate:** deploy FLS with the fields (JSI-122/86 lesson).

## 12. Sources
- Live org: `describe Opportunity`, `npsp__Customizable_Rollup_Settings__c`, `npsp__Filter_Group__mdt`,
  `npsp__Filter_Rule__mdt`, flexipage inspection (2026-06-25).
- [IRS Pub 561 — Determining the Value of Donated Property](https://www.irs.gov/publications/p561);
  [Trailhead — Exclude an Opportunity Record Type from Rollups](https://trailhead.salesforce.com/content/learn/projects/create-an-opportunity-record-type-for-npsp/customize-rollups-to-exclude-an-opportunity-record-type);
  NPSP In-Kind Gifts help. **Roadblock:** "Configure In-Kind Gifts" help page is JS-gated (Jason to pull if exact wording needed).

## 13. Build Log

### 2026-06-25 — Securities fields, page, reports deployed & verified ✅
- **Securities fields (Opportunity):** `Number_of_Shares__c` (Number 16,4), `Stock_Ticker_Symbol__c`
  (Text 10), `Date_Stock_Received__c` (Date), `Stock_Valuation_Method__c` (restricted picklist:
  Average of High and Low (Publicly Traded) / Closing Price / Qualified Appraisal / Donor-Declared /
  Other — **slash-free values** to avoid the picklist-encoding gotcha). **FLS** on Admin + 4 JCRC
  profiles via additive minimal-profile deploy; repo profiles synced (contiguous insert).
- **Securities page:** added the 4 fields to the existing "Securities Gift Details" section (expanded
  to two columns: col0 FMV + Shares + Ticker; col1 Date Received + Valuation Method). In-Kind page
  unchanged (already complete).
- **Reports** (folder "Securities & In-Kind Gift Reports"): **Securities Gifts (This Fiscal Year)**
  (summary by Account, sum Amount, INTERVAL_CURFY) + **In-Kind Gifts by Type** (summary by In-Kind
  Type, sum FMV). *(Gotcha: standard-report-type custom-field columns need the **`Opportunity.Field__c`**
  token, not the bare API name; and folder+reports must deploy **together** — transactional rollback.)*
- **Verified** (anon Apex, savepoint→rollback): securities Opp Amount=10,500 with Shares/Ticker/Method,
  Deductible=10,500 (fully deductible); in-kind Opp **Amount=null** with FMV=2,500 / Type=Goods;
  restricted picklist rejects a bad value.

### ⏳ Remaining — Jason (NPSP Customizable Rollups UI)
- **Exclude `In_Kind_Gift` from the Hard-Credit + Soft-Credit filter groups** (§5.2 steps). Then
  verify: create an in-kind gift, recalc rollups, confirm the donor's **Total Gifts is unchanged**.
  *(The in-kind `Amount`-blank convention already prevents cash rollup; this exclusion is the
  belt-and-suspenders / handles any in-kind with an Amount.)*
- **Deferred (other story):** IRS-compliant acknowledgment templates (DoD #6).
