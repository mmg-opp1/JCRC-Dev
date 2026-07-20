# JSI-108 — Constituent communication preference center

> **Source:** [JSI-108 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-108)
> Retrieved from Jira on 2026-07-20 by Jason Ott. Documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-108 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-3 — Email Marketing |
| **Sprint** | Implementation Sprint 2 (2026-07-10 → 2026-08-10) |
| **Labels** | Must-Have, US-047 |
| **Feature Owner** | Communications |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-07-09 |

## User Story

> As a constituent, I want clear preferences about what kinds of communications I
> receive, so that I'm not spammed with messages I don't care about.

## Definition of Done

*(Annotated with likely owner: **CC** = native Constant Contact feature/config · **Sync** = depends on the JSI-107 integration · **Process** = training/policy, no build.)*

- **Email preference center with multiple subscription topics** (advocacy, events, fundraising appeals, newsletter). — _**CC**: Constant Contact's subscription/update-profile center, with each "topic" = a CC list. To verify._
- **Preferences stored on the NPSP Contact record and synced to Constant Contact.** — _**Sync**: the one genuinely Salesforce-touching item. Global opt-out already round-trips via JSI-107; **topic-level** preference storage + list-membership sync may be an extension. To scope._
- **Unsubscribe options support both global and topic-specific opt-out.** — _**CC**: subscription center supports per-list and account-wide unsubscribe. To verify._
- **Confirmation page after preference update.** — _**CC**: native confirmation on profile update. To verify._
- **Privacy policy linked from preference center.** — _**CC**: footer/branding/link config on the center. To verify._
- **Staff trained never to override an unsubscribe.** — _**Process**: policy/training, no build. (Reinforced by JSI-107 which respects opt-outs.)_

## Notes & Context

**Feature Owner:** Communications.

**Dictation intent (JSI-108_StoryDictationNotes.MD):** Jason believes there is likely **nothing to build in Salesforce** — the preference center lives in **Constant Contact** (this project's email provider). Task: deep-dive the DoD, review the JSI-107 integration docs/plan to see how CC is wired up, **verify against Constant Contact's actual features** that everything here is handled (in CC and/or already covered by JSI-107's sync), and **mark the story done** if so.

**MMG Notes (Jira comment, Jason Ott):** *"Subscription preferences need to go CC → SF primarily. Should we allow the opposite?"* → preference/list-membership sync is **primarily CC → SF**; open question whether SF → CC should also be allowed.

## Outstanding Questions / Design Decisions

1. **Does DoD #2 ("stored on the NPSP Contact + synced") require net-new Salesforce work** — e.g., topic/list-membership fields on Contact and a list-membership sync — or is it satisfied by JSI-107 (global opt-out round-trip + SF Campaign→CC list push) plus CC's native list memberships? **Core scoping question.**
2. **Sync direction (from the comment):** CC→SF primary confirmed; allow SF→CC preference/list changes too? (JSI-107's native connector already pushes SF audiences→CC one way.)
3. **Which topics** become CC lists (advocacy, events, fundraising appeals, newsletter — examples or the actual set?), and do they map to Salesforce Campaigns/list memberships?
4. **Default vs. custom preference center:** is CC's built-in subscription/update-profile page sufficient, or does Communications want a custom-branded preference center (topics as checkboxes)?
5. **Privacy policy URL** to link, and any branding requirements — CC config owned by Communications.

## Related Reference Material

- **JSI-107** (`../JSI-107/`) — the Constant Contact integration this story leans on: `JSI-107_Implementation_Plan.md` (hybrid native + inbound poller), opt-out sync, SF↔CC field model.
- [`JSI-108_StoryDictationNotes.MD`](./JSI-108_StoryDictationNotes.MD) — Jason's dictation + 6-step process.
- Constant Contact subscription/preference-center documentation (to be researched).
