# JSI-122 — Tag Management

> **Source:** [JSI-122 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-122)
> Authored on 2026-06-24 by Jason Ott from the `StorySpecs.MD` working notes, then
> synced **to** Jira (description + Definition of Done). Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-122 |
| **Type** | Story |
| **Status** | In Progress |
| **Priority** | Lowest |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-9 — Contact Management |
| **Sprint** | Implementation Sprint 1 (2026-06-05 → 2026-07-06, *future*) |
| **Labels** | _None_ |
| **Feature Owner** | Development team _(inferred — not set in Jira)_ |
| **Reporter** | Jason Ott |
| **Assignee** | _Unassigned_ |
| **Created** | 2026-06-19 |
| **Updated** | 2026-06-24 |

## User Story

> As a member of the JCRC NY Development team, I want to apply **categorized tags** to
> contacts and accounts from a clean, in-line interface on the record page, so that I can
> consistently **segment constituents** by shared attributes and **report on everyone who
> carries a given tag**.

## Definition of Done

_Written as user-facing outcomes — the experience the Development team should have. The "how"
(objects, components, automation) lives in the Implementation Plan, not here._

- Tagging lives **right on the Contact and Account records I work in every day** — embedded in
  the record view with **no extra clicks** and without navigating to a separate screen.
- I can **find an existing tag just by typing** — the tag entry box **searches, sorts, and
  filters** existing tags as I type, with **type-ahead / text prediction**, so I rarely type the
  whole thing.
- While searching, I can **see each tag's category** so I apply the right one.
- The **same tags are reused** across the org rather than duplicated — when a tag already exists,
  typing it surfaces the existing tag instead of letting me create a near-duplicate.
- If the tag I need **doesn't exist yet, I can create it on the spot** and apply it without
  leaving the record (for users authorized to create tags).
- Every tag belongs to a **category**, and categories are **consistent and reusable** across the
  org so tagging stays organized.
- I can **see all the tags currently on a record at a glance** and **remove** one easily; a record
  never shows the same tag twice.
- I can **report on tags** — pull a list of every contact or account that carries a given tag, and
  **group or filter by category**.
- Tagging **respects security** — only authorized users can apply tags or create new ones.

## Notes & Context

- This is the **first phase** for JSI-122: author the User Story + Definition of Done and sync
  them to Jira. Build work follows the same flow as prior stories — pull the story back down
  from Jira, plan, then implement against the JCRC-Dev sandbox.
- **Final architecture** (forks resolved 2026-06-24, see below):
  - `Tag__c` — reusable tag library. Fields: `Name` (tag value), `Category__c` (**picklist**).
  - `Tag_Assignment__c` — junction. Fields: `Tag__c` (lookup), `Contact__c` (lookup),
    `Account__c` (lookup); validation enforces **exactly one** of Contact/Account is set.
- We are **not constrained to standard page layouts** — a custom LWC on the record page is the
  intended UX, so the type-ahead "search-or-create" experience can be made genuinely clean.

## Resolved Design Decisions (2026-06-24)

All design forks were settled with Jason before planning the build:

1. **Category model → picklist on `Tag__c`.** Simplest to build and to group reports by; admin
   maintains the category list via the picklist. (No separate `Tag_Category__c` object.)
2. **Junction shape → one `Tag_Assignment__c` with two lookups.** `Contact__c` + `Account__c`
   on a single junction, with a validation rule requiring exactly one to be populated. Keeps the
   LWC and reporting uniform. (Not two separate junction objects.)
3. **Tag-creation governance → permission-set based.** Any user **holding the tagging permission
   set** can create a brand-new tag inline; case-insensitive dedupe + type-ahead reuse prevent
   near-duplicates. Users without it apply existing tags only (or have no access, per final
   permission-set design in the plan).
4. **Remove behavior → hard-delete** the Tag Assignment. The tag itself stays in the library; no
   add/remove audit trail kept. (No `Active__c` soft-delete.)
5. **Taggable scope → Contact + Account, built extend-ready.** Ship for Contact and Account now,
   but structure the junction and LWC so adding another object's lookup later is a small change.
6. **Tag display extras → deferred.** `Tag__c` stays lean (value + category); `Color__c` /
   `Description__c` can be added later if wanted.

## Related Reference Material

- [`StorySpecs.MD`](./StorySpecs.MD) — the original working notes/dictation this story was
  authored from.
