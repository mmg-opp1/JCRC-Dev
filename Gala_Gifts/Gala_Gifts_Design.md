# Gala Event Gifts — Design Proposal (working draft)

> Drafted 2026-07-31 by Jason Ott. Spec-for-discussion — no build yet. Slot into a `JSI-XX/` folder once
> a Jira story exists. **Primary user: a non-technical, change-averse gala manager → the data-entry flow
> must be simple, guided, and forgiving. Nail the UX, not just the schema.**

## What the client told us
- Individuals sign up for the gala and **pay**, and receive various things depending on what they buy.
- Every ticket/purchase has a **LEVEL** — individual ticket, sponsorship, table, etc. **Exact levels TBD from client.**
- Capture this **cleanly, related to the Opportunity** (the gift/payment).
- Donors may buy a **whole table**; guests may be known at purchase or **added over time**; a table may be
  **partially filled**; **major sponsors get multiple tables**.
- Track guest **dietary restrictions**, etc.
- **Future:** a third-party **event-management module** will run ticket purchasing and integrate — but we
  spec the Salesforce side first so it's integration-ready.

## Best practice (research summary)
- **Campaign (Type = Event)** = the gala event; **Opportunity** = the purchase/payment; **attendees** =
  guest/seat records. Standard NPSP pattern.
- Gala tools (GalaBid, Event.Gives, Swoogo, RSVPify, Blackthorn Events) support **seat assignment at
  purchase or later**, **dietary/meal capture**, **partial table fill**, and **sync to SF** as Contacts +
  Opportunities + custom table/attendee fields. → Keep our model close to what a module maps to.

## Build status (2026-07-31) — BUILT + DEPLOYED + PUSHED to JCRC-Dev
- **Phase A (schema)** `47a255a` — `Gala_Level__c` / `Gala_Table__c` / `Gala_Guest__c` + `Opportunity.Gala_Level__c`; FLS on 5 profiles; verified.
- **Phase C (UI)** `b58ecfc` — record pages for all 3 objects; **"Gala" tab** on the Event Registration Opportunity page (Tables + Guests related lists) + the Gala Level field in Opp Info.
- **Phase B (automation)** `ff756c9` — `GalaAutomationService` + `GalaGuestTrigger` + `OpportunityGalaTrigger`: pick a level → FMV split stamped + tables auto-created (idempotent); Seats Filled live; guest inherits the Opportunity; **Add as Contact** finds-or-creates the Contact + back-fills the lookup.
- **Add-as-Contact fuzzy upgrade** `d1d6649` — resolver rewritten to `Datacloud.FindDuplicates` (JSI-89 fuzzy first+last rule): 0 matches → create+link · 1 → link · 2+ → leave blank + set new `Contact_Match_Needs_Review__c`. Tests **3/3**.
- **Record pages finalized** `2109320` + `a72d7ea` — Jason customized the 3 pages in App Builder (App Builder cloned them under the `...Record_Page1` API name; display labels unchanged) and **activated them as Org Default**. Pulled into the repo; the orphaned scaffold pages deleted from org + repo. Each gala object now has exactly one record page.

**⏳ Remaining (weekend carryover):**
- **CLIENT (blocking seed):** exact **levels / prices / deductible (FMV) splits** → seed `Gala_Level__c` records; confirm the **dietary-restriction** and **meal-choice** picklist values (currently placeholders incl. Kosher).
- **Reports (buildable now):** dietary/caterer list, table fill-status roster, revenue by level.
- **Prod caveat (no action in sandbox):** the record-page **Org Default activation is UI-only** — Salesforce doesn't store org-default assignments in metadata, so at prod cutover Jason re-activates the 3 pages in App Builder (one click each). To make it deploy automatically, assign as **App Default** inside an app instead and re-pull.
- **Future:** 3rd-party event module integration (ticket purchasing) — schema is intentionally Opportunity-anchored, not Campaign-locked, to accommodate it.

## Decisions (Jason, 2026-07-31)
1. **`Gala_Level__c` is a CONFIG object** — seats, tables, price, deductible, etc. are set in config (admin-maintained), not hard-coded. **(Fork 1 locked.)**
2. **Guest can be a Contact OR a name, plus an `Add as Contact` checkbox + a flow** that checks whether the contact already exists, creates it if not, and **populates the Contact lookup** when created. **(Fork 3 locked + extended.)** Reuse the JSI-89 resolver pattern (`Datacloud.FindDuplicates` + matching rule + name-parser CMDT) so we don't reinvent dedupe/fuzzy-match.
3. **Do NOT hard-wire everything to the Campaign.** The **Opportunity is the hub.** A gala **Campaign** will be *associated with* the Opportunity, but they may also use the **3rd-party Events object** — so keep the event association a **loose lookup on the Opportunity** (and leave room for a future Event-object lookup); tables/guests anchor on the **Opportunity/Table**, not the Campaign.

## Proposed model (Opportunity-anchored + reuse + 3 small custom objects)

