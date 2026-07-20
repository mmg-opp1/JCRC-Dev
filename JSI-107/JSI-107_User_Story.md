# JSI-107 — Sync Constant Contact lists with NPSP

> **Source:** [JSI-107 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-107)
> Retrieved from Jira on 2026-07-19 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-107 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-3 — Email Marketing |
| **Sprint** | Implementation Sprint 2 (2026-07-10 → 2026-08-10, *future*) |
| **Labels** | Must-Have, US-045 |
| **Feature Owner** | Communications |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-07-09 |

## User Story

> As a Communications staff member, I want contact lists in Constant Contact
> synchronized with Salesforce NPSP, so that I'm always emailing from current data.

## Definition of Done

*(Annotated with this-story scope. Direction noted: **SF→CC** = Salesforce out to Constant Contact; **CC→SF** = Constant Contact back into Salesforce.)*

- **Constant Contact integration with Salesforce configured and tested.** — _In scope (foundational)._
- **Salesforce Reports/Campaigns can be pushed as audiences to Constant Contact.** — _In scope. **SF→CC** direction; this is the one direction the vendor's standard integration supports._
- **Email engagement (sends, opens, clicks, bounces, unsubscribes) flows back to NPSP Contact records.** — _In scope. **CC→SF** direction — **NOT supported by the standard one-way integration** (see Outstanding Questions / research)._
- **Email opt-out in Constant Contact updates a corresponding field in NPSP within 24 hours.** — _In scope. **CC→SF**; the primary bidirectional requirement Jason called out in dictation._
- **Hard bounces flagged on Contact records for cleanup.** — _In scope. **CC→SF**._
- **Sync errors logged and surfaced to System Administrator.** — _In scope. Error-logging/monitoring layer._

## Notes & Context

**Feature Owner:** Communications

**MMG Notes (from Jira comment, Jason Ott 2026-06-18):**
- Open Question: Anything that we should **not** be touching in email marketing?
- What is the business process for handling **multiple email addresses for one contact**?

**Dictation intent (JSI-107_StoryDictationNotes.MD):**
- This is the **first of the Constant Contact integration stories.** Jason wants deep analysis of **standard Salesforce integration vs. custom Constant Contact API integration** before building.
- Core need right now is **syncing lists back and forth — bidirectional.** Opt-outs and any subscription-center changes made on the Constant Contact side must sync back into Salesforce.
- Want **subscription settings visible on the Salesforce side.**
- Want **deliverability statistics visible on the Salesforce side** (received/delivered, opened, etc.).

## Outstanding Questions / Design Decisions

*(Full analysis in the Implementation Plan; seeded here.)*

1. **Standard vs. custom API** — The vendor's **standard Salesforce integration is one-way (SF→CC)** and explicitly does **not** send unsubscribes or activity back to Salesforce (vendor doc line 9). The bidirectional/engagement/opt-out DoD items therefore cannot be met by the standard integration alone. Decision needed: (a) custom API integration, (b) standard one-way + a separate reverse-sync mechanism, or (c) adopt Constant Contact's *Lead Gen & CRM* product (bidirectional, but a different/heavier product). **Recommendation pending research.**
2. **Client — "anything we should NOT touch in email marketing?"** (scope guardrails).
3. **Client — multiple email addresses per Contact**: which email is authoritative for sync, and how are opt-out/bounce states reconciled across them?
4. **Which NPSP fields** hold subscription status, opt-out, bounce, and engagement data (reuse native `HasOptedOutOfEmail`/`npe01__*`/`npo02__*` vs. new custom fields) — to be settled in the plan.
5. **Sync scope / grain**: which lists/segments, initial direction of authority per field, and sync cadence (opt-out DoD requires ≤24h).

## Related Reference Material

- [`ConstantContactDocumentation.MD`](./ConstantContactDocumentation.MD) — vendor help docs Jason pasted: the standard Salesforce sync (one-way) **and** the separate *Lead Gen & CRM* Salesforce sync (bidirectional — a different product).
- [`JSI-107_StoryDictationNotes.MD`](./JSI-107_StoryDictationNotes.MD) — Jason's dictation and 6-step process for this story.
- Constant Contact API guide: https://developer.constantcontact.com/api_guide/index.html (to be researched; may be JS-gated).
