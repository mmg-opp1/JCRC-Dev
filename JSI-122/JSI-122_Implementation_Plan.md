# JSI-122 — Implementation Game Plan: Tag Management

> **Status:** 🟡 PLANNED — not yet built. Design forks resolved 2026-06-24 (see `JSI-122_User_Story.md`).
> **Author:** Jason Ott · **Date:** 2026-06-24 (rev. 1)
> **Related:** `JSI-122_User_Story.md`, `StorySpecs.MD`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-122 (Epic JSI-9 — Contact Management)
> **Org:** JCRC-Dev sandbox · NPSP 3.237 · API v67.0

---

## 1. Scope

**IN scope:** Let the Development team apply reusable, **categorized tags** to **Contacts** and
**Accounts** from a clean component **embedded on the record page** (no extra clicks). Type-ahead
**search / sort / filter** of existing tags; **reuse** of existing tags (no duplicates); **create
a new tag inline** (for authorized users); **view & remove** a record's tags; **report** on every
contact/account carrying a given tag, grouped by category. Built **extend-ready** so other objects
(Opportunity, Campaign, …) can be added later with minimal change.

**OUT of scope (this story):** tagging objects other than Contact/Account; tag color/description
display extras; tag analytics dashboards; bulk-tagging from list views; merge-tags admin UI
(basic retire/merge approach documented, full tooling deferred).

**Recognition of constraints:** the DoD is written as user outcomes; this plan owns the "how."

---

## 2. Architecture decision — **two custom objects + a record-page LWC** ✅

Resolved with Jason on 2026-06-24 (full rationale in the User Story "Resolved Design Decisions"):

| Decision | Choice | Why |
|---|---|---|
| Tag storage | **`Tag__c`** (reusable library) | One row per distinct tag; reused org-wide. |
| Category | **Picklist `Category__c` on `Tag__c`** | Simplest; easy report grouping; admin maintains the list. (No separate object.) |
| Tag↔record link | **One junction `Tag_Assignment__c`** with `Contact__c` + `Account__c` lookups | Uniform LWC + reporting; standard SF pattern. Validation enforces exactly one. |
| UI | **LWC on Contact & Account Lightning record pages** | "Embedded where I work every day, no extra clicks"; standard layouts can't do type-ahead search-or-create. |
| Tag creation | **Permission-set gated**, case-insensitive dedupe | Any user holding the tagging permission set can mint tags; reuse prevents near-dupes. |
| Remove | **Hard-delete** the assignment | No audit-history requirement. |
| Extensibility | Contact + Account now; junction/LWC **structured to add objects** | Avoids a rebuild later. |

---

## 3. Verified org context (JCRC-Dev — from local metadata, in sync per Jason 2026-06-24)