| Piece | Object | Role |
|---|---|---|
| **The purchase/payment — the HUB** | **Opportunity** (record type **Event Registration**, exists) | the gift; + `Gala_Level__c` lookup; Amount + Deductible/Non-Deductible (JSI-86). **Event association is a loose lookup** — a **Campaign** lookup (the gala) now, room for a **3rd-party Event** lookup later. Not a structural parent. |
| The sellable levels | **`Gala_Level__c`** (config, admin-maintained) | Name, Price, **Seats Included**, **Tables Included**, **Deductible Amount** (or FMV/non-deductible per seat), Benefits/Description, Active. **Client provides the exact list.** |
| A physical table | **`Gala_Table__c`** | **Purchasing Opportunity** (host, primary link), Table Name/Number, **Capacity**, **Seats Filled** (roll-up), **Seats Remaining** (formula), Host/Captain contact. (Optional Campaign/Event tag inherited from the Opp.) Multi-table sponsor → multiple records. |
| A guest / seat | **`Gala_Guest__c`** | Table (lookup) + Opportunity; **Contact (optional lookup) + First/Last free-text name**; **`Add as Contact` checkbox** → flow finds-or-creates the Contact and back-fills the lookup; **Dietary Restrictions** (multi-select), Meal Choice, RSVP/Attended, Notes |

**Why this shape:** the Opportunity is the anchor (flexible on how the event itself is represented — Campaign
today, possibly a 3rd-party Event object later). The Level carries the rules (seats/tables/price/deductible),
so the manager just *picks a level* and the rest follows. Tables are real records (multi-table sponsors,
capacity, host). Guests are a clean per-seat record filled in over time, don't require a Contact, and can be
**promoted to a Contact on demand** via the checkbox + resolver.

## The clean data-entry flow (what the gala manager does)
1. **Record a purchase** — new Opportunity (Event Registration), pick the **Level**, and associate the gala
   (Campaign lookup now; a 3rd-party Event later). Amount + deductible/non-deductible auto-calc from the level
   (reuses JSI-86).
2. **Tables auto-create** from the level (e.g., "Table" → 1 table of 10; "Diamond Sponsor" → 2 tables) —
   no manual table setup.
3. **Add guests over time** from a simple related list on the table/purchase — pick an existing Contact
   *or just type a name* — plus dietary restrictions. **Seats Remaining** shows partially-filled tables at
   a glance.
4. **Promote a guest to a Contact on demand** — tick **`Add as Contact`**; a flow finds a matching Contact
   (reusing the JSI-89 `Datacloud.FindDuplicates` + matching-rule + name-parser resolver), creates one if
   none exists, and **back-fills the guest's Contact lookup**. (Guided, minimal clicks — the change-averse-user requirement.)

## Reporting the manager/caterer needs
- **Dietary list for the caterer** (guests grouped by restriction).
- **Table roster + fill status** (who's at each table, seats remaining).
- **Revenue by level**; sponsor **benefits** fulfillment; **check-in / attended** list.

## Design forks
1. ✅ **Level = config object `Gala_Level__c`** — LOCKED (Jason).
2. **Physical table = `Gala_Table__c` object** (recommended — multi-table sponsors, capacity, host) vs a "Table Number" field on guests. — *still to confirm.*
3. ✅ **Guest identity = Contact lookup + free-text name + `Add as Contact` resolver** — LOCKED (Jason).
4. **Auto-create tables from the level** via automation (recommended — keeps the flow clean). — *still to confirm.*
5. ✅ **Event association is a loose lookup on the Opportunity (Campaign now, 3rd-party Event later)** — LOCKED (Jason).

## Questions to gather from the client (at the meeting)
- 🔴 **The exact LEVELS** — for each: **price**, **# seats/tickets included**, **# tables included**,
  **deductible vs non-deductible split** (FMV of the dinner/benefits), and **benefits** (ad, signage, VIP…).
- **Standard table capacity** (10? varies by table?).
- **Dietary restriction options** — the picklist values (Vegetarian, Vegan, Gluten-Free, **Kosher**,
  nut/other allergies, …). (Kosher likely central for JCRC.)
- Do they want a **Contact record for every guest**, or are names fine for non-donors?
- **Meal choices** — is it a plated dinner with an entrée selection to capture?
- **Sponsor benefits** — track fulfillment (program ad, table signage, tickets) in scope now?
- **Check-in / seating chart** — needed now, or handled by the future module?
- Which **event-management module** are they leaning toward (Blackthorn Events, Classy, GalaBid, Swoogo…)?
  — shapes the integration mapping.
- Confirm they track the **deductible split** on gala gifts (gift − FMV) — JSI-86 fields already exist.

## Future third-party module (integration-ready by design)
- The module maps cleanly: online **purchase → Opportunity + Level**, **registrant → Gala Guest**,
  **table purchase → Gala Table**. Salesforce stays the system of record; the module writes into these.
- **Cross-story tie-in:** the JSI-123 board work has an open TBD — *do gala-ticket deductible portions
  count toward a board member's giving commitment?* Same deductible split feeds that answer.

## Not yet decided / out (until client confirms)
- Exact levels + prices + deductible amounts (client). · Seating-chart visualization (likely the module). ·
  Online payment/registration (the module). · Auction/paddle-raise items (separate scope if any).
