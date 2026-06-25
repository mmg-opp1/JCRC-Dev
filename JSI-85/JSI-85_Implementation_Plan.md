# JSI-85 — Implementation Game Plan: Auto-apply Soft Credits for Multi-Party Gifts

> **Status:** Plan only — **no build yet** (per dictation step 6: build after clarifications + plan review).
> **Author:** Jason Ott · **Date:** 2026-06-25
> **Related:** `JSI-85_User_Story.md`, `JSI-85_StoryDictationNotes.MD`
> **Jira:** https://missionmattersgroup.atlassian.net/browse/JSI-85

---

## 1. Scope

**IN scope:** Configure NPSP so soft credits are applied (largely automatically) for the
multi-party gift patterns JCRC has — **household/spouse, employer match, donor-advised fund
(DAF), Benevity, honoree** — define the **soft-credit roles**, ensure totals **roll up to
Contact and Household** without double-counting, deliver **reports** that separate hard vs soft
vs household, and the requested **UI**: user-friendly **Relationship** and **Affiliation**
record pages + a **"Relationships" tab** on the Contact record page.

**OUT of scope (explicit, per dictation):**
- **Exception process documentation** for manual soft credit entry — *client handles.*
- **Staff training** on which credit type to use — *separate training track.*
- **Partial Soft Credits** — client finds them confusing → **not implemented** (see §5).

---

## 2. The key finding — this is ~90% native NPSP (verified in JCRC-Dev metadata)

NPSP already ships the entire soft-credit engine, and the org is largely configured. Verified
against the repo + live org:

| Capability | Native mechanism (verified) | Evidence |
|---|---|---|
| **Spouse / household soft credit** | NPSP auto-creates a **"Household Member"** Opportunity Contact Role (OCR) for every household member when one member gives. | `npo02__Households_Settings__c.Household_Member_Contact_Role__c = "Household Member"`; role is in Soft Credit Roles. |
| **Relationship-driven soft credit** (beyond household) | `npe4__Relationship__c.npsp__Related_Opportunity_Contact_Role__c` — *"When you create an Opportunity for the Contact in this Relationship, NPSP assigns this Opportunity Contact Role to the Related Contact."* Values: **Soft Credit / Solicitor / Tribute**. | field metadata |
| **Corporate / affiliation soft credit** | `npe5__Affiliation__c.npsp__Related_Opportunity_Contact_Role__c` — *"When you create an Opportunity for the **Organization** in this Affiliation, NPSP assigns this … to the affiliated Contact."* Values: **Soft Credit / Solicitor**. Fires when the **org** is the donor → credits the individual. | field metadata |
| **Roll up soft credits to Contact + Household** | **Customizable Rollups** (just enabled) with hard/soft kept as **separate** fields; the **Account Contact Soft Credit** rollup type **de-dupes** by opportunity. | `npsp__Customizable_Rollup_Settings__c.Customizable_Rollups_Enabled__c = true` |
| **Which roles roll up** | `npo02__Households_Settings__c.Soft_Credit_Roles__c = "Matched Donor; Soft Credit; Household Member"` | settings |
| **Org-level soft credit** | `npsp__Account_Soft_Credit__c` (Account, Amount, Opportunity, Role) | object exists |
| **Auto-affiliation creation** | `npe5__Affiliations_Settings__c.Automatic_Affiliation_Creation_Turned_On__c = true` | settings |

**Implication:** the bulk of the build is **configuration + a small amount of automation to set
defaults**, plus the requested UI and reports — **not** custom credit-calculation code.

### 2.1 Gaps found (must fix — these are the real work)

1. **🔴 Opportunity Contact Role "Role" picklist still has only the stock *Sales* values**
   (Business User, Decision Maker, Economic Buyer, …) — **none** of the NPSP fundraising roles
   (Donor, Household Member, Soft Credit, Matched Donor, Solicitor, Tribute/Honoree) are in the
   picklist, even though the Household settings already reference "Matched Donor; Soft Credit;
   Household Member" as soft-credit roles. **NPSP's auto-roles set the role as text, but the
   picklist must include these values** for manual entry, reporting, and consistency. → Add the
   NPSP roles.
2. **No Relationship or Affiliation Lightning record pages** exist (`flexipages/`); they use the
   default page. → Build user-friendly pages (dictation request).
