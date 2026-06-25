# JSI-86 — Distinguish tax-deductible vs. non-deductible gift portions

> **Source:** [JSI-86 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-86)
> Retrieved from Jira on 2026-06-25 by Jason Ott. This is a documentation snapshot — Jira remains
> the system of record. (Story already had a description + DoD in Jira; nothing pushed back.)

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-86 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | Must-Have, US-019 |
| **Feature Owner** | Development Operations |
| **Reporter** | Jason Ott |
| **Assignee** | Jason Ott |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-25 |

## User Story

> As a Gift Officer, I want a clear distinction between **tax-deductible** and **non-tax-deductible**
> portions of a gift, so that **acknowledgments and receipts are accurate**.

## Definition of Done (from Jira) — with this-story scope annotated

The dictation (`JSI-86_StoryDictationNotes.MD`) narrows what **this** story builds; the rest is owned
by other stories or the client.

1. **Opportunity record includes tax-deductible amount and non-tax-deductible amount fields.**
   → ✅ **IN — this story.**
2. **Event tickets and gala registrations split goods-and-services value from charitable portion
   automatically.** → ⚠️ **IN — this story**, but "automatically" depends on where the
   goods/services (FMV) value comes from (see Outstanding Questions). A new **Event/Ticket record
   type** is in scope.
3. **Event integration carries the tax-deductible split through to NPSP.** → ⚠️ **DEPENDS on the
   event platform/integration** — likely a separate/dependent effort; can't be built until the
   integration + field mapping is known.
4. **Acknowledgment letter templates pull the correct tax-deductible amount.** → 🔜 **DEFERRED** —
   covered by a separate acknowledgments story (per dictation).
5. **Year-end giving statements show tax-deductible amounts only.** → 🔜 **DEFERRED** — covered by a
   separate giving-statements story (per dictation).
6. **Process documented and reviewed with Finance.** → 👤 **CLIENT-OWNED** (per dictation).

**So this story's build = #1, the field model + a new Event/Ticket record type (#2), surfaced on the
gift record pages.** #3 is scoped only as far as the field model that an integration would populate.

## Notes & Context

**Feature Owner:** Development Operations.

**JCRC note (from the Jira comment):** *Marcy — are we thanking them for their full gift, or only the
part that is tax-deductible?*

**MAF answer:** *The fact that part of a gift isn't tax-deductible for a donor is irrelevant. The
entire gift is still revenue for JCRC.*

➡️ **Resolved implication:** the Opportunity **`Amount` stays the full gift** (revenue is unchanged —
NPSP donor/campaign rollups keep crediting the full amount). The deductible / non-deductible split is
**informational** (for receipts), not a change to recognized revenue. *What* a thank-you/receipt shows
(full vs. deductible) is decided in the deferred acknowledgments story; this story just makes both
numbers available and correct.

**NPSP research (2026-06-25):**
- Opportunity already has a native **`npsp__Fair_Market_Value__c`** (Currency), but NPSP documents it
  for **in-kind gift valuation** (the FMV of a donated *item*) — semantically different from "value of
  the goods/services the donor receives back" (the quid-pro-quo case this story is about). See the
  field-reuse fork below. *(Official "Configure In-Kind Gifts" help page is JS-gated — Jason to pull
  if we need the exact intended use.)*
- Standard NPSP pattern: **deductible = `Amount − benefit value`** via a formula field; deductible
  **totals over time** are done with **Contact customizable rollups** — but those rollups serve the
  **deferred** year-end-statements story, so they're noted, not built here.

## Outstanding Questions / Design Decisions (for review before build)

1. 🚩 **Field model — reuse NPSP FMV vs. new field.** Recommend a **dedicated
   `Non_Deductible_Amount__c`** (value of goods/services received) + **`Deductible_Amount__c`**
   formula (`Amount − Non-Deductible`, floored at 0), keeping NPSP's `npsp__Fair_Market_Value__c` for
   its in-kind meaning. Alternative: reuse `npsp__Fair_Market_Value__c` as the non-deductible field
   (fewer fields, but overloads an in-kind concept onto cash gifts). **Decision needed.**
2. **Event/Ticket record type:** name (e.g., *Event Registration* / *Ticket Purchase*), one type for
   all event/gala/ticket revenue? Which stage process (the existing **Donation_Process** stewardship
   pipeline, or a dedicated one)? Auto-create payment behavior (like Donations) or excluded?
3. 🚩 **Source of the "automatic" event split (DoD #2/#3).** Where does the goods/services (FMV) value
   come from per registration — **Salesforce Products/Price Book** (ticket = product carrying an FMV,
   rolled up), or an **external event platform** (Classy/Eventbrite/Cvent/Fonteva/etc.) that sends it?
   This determines whether "automatic" is a rollup/flow we build now or an integration mapping that
   waits on the platform. **Which platform (if any) does JCRC use for events?**
4. **Default behavior:** when no non-deductible value is entered, deductible = full `Amount` (gift is
   fully deductible). Confirm.
5. **Validation:** enforce non-deductible ≤ `Amount` (can't exceed the gift)? Recommend yes.
6. **Scope of fields:** show deductible / non-deductible on **all gift record-type** Lightning pages
   (dictation says "every gift record type"), or only where a benefit can occur? Recommend all, but
   only the Event/Ticket and standard Donation pages emphasize it.
7. **Other quid-pro-quo cases** beyond events (membership perks, dinners, auctions) — same field model
   covers them; confirm none need special handling now.
8. **Contact deductible rollups:** build now or defer with the statements story? Recommend **defer**
   (the field model here is the prerequisite; rollups belong to JSI's statements story).

## Related Reference Material

- [`JSI-86_StoryDictationNotes.MD`](./JSI-86_StoryDictationNotes.MD) — Jason's working notes + the
  6-step process for this story.
- NPSP / IRS background (quid pro quo contributions, Pub 1771): deductible = payment − FMV of benefits.
