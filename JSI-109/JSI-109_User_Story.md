# JSI-109 — Email engagement metrics at contact level

> **Source:** [JSI-109 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-109)
> Retrieved from Jira on 2026-07-20 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-109 |
| **Type** | Story |
| **Status** | To Do |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-3 — Email Marketing (Constant Contact) |
| **Sprint** | Implementation Sprint 2 (2026-07-10 → 2026-08-10, *future*) |
| **Feature Owner** | Communications |
| **Reporter** | Jason Ott |
| **Created** | 2026-06-18 |

## User Story

> As a Communications staff member, I want email engagement metrics visible at the
> contact level in Salesforce, so that I can see whether a donor is reading our
> communications.

## Definition of Done (annotated with this-story scope)

- **Recent email activity (last 5 sends, opens, clicks) visible on the NPSP Contact record.**
  → related list of per-contact email-activity records on the Contact page.
- **Engagement metrics rolled up: total opens last 90 days, total clicks last 90 days.**
  → rollups from the new activity records to the Contact (supersedes / feeds the JSI-107 summary counters).
- **Reports available for highly engaged and disengaged constituents.**
  → reports over the new engagement objects.
- **Engagement data refreshes at minimum daily.**
  → reuse the existing JSI-107 scheduled CC poller (currently hourly) — comfortably meets "daily".
- **Privacy considerations documented (e.g., what's stored vs. inferred).**
  → what raw engagement we store vs. what we infer; retention.

## Notes & Context (from dictation + Jira comments)

**Jira comments**
- *Feature Owner: Communications* (Jason, 2026-06-18)
- *"We are going to bring over individual emails as well as contact interaction data."* (Jason, 2026-07-20)

**Dictation — the chosen shape (Jason):**
- This story **changes what JSI-107 did**: rather than maintain many hard-to-report summary fields on Contact, bring in **all the email detail from Constant Contact** on the **existing regularly-scheduled poll**.
- Use a **custom object** model, not more Contact summary fields:
  - **`Email__c`** — one record per individual email the client sends in Constant Contact. Lookup to **Campaign** populated with the CC campaign; possibly a **second lookup to Campaign** to associate the email with its **email list** (the `CC List` record-type Campaign from JSI-108, e.g. a newsletter ↔ its newsletter list).
  - **`Email_Activity__c`** — child of `Email__c`, the **link to the Contact**. One **summary** record per contact per email (NOT one row per click): status, opened?, clicked?, number of opens, open date, click date, and any other per-recipient data CC exposes. Keep each contact's activity on that email **up to date** on each poll — do not append a new record per event.
- Deep-dive the **Constant Contact API documentation** for the reporting/activity endpoints before building.

## Outstanding Questions / Gaps (to settle in Step 5)

See `JSI-109_Implementation_Plan.md` §Open Decisions. Headlines:
1. **The two Campaign lookups** — exactly what does the *primary* "campaign out of constant contact" lookup point to vs. the *secondary* "email list" lookup? (CC's model: an email *campaign* is sent to *lists*.)
2. **Relationship types** — is `Email_Activity__c` a **junction** (master-detail to both `Email__c` and `Contact`, enabling native rollups both ways), or child-of-`Email__c` + lookup-to-`Contact`?
3. **What happens to the JSI-107 Contact summary fields** (`Email_Last_Open__c`, `Email_Opens_Last_90_Days__c`, …) — retire, keep, or repoint as rollups of the new activity records?
4. **CampaignMember vs. custom** — JSI-108 already uses CampaignMember for CC-List subscription; native Campaign/CampaignMember is Salesforce's built-in email-analytics model. Dictation chose custom objects; confirm we're not double-modeling.
5. **Which CC reporting granularity** — per-campaign tracking rollups vs. per-contact activity summary (drives the poller design + API call volume).

## Related Reference Material

- [`../JSI-107/ConstantContactDocumentation.MD`](../JSI-107/ConstantContactDocumentation.MD) — CC integration reference (native = one-way; v3 API).
- [`../JSI-107/JSI-107_Implementation_Plan.md`](../JSI-107/JSI-107_Implementation_Plan.md) — the hybrid CC integration this story extends (poller, `Integration_Log__c`, Contact CC fields).
- [`../JSI-108/JSI-108_Implementation_Plan.md`](../JSI-108/JSI-108_Implementation_Plan.md) — Campaign `CC List` record type + CampaignMember subscription model.