3. **Contact page has no Relationships tab** (`Contact_Record_Page` tabs = Related Lists, Details,
   Work Information, Activity, Collaborate). → Add a **Relationships** tab.
4. **Spouse soft-credit path** — *(resolved)* household membership and a Relationship role don't
   produce a duplicate (NPSP precedence picks one — §4.1). **Decided: use Household Member (Q3).**

---

## 3. Requirement (DoD) → mechanism

| DoD item | Mechanism | Native? |
|---|---|---|
| Soft credit roles defined (spouse, employer match, DAF advisor, honoree) | Add values to **OpportunityContactRole.Role** + set **Soft Credit Roles** | config |
| Automation creates soft credits from relationships | **Household auto-OCR** + **Relationship/Affiliation Related OCR** fields (+ default automation, §4/§7) | native + small automation |
| Roll up to Contact + Household | **Already native — 16 soft-credit rollups on Contact ship OOTB** (verified). Household-level soft-credit rollup is the only possible addition (Q7). | **native (no build)** |
| Reports separate hard / soft / household | Reports on OCR (filtered by role) + Opportunity hard credit + household account rollups | native |

---

## 4. Scenario design

> ### NPSP OCR Order of Precedence (resolves the "multiple soft credits" worry)
> NPSP creates **only ONE Opportunity Contact Role per contact per opportunity**, by this
> precedence (from the official *Logic for Creating OCRs* doc Jason pulled): **Primary Contact →
> Honoree → Notification Recipient → Affiliated/Related Contact → Household Member.** So a contact
> who qualifies for several never gets stacked roles — NPSP picks the highest. This is the direct
> answer to **MAF's "multiple soft credits for one gift"** concern: it doesn't happen.

### 4.1 Spouse / household — **DECIDED: use Household Member (Q3)**
- **Same household:** rely on **NPSP Household Member auto-OCR** — when Jason gives, Margaret
  automatically gets a *Household Member* soft-credit OCR (rolls up). **No per-record setup.**
- **Important (precedence):** if a same-household spouse *also* had a Relationship with
  `Related_Opportunity_Contact_Role = Soft Credit`, NPSP would create **one** OCR (the Relationship
  "Soft Credit" **wins** over Household Member) — **not a duplicate**. So there's no double-OCR bug;
  it only changes *which* soft-credit role shows. **Per Q3 we keep spouses on Household membership**
  (don't set a Relationship role for them). Reserve the **Relationship** soft-credit path for
  relations **outside** the household (e.g., an adult child in their own household).
- ✅ **Household roll-up de-dupe (verified in the doc):** with **Customizable Rollups**, the
  **Account (Contact Soft Credit)** rollup type **does not double-count** — *"if Dante and Terrance
  each received a $500 soft credit, the field will only show $500."* Hard and soft live in
  **separate** household fields. **No silent double count.**

### 4.2 Employer match — **DECIDED: soft-credit the individual (Q1)**
- **Donation** opportunity from the individual (Jason) — hard credit Jason.
- **Matching Gift** opportunity (record type **Matching Gift**, already exists) with the
  **corporation (MMG)** as the Account — hard credit MMG.
- **Link:** on the **Donation**, `npsp__Matching_Gift__c` is a **lookup to the Matching Gift
  opportunity** (verified field). `npsp__Matching_Gift_Account__c` / `_Employer__c` / `_Status__c`
  (Potential/Submitted/Received) round it out.
- **Soft-credit mechanism (build):** a **record-triggered Flow on Opportunity (Donation)** —
  **when `npsp__Matching_Gift__c` becomes populated**, create an **OpportunityContactRole on the
  linked Matching Gift opportunity** for the **Donation's Primary Contact** with role **"Matched
  Donor"** (already a soft-credit role in the Soft Credit Roles setting). Result: Jason gets a soft
  credit on MMG's matching gift. Guard against duplicates (don't re-add if the OCR already exists).
  - *NPSP's "Find & Create Matched Gifts" utility is how matching gifts get created/linked; the Flow
    ensures the matched-donor soft credit regardless of how the link is set.*

