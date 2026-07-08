# JSI-87 — Timely, consistent gift acknowledgment letters

> **Source:** [JSI-87 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-87)
> Retrieved from Jira on 2026-07-08 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.
> The Jira story is already populated (description + DoD), so this is a **one-way snapshot** (not pushed back).

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-87 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-15 → 2026-07-10, *active*) |
| **Labels** | Must-Have, US-020 |
| **Feature Owner** | Gift Officer |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-07-08 |

## User Story

> As a **Gift Officer**, I want acknowledgment letters generated **timely and consistently** after a
> gift is recorded, so that donors are **thanked promptly**.

## Definition of Done — with this-story scope annotated

> Verbatim from Jira `customfield_10029`, each item annotated with its scope after org verification
> (2026-07-08) and the dictation. **Legend:** ✅ native/already-done · 🟢 in scope (build the framework) ·
> 🟡 in scope but placeholder-only (real content client-pending) · 🔴 client-pending / deferred.

1. **Acknowledgment status field on every Opportunity (Not Acknowledged / Acknowledged / Do Not Acknowledge).**
   ✅ **Native NPSP** — `npsp__Acknowledgment_Status__c` (picklist) already exists on Opportunity with
   values **To Be Acknowledged / Acknowledged / Do Not Acknowledge** (+ *Email Acknowledgment Now* /
   *Email Acknowledgment Not Sent* for NPSP's native email engine). Scope: **use the native field**;
   ensure it's surfaced on the gift record pages. ("To Be Acknowledged" = the DoD's "Not Acknowledged.")
2. **Mail-merge or templated letter generation — individual and batch.**
   🟢 **Core build (framework).** No native mail-merge; build Jason's proven pattern (screen flow renders
   a text-template letter → embedded on a Visualforce page with a **Print** button → placed on the gift
   record page). Individual first; **batch generation is a design fork** (see Outstanding Questions).
3. **Multiple template options for major gifts, recurring gifts, in-kind gifts, and tribute gifts.**
   🟡 **Placeholder templates only** (per dictation). Build a few demo/test templates keyed to gift
   type/level; **actual letter content + the full scenario list are client-pending** (MMG note).
4. **Acknowledgment date stamped on Opportunity when sent.**
   ✅ **Native field exists** — `npsp__Acknowledgment_Date__c` (Date). Scope: **auto-stamp it** (and set
   status = Acknowledged) when the user prints/sends, per the dictation.
5. **Daily report shows gifts pending acknowledgment.**
   🟢 **In scope** — report on Opportunities where status = To Be Acknowledged (work queue).
6. **48-hour acknowledgment SLA defined and trackable in reports.**
   🟡 **In scope (mechanism), definition client-pending** — build an aging formula field (live `TODAY()`
   vs. gift/close date) + report bucket; the exact SLA policy (business days? from gift date or entry
   date?) needs client confirmation.
7. **DM» thank-you letter text customization based on fund and campaign.**
   🔴 **Client-pending / deferred** — requires the actual template content + the per-fund/campaign text
   rules. Framework will be extensible to support it; not buildable until content is provided.
8. **DM» thank-you letter timing customization based on fund and campaign.**
   🔴 **Client-pending / deferred** — the routing/timing rules (which gifts get which template, and when)
   live in the master routing flow, but the rule values are client-pending.

## Notes & Context

**Feature Owner:** Gift Officer.

**JCRC Notes (from the Jira comment):**
- Deep-customization nuances — e.g. **board members vs. regular donors**.
- **Document as many of the variations** as possible.
- **Allow review before letters go out.**
- Differentiate **CITI vs. individual vs. Mastercard** (gift source / payment type).
- Differentiate **long-time donor vs. new donor**.
- **Don't lose personalization while reducing time.**

**MMG Note:** Need to **define the different templates and acknowledgement scenarios** (client-pending).

**Jason's dictation (`JSI-87_StoryDictationNotes.MD`) — build intent:**
- **Build the framework now** as plug-and-play so it's ready when the client provides templates/rules.
- Use **standard NPSP** where possible: **email templates** for lower-level gifts ($1–100) that should
  get an email acknowledgment, and **printable letter templates** for print/hard-sign/mail.
- Proven pattern (see `JSI-87/Examples/`): **screen flow renders the template** (text templates + images/
  formatting) → **embedded on a Visualforce page** that has a **Print** button → **VF page placed on the
  Lightning record page**.
- Build **placeholder templates** for a few gift types/levels (e.g. <$100, $100–500, …) for demo/test.
- A **master routing flow** holds the configurable if/then rules → send email **or** present the print
  screen.
- On print, let the user **set Acknowledgment Status = Acknowledged and auto-stamp the Acknowledgment Date.**
- Much of the template content + rules is **pending with the client**; several DoD items are generic
  (LLM-generated) and "not directly buildable" yet.

## Outstanding Questions / Design Decisions

- **Native NPSP email-acknowledgment engine vs. custom flow?** NPSP ships a native Email Acknowledgment
  feature (the *Email Acknowledgment Now* / *Not Sent* status values + a batch). Do we lean on it for the
  email path, or route everything through the custom master flow? *(Research + fork — see plan.)*
- **Batch letter generation (DoD #2):** individual print is straightforward; what's the batch mechanism
  (list-view button → merged multi-letter VF page? scheduled email batch?)?
- **Template taxonomy:** which template dimensions drive selection — gift **type** (major/recurring/in-kind/
  tribute), **level** ($ bands), **donor type** (board/long-time/new), **fund/campaign**, **payment source**
  (CITI/Mastercard/individual)? The client must define the scenario matrix.
- **Email vs. print decisioning:** what determines email path vs. printed letter (gift level? donor
  preference? channel)?
- **SLA definition (DoD #6):** 48 hours from gift date or entry date? business days? 
- **"Review before going out":** what's the review step — a status gate, an approval, or just the print/send
  being manual?
- **Personalization source:** how much is merge-field driven (name, amount, fund) vs. hand-edited per letter?

## Related Reference Material

- [`JSI-87_StoryDictationNotes.MD`](./JSI-87_StoryDictationNotes.MD) — Jason's build intent + the 6-step process.
- [`Examples/`](./Examples/) — Jason's proven VF-page-print pattern from prior work: `Screen_*` screen flows
  that render "Attachment A" statement/letter templates, embedded in Visualforce `.page` components with a
  Print button (`AttachmentA*`, `Printable_Invoice_for_Accounting`).
- Native NPSP fields verified in org: `npsp__Acknowledgment_Status__c`, `npsp__Acknowledgment_Date__c`.
