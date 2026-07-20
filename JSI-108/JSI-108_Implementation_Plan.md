# JSI-108 — Implementation / Verification Plan: Constituent Communication Preference Center

> **Story:** [JSI-108](https://missionmattersgroup.atlassian.net/browse/JSI-108) · Epic JSI-3 Email Marketing · Must-Have (US-047) · Sprint 2 · Feature Owner **Communications**.
> **Author:** Jason Ott · **Drafted:** 2026-07-20 · Status: **VERIFICATION — awaiting one scope decision (DoD #2) before close.**
> Per dictation, this is chiefly a **verify-against-Constant-Contact** story: confirm the preference center is delivered by CC (the project's email provider) and/or already covered by the JSI-107 integration, and close it. This plan maps every DoD item to a capability and isolates the single item that needs a decision.

---

## 1. Scope

**Purpose:** verify that JSI-108's DoD is satisfiable by **Constant Contact configuration** (Communications) + the **JSI-107 integration** + **staff process**, and determine whether **any net-new Salesforce build** is required. Expected outcome (Jason's read): little-to-no Salesforce work.

**Not in scope:** rebuilding a preference center in Salesforce (CC provides one); the CC-side configuration itself is **Communications' to perform** — this plan gives them the checklist.

---

## 2. DoD → capability map (verified against CC features)

| DoD item | Owner | Verified capability |
|---|---|---|
| **1. Preference center with multiple subscription topics** (advocacy, events, fundraising, newsletter) | **CC config** | CC **Update Profile Form** (email-footer link) lets contacts self-manage list membership. Each "topic" = a **CC list** you designate as available on the form. ✅ Native. |
| **2. Preferences stored on the NPSP Contact record and synced to CC** | **DECISION (see §3)** | **Partially covered.** Global opt-out already round-trips via JSI-107 (`HasOptedOutOfEmail`). **Topic-level list memberships flowing CC→SF and stored on the Contact is NOT built** (JSI-107's native connector pushes SF→CC only; the custom poller syncs global opt-out, not per-list memberships). |
| **3. Global + topic-specific unsubscribe** | **CC config** | CC lets contacts unsubscribe from **specific designated lists** or **all**; designated lists appear on the Update Profile + unsubscribe-confirmation pages. ✅ Native. |
| **4. Confirmation page after preference update** | **CC config** | CC Update Profile flow includes a confirm/verify landing page + an unsubscribe confirmation page. ✅ Native. |
| **5. Privacy policy linked from preference center** | **CC config** | CC unsubscribe/profile pages and email footer are customizable/brandable — add the privacy-policy link there. ✅ Config. |
| **6. Staff trained never to override an unsubscribe** | **Process** | Training/policy — no build. Reinforced by JSI-107, which is built to **respect** opt-outs (never re-subscribes without consent). |

**Net:** **4 of 6 = CC configuration** (Communications), **1 = staff process**, **1 = a scoping decision** (DoD #2).

---

## 3. The one open item — DoD #2 (the only possible Salesforce work)

DoD #2 says preferences are *"stored on the NPSP Contact record and synced to Constant Contact."* The comment adds: *"Subscription preferences need to go CC → SF primarily. Should we allow the opposite?"* Interpretation drives whether there's any SF build:

- **Option A — CC is system of record for topic preferences (recommended for "done now"):** Salesforce stores only the **global** email opt-out (`HasOptedOutOfEmail`), which **already syncs CC→SF via JSI-107**. Topic/list memberships live in CC. Satisfies the *spirit* of DoD #2 (opt-out preference stored + synced) with **zero new SF work**. Matches Jason's "nothing to build in Salesforce." Risk: topic-level preferences are not visible/reportable on the SF Contact.
- **Option B — Sync topic/list memberships CC→SF onto the Contact:** extend the JSI-107 poller to pull each contact's `list_memberships` and represent them on the SF Contact (topic checkboxes, a multi-select, or Campaign/CampaignMember). Real SF build + design (which lists = which topics). Delivers full "preferences stored on the Contact." **Blocked** anyway until the JSI-107 CC authorize is cleared.

**✅ DECISION (Jason, 2026-07-20): Option B** — sync topic/list memberships CC→SF and store them on the Contact. So JSI-108 **does** have a net-new Salesforce build (design in §9). **Dependency:** the live CC→SF sync rides on the JSI-107 authorize (blocked on the CC Account Owner) — the SF data model + sync logic + mocked tests can be built now; live verification waits on that authorize.

---

## 4. Verified org context (JCRC-Dev)

- **No topic/subscription-preference fields exist on Contact today** (Contact has `HasOptedOutOfEmail`, `npsp__Do_Not_Contact__c`, `npe01__Preferred_Email__c`, and the JSI-107 `CC_*` fields). NPSP has no native "communication topic" model. So Option B would be net-new; Option A needs nothing.
- **JSI-107 already delivers** the relevant plumbing: native SF→CC list/audience push, and CC→SF **global** opt-out sync (`HasOptedOutOfEmail`) + bounce/subscription-status fields. Topic-level membership sync is *not* in JSI-107's scope.
- **Dependency:** any CC→SF preference sync (Option B) rides on the **JSI-107 authorize**, currently blocked on the CC Account Owner.

---

## 5. Can JSI-108 be marked "Done"?

**Almost — it's a close, not a build, but two conditions must hold first:**
1. **Communications actually configures the CC preference center** (see §6 checklist) — designate topic lists, enable Update Profile link, brand the pages, add the privacy link. Until that's done in CC, the DoD isn't literally met.
2. **DoD #2 decision** (Option A vs B). With **Option A**, there is **no Salesforce build** and the story closes on the CC config + JSI-107's existing opt-out sync + staff training.

So: **nothing for Claude to build in Salesforce under Option A.** The story's completion = a Constant Contact configuration + training task for Communications, which we verify and then mark done.

---

## 6. Constant Contact configuration checklist (for Communications)

To satisfy DoD #1/#3/#4/#5 in CC:
1. Create/confirm **topic lists** (e.g., Advocacy, Events, Fundraising Appeals, Newsletter).
2. In each list's settings, mark it **available on the Update Profile Form / unsubscribe page** so contacts can self-select.
3. Add the **Update Profile** link to email footers (self-service preference center).
4. Ensure the **unsubscribe confirmation** page is enabled and shows the topic lists + a "select which to leave" option (topic-specific opt-out).
5. **Brand** the profile/unsubscribe pages and add the **privacy-policy link**.
6. Confirm **global unsubscribe** is available alongside topic-level.

## 7. Open questions
- **D1 — ✅ RESOLVED (Jason, 2026-07-20): Option B** (sync topic memberships to the Contact). Build design in §9; live sync depends on the JSI-107 authorize.
- **D1b (Jason) — topic-membership model (NEW, blocking the build):** Campaign/CampaignMember vs. a child `Email_Subscription__c` object vs. per-topic checkbox fields (see §9).
- **D2 (Communications):** the actual topic list set (advocacy/events/fundraising/newsletter = final, or a different set?).
- **D3 (from comment):** any need for SF→CC preference writes, or is CC→SF (opt-out, already built) sufficient?
- **D4 (Communications):** privacy-policy URL + branding for the CC pages.
- **D5 (Jason):** confirm Communications has done/will do the §6 CC config before marking the Jira story Done.

## 8. Sources
- CC Update Profile Form / self-service list preferences: https://knowledgebase.constantcontact.com/email-digital-marketing/articles/KnowledgeBase/5778-Let-contacts-update-their-information-and-list-preferences-with-the-Update-Profile-Form
- CC list-specific vs global unsubscribe (designated lists on the confirmation page): Constant Contact community/empowerment-hub "Allowing Subscribers to Unsubscribe from Specific Lists Only"; "Customizing Unsubscription Pages."
- JSI-107 (`../JSI-107/JSI-107_Implementation_Plan.md`) — the CC integration this story leans on (opt-out CC→SF, SF→CC list push).

---

## 9. Option B — Design & Build Plan (chosen path)

**Goal:** each constituent's **topic subscriptions** (which CC lists they're on) are stored on the Salesforce Contact and kept current from Constant Contact (**CC→SF primary**, per the comment).

### 9.1 How to model topic membership on the Contact — **D1b (needs Jason)**
| Option | What it is | Pros | Cons |
|---|---|---|---|
| **(i) Campaign + CampaignMember** *(recommended)* | Each topic = a Salesforce **Campaign** (mapped 1:1 to a CC list); a contact's subscription = a **CampaignMember** (Status = Subscribed/Unsubscribed) | Native + reportable; **unifies with JSI-107** (which already pushes SF Campaigns→CC lists) so topic = Campaign = CC list end-to-end; no per-topic schema; scales to new topics by adding a Campaign | Campaign semantics stretched slightly to "subscription topic"; CampaignMember status upserts |
| **(ii) Child object `Email_Subscription__c`** | One row per Contact×Topic (Topic lookup/picklist + Status + Source) | Purpose-built, flexible, scales; clean history | New object + related list + report type; another thing to maintain |
| **(iii) Per-topic checkbox fields** on Contact | `Topic_Advocacy__c`, `Topic_Events__c`, … | Dead simple; visible inline on the Contact | Not scalable (admin adds a field + automation per new topic); poor for reporting across topics |

**✅ DECISION (Jason, 2026-07-20): (i) Campaign/CampaignMember** — native marketing model, directly reportable, and reuses the JSI-107 Campaign↔CC-list mapping so the topic model is consistent in both directions. A topic list in CC ↔ a Campaign in SF ↔ CampaignMember per constituent.

### 9.2 Build (live sync gated on the JSI-107 authorize)
1. **Topic ↔ CC-list mapping via a Campaign field** — add `Campaign.CC_List_Id__c` (Text, **External ID**) holding the mapped CC list id. The mapping lives **on the Campaign itself** (no separate CMDT): a topic Campaign carries its CC list id, so the poller resolves CC list → Campaign directly. Admin sets it per topic Campaign. + profile FLS.
2. **Extend the JSI-107 client** — add `getListMemberships(sinceCursor)` (CC `GET /contacts?include=list_memberships&updated_after=…`), producing per-contact topic-membership updates.
3. **Extend the applier** — upsert **CampaignMember** (or the chosen model) per contact×topic; reuse the existing SF-Id/email matching; log to `Integration_Log__c` (Operation = a new `Preference Sync` value).
4. **Tests** — `HttpCalloutMock` for the new fetch + applier path (≥90%), no live auth needed.
5. **Verify live** after the JSI-107 authorize clears; schedule alongside the opt-out poller.

### 9.2a Additional deliverables (Jason, 2026-07-20)
- **View-only LWC on the Contact record page** — `contactListSubscriptions`: a clean, read-only display of the constituent's topic subscriptions (their CampaignMembers on CC List campaigns → topic name + status). **No edit controls** — users view only; changes happen in CC and sync back. Apex controller `with sharing`, `USER_MODE`, cacheable.
- **"CC List" Campaign record type + dedicated page** — because Campaigns are used for multiple purposes, add a **`CC List` record type** on Campaign so these subscription-topic campaigns are unmistakable, plus a clean Lightning record page (flexipage) for that record type (CC List Details incl. `CC_List_Id__c` + Campaign Members). Page→record-type assignment is Jason's in App Builder.

### 9.3 Still Communications' side (unchanged from §6)
The CC preference center config (topic lists, Update Profile link, unsubscribe pages, privacy link) — DoD #1/#3/#4/#5 — plus staff training (#6). Option B adds the SF storage/sync for those topic memberships.

**Net for Option B:** SF build = topic model (D1b) + a CC list-membership fetch + applier extension + config mapping + tests. All buildable now **except** the live run, which waits on the JSI-107 CC authorize (same external blocker).

---

## 10. Build Log

**✅ BUILT, DEPLOYED & TESTED 2026-07-20 (not committed). Live CC→SF run pending the JSI-107 authorize.**
- **Schema:** `Campaign.CC_List_Id__c` (Text 50, External ID) mapping a topic Campaign to its CC list; FLS on Admin + 4 JCRC profiles.
- **Record type + view:** Campaign **`CC List`** record type + a dedicated **`Campaign-CC List Layout`** (CC List Details incl. `CC_List_Id__c`, Campaign Members related list), assigned to the record type on all 5 profiles.
- **View-only LWC:** `contactListSubscriptions` + `ContactSubscriptionsController` (`with sharing`, `USER_MODE`, cacheable) — reads a contact's CC List CampaignMembers; **no edit controls**. Expose on Contact record pages (Jason places in App Builder). Test 2/2, 100%.
- **Preference sync (DoD #2):** `ConstantContactClient.getListMemberships` (CC `GET /contacts?include=list_memberships,custom_fields&updated_after=…`) → `ConstantContactSyncService.applyTopicMemberships` reconciles **CampaignMembers** (subscribed→'Subscribed'; left→'Unsubscribed') across CC List campaigns, matched by pushed SF Id / email; `ConstantContactSyncQueueable('PREFERENCE')` orchestrates with an incremental cursor; new `Preference Sync` Operation on `Integration_Log__c`. `HttpCalloutMock` tests. **All JSI-107+108 Apex: 10/10 pass** (Service 93%, Client 97%, Queueable 91%, Schedulable 100%, SubscriptionsController 100%).

**⏳ Jason (UI / config):**
- **Record-type default:** granting `CC List` on the Admin profile made it Admin's *default* Campaign type (metadata can't express "visible, not default" when Master is the only other type). In Setup → Profiles → System Administrator → Campaign record types, **set the default back to Master** (keep CC List visible); enable CC List visibility on **JCRC - Marketing** if they'll create topic Campaigns.
- **Place the `contactListSubscriptions` LWC** on the Contact record page (App Builder).
- **CampaignMemberStatus:** each CC List Campaign needs **`Subscribed`** + **`Unsubscribed`** member statuses (the sync sets these).
- **Topic Campaigns (D2, Communications):** create the topic Campaigns (Advocacy/Events/Fundraising/Newsletter/…) as **CC List** record type and set each one's `CC List ID` to the matching CC list id.

**✅ Jason config VERIFIED 2026-07-20:** CC List Campaign `Salesforce Sandbox` (RT CC List, `CC_List_Id__c`=`caa461ea-…` real CC list UUID); `Subscribed`+`Unsubscribed` member statuses present; `contactListSubscriptions` LWC placed on `Contact_Record_Page`; `CC_List_Compact_Layout` + `Campaign_Record_Page` built; **Campaign RT structure** now Fundraising Campaign (default) / CC List / Event / Master — CC List correctly non-default. Retrieved his page work to source. **End-to-end applier verified against the real campaign** (anon Apex savepoint→rollback): matched a live Contact → created a `Subscribed` CampaignMember on `Salesforce Sandbox` (updated=1, failed=0). Only the live CC *fetch* remains.

**⏳ Blocked (external):** live CC→SF preference sync runs once the **JSI-107 CC authorize** clears (Account Owner). Then: schedule `ConstantContactSyncQueueable('PREFERENCE')` and verify end-to-end.
