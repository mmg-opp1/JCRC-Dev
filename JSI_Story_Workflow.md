# JSI Story Workflow — How We Build JCRC Stories

> Our repeatable playbook for taking a JSI story from notes to deployed, verified, committed metadata.
> Authored 2026-06-25 by Jason Ott. Applies to every `JSI-XX` story. See `CLAUDE.md` for the core
> development tenets this builds on.

Each story lives in its own repo folder `JSI-XX/` holding: the **dictation notes**, the **User Story**
snapshot, the **Implementation Plan**, and any reference docs. The workflow is the 6 steps Jason
records in each `JSI-XX_StoryDictationNotes.MD`, plus the build conventions we've settled.

---

## The seed: `JSI-XX_StoryDictationNotes.MD`
Jason writes a short dictation per story describing real scope, what's already handled by other
stories, what's explicitly out, and any clarifications — followed by the standard 6-step process. The
dictation is the source of intent; **Jira is the system of record** for the story text + DoD.

---

## Step 1 — Pull the story from Jira → save locally
- Creds in `.jira_creds.json` (repo root, **gitignored — never commit**). `email` + `api_token` (basic auth), `base_url`.
- `GET /rest/api/3/issue/JSI-XX?expand=names` → `summary`, `issuetype`, `status`, `priority`,
  `parent` (epic), `labels`, `reporter`/`assignee`, `created`/`updated`, **Sprint** = `customfield_10007`,
  **Definition of Done** = `customfield_10029`. Description + DoD are **ADF** (walk the `content` tree).
- `GET /rest/api/3/issue/JSI-XX/comment` → **Feature Owner** + **JCRC/MAF notes** live in a comment.
- Save **`JSI-XX_User_Story.md`** in house format: Overview table · User Story (As a… I want… so
  that…) · **Definition of Done with this-story scope annotated** · Notes & Context · Outstanding
  Questions / Design Decisions · Related Reference.
- **Snapshot vs. sync:** if the Jira story already has a description + DoD, this is a one-way
  **snapshot** (don't push back). If the story is a **stub** (e.g. JSI-122), author the User Story +
  DoD and **push to Jira** (`PUT` description + `customfield_10029` as ADF), then re-pull to verify.

## Step 2 — Reconcile dictation vs. Jira; find the gaps
- Map each DoD item to: **already done** (prior story), **in scope (this story)**, **deferred** (other
  story), or **statement of fact** (no build). Most stories build less than the DoD implies — earlier
  stories (JSI-82 record types, JSI-86 tax section, JSI-89 pages) often already cover items.
- List **Outstanding Questions / Design forks** the client or Jason must answer.

## Step 3 — Research & due diligence (NO GUESSING — per CLAUDE.md)
- **Verify the org with the `sf` CLI**, never assume: `sf sobject describe`, `sf data query`
  (FieldDefinition, RecordType, settings, **NPSP Customizable Rollups** filter groups/rules), grep the
  flexipages/objects in `force-app`.
- **Research best practice**: WebSearch/WebFetch for NPSP behavior + industry/IRS standards. Cite
  sources in the plan. **Salesforce Help pages are often JS-gated** (return a CSS-error shell) — when
  that happens, **flag it for Jason to pull**; don't guess the wording.
- Reuse the hard-won gotchas in the `reference-sf-metadata-gotchas` memory.

## Step 4 — Implementation Plan (`JSI-XX_Implementation_Plan.md`)
House format (see JSI-80/82/84/86): Scope (in/out) · Decisions to confirm · **Verified org context**
· Requirement → mechanism · Design (fields/objects/automation/pages) · Security & FLS · Reporting ·
Phased build plan · Net-new metadata · Risks · Sources · **Build Log** (filled as you deploy).

## Step 5 — Settle the design forks
- Surface forks as **explicit decisions with a recommended option first** (use AskUserQuestion).
  Jason answers. Flag anything needing **client confirmation** in the doc.
- **Definition of Done = user-facing OUTCOMES, never implementation specs** (JSI-122 correction). The
  "how" (objects, LWC, flows) belongs only in the Implementation Plan.

## Step 6 — Build → deploy → verify → commit → push
- **Deploy by component:** `sf project deploy start -m "Type:Name"` (use **absolute paths** for
  `--source-dir`); deploys are transactional (one failure rolls back the batch).
- **Deploy FLS *with* new fields** or they're invisible (to admins, the Apex compiler, and reports).
  Full profiles aren't source-deployable in this org → use the **additive minimal-profile** technique
  (a stripped `<Profile>` with only the new `fieldPermissions`/`recordTypeVisibilities` from a temp
  dir), then sync the repo profile by inserting **contiguously** after the last `</fieldPermissions>`.
  A focused **permission set** is the cleaner alternative when Jason doesn't need profile FLS.
- **Verify in-org** with anonymous Apex inside `Database.setSavepoint()` → `Database.rollback(sp)` so
  no test data persists. Assert the real behavior (formulas, validation, rollups, picklists).
- **Commit ONLY this story's files.** Multiple story threads run in parallel (JSI-80/85/89/… land work
  concurrently) — stage explicit paths, never `git add -A`; exclude other stories' files. End commit
  messages with the `Co-Authored-By` trailer. **Push only when Jason asks.**
- Update the plan **Build Log** and the **project-jcrc-story-pipeline** memory; record new gotchas in
  the **reference-sf-metadata-gotchas** memory.

---

## Division of labor (who does what)
- **Jason (UI / config):** Flow Builder, **NPSP Settings & Customizable Rollups**, Lightning **App
  Builder** record pages + **page→record-type assignments** (not in source metadata), report builder,
  DLRS setup.
- **Claude (version-controlled metadata):** objects/fields/record types/validation/flows/Apex/LWC/
  reports/report types/permission sets/profile FLS — authored, deployed via `sf`, and **verified**.

## Conventions cheat-sheet
- Author = **"Jason Ott"** in all code/metadata headers (CLAUDE.md).
- Restricted picklist values: **avoid "/"** (encoding pain in record-type assignments).
- Currency **formula** fields need **both** `precision` and `scale`.
- Every Apex class needs its own **`.cls-meta.xml`**; aim ≥ 90% coverage; `with sharing` + `USER_MODE`.
- **Reports:** standard report-type custom columns use the **`Opportunity.Field__c`** token (not bare
  API name); a report folder + its reports must deploy **together**; record-type filter = column
  `RECORDTYPE`, value `Opportunity.<DevName>`.
- **FlexiPage field sections:** anchor inserts on the **System Information** marker
  (`@@@SFDCSystem_InformationSFDC@@@`) — present on every Opportunity record page despite differing
  facet structures (JSI-89 named facets vs JSI-82 GUID facets). Page→RT assignment is Jason's in App Builder.
- **NPSP in-kind:** value in `npsp__Fair_Market_Value__c`, `Amount` blank; **exclude the In-Kind record
  type from the HC + SC Customizable-Rollups filter groups** (`Opportunity.RecordType Not_Equals <DevName>`).

---

## Story status at a glance
The live pipeline status lives in the **`project-jcrc-story-pipeline`** memory. As of 2026-06-25:
JSI-82 ✅, JSI-122 ✅, JSI-86 ✅, JSI-84 ✅ (all pushed); JSI-89 & JSI-85 owned by parallel threads;
JSI-80 (NPSP Gift Entry) in progress.
