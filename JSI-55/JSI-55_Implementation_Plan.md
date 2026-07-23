# JSI-55 — Implementation / Verification Plan: Log bulk email sends on constituent record

> **Story:** [JSI-55](https://missionmattersgroup.atlassian.net/browse/JSI-55) · Epic JSI-3 Email Marketing · Should-Have (US-051) · Sprint 2 · Feature Owner **Communications**.
> **Author:** Jason Ott · **Drafted:** 2026-07-21 · Status: **VERIFICATION — recommends CLOSE as "not for implementation" (delivered by JSI-109 + config/training).**
> Per Jason's dictation ("very much the same as JSI-50"), this verifies that bulk-email logging on the constituent record is **already delivered by JSI-109** (the `CC_Email_Activity__c` model), and isolates the one item that could be net-new.

---

## 1. Verdict

**No net-new Salesforce build.** "Logging bulk email sends on the constituent record" is delivered by **JSI-109**: each Constant Contact email a contact received is a `CC_Email_Activity__c` record, surfaced on the Contact via the **`CC_Email_Activities__r` related list**, with subject / send date / opened / clicked. Recommend **closing JSI-55 as not-for-implementation**, contingent on one client clarification (§4).

---

## 2. DoD → delivered (verified in org metadata 2026-07-21)

| DoD item | Delivered by | Evidence |
|---|---|---|
| Email send activity appears on the Contact | **JSI-109** | `CC_Email_Activities__r` related list present on `Contact_Record_Page` (verified) |
| Subject line, send date, engagement (opened/clicked) shown | **JSI-109** | `CC_Email_Activity__c` fields `Email_Subject__c`, `Email_Sent_Date__c`, `Opened__c`, `Clicked__c` (+ counts, status) — verified present |
| Searchable and filterable | **JSI-109** | object `enableSearch=true` (verified) + "Email Engagement by Contact" report + list views |
| Visibility controlled by security profile | **JSI-109** | object OWD Public Read-Only + FLS on Admin + 4 JCRC profiles (poller-maintained fields read-only) |
| Staff trained on checking activity before outreach | **Process** | training — no build |

---

## 3. The "activity history / timeline" reinterpretation (Jason)

The DoD literally says *"appears in the Contact's **activity history**."* In Salesforce that phrase implies the native **Activity timeline** (Tasks/Activities). **Jason's explicit call: that is an AI-generated DoD item and is NOT wanted** — the **`CC_Email_Activity__c` related list is the intended log and suffices** (it's purpose-built, reportable, and doesn't clutter the Activity timeline with one Task per recipient per send, which at bulk scale would be enormous). 

- **So this is a deliberate design decision, not a missing feature.** Logging each send as a native Task/Activity is explicitly **out of scope**.
- *(If the client later insists on the native timeline: that would be net-new — an after-save automation creating an Activity/Task per `CC_Email_Activity__c`, with volume/scale considerations. Not recommended, not planned.)*

---

## 4. The one possible net-new item — DoD "sensitive campaigns" (client decision)

DoD: *"Visibility controlled by security profile for **sensitive campaigns**."*
- **Already true at the profile level:** who can see email engagement is governed by object + FLS on the JCRC profiles (OWD Public Read-Only within staff, not external).
- **Not built:** *per-campaign* sensitivity — i.e., hiding *specific* sends/emails from *some* staff while showing others. That would need a real design (e.g., a `Sensitive__c` flag on `CC_Email__c` + restricted OWD + sharing, or a separate record type/sharing model).
- **Question for the client (Communications):** does "sensitive campaigns" mean *per-campaign restricted visibility*, or just "staff-only, controlled by profile" (which is done)? **Only the former is a build** — and given it's a Should-Have with no concrete sensitive-campaign requirement stated, the recommendation is to **confirm it's not needed and close**, or spin a separate story if it is.

---

## 5. Recommendation
**Close JSI-55 as "not for implementation"** — delivered by JSI-109 (related list + fields + search + profile FLS), plus staff training (Communications). Two confirmations, neither a blocker to closing:
1. The **related list (not native Activity timeline)** is accepted as the "log." *(Jason: yes.)*
2. **"Sensitive campaigns"** means profile-level control (done), not per-campaign restricted sharing — or, if per-campaign is truly required, track it as its own story.

## 6. Sources
- JSI-109 (`../JSI-109/JSI-109_Implementation_Plan.md`) — `CC_Email__c` / `CC_Email_Activity__c` model, Contact related list, reports, FLS.
- Org verification 2026-07-21: `Contact_Record_Page` related list `CC_Email_Activities__r`; `CC_Email_Activity__c` fields (`Email_Subject__c`, `Email_Sent_Date__c`, `Opened__c`, `Clicked__c`, `Status__c`); `enableSearch=true`.
