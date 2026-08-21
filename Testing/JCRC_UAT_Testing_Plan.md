# JCRC — User Acceptance Testing Plan

> **Author:** Jason Ott · **Written:** 2026-08-21
> **Status:** Proposal for review. Nothing has been sent to the client.
>
> **Change Log:**
> - 2026-08-21 — Jason Ott — Initial plan: approach, feature sets, readiness, sequencing.

---

## 1. The problem this plan is built around

Client testing fails in two opposite ways, and both produce the same result — no useful
feedback.

**Too prescriptive.** Give a fundraiser thirty numbered clicks and they will follow those
thirty clicks, watch them work, and conclude the system is fine. They never leave the path
the script laid down, so the script can only confirm what we already knew. The research term
for this is the **happy path**: *"When testers default to the happy path, which is already
covered by scripted test cases, the session generates no new quality signal."*

**Too vague.** Give a non-technical user "please test contact management" and they open
Salesforce, feel lost, click three things, and stop. They will not tell you they gave up;
they will tell you it looked fine.

The fix is not a midpoint between the two. It is **doing both deliberately, and labelling
which is which** — the strongest and most consistent finding in the research:

> *Prepare both formal scripts for business users to run and informal, unstructured scripts as
> well, since the informal scripts are the ones that will pull out defects about how the system
> isn't intuitive to use.*

So every script in this plan has two parts:

| Part | What it is | What it catches |
|---|---|---|
| **Part 1 — Guided scenarios** | Real work, described as a goal and an expected outcome. Enough footing to start, not a click-by-click recipe. | "Does the system do the job at all?" |
| **Part 2 — On your own** | Named **charters** — a specific thing to poke at, with a stated worry, and no instructions. | "Is it right when a real person uses it?" — the defects scripts never find |

---

## 2. What the research says, and how each finding is applied

| Finding | Source | How this plan applies it |
|---|---|---|
| Write in plain, non-technical language; describe the workflow, not the UI | Testsigma, TestMonitor | Scripts say *"record a $500 gift from a new donor"*, never *"click the New button in the Opportunities related list"* |
| A scenario is 5–9 steps with specific test data and an observable outcome | UI Zap UAT scenario guide | Each scenario states the data to use and one clear "you should see" |
| Realistic data and frictionless issue reporting are what stop testers disengaging | TestMonitor | See §5 — the sandbox is nearly empty and this is the single biggest risk to the whole exercise |
| Charter specificity drives session quality — a charter naming a **risk hypothesis** explores territory the scripts have not | TestRail, SD Times | Every charter in Part 2 names the specific worry, e.g. *"we think tributes get confusing when the honoree is already in the database"* |
| Scripted tests assume clean state; exploratory sessions find what happens when earlier steps leave odd state | TestRail | Charters deliberately ask testers to revisit and change records they created earlier |
| UAT should model whole business workflows over time, not single functions | PractiTest | Feature sets are grouped by the fundraiser's job, not by how we built it |

