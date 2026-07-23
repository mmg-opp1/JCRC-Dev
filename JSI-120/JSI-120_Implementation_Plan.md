# JSI-120 — Implementation Plan: Track grant lifecycle stages

> **Story:** [JSI-120](https://missionmattersgroup.atlassian.net/browse/JSI-120) · Epic JSI-8 Fundraising · Should-Have (US-063) · Sprint 2 · Feature Owner **Grant Manager / Fundraising**.
> **Author:** Jason Ott · **Drafted:** 2026-07-21 · Status: **PLAN — awaiting fork decisions (Step 5), no build yet.**
> A real build: give the existing **Grant** Opportunity record type a proper grant **sales process**, the pertinent **fields**, a clean **Lightning page**, the native **Deliverables** related list + its own record page, and decide the **Deliverable→Task** automation.

---

## 1. Scope

**In scope:**
- A **Grant sales process** (Identification → Request → Response → shared closed stages) on the `Grant` record type.
- **Fields** for the lifecycle: date of funding, type of program, program officer (+ reuse NPSP's rich grant field set).
- **Grant Lightning record page** (enhance the existing one, JCRC standard format): grant field section + **Deliverables** dynamic related-list (single component) with helpful fields + path.
- **Deliverable Lightning record page** (native `npsp__Grant_Deadline__c`, label "Deliverable") — net-new flexipage.
- **Deliverable → Task automation** — research (below) + a decision, build if chosen.

**Out of scope / deferred:** a custom Deliverables object (native NPSP one is used); grant *application intake* forms; outbound/grantmaking (OFM) — JCRC is a grant **recipient**; anything the client adds later.

---

## 2. Verified org context (2026-07-21)
- **`Grant` record type exists**, but uses **`Pledge_Process`** (no grant stages). **`Grant_Record_Page` exists** (JCRC format; already has `npsp__Grant_Deadlines__r`).
- **NPSP grant fields present** (`npsp__Grant_Period_Start/End_Date__c`, `Grant_Contract_Date/Number__c`, `Grant_Program_Area_s__c`, `Requested_Amount__c`, `Is_Grant_Renewal__c`, `Next_Grant_Deadline_Due_Date__c`, `Previous_Grant_Opportunity__c`, `Grant_Requirements_Website__c`).
- **Deliverables = native `npsp__Grant_Deadline__c`** (label **"Deliverable"**): Opportunity lookup, Due Date, Close Date, Requirements, Type. **No Lightning page yet.**
- `OpportunityStage` lacks **Identification / Request / Response**.

---

## 3. Design

### 3.1 Grant sales process (D1)
Add **Identification, Request, Response** to the `OpportunityStage` StandardValueSet (open: not closed/won), then create a **`Grant_Process`** business process and **reassign the `Grant` record type** to it. Proposed stage set:

| Stage | Type | Notes |
|---|---|---|
| Identification | Open | Prospect/opportunity identified |
| Request | Open | Application/request submitted |
| Response | Open | Awaiting funder decision |
| Pledged | **Won** | Awarded / committed (reuse existing) |
| Partially Posted | **Won** | Partial funds received (reuse) |
| Posted | **Won** | Funds received (reuse) |
| Declined | **Lost** | Not awarded (reuse) |
| Written Off | **Lost** | Awarded but uncollectible (reuse) |

*(Gotcha: business processes can't set a stage `<default>`; no "/" in stage API names — all clean here. Adding SVS values is additive.)*

### 3.2 Fields (D2)
- **Type of Program:** reuse **`npsp__Grant_Program_Area_s__c`** (NPSP "Grant Program Area(s)") *(recommended)*, or a new JCRC `Program__c` picklist if JCRC has a fixed program list.
- **Program Officer (D2a):** new field — **Contact lookup** `Program_Officer__c` (the funder's program officer) *(recommended interpretation)*, vs a **User** lookup (internal grant manager) vs free text.
- **Date of Funding:** new **Date** `Date_of_Funding__c` *(recommended — explicit)*, vs reuse Close Date / `npsp__Grant_Period_Start_Date__c`.
- Everything else (period, contract #, requested amount, renewal, next deadline, previous grant) reuses the existing NPSP fields — no new build.
- FLS for any new field on Admin + JCRC profiles (additive minimal-profile technique).

### 3.3 Deliverables — native `npsp__Grant_Deadline__c` (D3)
Use the **native** object (already related to Opportunity, already on the Grant page). No custom object. On the Grant page, the `npsp__Grant_Deadlines__r` **dynamic related-list (single)** shows helpful fields: **Deliverable Name, Type, Due Date, Close Date, Requirements**.

### 3.4 Grant Lightning record page (enhance existing)
JCRC standard format: `dynamicHighlights` header + **path** (grant stages) + a **"Grant Details"** field section (NPSP grant fields + the new fields) + the **Deliverables** dynamic related list with the fields above + existing related lists. Page→RT activation is Jason's in App Builder.

### 3.5 Deliverable Lightning record page (net-new)
A flexipage for `npsp__Grant_Deadline__c`: highlights + a field section (Deliverable Name, Type, Due Date, Close Date, Requirements, parent Opportunity) so it's usable/clean when a user drills in. Jason activates + assigns.

### 3.6 Deliverable → Task automation — research + decision (D4)
**Native NPSP behavior (verified):** the only automation is a **rollup** — NPSP populates **`Opportunity.npsp__Next_Grant_Deadline_Due_Date__c`** from the soonest open Deliverable. **NPSP does NOT create Tasks/reminders** from Deliverables; per Salesforce/partner guidance, task reminders are **built** with flow/automation. So there is no native Deliverable↔Task sync to "turn on."
**Options:**
- **(a) None** — rely on the Next-Deadline rollup + the Deliverables related list; users watch it manually.
- **(b) Reminder flow *(recommended)*** — a record-triggered flow on `npsp__Grant_Deadline__c` that creates a **Task** (reminder) for the grant's Owner, due **N business days before** the Deliverable Due Date, on create or when Due Date is set/changed; idempotent (don't duplicate). Configurable N (e.g., 30). Optionally a second Task at the due date.
- **(c) Scheduled flow** — a daily scheduled flow that surfaces deliverables due in the next N days as Tasks/notifications. Heavier; (b) covers most needs.

---

## 4. Security & FLS
New fields → FLS on **Admin + JCRC Development/Fundraising/Marketing/Volunteering** (additive minimal-profile technique, per org standard — no perm sets). Deliverable object access already via NPSP + profiles; verify read/create/edit for grant users. Deliverable record page + Grant page are Jason's to activate.

## 5. Reporting (light)
Optional: a **Grant Pipeline** report (Opportunities, RT=Grant, grouped by Stage) + a **Deliverables Due** report (`npsp__Grant_Deadline__c`, Due Date in next 30/60 days, open). Confirm if wanted (D5).

## 6. Phased build
1. **Stages + process [Claude]:** add Identification/Request/Response to `OpportunityStage` SVS; create `Grant_Process`; reassign `Grant` RT. Verify.
2. **Fields [Claude]:** add the confirmed new fields + FLS.
3. **Grant page [Claude]:** enhance `Grant_Record_Page` (field section, path, Deliverables dynamic related list fields). Jason activates.
4. **Deliverable page [Claude]:** new `npsp__Grant_Deadline__c` flexipage. Jason activates.
5. **Automation [Claude, if D4=b]:** deliverable reminder flow + verify (anon-Apex savepoint/rollback).
6. **Reports [Claude, if D5]** · commit + push.

## 7. Open decisions — ✅ SETTLED (Jason, 2026-07-21)
- **D1 — ✅ Grant stages:** Identification → Request → Response → **Pledged / Partially Posted / Posted (Won)** → **Declined / Written Off (Lost)** (reuse existing closed stages).
- **D2 — ✅ fields:** Type of Program = reuse **`npsp__Grant_Program_Area_s__c`**; Date of Funding = **Close Date** (no new fields for these). **D2a — Program Officer = Contact lookup** `Program_Officer__c` (the funder's PO) — the only net-new field.
- **D3 — ✅ Deliverables = native `npsp__Grant_Deadline__c`** (no custom object).
- **D4 — ✅ Deliverable→Task automation = reminder flow** (record-triggered on `npsp__Grant_Deadline__c`; Task for the grant Owner N business days before Due Date; idempotent).
- **D5 — reports:** optional, low priority — build if time after the core.

## 8. Sources
- NPSP Manage Grants (Grant RT on Opportunity + Grant Deadlines/Deliverables): https://help.salesforce.com/s/articleView?id=sfdo.npsp_create_manage_grants.htm
- NPSP deliverables track requirements/deadlines; **task reminders are built via workflow/flow** (not native): https://www.formassembly.com/blog/how-nonprofits-use-salesforce-npsp-to-manage-grant-applications-and-reporting/ · https://mirketa.com/grant-management-with-npsp/
- Org verification 2026-07-21: `Grant` RT (→ Pledge_Process), `Grant_Record_Page`, NPSP grant fields, `npsp__Grant_Deadline__c` (label "Deliverable") fields, `OpportunityStage` values.

## 9. Build Log

**Phase 1 — grant stages + sales process — ✅ BUILT, DEPLOYED & VERIFIED 2026-07-22 (not committed).**
- Added **Identification / Request / Response** to the `OpportunityStage` StandardValueSet (open; forecast Pipeline/BestCase; probabilities 10/40/70) — verified **active** in org.
- Created **`Grant_Process`** business process (Identification → Request → Response → Pledged / Partially Posted / Posted → Declined / Written Off) and **reassigned the `Grant` record type** to it (was `Pledge_Process`).
- Deploy 3/3. *(Gotcha hit: the `Grant` record type file carried two **deactivated** `npsp__Acknowledgment_Status__c` values — "Email Acknowledgment Not Sent/Now" (deactivated in JSI-87) — which blocked the RT deploy "picklist value … not found"; removed those two stale `<values>` from the RT file. Also: the deploy is transactional — the first attempt's SVS+process "2/3" rolled back when the RT failed, so all three had to redeploy together. Business-process stage `<default>` kept false per the JSI-82 gotcha.)*

**Phase 2 — fields — ✅ BUILT, DEPLOYED & VERIFIED 2026-07-22 (not committed).**
- **`Opportunity.Program_Officer__c`** (Lookup → Contact = the funder's program officer; SetNull) + FLS on Admin + 4 JCRC profiles (5/5). Type of Program reuses `npsp__Grant_Program_Area_s__c`; Date of Funding = Close Date (no new fields, per D2).

**Phase 3 — Grant Lightning record page — ✅ ENHANCED & DEPLOYED 2026-07-22 (not committed).** The existing `Grant_Record_Page` already had the grant fields, the **path** (now auto-shows the new grant stages), and the **Deliverables** dynamic related list (`npsp__Grant_Deadlines__r`, ADVGRID) with helpful columns (Name/Type/Requirements/Due Date/Close Date). Added to the Grant Details section: **`Program_Officer__c`**, `npsp__Requested_Amount__c`, `npsp__Grant_Program_Area_s__c` (Type of Program), `npsp__Next_Grant_Deadline_Due_Date__c`; fixed a pre-existing duplicate (Grant Period Start listed twice → second is now **End Date**). Deployed 1/1. Jason activates.

**Phase 4 — Deliverable Lightning record page — ✅ BUILT & DEPLOYED 2026-07-22 (not committed).** New `Deliverable_Record_Page` flexipage for `npsp__Grant_Deadline__c` (highlights + a "Deliverable Details" section: Name, Opportunity, Type, Due Date, Close Date, Requirements). Deployed 1/1. Jason activates + assigns as the org default for the object.

**Phase 5 — deliverable reminder flow — ✅ BUILT, DEPLOYED & VERIFIED 2026-07-22 (not committed).** `Grant_Deliverable_Reminder_Task` — record-triggered (after-save, **Create**) on `npsp__Grant_Deadline__c` where Due Date + Opportunity are set → Gets the grant Opportunity → creates a **Task** for the Opp **Owner**, subject "Grant deliverable due: {Name}", `ActivityDate` = Due Date − 14 (calendar) days, linked to the grant (WhatId), Description = Requirements. **Create-only = idempotent** (no duplicate tasks on edits). Verified via anon Apex (savepoint→rollback): 1 task, correct subject/date(08-08 for a 08-22 due)/owner. *(Simplification: 14 **calendar** days, not business days — a reminder buffer; business-day precision would need a helper. If a deliverable's due date is added *after* creation, no task fires — extend to due-date-change later if wanted.)*

**Remaining:** Phase 6 optional reports (Grant pipeline; Deliverables due) · commit + push · Jason activates the two pages.
