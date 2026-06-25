# JSI-84 — Record stock and in-kind gifts with valuation

> **Source:** [JSI-84 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-84)
> Retrieved from Jira on 2026-06-25 by Jason Ott. Documentation snapshot — Jira remains the system of
> record. (Story already had description + DoD in Jira; nothing pushed back.)

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-84 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | Should-Have, US-017 |
| **Feature Owner** | Gift Officer |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-25 |

## User Story

> As a Gift Officer, I want **stock and in-kind gifts recorded with appropriate valuation fields**, so
> that we can **recognize non-cash gifts properly**.

## Definition of Done (from Jira) — with this-story scope annotated

| # | DoD item | Status / scope |
|---|----------|----------------|
| 1 | Opportunity record types for Stock Gift and In-Kind Gift | ✅ **DONE** — `Securities_Gift` + `In_Kind_Gift` exist (JSI-82). "Stock" = the **Securities Gift** type (renamed). |
| 2 | Stock gifts capture: # shares, ticker, date received, valuation method | ✅ **IN — this story** (net-new fields; no native NPSP stock fields). |
| 3 | In-kind gifts capture: description of goods/services + fair market value | ✅ **DONE** — native NPSP fields (`npsp__In_Kind_Description__c`, `npsp__In_Kind_Type__c`, `npsp__Fair_Market_Value__c`, `npsp__In_Kind_Donor_Declared_Value__c`) already on the In-Kind page (JSI-89). |
| 4 | Tax-deductible amount calculated and stored for both types | ✅ **DONE** — JSI-86's **Tax Information** section (`Non_Deductible_Amount__c` + `Deductible_Amount__c`) is already on both pages. |
| 5 | Reports include stock and in-kind gifts with appropriate flags | ✅ **IN — this story** — a few simple, industry-standard reports (see note on "total contributed revenue" below). |
| 6 | Acknowledgment templates use IRS-compliant language | 🔜 **DEFERRED** — separate acknowledgments story (per dictation). |
| 7 | Business policy: cash the stock the day of donation | ℹ️ **Statement of fact — no build** (per dictation; confirmed by Simcha's comment). Drives: **securities `Amount` = the day-of liquidated value**. |

**Extra requirement from the dictation (beyond the written DoD):** **In-kind gifts must NOT roll up to
the Contact/Account** — they're non-cash, recorded only for participation/engagement. → **IN, this
story** (NPSP rollup exclusion).

## Notes & Context

**Feature Owner:** Gift Officer.

**JCRC note (Jira comment):** *Simcha — accounting for stock donations: cash out immediately or retain?
Thank-you letter reflects day-of value.* → JCRC **liquidates securities on receipt** (no brokerage/
holding), so the Opportunity **`Amount` = the value at which the security is liquidated** (day-of), and
the thank-you reflects that value.

**"Total contributed revenue" (DoD #5) vs. "don't roll up" (dictation):** reconciled as — in-kind gifts
appear in **gift/Opportunity reports** (for visibility) but are **excluded from the Contact/Account
donor rollups** (cash-giving totals). Stock gifts are cash once liquidated, so they roll up normally.

**NPSP / org research (2026-06-25, verified):**
- **In-kind capture is 100% NPSP-native** — the four `npsp__In_Kind_*` / `Fair_Market_Value` fields
  exist and are already surfaced on the In-Kind page. No new in-kind fields needed.
- **No native stock fields** — shares / ticker / valuation method are net-new.
- **Customizable Rollups is ENABLED**; the Hard-Credit & Soft-Credit filter groups currently filter
  only on `IsWon=true` + `Amount ≠ null` — **no record-type exclusions exist yet**. NPSP's documented
  best practice is to **exclude the In-Kind record type from the rollups** (Trailhead: *Customize
  Rollups to Exclude an Opportunity Record Type*).
- **IRS valuation (Pub 561):** publicly-traded stock FMV = **mean of the high/low quoted price on the
  gift date**; closely-held needs a qualified appraisal. Standard captured fields: # shares, ticker,
  gift/receipt date, value.

## Outstanding Questions / Design Decisions (for review before build)

1. 🚩 **In-kind rollup exclusion mechanism + Amount convention.** Recommend: **exclude the
   `In_Kind_Gift` record type from the Hard-Credit & Soft-Credit filter groups** (NPSP best practice),
   **and** leave the in-kind **`Amount` blank** (value lives in `Fair Market Value`), so in-kind never
   inflates cash totals. Who configures the filter-group exclusion — **Jason in the NPSP Customizable
   Rollups UI** (recommended; he owns NPSP Settings) or Claude via `npsp__Filter_Rule__mdt` deploy?
2. **Securities fields (4):** `Number_of_Shares__c` (Number, fractional ok), `Stock_Ticker_Symbol__c`
   (Text), `Date_Stock_Received__c` (Date — dedicated vs. reuse `CloseDate`), `Stock_Valuation_Method__c`
   (picklist). **Valuation method values?** Proposed: *Average of High/Low (Publicly Traded)* (IRS
   default), *Closing Price*, *Qualified Appraisal*, *Donor-Declared*, *Other*.
3. **Reports — how many/what?** Proposed (simple, per dictation): **Securities Gifts** (this FY; +
   optional by donor) and **In-Kind Gifts** (this FY, grouped by In-Kind Type). ~2 each.
4. **FLS** for the new stock fields — **profiles** (Admin + 4 JCRC, matching JSI-86) or a permission set?

## Related Reference Material

- [`JSI-84_StoryDictationNotes.MD`](./JSI-84_StoryDictationNotes.MD) — Jason's working notes + 6-step process.
- IRS Pub 561 (valuing donated property); NPSP In-Kind Gifts + Customizable Rollups docs.