| Fact | Source | Implication |
|------|--------|-------------|
| **No `Tag__c` / `Tag_Assignment__c` exist** | `objects/` listing | **Greenfield** — no migration, clean build. |
| **Account RTs:** `HH_Account` (Household), `Organization` | `objects/Account/recordTypes` | Tagging applies to both; LWC keys on `objectApiName`, RT-agnostic. |
| **Contact:** no custom RTs | `objects/Contact` | No RT branching needed. |
| **Record pages present:** `Contact_Record_Page`, `Contact_Record_Page_Three_Column`, `Account_Record_Page_Three_Column` | `flexipages/` | Candidate embed targets — **confirm the active/assigned page in App Builder at build time** (assignment isn't fully in flexipage metadata; see JSI-82 lesson). |
| **Permission model:** prior stories use a permission set pattern (`Sales_User`, etc.) | `permissionsets/` | Create a **`Tag_Management`** permission set rather than editing profiles. |
| **No Apex authored by JCRC; all automation Flow-based today** | org review 2026-06-24 | First JCRC Apex (a small `@AuraEnabled` controller) — keep it lean, tested, FLS-safe. |
| **API v67.0** | `sfdx-project.json` | Target version for all new metadata. |

---

## 4. Data model

### 4.1 `Tag__c` — reusable tag library
| Field | API Name | Type | Notes |
|---|---|---|---|
| Tag Name | `Name` | Text (standard) | The tag value (e.g., "Board Member"). |
| Category | `Category__c` | Picklist (required, **restricted**) | Values (confirmed 2026-06-24): **Interest, Program, Demographic, Geographic, Skills, Hobbies, Employment, Education, General, Other**. |
| Tag Key | `Tag_Key__c` | Text(255), **External ID, Unique — case-insensitive** | Dedupe backstop = `LOWER(Name) + '|' + Category__c`. Populated by the Apex create path (and a small before-save Flow as a data-load safety net). |

- **Object settings:** Allow Reports ✅, Allow Search ✅, Track Activities ✗, Deployment = Deployed.
- **OWD:** **Public Read/Write** (reference data everyone shares). Tighten later only if needed.
- **Dedupe (case-insensitive, per category):** primary enforcement in the Apex create method
  (SOQL text `=` is case-insensitive → reuse on match); `Tag_Key__c` unique field is the DB
  backstop for imports/data loads.

### 4.2 `Tag_Assignment__c` — junction (Tag ↔ Contact **or** Account)
| Field | API Name | Type | Notes |
|---|---|---|---|
| Name | `Name` | Auto Number `TA-{0000}` | No natural name needed. |
| Tag | `Tag__c` | Lookup(`Tag__c`), **required** | The applied tag. |
| Contact | `Contact__c` | Lookup(Contact) | Set when applied on a Contact. |
| Account | `Account__c` | Lookup(Account) | Set when applied on an Account. |
| Assignment Key | `Assignment_Key__c` | Text(255), **Unique** | Backstop against the same tag twice on a record = `Tag__c + '|' + (Contact__c or Account__c)`. |

- **Lookups, not master-detail:** a junction can't master-detail to two parents *and* support an
  "either/or" record; lookups + validation is the correct pattern here. (Set lookup delete
  behavior to **"don't allow deletion of the lookup record that's part of a relationship"** =
  off → clearing is fine; assignments are cheap and hard-deleted on remove.)
- **OWD:** **Public Read/Write** internally (simplest; revisit if Contact/Account visibility must
  cascade — lookups can't be "controlled by parent").
- **Validation rule `Exactly_One_Parent`:** error formula
  `ISBLANK(Contact__c) = ISBLANK(Account__c)` — true (blocks save) when **both** blank or **both**
  set; passes only when exactly one is populated. Message: "A tag assignment must link to exactly
  one Contact or one Account."
- **Assignment dedupe:** enforced in the Apex add path (query existing for record+tag); the unique
  `Assignment_Key__c` is the backstop.

### 4.3 Extensibility note
To add a future object (e.g., Opportunity), add `Opportunity__c` lookup + extend the
`Exactly_One_Parent` rule and the `Assignment_Key__c` formula; the LWC already passes
`objectApiName`/`recordId` generically, so the controller maps it to the right lookup via one
`Map<String,String>` (objectApiName → field). No structural rebuild.

---

## 5. UX — the record-page component (LWC)

**Component `tagManager` (LWC)** placed on the Contact and Account Lightning record pages.

- **Inputs:** `@api recordId`, `@api objectApiName` (both provided automatically on a record page).
- **Layout:** a compact card titled "Tags" with (1) a search input and (2) the current tags as
  pills.
- **Type-ahead search:** as the user types (debounced ~300 ms), call
  `searchTags(term)` → returns matching `Tag__c` rows **with category**, ordered by best match
  (starts-with first, then contains), filtered to exclude tags already on the record. Render as a
  dropdown showing **`Tag — Category`**.
- **Apply existing:** click a result → `addTag(tagId, recordId, objectApiName)` → creates a
  `Tag_Assignment__c`; pill appears; `refreshApex` the current-tags list.
- **Create-and-apply (authorized only):** if no exact match, show a "+ Create '<term>'" action
  with a category picker → `createAndAddTag(name, category, recordId, objectApiName)`. Visibility
  of this action is driven by `canCreateTags` (returned from the controller via
  `Tag__c.SObjectType.getDescribe().isCreateable()`), so the permission set controls it.
- **View & remove:** current tags render as `lightning-pill`s grouped/badged by category; the pill
  remove (×) calls `removeAssignment(assignmentId)` → hard delete → refresh.
- **Dedupe UX:** a tag already on the record never appears in search results and can't be added
  twice (also enforced server-side).
- **Empty/edge states:** "No tags yet," no-results → offer create (if authorized), spinner during
  calls, toast on error (FLS/permission).

> **Why LWC over standard related list:** the DoD demands type-ahead/search-or-create with zero
> navigation. A standard related list requires a modal + manual lookup and can't create-on-miss
> inline. (We are explicitly not constrained to standard layouts — User Story note.)

---

## 6. Apex controller `TagManagerController`

Single `with sharing` class, all methods `@AuraEnabled`, **FLS/CRUD-checked** (per CLAUDE.md
security tenet). JCRC's first Apex — header block + method comments per standards; test class
`TagManagerControllerTest` to ≥ 90 %.

| Method | Signature | Behavior |
|---|---|---|
| Search | `searchTags(String term, Id recordId, String objectApiName)` → `List<TagDTO>` (`cacheable=true`) | SOQL `WHERE Name LIKE :('%'+term+'%')` (escaped) ordered starts-with first; excludes tags already assigned to `recordId`; LIMIT ~20. Returns id, name, category. |
| Current tags | `getAssignments(Id recordId, String objectApiName)` → `List<AssignmentDTO>` (`cacheable=true`) | Assignments for the record with Tag name+category; for `refreshApex`. |
| Add existing | `addTag(Id tagId, Id recordId, String objectApiName)` → `AssignmentDTO` | Maps objectApiName→lookup field; guards duplicate (record+tag); inserts assignment. |
| Create + add | `createAndAddTag(String name, String category, Id recordId, String objectApiName)` → `AssignmentDTO` | Case-insensitive reuse (SOQL `=` on Name+Category); insert `Tag__c` if new (sets `Tag_Key__c`); then `addTag`. CRUD-checks Tag create. |
| Remove | `removeAssignment(Id assignmentId)` → `void` | Hard-delete (CRUD-checked). |
| Permissions | `canCreateTags()` → `Boolean` (`cacheable=true`) | `Tag__c.SObjectType.getDescribe().isCreateable()`. |

- **Injection safety:** bind variables only; `String.escapeSingleQuotes` + strip wildcards on the
  search term. **Bulk-safe:** single-record UI calls, but DTO mapping written set-based.
- **objectApiName→field map:** `{'Contact'→'Contact__c','Account'→'Account__c'}` — the one place a
  new taggable object is registered.

---

## 7. Security & sharing

- **Permission set `Tag_Management`:**
  - Object perms: `Tag__c` (Read, **Create**), `Tag_Assignment__c` (Read, Create, **Delete**).
  - FLS: read/edit on the custom fields above.
  - Apex class access: `TagManagerController`.
  - *(Holding this set = can apply **and** create tags. The create affordance auto-hides for users
    without `Tag__c` create.)*
- **Optional two-tier (deferred unless wanted):** a lighter `Tag_User` (apply only, no Tag create)
  vs. `Tag_Management` (create) — note for Jason; default is the single set above per the
  "any user with the permission set can create" decision.
- **OWD:** `Tag__c` Public Read/Write; `Tag_Assignment__c` Public Read/Write (internal). Documented
  as a deliberate choice; revisit if constituent-record confidentiality requires cascade.

---

## 8. Reporting

- **Custom report type `Tag_Assignments_with_Tag` (primary = `Tag_Assignment__c`):** exposes
  Tag (Name, Category), Contact (Name, …), Account (Name, …). One report type covers both because
  the junction holds all three lookups.
- **Reports (folder "Tag Reports"):**
  - **Contacts by Tag** — filter `Contact__c != null`, group by `Tag__c.Category__c` then `Tag__c.Name`.
  - **Accounts by Tag** — filter `Account__c != null`, grouped the same way.
  - Both filterable to a specific tag value → "everyone tagged X." (Report record-type/filter
    gotchas from JSI-82 don't apply here — no RT filtering on the junction.)
- *(Reverse "what tags does this contact have" is the LWC; reporting is the cross-record view.)*

---

## 9. Phased build plan

1. **Objects & fields [CLI]:** `Tag__c` (+ `Category__c`, `Tag_Key__c`) and `Tag_Assignment__c`
   (+ lookups, `Assignment_Key__c`, auto-number); validation rule `Exactly_One_Parent`; OWD.
2. **Dedupe backstop [CLI/Flow]:** before-save Flow (or formula default) populating `Tag_Key__c`
   and `Assignment_Key__c` for non-LWC inserts (imports). *(LWC path sets them in Apex.)*
3. **Apex [CLI]:** `TagManagerController` + `TagManagerControllerTest` (≥ 90 %, FLS/CRUD + dupe
   paths). Deploy.
4. **LWC [CLI]:** `tagManager` component; deploy; add to Contact + Account record pages (confirm
   active page assignment in App Builder).
5. **Security [CLI]:** `Tag_Management` permission set (object/FLS/Apex); assign to test user.
6. **Reporting [CLI]:** `Tag_Assignments_with_Tag` report type + "Contacts by Tag" / "Accounts by
   Tag" reports in a "Tag Reports" folder.
7. **Test & docs:** seed a few tags; end-to-end on a Contact and an Account (search, apply, create
   inline, dedupe, remove, report); runbook (apply/remove + admin retire/merge). Deploy via source;
   commit to repo.

---

## 10. Decisions — resolved 2026-06-24

| # | Decision (locked) |
|---|---|
| 1 | Category = **picklist** on `Tag__c` (not a separate object). |
| 2 | **One** `Tag_Assignment__c` junction, Contact + Account lookups, `Exactly_One_Parent` validation. |
| 3 | Tag creation **permission-set gated**; case-insensitive dedupe; reuse over duplicates. |
| 4 | Remove = **hard-delete** the assignment. |
| 5 | Scope **Contact + Account**, built **extend-ready** (objectApiName→field map). |
| 6 | Tag display extras (color/description) **deferred**. |

**Verify before/at build:** final **`Category__c` value list** with Jason; **active Contact/Account
record page** assignment in App Builder; whether a **two-tier** permission set is wanted; OWD choice
for `Tag_Assignment__c` (Public R/W vs. tighter).

---

## 11. Net-new metadata

| Item | Type |
|------|------|
| `Tag__c` (+ `Category__c`, `Tag_Key__c`) | Custom object + fields |
| `Tag_Assignment__c` (+ `Tag__c`/`Contact__c`/`Account__c` lookups, `Assignment_Key__c`, auto-number) | Custom object + fields |
| `Exactly_One_Parent` | Validation rule (Tag_Assignment__c) |
| `Tag_Key__c` / `Assignment_Key__c` population | Before-save Flow (import safety net) |
| `TagManagerController` + `TagManagerControllerTest` | Apex (JCRC's first) |
| `tagManager` | LWC; added to Contact + Account record pages |
| `Tag_Management` | Permission set |
| `Tag_Assignments_with_Tag` | Custom report type |
| Contacts by Tag, Accounts by Tag (folder "Tag Reports") | Reports |

---

## 12. Risks

- **R1 — Record-page assignment not in metadata:** adding the LWC to the flexipage may not match
  the org's *active* page. **Mitigate:** confirm/assign in App Builder; note for PROD (JSI-82 lesson).
- **R2 — Dedupe race / case:** two users create the same tag at once. **Mitigate:** Apex reuse-check
  **plus** unique case-insensitive `Tag_Key__c` (DB-level catch); handle `DmlException` → reuse.
- **R3 — Tag sprawl despite reuse:** free-text creation can still spawn near-dupes ("Board mbr").
  **Mitigate:** strong type-ahead surfacing + restricted category picklist; admin retire/merge
  runbook; optional later two-tier perm set.
- **R4 — FLS/CRUD gaps (first Apex):** **Mitigate:** `with sharing`, `WITH USER_MODE`/explicit
  `isAccessible/isCreateable` checks, negative tests.
- **R5 — OWD too open/closed:** Public R/W exposes assignments broadly. **Mitigate:** confirm
  constituent-confidentiality needs with Jason; tighten if required.
- **R6 — Junction lookup orphan on parent delete:** deleting a Contact/Account leaves assignments.
  **Mitigate:** lookups clear on parent delete; optionally a cleanup later (low value — hard-delete
  model, cheap rows).

---

## 13. Sources

- Local org review (2026-06-24): `objects/`, `flexipages/`, `permissionsets/`, `sfdx-project.json`.
- JSI-82 plan (`JSI-82_Implementation_Plan.md`) — house format, report/flexipage/FLS gotchas reused.
- Salesforce: LWC on record pages (`recordId`/`objectApiName`), `@AuraEnabled(cacheable=true)` +
  `refreshApex`, case-insensitive unique text fields, junction-via-lookups pattern. *(Cite exact
  Help links in the build log; flag any JS-gated pages for Jason to pull — per working agreement.)*

---

## 14. Build Log

### 2026-06-24 — Phase 1 (objects & fields) + permission set deployed & verified ✅
- **Deployed (deploy `0AfiI0000000rfRSAQ`, 9/9 created):**
  - `Tag__c` (object; OWD ReadWrite; reports+search on) + `Category__c` (restricted picklist:
    Interest, Program, Demographic, Geographic, Skills, Hobbies, Employment, Education, General,
    Other) + `Tag_Key__c` (Text 255, **unique, case-insensitive**, External ID).
  - `Tag_Assignment__c` (object; OWD ReadWrite; auto-number `TA-{0000}`) + `Tag__c` lookup
    (required, delete=Restrict), `Contact__c` lookup (SetNull), `Account__c` lookup (SetNull),
    `Assignment_Key__c` (Text 255, unique, External ID).
  - Validation rule `Exactly_One_Parent`: `ISBLANK(Contact__c) = ISBLANK(Account__c)`.
- **Permission set `Tag_Management`** deployed + assigned to `jcrcny@…dev` (object perms + FLS).
- **Verified in-org** (anonymous Apex in a savepoint→rollback, no data left): tag insert OK;
  case-insensitive `Tag_Key__c` dedupe **blocks** `BOARD MEMBER|GENERAL` vs `board member|general`
  (`DUPLICATE_VALUE`); `Exactly_One_Parent` **blocks** both-blank and both-set
  (`FIELD_CUSTOM_VALIDATION`); Contact-only and Account-only **allowed**.
- **Gotchas resolved:**
  - **Fields deployed without FLS are invisible** to the admin in `FieldDefinition`/describe
    *and* the anonymous-Apex compiler couldn't resolve them — even though the deploy report
    confirmed `created=True` (Tooling API `CustomField` proved server-side existence). Fix:
    deploy the **`Tag_Management` permission set with FLS** (mirrors JSI-82's "deploy FLS with the
    field"). Only the **required** fields (`Category__c`, `Tag__c` lookup) showed before FLS,
    because required fields always carry access.
  - **Required fields can't take `fieldPermissions` in a permission set** ("You cannot deploy to a
    required field") — omit `Category__c` and the required `Tag__c` lookup from FLS.
  - Permission set `description` max length **255**.
  - `sf` relative `--source-dir` didn't resolve from the PowerShell cwd → use **absolute paths**.
- **Next (phase 2+):** before-save Flow to populate `Tag_Key__c`/`Assignment_Key__c` for non-LWC
  inserts; `TagManagerController` + tests; `tagManager` LWC; report type + reports.

### 2026-06-25 — Phases 2–5 deployed & verified ✅
- **Phase 2 — before-save Flows:** `Tag_Set_Tag_Key_Before_Save` (Tag_Key__c = `LOWER(TRIM(Name))+'|'+Category`)
  and `TagAssignment_Set_Key_Before_Save` (Assignment_Key__c = `Tag+'|'+(Contact or Account)`). One
  source of truth for the keys → unique fields enforce dedupe on every path (LWC, import, manual).
  Verified by anon Apex (savepoint): keys stamped; case-insensitive dedupe blocks, different
  category allowed, same-tag-twice blocked.
- **Phase 3 — Apex:** `TagManagerController` (`with sharing`, all SOQL/DML in `USER_MODE` /
  `as user`; `searchTags`/`getAssignments`/`addTag`/`createAndAddTag`/`removeAssignment`/`canCreateTags`;
  `OBJECT_TO_FIELD` map is the one extensibility point) + `TagManagerControllerTest` — **10/10 pass,
  91% coverage**. Duplicate guard simplified to rely on the unique `Assignment_Key__c` +
  `friendly()` (status-code based), which also lifted coverage past 90%. Class access added to the
  permission set. Remaining uncovered lines are defensive race/delete catches.
- **Phase 4 — LWC `tagManager`:** record-page component (Contact + Account targets); type-ahead
  (300 ms debounce) → apply / inline create-and-apply (category combobox via `getPicklistValues`,
  gated by `canCreateTags`) / pills with remove. Deployed.
- **Phase 5 — Reporting:** report type `Tag_Assignments_with_Tag` (base `Tag_Assignment__c`) +
  reports **Contacts by Tag** / **Accounts by Tag** (folder "Tag Reports"), grouped by category → tag.
- **Gotchas resolved (this session):**
  - **Custom report types can't dot-walk parent lookups** — neither the report type
    (`<table>Base.Lookup__r</table>` → "Could not find table for path") nor the report
    (`Base.Lookup__r$Field` → "Invalid field name"). **Fix:** add **cross-object formula fields**
    on the junction (`Tag_Name__c = Tag__r.Name`, `Tag_Category__c = TEXT(Tag__r.Category__c)`),
    expose those base fields, and group/filter on them.
  - Formula field `formulaTreatBlanksAs` enum is **`BlankAsBlank`** (singular), not `BlankAsBlanks`.
  - Each Apex class needs its own **`.cls-meta.xml`** (missing one → "named in package.xml but not
    found in zipped directory").
- **⏳ Carryover for Jason (UI — App Builder):**
  1. **Place the "Tag Manager" component** on the Contact and Account Lightning record pages (LWC
     is exposed; record-page placement/assignment isn't in source metadata — same pattern as JSI-82/89).
  2. **Assign the `Tag_Management` permission set** to the users who should tag (and create tags).
  3. Optional: seed a starter set of tags; add a Tag tab/app nav if desired.
