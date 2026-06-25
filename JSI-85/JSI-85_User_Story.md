# JSI-85 — Auto-apply soft credits for multi-party gifts

> **Source:** [JSI-85 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-85)
> Retrieved from Jira on 2026-06-25 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-85 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 1 (2026-06-15 → 2026-07-10, *active*) |
| **Labels** | Must-Have, US-018 |
| **Feature Owner** | Development Operations |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-18 |
| **Updated** | 2026-06-25 |

## User Story

> As a member of the Development team, I want soft credits applied automatically when a
> gift involves multiple parties (spouse, employer match, donor-advised fund), so that all
> involved parties see giving history reflected accurately.

## Definition of Done

- NPSP soft credit **roles defined** (spouse, employer match, DAF advisor, honoree).
- **Automation creates soft credits based on relationships** when a primary gift is recorded.
- Soft credit totals **roll up to contact and household** giving summaries.
- **Reports** clearly distinguish hard credit, soft credit, and household totals.
- Exception process documented for manual soft credit entry. *(Out of build scope — client. See Plan §1.)*
- Staff trained on which credit type to use in common scenarios. *(Out of build scope — training track. See Plan §1.)*

## Notes & Context

**Feature Owner:** Development Operations

**MMG Notes**
- What are the various soft-credit scenarios that **actively contribute to soft-credit roll-ups**?
- What **donation roles** do you want to track that are **not** soft credits?
- Are there **partial soft credits**?
- How will you handle **Benevity / DAF** gifts?

**MAF Notes**
- "I think this could get confusing if there are **multiple soft credits for one gift**."

## Dictation summary (Jason)

- Story is largely **native NPSP**. Use **Relationships** to auto-create soft credits for
  household members (spouses); use **Affiliations** for corporate giving.
- **Employer match design:** a **Donation** (individual donor) **+** a separate **Matching Gift**
  Opportunity (record type *Matching Gift*) from the corporation. E.g., Jason Ott donates; Mission
  Matters Group makes the match as a *Matching Gift* opportunity owned by MMG.
- **Partial soft credits:** client finds them **confusing → do not implement.**
- **Benevity:** accountant hard-credits the **individual donor** (it's the donor's money), not
  Benevity — match that in CRM.
- Wants **Relationship & Affiliation Lightning record pages** that are user-friendly, and a
  **"Relationships" tab on the Contact record page** with dynamic related-list components for
  **both Relationships and Affiliations** (separate from Details / Related tabs).

## Decisions (resolved 2026-06-25 by Jason)

> Detail in [`JSI-85_Implementation_Plan.md`](./JSI-85_Implementation_Plan.md) §9.

- ✅ **Employer match → soft-credit the individual:** Flow adds a **Matched Donor** OCR for the
  donation's primary contact on the matching-gift opp when `Opportunity.npsp__Matching_Gift__c` is set.
- ✅ **DAF model = "DAF as Payment Method"** (hard-credit the individual; fund = reference). Benevity same.
- ✅ **Spouse soft credit = Household Member** (not Relationship). NPSP's OCR precedence means no
  duplicate even if both applied — answers MAF's "multiple soft credits" concern.
- ✅ **Roles = standard NPSP OOTB set**; adjust later as needed.
- ✅ **Honoree** = tracked Contact Role, **not** rolled up to soft credit.
- 📌 **PINNED (client):** combined **"Total Giving (Hard + Soft)"** rollup vs. keep separate —
  Jason to confirm with client. (Build hard/soft separate now.)

## Related Reference Material

- [`JSI-85_Implementation_Plan.md`](./JSI-85_Implementation_Plan.md) — NPSP analysis, native vs.
  custom, double-counting, DAF/Benevity, UI pages, reports, decisions.
- [`Soft_Credit_Documentation.MD`](./Soft_Credit_Documentation.MD) — authoritative Salesforce/NPSP
  soft-credit docs (OCR precedence, rollups, configuration) Jason pulled (the JS-gated pages).
- [`JSI-85_StoryDictationNotes.MD`](./JSI-85_StoryDictationNotes.MD) — Jason's dictation.