### 4.3 Donor-Advised Fund (DAF) — **recommend "DAF as Payment Method"**
Per the accountant ("don't hard-credit the fund; credit the individual; must match accounting,
no reconciliation issues"), use **Option 2** from the [Soliant NPSP DAF guide](https://www.soliantconsulting.com/blog/salesforce-blog/donor-advised-funds-salesforce-npsp/):
- **Opportunity Account = the individual** (their household) → **hard credit the donor** (Jason).
- Add **"DAF"** to the **Payment Method** picklist (so the gift is identifiable as a DAF gift);
  optionally a **"DAF Sponsor"** reference field (text/lookup) for reporting on which fund.
- The DAF sponsor (Schwab/JCF) is **reference only** — no hard or soft credit (matches accounting).
- **Tax-deductibility is NOT part of this story.** It is an **amount** handled by **JSI-86**
  (`Deductible_Amount__c` / `Non_Deductible_Amount__c`) — *not* a payment-method-driven checkbox.
  For a DAF gift, staff set the non-deductible amount per JSI-86 if/as needed; JSI-85 adds **no**
  deductibility field or automation.
- *(Alternative "Option 1" — DAF org as Account + donor soft credit — is the textbook approach but
  it's what the accountant explicitly does NOT want, and it complicates development reporting.)*

### 4.4 Benevity (workplace giving)
- Accountant treats it like a DAF: **hard credit the individual donor** (it's their money), **not
  Benevity**. → Same model as §4.3: individual hard credit; "Benevity" as a Payment Method value;
  Benevity is reference only. No credit to Benevity.

### 4.5 Honoree / Tribute — **DECIDED: tracked, not rolled up (Q5)**
- **Honoree** is a Contact Role but is **excluded** from soft-credit rollups (an honoree didn't
  give). NPSP also exposes **Tribute** as a Related OCR value. (Tribute capture itself is JSI-89.)

### 4.6 Partial soft credits — **not implemented**
Partial Soft Credits split one check across multiple donors (e.g., a Benevity/Facebook
disbursement list, each donor credited their portion). **Client declined as confusing.** We will
**not** configure them; Benevity is handled per §4.4 instead.

---

## 5. Soft-credit roles & rollup config

1. **Add the standard NPSP OOTB roles to `OpportunityContactRole.Role`** (per Q4 — "use whatever
   the standard NPSP roles are; configure the rest later"). The documented out-of-the-box set:
   **Donor** (hard), **Household Member**, **Soft Credit**, **Matched Donor**, **Honoree**,
   **Notification Recipient**, **Grant Manager**, **Decision Maker**, **Influencer**, **Solicitor**,
   **Workplace Giving**, **Other**. *(Standard picklist — confirm deployability; managed-context
   picklists sometimes need a UI edit, like JSI-80's Payment Method.)*
2. **Soft Credit Roles setting** (which roles roll up) — keep the current, correct set: **Soft
   Credit; Household Member; Matched Donor**. **Exclude** Honoree (Q5 — tracked, not rolled up),
   Solicitor, Notification Recipient, etc. (Customizable Rollups uses **Filter Groups/Rules** to
   define which OCR roles count — configure the soft-credit filter group to these three roles.)
3. **Customizable Rollups — already exist; do NOT rebuild** (Jason's correction, verified in org):
   NPSP ships **16 soft-credit Customizable Rollups, all on Contact** (Total/First/Last/Largest/
   this-year/count/etc.) out of **87** total rollups. **No Contact rollups to build.** Work here is
   only: (a) **verify the soft-credit Filter Group/Rule** includes our roles (Soft Credit, Household
   Member, Matched Donor) so the right OCRs count, and (b) **optionally** add **one** *Account
   (Contact Soft Credit)* rollup to the **Household Account** **only if** the client wants a
   household-level soft-credit total — **0 Account soft-credit rollups exist today**. That single
   rollup is **gated on Q7** (pinned). Hard and soft stay separate fields regardless.

---

## 6. UI — Relationship & Affiliation pages + Contact "Relationships" tab (dictation request)

### 6.1 Relationship & Affiliation Lightning record pages (net-new flexipages)
Build clean record pages (none exist today) emphasizing the fields that drive soft credits:
- **Relationship page:** Contact, Related Contact, Type, Status, **Related Opportunity Contact
  Role** (the soft-credit driver — make it prominent with help text), Description.
- **Affiliation page:** Contact, Organization, Role, Primary, Start/End Date, Status, **Related
  Opportunity Contact Role**.
- Match the org's existing flexipage conventions (see JSI-89 — Pledge/Grant pattern, dynamic
  highlights, path where relevant).

### 6.2 Contact "Relationships" tab
- Add a **"Relationships"** tab to the active Contact record page (`Contact_Record_Page` — uses
  `recordHomeTemplateDesktop`; **confirm which Contact page is assigned** — two exist:
  `Contact_Record_Page` and `Contact_Record_Page_Three_Column`).
- On that tab, add **two `force:relatedListSingleContainer` (dynamic related list) components**:
  - **Relationships** → related list **`npe4__Relationships__r`** (Contact's relationships)
  - **Affiliations** → related list **`npe5__Affiliations__r`**
- Tab sits **separate** from Details and the standard Related-lists tab (per dictation).

---

## 7. Automation (small, only where native defaults fall short)
- **Default the Relationship/Affiliation soft-credit role:** so staff don't hand-set it each time
  for the patterns we want auto-credited, a **record-triggered Flow** can default
  `Related_Opportunity_Contact_Role = Soft Credit` on qualifying records (e.g., spouse
  relationships **outside** the household, or affiliations flagged for matching). **Scope TBD by
  §9 answers** — may not be needed if household membership covers spouses and affiliations are set
  per-case. Keep automation minimal; prefer native settings.
- **Matched Donor OCR** Flow (§4.2) — the one automation this story definitely needs.

---

## 8. Reports (DoD: distinguish hard / soft / household)
- **Hard Credit report** — Opportunities by donor (Account/Primary Contact).
- **Soft Credit report** — Opportunity Contact Roles filtered to Soft Credit Roles (Soft Credit /
  Household Member / Matched Donor), grouped by Contact.
- **Household giving** — Household Account hard + soft rollup fields side by side.
- **DAF / Benevity report** — Opportunities by Payment Method (or DAF Sponsor field).
- Follow the JSI-82/89 report patterns (version-controlled `report-meta.xml`).

---

## 9. Decisions (resolved 2026-06-25 by Jason)

| # | Question | **Decision** |
|---|---|---|
| 1 | Employer match → soft-credit the individual? | ✅ **Yes.** Flow: when Donation `npsp__Matching_Gift__c` is set, add a **Matched Donor** OCR for the donation's primary contact on the matching-gift opp (§4.2). |
| 2 | DAF model = "DAF as Payment Method"? | ✅ **Yes** — "as good a method as any for now." Hard-credit individual; fund = reference (§4.3). |
| 3 | Spouse soft credit via Household (not Relationship)? | ✅ **Yes** — use Household Member (§4.1). |
| 4 | Which non-soft-credit roles to track? | ✅ **Use the standard NPSP OOTB roles** (§5.1); configure/adjust later as needed. |
| 5 | Honoree rolls up as soft credit? | ✅ **No** — Honoree is a Contact Role but **excluded** from soft-credit rollups. |
| 6 | Benevity = same as DAF? | ✅ **Yes** (§4.4). |
| 7 | Combined "Total Giving (Hard + Soft)" vs separate? | 📌 **PINNED — Jason to confirm with client.** Build hard/soft separate now; add combined later if wanted. |

**Still needs a client answer before that piece builds:** only **Q7** (combined total). Everything
else is locked — the story is ready to build on Jason's go-ahead.

---

## 10. Net-new metadata (anticipated — pending §9)

| Item | Type | Lane |
|---|---|---|
| NPSP roles on `OpportunityContactRole.Role` | Picklist values | UI or CLI (confirm) |
| Soft Credit Roles setting | NPSP setting | UI |
| ~~Contact soft-credit rollups~~ — **already exist (16 OOTB), do not build** | — | — |
| *Optional* single Household *Account (Contact Soft Credit)* rollup | NPSP CRLP (`npsp__Rollup__mdt`) | UI (then retrieve) — **gated on Q7** |
| Payment Method: add **DAF**, **Benevity** | Picklist (managed `npe01`) | UI (per JSI-80) |
| *Optional* **DAF/Benevity Sponsor** reference field (for reporting) | Custom field | CLI |
| ~~Tax-Deductible field / automation~~ — **NOT this story; deductibility = amount, owned by JSI-86** | — | — |
| Relationship & Affiliation record pages | FlexiPages | CLI |
| Contact "Relationships" tab (Relationships + Affiliations related lists) | FlexiPage edit | CLI (confirm which Contact page is assigned) |
| Optional role-defaulting automation | Record-triggered Flow | CLI |
| Hard / Soft / Household / DAF reports | Reports | CLI |

---

## 11. Research sources & access notes (per "flag JS-gated")

**Used:**
- ✅ **[`Soft_Credit_Documentation.MD`](./Soft_Credit_Documentation.MD)** — **the authoritative
  Salesforce Help / Trailhead content Jason pulled** (Customizable Rollups & Soft Credits, Configure
  Automated/Manual Soft Credits, **Logic for Creating OCRs / order of precedence**, Set up / Manage
  Soft Credits). This is the primary source for §4.1 precedence, §5 roles, and the de-dupe behavior.
- ✅ [Soliant — Tracking DAFs in NPSP](https://www.soliantconsulting.com/blog/salesforce-blog/donor-advised-funds-salesforce-npsp/) — the two DAF methods (drove §4.3).
- ✅ [Salesforce Ben — Guide to NPSP Soft Credits](https://www.salesforceben.com/guide-to-salesforce-npsp-soft-credits/).

**Access notes (per "flag JS-gated"):**
- 🚫 **`help.salesforce.com`** + **Trailhead** soft-credit pages — **JS-gated** (CSS-error shell to
  WebFetch). **Jason pulled the needed content into `Soft_Credit_Documentation.MD`.**
- 🚫 **`sforgdocs.com`** NPSP-docs mirror — **dead (404)** per Jason; do not rely on it.

**Verified directly in the org (not assumed):** Customizable Rollups enabled; Soft Credit Roles =
"Matched Donor; Soft Credit; Household Member"; Household Member role = "Household Member";
auto-affiliation on; Relationship/Affiliation `Related_Opportunity_Contact_Role` picklists & help
text; OCR Role picklist = stock Sales values (gap); related lists `npe4__Relationships__r` /
`npe5__Affiliations__r`; two Contact record pages; Matching Gift record type + matching-gift fields.

---

## 12. Build status — CLI build DONE & deployed 2026-06-25

**✅ Built & deployed to JCRC-Dev (CLI):**
- **`Opportunity_MatchedDonor_SoftCredit`** flow — when a Donation's `npsp__Matching_Gift__c` is
  set, adds a **Matched Donor** OCR for the donation's Primary Contact onto the matching-gift opp;
  duplicate-guarded. **Verified** via anon-apex savepoint test (OCR created w/ role "Matched Donor";
  no duplicate on re-update).
- **`Relationship_Record_Page`** + **`Affiliation_Record_Page`** flexipages — user-friendly pages
  leading with the **Related Opportunity Contact Role** soft-credit field.
- **`Contact_Record_Page`** — new **"Relationships" tab** with dynamic related lists for
  **Relationships** (`npe4__Relationships__r`) + **Affiliations** (`npe5__Affiliations__r`).
- **Soft Credit Reports** folder + 2 reports: **Donations by Donor (Hard Credit)** and **Contact
  Giving — Hard, Soft & Household** (native rollups `npo02__TotalOppAmount__c` /
  `npo02__Soft_Credit_Total__c` / `npo02__OppAmount{This,Last}YearHH__c`).

**⏳ Jason — UI steps (cannot be done via metadata / NPSP-managed):**
1. **OCR Role picklist** — Setup → *Contact Roles on Opportunities* → add **Donor** (default),
   **Household Member, Soft Credit, Matched Donor, Honoree, Notification Recipient, Grant Manager,
   Workplace Giving, Solicitor**. *(Metadata insert is blocked: "insert isn't supported for the
   standard value set OpportunityContactRole.")* The Matched Donor flow already works (picklist is
   unrestricted) but add the value so it's officially selectable.
2. **Payment Method** — add **DAF** and **Benevity** (managed `npe01` field; UI per JSI-80).
3. **Verify** the soft-credit **Customizable Rollup Filter Group** includes roles **Soft Credit;
   Household Member; Matched Donor** (so they count). Confirm **Household Member auto-OCR** is ON
   (NPSP Settings → Donations | Contact Roles).
4. **Assign** the new **Relationship** & **Affiliation** record pages (Lightning page Activation);
   **confirm `Contact_Record_Page` is the active Contact page** (the tab was added there; if
   `Contact_Record_Page_Three_Column` is active instead, say so and I'll move it).

**Open / deferred:** Q7 (combined Hard+Soft total → optional single Household *Account (Contact
Soft Credit)* rollup); optional **DAF Sponsor** reference field (CLI, on request). **Not committed
to git.**