**Sources:**
[Testsigma — UAT test scripts](https://testsigma.com/blog/uat-test-scripts/) ·
[TestMonitor — 5 tips for non-technical users](https://www.testmonitor.com/blog/5-tips-for-making-user-acceptance-testing-easier-for-non-technical-users) ·
[UI Zap — UAT scenario writing guide](https://blog.uizap.com/uat-scenario-writing-guide/) ·
[TestRail — exploratory techniques that find real defects](https://www.testrail.com/blog/perform-exploratory-testing/) ·
[SD Times — exploratory testing for UAT](https://sdtimes.com/test/exploratory-testing-for-uat/) ·
[PractiTest — what is UAT](https://www.practitest.com/resource-center/article/what-is-uat-testing/)

---

## 3. The feature sets

Grouped by **what a fundraiser is trying to do**, not by how it was built. Several stories
usually combine to deliver one job, and some stories appear in more than one set — which is
exactly why testing story-by-story would miss the seams between them.

| # | Feature set | What the tester is doing | Stories covered | Ready? |
|---|---|---|---|---|
| **1** | **Constituents & Relationships** | Finding and creating people and organisations, households, affiliations, relationships, tagging and segmenting | JSI-122, JSI-89 (matching/duplicates), NPSP household model | ⚠️ Ready, but almost no data |
| **2** | **Everyday Giving** | Recording an ordinary gift and seeing it land correctly on the donor | JSI-80, JSI-85, JSI-86, JSI-90 | ✅ Ready |
| **3** | **Pledges & Installments** | A commitment paid over time — schedule, payments, balance, what the donor is told | JSI-82, JSI-125, JSI-126 | ⚠️ Ready except the donor emails (§5) |
| **4** | **Grants** | A grant through its lifecycle, with deliverables and deadlines | JSI-120 | ✅ Ready |
| **5** | **Complex & Non-Cash Gifts** | In-kind, securities, matching gifts, donor-advised funds, and what is tax-deductible | JSI-84, JSI-86, JSI-124, JSI-85 | ✅ Ready |
| **6** | **Tributes & Notifications** | Gifts in honour or memory of someone, and telling the right person | JSI-89 | ✅ Ready |
| **7** | **Thank-Yous & Acknowledgments** | The right letter, to the right person, saying the right thing | JSI-87, JSI-124 | ⚠️ Printed letters ready; email blocked (§5) |
| **8** | **Board Management** | Board service, committees, meetings, attendance, giving commitments | JSI-123, JSI-90 | ✅ Ready — **example script written** |
| **9** | **Gala & Event Gifts** | Tables, seats, guests, meal choices, what portion is deductible | Gala Gifts | ❌ Blocked — client has not supplied levels/prices |
| **10** | **Website Donations** | A gift submitted on jcrcny.org arriving correctly in Salesforce | Website Donations, JSI-127 | ⚠️ Works; needs one client decision (§5) |
| **11** | **Email Marketing & Engagement** | Lists, preferences, who opened what | JSI-107, JSI-108, JSI-109, JSI-50, JSI-55 | ❌ Blocked — no contacts in the CC sandbox |

**Deliberately not a feature set:** *Reports and dashboards.* Reporting is how a fundraiser
checks their own work, so it is tested **inside** each set — "now find this gift on a report"
— rather than as an abstract exercise nobody has context for.

---

## 4. Suggested sequence

Order matters. Later sets depend on records created in earlier ones, which is deliberate —
it is how the seams get tested.

| Round | Sets | Why here |
|---|---|---|
| **1** | 1 Constituents · 2 Everyday Giving | Everything else needs donors and gifts to exist. Also the fastest way to find out whether the basics feel right before anyone invests a day. |
| **2** | 3 Pledges · 5 Complex Gifts · 6 Tributes | The gift types that carry the most policy — deductibility, credit, who gets told |
| **3** | 7 Thank-Yous · 8 Board | Both consume what rounds 1–2 created. Thank-yous especially: they only make sense once there are gifts of different kinds to acknowledge. |
| **4** | 4 Grants · 10 Website Donations | More specialised, fewer testers |
| **5** | 9 Gala · 11 Email Marketing | Once blocked |

---

## 5. Before anyone tests — the honest blockers

These are the things that will waste the client's time if not handled first.

### 🔴 The sandbox is nearly empty — this is the biggest risk

| Object | Records |
|---|---|
| Contacts | **8** |
| Accounts | 18 |
| Opportunities | 13 |
| Payments | 7 |
| Campaigns | 8 |
| Gala Levels | 1 (placeholder) |

A fundraiser cannot test "find the right donor among many" with eight contacts, and every
research source names **realistic data** as a precondition for non-technical testers engaging
at all. Searching, duplicate handling, list views, reports and segmentation are all untestable
at this volume — and worse, they will *look* fine, because with eight contacts everything
works.

**Recommendation:** seed a few hundred realistic constituents, gifts and campaigns before
round 1. I can generate them, but see the questions in §8 — whether it should be scrubbed real
data or invented data is the client's call, not mine.

### 🟠 Donor emails do not reach the inbox

DKIM is not yet active on `jcrcny.org`, so mail sent from Salesforce is **spam-foldered**. It
sends and arrives — in spam. Any test of an email acknowledgment or an installment notification
will read as a failure to a tester who does not know this.

**Recommendation:** either finish DKIM before round 3, or state plainly in the script that
emails land in spam for now and ask testers to check there.

### 🟠 Two client decisions block their own feature sets

- **Gala** — no levels, prices, or deductible splits supplied, so there is nothing meaningful
  to test. `Gala_Level__c` holds one placeholder.
- **Website donations** — designations need to resolve to either a GAU or a Campaign. Until
  JCRC decides, gifts arrive correctly but the money is not allocated to a fund.

### 🟡 Constant Contact has no test population

The sandbox has 8 contacts and the CC sync reports "no contact match" for ~2,300 addresses
every hour. Email marketing cannot be meaningfully tested until there are matching contacts.

---

## 6. How the scripts are written

Every script follows the same shape, so a tester learns the format once:

1. **Why we are asking** — one short paragraph, in their language
2. **What this covers** — plain description of the job being tested
3. **What is behind it** — the stories, for our traceability, and a short technical note
4. **Before you start** — where to log in, which app, what to expect
5. **Part 1 — Guided scenarios** — each with: the situation, what to do, **what you should
   see**, and a box to record what actually happened
6. **Part 2 — On your own** — charters, each naming a specific worry, with no instructions
7. **Anything else** — deliberate space for "this felt awkward" feedback, which is often the
   most valuable thing in the whole exercise
8. **How to tell us** — one channel, low friction

**The rule that makes Part 1 work:** state the **goal and the expected outcome**, never the
clicks. *"Record a $500 gift from Miriam Rosen dated today, designated to the General Fund.
You should see her total giving update and the gift appear on her record."* — not *"click New,
then select Donation, then…"*. If a tester cannot find how to do that, **that is a finding**,
and the click-by-click version would have hidden it.

---

## 7. Capturing what they find

Non-technical testers stop reporting when reporting is work. Options, cheapest first:

| Option | Good | Bad |
|---|---|---|
| **A results table inside each script** (recommended) | Zero new tools; context sits next to the question | Manual to collate; easy to lose in email |
| A shared spreadsheet, one row per scenario | Collates easily; several testers at once | One more place to go |
| A Salesforce object for feedback | Lives with the work; reportable | Testers must be in Salesforce to report a Salesforce problem, which fails when the problem is "I could not log in" |
| Jira direct | Straight into the backlog | Too much for this audience — would suppress reporting |

**Recommendation:** the in-document table for round 1, and reconsider if collation hurts. Ask
for **three fixed things** each time — *what you tried, what you expected, what happened* —
because a report missing any one of those cannot be acted on.

---

## 8. Questions before this goes out

1. **Who is testing, and how many?** The plan assumes a handful of fundraisers rather than one
   person. It changes how the sets are split up.
2. **How much time do they realistically have?** Each script is roughly 45–60 minutes. Eleven
   sets is a lot; the sequence in §4 exists so this can be staged, but I need to know the
   appetite.
3. **Test data — scrubbed real data, or invented?** Real data is far more convincing for a
   fundraiser, but carries donor PII into a sandbox that has a public webhook endpoint.
   Invented data is safe but people test it less carefully. **This is a client decision.**
4. **Is this UAT for sign-off, or exploratory feedback?** It changes the tone of the intro
   and whether we ask for a pass/fail verdict per scenario.
5. **Should testers work in their own Salesforce accounts?** Attribution makes follow-up
   possible and tests permissions realistically. Shared logins would obscure both.
6. **Do you want the results table in the document, or a shared sheet?** §7.

---

## 9. What exists so far

- **This plan** — `Testing/JCRC_UAT_Testing_Plan.md`
- **Example script** — `Testing/Test_Script_08_Board_Management.md`, written in full as the
  format proposal. Board Management was chosen because it is fully built, has real seeded data,
  spans two stories, and is not blocked by DKIM or any pending client decision — so it can be
  sent as soon as the format is approved.

The remaining ten scripts follow once the format and the questions in §8 are settled.
