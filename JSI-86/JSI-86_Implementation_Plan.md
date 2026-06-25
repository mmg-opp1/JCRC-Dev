# JSI-86 — Implementation Game Plan: Tax-Deductible vs. Non-Deductible Gift Portions

> **Status:** ✅ BUILT & DEPLOYED to JCRC-Dev (fields, formula, validation, Event Registration record
> type, FLS, **Tax Information section on all 8 gift record pages**) — verified 2026-06-25. **Only
> remaining:** Jason assigns the new Event Registration page to its record type in App Builder; plus
> the deferred/dependent items (§1 OUT). Build Log in §12.
> **Author:** Jason Ott · **Date:** 2026-06-25 (rev. 2 — core built)
> **Related:** `JSI-86_User_Story.md`, `JSI-86_StoryDictationNotes.MD`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-86 (Epic JSI-8 — Fundraising; US-019, Must-Have)
> **Org:** JCRC-Dev sandbox · NPSP 3.237 · API v67.0

---

## 1. Scope

**IN scope (this story):**
- Two Opportunity fields to express the split: **`Non_Deductible_Amount__c`** (input — value of
  goods/services the donor received) and **`Deductible_Amount__c`** (formula = `Amount − Non-Deductible`).
- A validation rule so the non-deductible portion can't exceed the gift.
- A new **`Event_Registration`** Opportunity record type (event tickets / gala registrations), where
  the split matters most, on the existing **Donation stewardship** stages.
- Surface the two fields on the gift record pages/layouts (every gift record type — dictation) and a
  dedicated Event Registration Lightning page.
- **FLS deployed with the fields** (lesson from JSI-122 — fields without FLS are invisible).

