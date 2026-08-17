# JSI-127 — Implementation Game Plan: Other Campaigns from Website

> **Story:** [JSI-127](https://missionmattersgroup.atlassian.net/browse/JSI-127) — Other Campaigns from Website (Epic JSI-8 Fundraising)
> **Author:** Jason Ott · **Written:** 2026-08-17
>
> **Change Log:**
> - 2026-08-17 — Jason Ott — Initial plan: Jira pull, dictation reconciliation, org verification, design.

---

## 1. Scope

**In scope**

- A field on Opportunity to **receive the campaign name a donor typed** into the website's
  "other" box, plus its **NPSP Data Import counterpart and field mapping** so the value
  survives Gift Entry and Data-Import-based intake (the JSI-80 pattern).
- The **review work queue report** for the Development team (DoD #3), based on the static
  campaign so it self-empties as gifts are reassigned.

**Out of scope**

- The website form itself and the platform-side field mapping (DoD #1) — not Salesforce
  metadata. See §7 Risk 1.
- Creating the static campaign — **already done**: Jason created **"Website Donation - Other"**
  in the org.
- Auto-assigning the campaign when the write-in text is populated — see Q2; deliberately not
  built.

---

## 2. Verified org context (checked against JCRC-Dev, 2026-08-17)

| Fact | Value |
|---|---|
| Static campaign | **`Website Donation - Other`** already exists — `701iI000001RTqFQAW`, record type `Fundraising_Campaign`, Active. **DoD #2's Salesforce half is done.** |
| Other campaigns present | FY27, FY27 Appeals, FY27 Fall Appeal, FY27 Gala, FY27 Spring Appeal, JCRC-Long Island, plus the CC List campaign from JSI-108 |
| Campaign record types | `Fundraising_Campaign` (default), `CC_List`, `Event`, `Master` |
| Existing write-in field | **None** — no Opportunity field holds a campaign write-in today |
| `Approach__c` picklist | Direct Mail / **Online** / Event / Major Gift / Phone / In Person / Other — so website gifts are already distinguishable by channel |
| JSI-80 precedent, verified in repo | `Opportunity.Approach__c` **plus** `npsp__DataImport__c.Approach__c` **plus** field-mapping CMDT `npsp__Data_Import_Field_Mapping.Approach_c48db3485` (set `Migrated_Custom_Field_Mapping_Set`, target object mapping `Opportunity_ce8a6ed7b`) |

---

## 3. Design

### 3.1 New metadata

| Component | Type | Purpose |
|---|---|---|
| `Opportunity.Other_Campaign_Write_In__c` | Text(255) | Holds exactly what the donor typed |
| `npsp__DataImport__c.Other_Campaign_Write_In__c` | Text(255) | Data Import / Gift Entry source field |
| `npsp__Data_Import_Field_Mapping.Other_Campaign_Write_In` | CMDT record | Maps source → target, mirroring the `Approach` record |
| `Website Donation Reports` | ReportFolder | New folder — nothing existing fits |
| `Other Campaign Write-Ins to Review` | Report | The Development team's review queue |

### 3.2 Why also build the Data Import field and mapping

Without it, the write-in value is invisible to **NPSP Gift Entry** — which this org actively
uses (JSI-80 built five Form Templates) — and to any Data-Import-based intake. A staff member
manually entering a website gift would have nowhere to record what the donor typed. JSI-80 hit
exactly this question for `Approach__c` and answered it the same way, so this follows an
established, verified pattern in this org rather than inventing one.

If the donate-page platform ends up writing straight to Opportunity, the Data Import field is
simply unused — harmless, and Gift Entry still benefits.

### 3.3 Report specification — `Other Campaign Write-Ins to Review`

| Aspect | Spec |
|---|---|
| Report type | `Opportunity` (standard) |
| Format | Tabular — it is a work queue |
| Filter | Campaign name = **Website Donation - Other** |
| Columns | Opportunity Name, Account, Close Date, Amount, **Other Campaign Write-In**, Approach, Stage, Owner |
| Sort | Close Date descending — newest first |

**Self-emptying by design:** filtering on the campaign rather than on the text means a gift
drops off the queue the instant a staff member reassigns it, with no "reviewed" flag to
maintain. The write-in text stays on the record permanently as the audit trail.

### 3.4 Security

FLS via the additive minimal-profile deploy — read/**edit** on Admin + the four JCRC profiles
(staff must be able to correct the text, unlike the read-only rollups in JSI-125/126).

---

## 4. Requirement → mechanism

| Requirement | Mechanism |
|---|---|
| Donor types a campaign name | Website form (out of scope) |
| Text maps into Salesforce | `Opportunity.Other_Campaign_Write_In__c` + Data Import source field and mapping |
| Gifts land in a static Other category | The existing **Website Donation - Other** campaign |
| Team reviews and adjusts | `Other Campaign Write-Ins to Review` report; staff reassign the Campaign lookup, which clears the row |
| Confirm a valid campaign | Staff create the Campaign and reassign — no automation needed |

---

## 5. Research

There is no NPSP feature for "donor-suggested campaigns"; NPSP models campaigns as standard
Salesforce Campaigns with no free-text intake concept. So a receiving text field plus a review
queue is the platform-standard answer, and the only real design question is where the value is
mapped — which is a function of the donate-page platform, not of NPSP.

Worth noting what this story is *not*: it deliberately does **not** try to auto-create
Campaigns from donor text. That would let anonymous website input create real reporting
objects, and the dictation is explicit that a human confirms first.

---

## 6. Phased build

| Phase | Work |
|---|---|
| **1** | `Opportunity.Other_Campaign_Write_In__c` + FLS |
| **2** | `npsp__DataImport__c.Other_Campaign_Write_In__c` + field-mapping CMDT |
| **3** | `Website Donation Reports` folder + `Other Campaign Write-Ins to Review` report |
| **4** | Verify — seed a gift on the Other campaign with write-in text, confirm the report criteria select it and that reassignment drops it |

---

## 7. Risks

1. **The platform-side mapping is the real dependency and is outside Salesforce.** Everything
   here is inert until whatever runs the donate page is configured to send the write-in value
   (and, per DoD #2, to set the campaign). This is the same unresolved online-platform
   question that JSI-86 deferred and JSI-89 flagged.
2. **A 255-character text field will truncate** a very long entry. Acceptable for a campaign
   name; worth knowing.
3. **Nothing prevents a gift sitting on the Other campaign forever** if nobody works the
   report. The queue makes it visible, but no SLA or reminder is built.

---

## 8. Decisions

| # | Decision | Outcome |
|---|---|---|
| **D1** | Report keyed on the campaign or on the text field? | **Campaign** — Jason's own refinement, and it makes the queue self-emptying (§3.3) |
| **D2** | Auto-set the campaign when text arrives? | **Not built** — belongs with the platform mapping (Q2) |
| **D3** | Clear the text after reassignment? | **Keep it** — audit trail |
| **D4** | Build the Data Import counterpart? | **Yes** — JSI-80 precedent; without it Gift Entry cannot capture the value (§3.2) |

---

## 9. Sources

- Live org verification, JCRC-Dev, 2026-08-17 (campaigns, record types, field inventory).
- In-repo: `JSI-80/` (`Approach__c` + Data Import source field + field-mapping CMDT pattern), `JSI-50/` (website/CC campaign arrangement).

---

## 10. Build Log

### 2026-08-17 — BUILT + DEPLOYED + VERIFIED (JCRC-Dev)

**Deployed**

| Component | Notes |
|---|---|
| `Opportunity.Other_Campaign_Write_In__c` | Text(255). FLS read **+ edit** on Admin + 4 JCRC (staff must be able to correct it). |
| `npsp__DataImport__c.Other_Campaign_Write_In__c` | Text(255) source field, same FLS. |
| `npsp__Data_Import_Field_Mapping.Other_Campaign_Write_In` | CMDT record mirroring the JSI-80 `Approach` mapping (set `Migrated_Custom_Field_Mapping_Set`, target object mapping `Opportunity_ce8a6ed7b`). |
| `Website Donation Reports` | New report folder. |
| `Other Campaign Write-Ins to Review` | Tabular review queue. |

**Verified — anon Apex, `setSavepoint()` → `rollback()`**

Seeded a website gift on the *Website Donation - Other* campaign with the write-in text
"Ukraine Emergency Relief", then walked the staff review loop:

| Expectation | Result |
|---|---|
| Gift appears in the queue | **PASS** — 1 row |
| Reassigning the Campaign clears it | **PASS** — 0 rows after reassigning to *FY27 Fall Appeal* |
| Write-in text survives reassignment | **PASS** — still "Ukraine Emergency Relief" (audit trail intact, D3) |
| Data Import source field usable | **PASS** — holds the write-in, so Gift Entry can capture it |

**A useful reuse, and the gotcha behind it**

The standard `Opportunity` report type turns out to expose **no native campaign column** that
a report filter can use — both `CAMPAIGN_NAME` and `Opportunity.CampaignId` are rejected
(*"Invalid value specified"*). Rather than guess further, the valid column list was pulled
from the org itself:

```
sf api request rest "/services/data/v60.0/analytics/reportTypes/Opportunity"
```

That returned exactly one usable campaign column: **`Opportunity.Campaign_Name__c`** — the
text formula field built two stories earlier for **JSI-124**, so the DAF template could merge
a campaign name. It is name-based rather than Id-based, which also makes the filter portable
to production. **JSI-124's field solved JSI-127's filter problem**; no new field was needed.

**⚠️ Nothing here is live until the platform side is done**

The field, the mapping and the report are all inert until whatever runs the JCRC donate page
is configured to (a) send the write-in text and (b) put the gift on the *Website Donation -
Other* campaign. That is outside Salesforce metadata and is the story's real dependency
(Risk 1 / Q1) — the same unresolved online-platform question JSI-86 deferred and JSI-89 flagged.

**Not built (deliberate)**

- Auto-setting the campaign when write-in text arrives (D2 / Q2) — belongs with the platform mapping.
- Any auto-creation of Campaigns from donor text (§5) — a human confirms first, per the dictation.
