# JSI-127 — Other Campaigns from Website

> **Source:** [JSI-127 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-127)
> Retrieved from Jira on 2026-08-17 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-127 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Medium |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | _None assigned_ |
| **Labels** | _None_ |
| **Feature Owner** | _Not stated (no comments on the issue)_ |
| **Reporter** | Jason Ott |
| **Assignee** | Jason Ott |
| **Created** | 2026-08-17 |
| **Updated** | 2026-08-17 |

## User Story

> As a Development team member, I want donors to be able to contribute to new campaigns
> that may not be mentioned in the existing categories on our website.

## Definition of Done

> - Constituents can write in free text entries for 'Other' campaigns.
> - Other donations will land in a static, 'Other - Website Donation' category in Salesforce.
> - Development team will need a process to review any donations made in this Other
>   category, confirm with donor and make adjustments as necessary.

**Annotated with this-story scope:**

| DoD item | Scope call |
|---|---|
| 1. Constituents can write in free text | **Website-side, not Salesforce.** The donate page already has the "other campaign" write-in box per the dictation. Salesforce's job is to *receive* the value. |
| 2. Land in a static 'Other - Website Donation' category | **Half already done in the org** — Jason created the Campaign **"Website Donation - Other"** (active, Fundraising Campaign record type). The Salesforce build here is the **field to hold the written-in text**. |
| 3. A review process for the Development team | **In scope** — the review work queue report, which self-empties as staff reassign each gift. |

## Notes & Context

**From Jason's dictation** (`JSI-127_StoryDictationNotes.MD`):

- The JCRC donate page lets a donor pick a campaign, and also offers an **"other campaign"
  free-text box**.
- He wants that text to **map into a text field in Salesforce**.
- He wants a **report** showing donations where a custom campaign name was written in.
- **The purpose is a review loop:** a staff member reads the report and either (a) confirms it
  is a valid campaign — likely adding it to the website's options list and creating the
  Campaign in Salesforce — or (b) manually changes the Campaign lookup on the Opportunity to
  something existing.
- He then refines the design mid-dictation: *"I think we probably need to have a static
  campaign that is like other website campaign and the report can be based off that static
  campaign."* — which is what he then built in the org.

**Why the static-campaign design is the better of the two he floated.** Basing the report on
the **Campaign** rather than on "write-in text is not blank" makes the queue **self-emptying**:
the moment a staff member reassigns the Opportunity to a real campaign, the row leaves the
report. A text-based filter would keep every reviewed gift in the queue forever and need an
extra "reviewed" flag to clear it. The plan therefore filters on the campaign, and keeps the
write-in text as a permanent audit trail of what the donor actually typed.

## Outstanding Questions

**For Jason / the client — the one real dependency:**

1. **What posts the donation into Salesforce, and who maps the field?** Salesforce can hold
   the value, but something on the website side has to send it. The plan builds the receiving
   field and — following the JSI-80 precedent — also the NPSP Data Import counterpart so the
   value survives Gift Entry and any Data-Import-based intake. **Whatever platform runs the
   donate page still needs its own field mapping configured, and that is outside Salesforce
   metadata.** This is the same open platform question that JSI-86 deferred (event platform)
   and JSI-89 flagged (online-gift intake).
2. **Should populating the write-in text automatically set the Campaign to "Website Donation
   - Other"?** Not built — if the platform already assigns the campaign (per DoD #2) this
   would be redundant, and if it does not, the rule belongs wherever the mapping lives. Cheap
   to add later as a before-save flow if the platform cannot set the campaign itself.
3. **Should the write-in text be cleared once a gift is reassigned?** The plan **keeps** it,
   as an audit record of the donor's own words. It does not affect the queue, which empties
   on campaign reassignment.

## Related Reference Material

- [`JSI-127_StoryDictationNotes.MD`](./JSI-127_StoryDictationNotes.MD) — Jason's dictation, the intent source.
- `JSI-80/` — the precedent for a custom Opportunity field plus its NPSP Data Import source field and advanced field mapping (`Approach__c`).
- `JSI-50/` — where the website / Constant Contact campaign arrangement was verified.
