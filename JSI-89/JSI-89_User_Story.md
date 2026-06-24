# JSI-89 — Track tribute and memorial gifts with notifications

> **Source:** [JSI-89 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-89)
> Retrieved from Jira on 2026-06-24 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-89 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | Should-Have, US-022 |
| **Feature Owner** | Development Operations |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-18 |

## User Story

> As a member of the Development team, I want tribute and memorial gifts tracked
> with notification preferences, so that the family or honoree is informed
> appropriately.

## Definition of Done

- Tribute fields capture: **tribute type** (in honor of / in memory of), **honoree name**, and **notification recipient**.
- Notification address can differ from the donor address.
- Notification status tracked (**pending / sent**).
- Tribute notification letters generated as a **batch process**.
- Tribute notification letters are **customized** based on the targeted **fund or campaign** of the donation.
- Reports available for **gifts by honoree**.
- Honorees retained as **related contacts** for future stewardship.

## Notes & Context

**Feature Owner:** Development Operations

**JCRC Notes**
- Will we need **Hebrew fonts** in our thank-you / notification letters?
- Do we want **customized** tribute letters?
- Is there a **tribute notification review process** (approval before letters go out)?

**MMG Notes**
- "Are tributes actually **contacts** or just **text fields**?"

## Outstanding Questions

> These map to the analysis in [`JSI-89_Implementation_Plan.md`](./JSI-89_Implementation_Plan.md).

- 🟢 **Tributes = contacts *and* text (answered by NPSP):** NPSP provides **both** a Contact
  lookup (`Honoree_Contact__c`, `Notification_Recipient_Contact__c`) **and** free-text fields
  (`Honoree_Name__c`, `Notification_Recipient_Name__c`, `…_Information__c`). This directly
  answers the MMG note and enables the online-donation flow (raw text in first, lookup
  resolved after). See Plan §3 / §5.
- 🚩 **CLIENT CONFIRMATION — Letter generation is out of NPSP scope:** NPSP **tracks** tribute
  notification status/date but does **not generate letters**. "Batch-generated, fund/campaign-
  customized letters with Hebrew-font support" requires a document-merge tool (e.g. Conga
  Composer, Salesforce flow + Visualforce/Doc template, or an external mail house). The
  tracking fields satisfy the *tracking* portion of the DoD; the *letter production* portion
  needs a tooling decision. See Plan §6.
- 🚩 **CLIENT CONFIRMATION — Online honoree/notification intake:** Confirm the online donation
  platform (Classy / Givebutter / etc.) and how it maps honoree + notification-recipient
  names into Salesforce so the text→lookup matching automation can be scoped. See Plan §5.
- 🟡 **Page placement (config build):** The tribute/notification fields are only surfaced on
  the **Pledge** record page today (which already has the **full** set). The five donation-side
  record types share a generic page with **no** tribute section. The plan creates dedicated
  record pages for Donation / Major Gift / Matching Gift (with Tribute & Notification) and
  In-Kind / Securities (without). See Plan §8.
- ❓ **Notification review process:** Does a gift officer review/approve tribute notifications
  before they are sent (a status step / queue), or is "Sent" set manually after mailing? See
  Plan §4.
- ❓ **Single vs. multiple tributes per gift:** This org uses NPSP's **single-tribute inline**
  model (no `npsp__Tribute__c` object). Confirm a gift never needs to honor more than one
  person; otherwise NPSP's Multiple-Tributes feature must be enabled. See Plan §2.

## Related Reference Material

- [`JSI-89_Implementation_Plan.md`](./JSI-89_Implementation_Plan.md) — NPSP-vs-story gap
  analysis and implementation plan.
- [`JSI-89_Story_Dictation_Cleaned.MD`](./JSI-89_Story_Dictation_Cleaned.MD) — Jason's dictation framing the work.