**OUT of scope (deferred / owned elsewhere — per dictation):**
- **Acknowledgment letter templates** pulling the deductible amount (DoD #4 → separate acks story).
- **Year-end giving statements** + the Contact **deductible rollups** that feed them (DoD #5 →
  separate statements story; decided to **defer** rollups).
- **Event-platform integration** that auto-carries the split into NPSP (DoD #3) — depends on the
  platform, which isn't selected; **manual FMV entry** now (decision 2).
- **Process documentation / Finance review** (DoD #6 → client-owned).

**Revenue policy (resolved by MAF):** the full gift remains JCRC revenue — **`Amount` is unchanged**
and NPSP rollups keep crediting the whole gift. The split is **informational** for receipts only.

---

## 2. Decisions — resolved 2026-06-25

| # | Decision (locked) |
|---|---|
| 1 | **New dedicated fields** — `Non_Deductible_Amount__c` (input) + `Deductible_Amount__c` (formula). **Do not** overload NPSP's `npsp__Fair_Market_Value__c` (kept for its in-kind meaning). |
| 2 | **Manual FMV entry now**; defer the "automatic" event split + event-platform integration (DoD #2 automation / #3) until a platform is chosen. |
| 3 | **Create the `Event_Registration` record type** now, on the existing Donation stewardship stages. |
| 4 | **Defer** Contact deductible-total rollups to the giving-statements story. |
| MAF | Full gift = revenue; `Amount` unchanged; split is informational. |

---

## 3. Verified org context (JCRC-Dev, 2026-06-25 — `sf` CLI, not assumed)

| Fact | Verified via | Implication |
|------|--------------|-------------|
| **No deductible field exists**; only **`npsp__Fair_Market_Value__c`** (Currency) is present | `sf sobject describe Opportunity` (114 fields) | Deductible/non-deductible are **net-new**; FMV stays for in-kind. |
| **7 Opportunity record types** (Donation=`NPSP_Default`, Grant, In-Kind, Major, Matching, Pledge, Securities) — **no Event type** | `SELECT … FROM RecordType` | Add **Event_Registration** (8th). |
| **Business processes:** `Donation_Process` (Prospecting/Cultivating/Posted/Declined), `Pledge_Process` | Org review (this session) | Event Registration → **Donation_Process**. |
| Record pages exist for all gift types (JSI-82 Pledge/Grant; JSI-89 Donation/Major/Matching/In-Kind/Securities) | `flexipages/` | Surface fields on these (see §5.4); coordinate with JSI-89's flexipages. |
| All automation is **Flow-based**; **profiles** `System Administrator` + `JCRC – Fundraising` carry RT visibility/FLS (JSI-82) | Org review | Follow that pattern for RT visibility; deploy field FLS (§6). |

---

## 4. Requirement → mechanism (most of this is net-new; NPSP has no deductible field)

| Requirement | Mechanism | Build? |
|---|---|---|
| Total gift (revenue) | **`Amount`** (unchanged) | ✅ exists |
| Non-deductible portion (goods/services received) | **`Non_Deductible_Amount__c`** (Currency, input) | ❌ net-new |
| Tax-deductible portion | **`Deductible_Amount__c`** = `MAX(Amount − BLANKVALUE(Non_Deductible_Amount__c,0), 0)` | ❌ net-new (formula) |
| Can't deduct more than paid | Validation: non-deductible ≤ `Amount` | ❌ net-new |
| Event tickets / gala registrations | **`Event_Registration`** record type | ❌ net-new |
| In-kind gift valuation (separate concept) | **`npsp__Fair_Market_Value__c`** | ✅ leave as-is |

---

## 5. Design

### 5.1 Fields (Opportunity) — **[CLI]**
- **`Non_Deductible_Amount__c`** — Currency(16,2), label *Non-Deductible Amount*. Help text: "Value of
  any goods or services the donor received in return (e.g., gala dinner, event benefits). Leave blank
  if the entire gift is tax-deductible." Not required; default blank.
- **`Deductible_Amount__c`** — Currency formula(2 dp), label *Tax-Deductible Amount*:
  `MAX(Amount - BLANKVALUE(Non_Deductible_Amount__c, 0), 0)`. Read-only. Help text: "Auto-calculated:
  gift Amount minus the Non-Deductible Amount."

### 5.2 Validation rule (Opportunity) — **[CLI]**
- **`Non_Deductible_Not_Over_Amount`**: error when
  `AND(NOT(ISBLANK(Non_Deductible_Amount__c)), NOT(ISBLANK(Amount)), Non_Deductible_Amount__c > Amount)`.
  Message on `Non_Deductible_Amount__c`: "The non-deductible amount can't be more than the gift Amount."

### 5.3 Record type — **[CLI]**
- **`Event_Registration`** ("Event Registration") → **`Donation_Process`** (Prospecting → Cultivating →
  Posted → Declined). Payment behavior: **like a Donation** (collected at registration; not excluded
  from auto-create). Visibility on **System Administrator + JCRC – Fundraising** profiles (JSI-82 pattern).
  Picklist value assignments mirror the Donation record type.

### 5.4 Surfacing the fields — **[CLI / UI]**
- **Event Registration Lightning record page** (net-new) — cloned from the org's donation page format
  (`recordHomeWithSubheaderTemplateDesktop` + dynamicHighlights + Donation tabs, per the JSI-89
  pattern), with a **"Tax Deductibility"** field section (Amount, Non-Deductible, Deductible).
- **Existing gift record types:** add the two fields to their detail view. **Build-time check:** if the
  JSI-89 / Pledge-Grant pages render fields via the **Record Detail** component, add the fields to the
  **page layout(s)** (low touch); if they use explicit `flexipage:fieldSection` components, the fields
  must be added to each flexipage — **coordinate with the JSI-89 thread** (it currently owns/just
  edited those pages). *(Per Jason's usual division of labor, final placement on Lightning pages may be
  done by Jason in App Builder — I'll build the metadata + the Event page and hand off placement.)*
- **JSI-80 (Gift Entry) coordination:** add `Non_Deductible_Amount__c` to the Gift Entry form
  template(s) so batch/event entry can capture it — note for the JSI-80 thread, not built here.

---

## 6. Security / FLS — **[CLI]**
- Deploy **FLS with the fields** (JSI-122 lesson — required so they're visible to admins, the Apex
  layer, and reports). Options: (a) a focused **permission set** `Gift_Deductibility` (Read/Edit on
  `Non_Deductible_Amount__c`, Read on the formula), or (b) add FLS to the **`JCRC – Fundraising`** +
  **Admin** profiles (matches JSI-82's Opportunity fields). **Recommend (a)** for cleanliness; confirm.
- `Deductible_Amount__c` is a formula → read-only inherently; grant **Read**.

---

## 7. Phased build plan
1. **Fields + validation [CLI]:** `Non_Deductible_Amount__c`, `Deductible_Amount__c` (formula),
   `Non_Deductible_Not_Over_Amount`. Deploy with FLS (§6).
2. **Record type [CLI]:** `Event_Registration` → Donation_Process; profile visibility.
3. **Pages [CLI/UI]:** build the Event Registration Lightning page; surface the two fields on existing
   gift pages/layouts (per §5.4 build-time check); hand placement to Jason where appropriate.
4. **Verify [CLI]:** anon Apex in a savepoint/rollback — set `Amount`=250, `Non_Deductible`=60 →
   `Deductible`=190; `Non_Deductible`=300 on a 250 gift → validation blocks; blank Non-Deductible →
   Deductible = Amount. Confirm Event_Registration creates on Donation stages.
5. **Docs/handoff:** Build Log; coordination notes for JSI-80 (Gift Entry field) and the deferred
   acks/statements stories; commit.

---

## 8. Net-new / changed metadata
| Item | Type |
|------|------|
| `Non_Deductible_Amount__c`, `Deductible_Amount__c` | Opportunity custom fields |
| `Non_Deductible_Not_Over_Amount` | Validation rule (Opportunity) |
| `Event_Registration` | Opportunity record type (→ Donation_Process) |
| Event Registration Lightning page; field placement on existing pages/layouts | FlexiPage / Layout |
| `Gift_Deductibility` permission set **or** profile FLS | Security |
| *(Reused, not rebuilt:* `Amount`, `npsp__Fair_Market_Value__c`, `Donation_Process` stages *)* | — |

---

## 9. Risks
- **R1 — Field semantics:** users could confuse Non-Deductible with NPSP's in-kind FMV. **Mitigate:**
  clear labels + help text; FMV stays on In-Kind pages only.
- **R2 — "Automatic" expectation (DoD #2):** stakeholders may expect auto-splitting at go-live.
  **Mitigate:** manual entry is explicit (decision 2); revisit when an event platform is chosen.
- **R3 — Page-surfacing collision with JSI-89 flexipages:** **Mitigate:** prefer page-layout placement
  or coordinate edits with the JSI-89 thread; build only the net-new Event page directly.
- **R4 — FLS omission:** **Mitigate:** deploy FLS with the fields (§6).
- **R5 — Amount blank on open opps:** `BLANKVALUE`/`MAX` guard keeps Deductible at 0, not negative.

---

## 10. Open questions / dependencies (not blocking the §7 build)
- **Event platform** for DoD #2/#3 automation/integration — which platform, and the FMV field mapping?
- **FLS mechanism** — permission set vs. profile (§6) — confirm.
- **Existing-page surfacing** — layout vs. flexipage edits; JSI-89 coordination (§5.4).
- **Gift Entry** — add the field to JSI-80 templates (coordinate).

---

## 11. Sources
- Live org verification (`sf` CLI, 2026-06-25): Opportunity describe (FMV present, no deductible
  field), record types, business processes.
- NPSP / IRS background: quid-pro-quo contributions (Pub 1771) — deductible = payment − FMV of
  benefits; NPSP pattern = deductible via formula + Contact rollups for period totals.
- **Research roadblock:** Salesforce Help "Configure In-Kind Gifts" (intended use of
  `npsp__Fair_Market_Value__c`) is **JS-gated** (CSS-error shell) — **Jason to pull** if exact wording
  is needed. ([Trailhead: Acknowledge a Donation](https://trailhead.salesforce.com/content/learn/modules/donation-management-basics-with-nonprofit-success-pack/acknowledge-a-donation))

---

## 12. Build Log

### 2026-06-25 — Core schema + record type + FLS deployed & verified ✅
- **Fields (Opportunity):** `Non_Deductible_Amount__c` (Currency 16,2, input) and
  `Deductible_Amount__c` (Currency formula `MAX(Amount - BLANKVALUE(Non_Deductible_Amount__c,0), 0)`,
  precision 16/scale 2). *(Formula currency requires **both** `precision` and `scale` — `precision`
  omitted failed "Must specify 'precision' for a CustomField of type Currency".)*
- **Validation:** `Non_Deductible_Not_Over_Amount` — blocks non-deductible > Amount.
- **Record type:** `Event_Registration` ("Event Registration") → `Donation_Process`, cloned from the
  `Major_Gift` picklist assignments. RT Id `012iI0000000HVVQA2`.
- **FLS (profiles, per Jason):** read/edit on `Non_Deductible_Amount__c`, read on
  `Deductible_Amount__c` for **Admin + all 4 JCRC profiles**; `Event_Registration` RT visibility on
  **Admin + JCRC - Fundraising** only (the profiles with an Opportunity default RT).
  - **Profile-deploy method (see [[reference-sf-metadata-gotchas]]):** full profiles are **NOT
    source-deployable** here (invalid tab settings on BroadcastTopic/DevopsActivityLog/PricebookEntry/
    QuickText/VideoCall/VideoCallParticipant). Applied FLS via an **additive minimal-profile deploy**
    (temp `<Profile>` with only the new members). Repo full-profile files were updated (entries
    inserted after the last `</fieldPermissions>` / `</recordTypeVisibilities>` — must be contiguous)
    to **document** the state; they remain non-wholesale-deployable (pre-existing baggage). Decision:
    **keep the edited full profiles** (Jason).
- **Verified in-org** (anon Apex, savepoint→rollback): Amount 250 / Non-Deductible 60 → Deductible
  **190.00**; blank Non-Deductible → Deductible = Amount (**100.00**); Non-Deductible 300 on a 250 gift
  → **blocked** by validation; `Event_Registration` creates on Donation stages.

### 2026-06-25 (cont.) — "Tax Information" section on all gift record pages ✅
- Added a **"Tax Information"** field section (`Non_Deductible_Amount__c` + `Deductible_Amount__c`,
  the latter read-only) to **all 7** Opportunity gift record pages — the 5 JSI-89 pages (Donation,
  Major, Matching, In-Kind, Securities) **and** the 2 JSI-82 pages (Pledge, Grant) — plus a **new
  `Event_Registration_Record_Page`** cloned from the Donation page. Deployed 8/8.
- **Uniform-anchor technique:** the JSI-89 pages use named facets (`Facet-detail`, `fs_oppinfo`)
  while the JSI-82 pages use **GUID facets** + `flexipage_fieldSection*` identifiers — so I anchored
  the insert on the **System Information** section (`@@@SFDCSystem_InformationSFDC@@@`, present on
  every page) and placed Tax Information just before it. Field-column Facets + a `cols` Facet +
  the `fs_tax` `flexipage:fieldSection`, all with unique `*_tax_*` identifiers.

### ⏳ Remaining
- **⏳ Jason (App Builder):** **assign `Event_Registration_Record_Page` to the Event Registration
  record type** (page→RT assignment isn't in source metadata). The other 7 pages were already
  assigned by Jason (JSI-82/89). Reorder the Tax Information section if desired (currently sits just
  above System Information).
- **Deferred / dependent (per §1 OUT):** acknowledgment templates, year-end statements + Contact
  deductible rollups, event-platform integration (DoD #3), Finance process docs; JSI-80 Gift Entry
  field add.
