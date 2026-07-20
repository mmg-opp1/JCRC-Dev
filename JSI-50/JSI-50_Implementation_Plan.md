# JSI-50 — Implementation / Verification Plan: Segmented email lists from NPSP data

> **Story:** [JSI-50](https://missionmattersgroup.atlassian.net/browse/JSI-50) · Epic JSI-3 Email Marketing · Must-Have (US-046) · Sprint 2 · Feature Owner **Communications**.
> **Author:** Jason Ott · **Drafted:** 2026-07-20 · Status: **VERIFICATION — recommends CLOSE with NO net-new Salesforce build (config + process + the JSI-107 native connector).**
> Per Jason's dictation, this is a *verify-against-Constant-Contact* story: confirm segmented lists are delivered by the **native CC↔Salesforce connector** driven by **Salesforce list views** + config, with nothing to build in Salesforce. This plan reconciles the one wording conflict (reports vs. list views), maps every DoD item to a mechanism, and gives Communications a config playbook.

---

## 1. Verdict

**No net-new Salesforce metadata to build.** Segmented lists are delivered by:
1. the **native Constant Contact ↔ Salesforce connector** (already the JSI-107 outbound mechanism — CC-hosted, one-way SF→CC, scheduled), plus
2. **Salesforce Contact list views** (and **Campaigns**) as the segment sources, built in the UI (config, not metadata), plus
3. a **staff process** for overlap rules + training.

Per the dictation's gate ("only produce an implementation plan if there's functionality to build"), there is **no build** — this is a verification + configuration/handoff.

---

## 2. The one wording conflict — reports vs. list views — RESOLVED

The DoD says *"Salesforce **reports** define the segments and push to Constant Contact lists."* Jason's dictation plans **list views**. **The native connector settles it: it imports by Contact list, Lead list, or Campaign — NOT reports.** Verbatim from CC's official article (`../JSI-107/ConstantContactDocumentation.MD`, updated 2026-07-17): *"There are three methods available for import: by Contacts List, Leads List, or Campaign List,"* and *"Select the Salesforce **contact list** to import from."* A CC import maps a **Salesforce Contact list view** (or a Campaign's members) → a Constant Contact list, on a schedule.

- **Report-based** SF→CC sync exists only via **third-party middleware** (Cazoomi SyncApps' filter/segmentation), which JSI-107 deliberately did **not** choose (no SaaS fee / no extra data processor).
- **⇒ Jason is right:** segments = **Contact list views** (and Campaigns). The "reports" wording in the DoD reflects the intent ("Salesforce defines the segment"), and the native mechanism is a **list view**. No report interface is needed.

---

## 3. Verified org context (JCRC-Dev, 2026-07-20)

- **NPSP giving rollups live on the Contact** (so donor-history segments are list-view-filterable): `npo02__LastCloseDate__c` (Last Gift Date), `npo02__OppAmountThisYear__c` / `npo02__OppAmountLastYear__c` (this/last-year giving), `npo02__TotalOppAmount__c`, `npo02__NumberOfClosedOpps__c`, membership fields (`npo02__MembershipEndDate__c`, `npo02__LastMembershipDate__c`), plus `npsp__Primary_Affiliation__c`. ✅
- **Event attendance = Campaign/CampaignMember** (gala = a Campaign; attendees = its members) → syncable via the connector's **Campaign lists import**.
- **Program affiliation** = `npsp__Primary_Affiliation__c` (Contact lookup) or a program field/Campaign — list-view/Campaign expressible.
- **Native connector** is the JSI-107 outbound path (Jason configures on the CC side). JSI-50 reuses it; **no new SF plumbing.**

---

## 4. DoD → mechanism map

| DoD item | Owner | Mechanism (no SF build) |
|---|---|---|
| SF "reports" define segments & push to CC lists | Config | **Contact list views** (donor-history/affiliation segments) + **Campaigns** (event attendance) → CC lists via the native connector's per-import mapping. (List views, not reports — §2.) |
| Lists refresh ≥ weekly | CC config | The connector import has a **frequency** setting — set weekly (or more often). |
| Sample segments (lapsed / current-year / gala / program-by-area) | Config | §5 — each expressed as a Contact list view or a Campaign. |
| Overlap rules (no double-email) | **Process/design** | §6 — the connector is add/update, **not exclusion-aware**; overlap is handled by how segments are defined and/or CC-side segments. |
| Staff trained | Process | Communications training on requesting/using segments — no build. |

---

## 5. Sample segments → definitions (config)

| Segment | Source | Criteria |
|---|---|---|
| **Lapsed donors** | Contact list view | `npo02__LastCloseDate__c` older than the lapsed threshold (e.g., > 13 months) **and** `npo02__TotalOppAmount__c` > 0 |
| **Current-year donors** | Contact list view | `npo02__OppAmountThisYear__c` > 0 (or `LastCloseDate` in the current giving year) |
| **Gala attendees** | **Campaign** import | Members of the gala Campaign (Campaign lists import) |
| **Program participants by area** | Contact list view / Campaign | `npsp__Primary_Affiliation__c` = the area's org, or a program field/Campaign per how "area" is stored (**client to define** — D3) |

> **List-view limit to note:** Contact list views filter **Contact fields** (incl. the NPSP rollups above), not related-object criteria (e.g., "is a member of Campaign X"). Membership-based segments therefore use the **Campaign import** method, not a list view. Both are native — still no build.

---

## 6. Overlap / no-double-email rules (process — D2)

The native connector creates/updates CC list membership per import; it does **not** remove a contact from other lists or dedupe across lists. So a person in two segments lands in two CC lists and could be emailed twice if both lists are mailed. Options (pick a policy — client):
- **(a) Mutually-exclusive segment definitions** — build list-view filters so segments don't overlap (e.g., "current-year donors" excludes those already in "major donors").
- **(b) CC-side segments/suppression** — send to a CC **segment** that unions the lists and dedupes, or use suppression lists, rather than mailing raw imported lists.
- **Recommendation:** (b) for send-time dedupe (CC segments dedupe recipients) + (a) where a clean split is natural. Document the chosen rule for Communications.

---

## 7. Constant Contact / Salesforce config playbook (for Communications + Jason)

1. Ensure the **native Salesforce integration is connected** on the CC side (JSI-107 Phase 1) against the right org.
2. In Salesforce, build the **segment Contact list views** (§5) and confirm the **gala Campaign** exists with its members.
3. In CC → Integrations → Salesforce → **Create an import** per segment: choose *Contacts list* (→ pick the list view) or *Campaign list* (→ pick the Campaign); map fields; pick/create the target **CC list**; set **frequency = weekly**; Import Type = **Merge** (don't overwrite); name it.
4. Repeat per segment (multiple scheduled imports are supported).
5. Define + document the **overlap policy** (§6) and **train** Communications on requesting/using segments.

---

## 8. The one "if" — when a small SF build *would* be needed
Only if a desired segment **cannot** be expressed as a Contact list view **or** a Campaign — e.g., complex cross-object criteria (multi-object AND/OR the connector can't consume). Then the lightest options are: **(i)** a scheduled **Flow** that stamps a `Segment__c` checkbox/picklist on Contact (list-view-able) or adds members to a segment **Campaign**; or **(ii)** middleware (Cazoomi) for report-based sync. **None of the DoD sample segments require this** — flagged only so we recognize it if a future segment outgrows list views.

## 9. Open decisions (client — no build hinges on these)
- **D1 — lapsed threshold:** how many months of no gift = "lapsed"? (e.g., 13 / 18 / 24 months.)
- **D2 — overlap policy:** §6 (a), (b), or both.
- **D3 — "program participants by area":** what field/model defines program + area (`npsp__Primary_Affiliation__c`? a program field? per-program Campaigns?).
- **D4 — giving year:** current-year donor = calendar year or JCRC's July–June giving year? (NPSP "this year" rollups are calendar; matches the JSI-90 org-FY note.)

## 10. Recommendation
**Close JSI-50 with no Salesforce build**, contingent on: (1) the JSI-107 native connector connected; (2) Communications building the segment list views/Campaign imports per §7; (3) the overlap policy documented; (4) training done. The four decisions above are content/process choices for the client, not blockers to any code.

## 11. Sources
- CC official — Connect Constant Contact with Salesforce (import by **Contacts List / Leads List / Campaign List**; list view as source; scheduled frequency; one-way): `../JSI-107/ConstantContactDocumentation.MD` (Article 000043703, updated 2026-07-17); https://knowledgebase.constantcontact.com/email-digital-marketing/articles/KnowledgeBase/43703-Connect-your-Constant-Contact-account-with-Salesforce
- Report-based sync = third-party middleware (Cazoomi SyncApps), not the native connector: https://support.cazoomi.com/hc/en-us/articles/21522839265051-Constant-Contact-s-Native-Salesforce-Integration-vs-SyncApps
- JSI-107 plan — native connector (SF→CC audience push) already in scope: `../JSI-107/JSI-107_Implementation_Plan.md`
- Org verification: `FieldDefinition` query for `npo02__`/`npsp__` Contact rollups (see §3).
