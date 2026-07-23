# JSI-120 — Track grant lifecycle stages

> **Source:** [JSI-120 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-120)
> Retrieved from Jira on 2026-07-21 by Jason Ott. This is a documentation snapshot — Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-120 |
| **Type** | Story |
| **Status** | To Do |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-8 — Fundraising |
| **Sprint** | Implementation Sprint 2 |
| **Labels** | Should-Have, US-063 |
| **Feature Owner** | _(Fundraising / Grant Manager)_ |
| **Reporter** | Jason Ott |

## User Story

> As a Grant Manager, I want my CRM to track the stages of a Grant.

## Definition of Done (annotated: what's a STAGE vs a FIELD — Jason)

- Ability to track the grant lifecycle:
  - **Stages** (sales process): **Identification → Request → Response →** then the shared **closed/won** stages used elsewhere (Pledged/Posted…) + lost (Declined/Written Off).
  - **Fields** (NOT stages): **date of funding, type of program, program officer**, + additional pertinent grant fields.
- *(Jira comment, Jason): "What about the different deliverables of grants?"* → the **Deliverables** piece (see dictation).

## Notes & Context (dictation — Jason)

- **Real build story** (light on detail; client may add more later). Goal: a **clean, well-functioning Grant Opportunity record type** with its own **Lightning record page** in JCRC's standard format.
- **Deliverables:** include the standard NPSP grant **Deliverables** object as a **related list** on the Grant page, using the **dynamic related-list single component** (JCRC's standard) with **helpful fields**; and **create a Deliverable Lightning record page** so Jason can activate it and users can see deliverables.
- **Grant sales process:** build the stages above on the Grant record type (Identification/Request/Response are stages; funding date / program type / program officer are fields).
- **Research (Jason wants a writeup + decision):** what automation NPSP includes for how **Deliverables interact with / sync to a user's Tasks** — then decide whether to build additional automation on top.

## Verified org context (2026-07-21)

- **Grant record type EXISTS** (`Opportunity.Grant`, active) — but currently uses the **`Pledge_Process`** business process (Cultivating/Prospecting/Pledged/Posted/Partially Posted/Written Off), i.e. **no grant lifecycle stages**.
- **`Grant_Record_Page` flexipage EXISTS** (JCRC standard format; already has `npsp__Grant_Deadlines__r` as a dynamic related list).
- **NPSP grant fields present** on Opportunity: `npsp__Grant_Period_Start/End_Date__c`, `Grant_Contract_Date/Number__c`, `Grant_Program_Area_s__c`, `Requested_Amount__c`, `Is_Grant_Renewal__c`, `Next_Grant_Deadline_Due_Date__c`, `Previous_Grant_Opportunity__c`, `Grant_Requirements_Website__c`.
- **Deliverables = NPSP `npsp__Grant_Deadline__c`** (object **label = "Deliverable"**): fields Opportunity lookup, Due Date, Close Date, Requirements, Type. **No Lightning record page for it yet.**
- Current `OpportunityStage` values: Qualification, Needs Analysis, Proposal, Negotiation, Prospecting, Cultivating, Pledged, Posted, Partially Posted, Written Off, Declined, Closed Won, Closed Lost. **Identification / Request / Response are absent.**

## Outstanding Questions / Gaps (Step 2 — for Step 5 forks)

1. **Grant stages set** — Identification → Request → Response → then which **won** stages (Pledged? Posted? Partially Posted?) and which **lost** (Declined? Written Off?). Which stage = "awarded/funded" (rolls up)?
2. **Fields to add:** *Program Officer* (User lookup, or Contact, or text?), *Type of Program* (reuse `npsp__Grant_Program_Area_s__c`, or a new picklist?), *Date of Funding* (Close Date, or a dedicated field?).
3. **Deliverables object** = confirm we use native **`npsp__Grant_Deadline__c`** ("Deliverable") rather than a new custom object (recommended — it's native, already related + on the page).
4. **Deliverable ↔ Task automation** — NPSP has **no native Task creation** from deliverables (only a Next-Deadline rollup on the Opportunity). Decide whether to build reminders/Tasks (§research in the plan).

## Related Reference Material

- [`../JSI-82/JSI-82_Implementation_Plan.md`](../JSI-82/JSI-82_Implementation_Plan.md) — pledge/grant record types + business processes + JCRC page format precedent.
- NPSP grant management (Opportunity Grant record type + Grant Deadlines/Deliverables): https://help.salesforce.com/s/articleView?id=sfdo.npsp_create_manage_grants.htm
