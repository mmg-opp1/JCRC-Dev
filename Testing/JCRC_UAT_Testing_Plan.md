# JCRC — User Acceptance Testing Plan

> **Author:** Jason Ott · **Written:** 2026-08-21
> **Status:** Proposal for review. Nothing has been sent to the client.
>
> **Change Log:**
> - 2026-08-21 — Jason Ott — Initial plan: approach, feature sets, readiness, sequencing.
> - 2026-08-21 — Jason Ott — Rebuilt for **formal sign-off** with **3–4 JCRC testers**;
>   test data seeded, so the data blocker is closed.

---

## 1. What this is for

JCRC is being asked to **accept** the system, not to browse it. That word changes the design of
everything below: every scenario ends in a recorded verdict, every problem gets a severity, and
each feature set ends with a named person signing that it is fit to go live.

But acceptance testing has a well-known failure mode, and it is worth naming up front because
this plan is built to avoid it.

**Sign-off pressure pushes testers toward "pass."** A tester who knows that "fail" delays
go-live will follow the steps, watch them work, tick the box, and move on. They never leave the
path the script laid down, so the script can only confirm what we already knew. The research
term is the **happy path**: *"When testers default to the happy path, which is already covered
by scripted test cases, the session generates no new quality signal."*

The opposite failure is just as real. Give a non-technical user "please test contact management"
and they open Salesforce, feel lost, click three things and stop. They will not tell you they
gave up; they will tell you it looked fine.

The fix is not a midpoint. It is **doing both deliberately, and labelling which is which** — the
strongest and most consistent finding in the research:

> *Prepare both formal scripts for business users to run and informal, unstructured scripts as
> well, since the informal scripts are the ones that will pull out defects about how the system
> isn't intuitive to use.*

So every script has two parts, and under a sign-off model they do different jobs:

| Part | What it is | Its role in sign-off |
|---|---|---|
| **Part 1 — Guided scenarios** | Real work, described as a goal and an expected outcome. Enough footing to start, not a click-by-click recipe. | **Produces the verdict.** Each scenario is passed or failed. |
| **Part 2 — Before you sign** | Named **charters** — a specific thing to poke at, with a stated worry, and no instructions. | **Informs the verdict.** Findings here set severity and any conditions attached to acceptance. |

Part 2 is not optional garnish. Signing off on a system you have only used along a scripted path
is how organisations accept software they later cannot work with.

---

## 2. What the research says, and how each finding is applied

| Finding | Source | How this plan applies it |
|---|---|---|
| Write in plain, non-technical language; describe the workflow, not the UI | Testsigma, TestMonitor | Scripts say *"record a $500 gift from a new donor"*, never *"click the New button in the Opportunities related list"* |
| A scenario is 5–9 steps with specific test data and an observable outcome | UI Zap UAT scenario guide | Each scenario states the data to use and one clear "you should see" |
| Realistic data and frictionless issue reporting are what stop testers disengaging | TestMonitor | See §6 — resolved; the sandbox now holds 180 constituents and 443 gifts |
| Charter specificity drives session quality — a charter naming a **risk hypothesis** explores territory the scripts have not | TestRail, SD Times | Every charter names the specific worry, e.g. *"we think tributes get confusing when the honoree is already in the database"* |
| Scripted tests assume clean state; exploratory sessions find what happens when earlier steps leave odd state | TestRail | Charters deliberately ask testers to revisit and change records they created earlier |
| UAT should model whole business workflows over time, not single functions | PractiTest | Feature sets are grouped by the fundraiser's job, not by how we built it |
| Acceptance needs an explicit, recorded decision and a defect severity scale, or "done" is a matter of opinion | PractiTest, TestMonitor | §4 — three verdicts, three severities, one signature per feature set |

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
| **1** | **Constituents & Relationships** | Finding and creating people and organisations, households, affiliations, relationships, tagging and segmenting | JSI-122, JSI-89, NPSP household model | ✅ Ready |
| **2** | **Everyday Giving** | Recording an ordinary gift and seeing it land correctly on the donor | JSI-80, JSI-85, JSI-86, JSI-90 | ✅ Ready |
| **3** | **Pledges & Installments** | A commitment paid over time — schedule, payments, balance, what the donor is told | JSI-82, JSI-125, JSI-126 | ⚠️ Ready; donor emails land in spam (§6) |
| **4** | **Grants** | A grant through its lifecycle, with deliverables and deadlines | JSI-120 | ✅ Ready |
| **5** | **Complex & Non-Cash Gifts** | In-kind, securities, matching gifts, donor-advised funds, and what is tax-deductible | JSI-84, JSI-86, JSI-124, JSI-85 | ✅ Ready |
| **6** | **Tributes & Notifications** | Gifts in honour or memory of someone, and telling the right person | JSI-89 | ✅ Ready |
| **7** | **Thank-Yous & Acknowledgments** | The right letter, to the right person, saying the right thing | JSI-87, JSI-124 | ⚠️ Printed letters ready; email lands in spam (§6) |
| **8** | **Board Management** | Board service, committees, meetings, attendance, giving commitments | JSI-123, JSI-90 | ✅ Ready — **example script written** |
| **9** | **Gala & Event Gifts** | Tables, seats, guests, meal choices, what portion is deductible | Gala Gifts | ❌ Blocked — client has not supplied levels/prices |
| **10** | **Website Donations** | A gift submitted on jcrcny.org arriving correctly in Salesforce | Website Donations, JSI-127 | ⚠️ Works; needs one client decision (§6) |
| **11** | **Email Marketing & Engagement** | Lists, preferences, who opened what | JSI-107, JSI-108, JSI-109, JSI-50, JSI-55 | ❌ Blocked — no contacts in the CC sandbox |

**Deliberately not a feature set:** *Reports and dashboards.* Reporting is how a fundraiser
checks their own work, so it is tested **inside** each set — "now find this gift on a report" —
rather than as an abstract exercise nobody has context for.

---

## 4. What sign-off means

### Verdict — recorded on every scenario

| Verdict | Meaning |
|---|---|
| **Pass** | It did what the script said it would. Nothing to raise. |
| **Pass with comments** | It worked, but something about it is wrong — wording, an extra step, a missing field. Does not block acceptance; goes on the list. |
| **Fail** | It did not work, or it produced the wrong result, or the tester could not find how to do it. |

**"I could not work out how to do that" is a Fail, not a tester error.** This needs saying
explicitly and repeatedly, because non-technical testers reliably blame themselves. If a
fundraiser cannot find the function, the function is not delivered.

### Severity — applied to anything that is not a clean Pass

| Severity | Definition | Effect on go-live |
|---|---|---|
| 🔴 **Blocker** | Work JCRC does routinely is impossible, or the system produces a wrong number that someone would act on | **Cannot go live** |
| 🟠 **Major** | Works, but painfully or partially. A workaround exists and is tolerable for a short period | Go live; fix on an agreed date |
| 🟡 **Minor** | Wording, layout, convenience, a preference | Go live; backlog |

Wrong money is always a Blocker. A gift that lands under the wrong donor, a receipt with the
wrong deductible amount, or a report that under-counts is not a "Major" however small it looks
on screen — those numbers go to donors and to the board.

### Outcome — recorded once per feature set, with a name against it

| Outcome | Condition |
|---|---|
| **Accepted** | No Blockers, no Majors |
| **Accepted with conditions** | No Blockers. Majors listed, each with an agreed fix date |
| **Not accepted** | One or more Blockers |

Each script ends with a sign-off block naming the person, their role, the date, the outcome and
any conditions. **One named person signs each feature set** — shared or anonymous sign-off means
nobody actually reviewed it.

---

## 5. Who tests what

Four testers, each owning whole feature sets end to end. Ownership matters more than coverage:
a person who tests one area properly finds more than four people sampling everything.

Assignments are by **role affinity** — the person whose real job the set describes. Map these
archetypes to actual JCRC names before sending.

| Tester | Role archetype | Feature sets | Rough time |
|---|---|---|---|
| **A** | Gift entry / development associate | 2 Everyday Giving · 5 Complex & Non-Cash Gifts · 6 Tributes | ~2½ hrs |
| **B** | Major gifts / development director | 3 Pledges & Installments · 7 Thank-Yous · 4 Grants | ~2½ hrs |
| **C** | Database / operations | 1 Constituents & Relationships · 10 Website Donations | ~2 hrs |
| **D** | Board liaison / executive office | 8 Board Management · **second pass on** 1 Constituents | ~2 hrs |

**Why Constituents is tested twice.** It is the screen everyone touches every day, and the one
where "obvious" is most in the eye of the beholder. Two testers disagreeing about it is a more
useful signal than one tester approving it. Tester C signs it; Tester D's findings are attached.

**If only three testers are available:** drop Tester D and give Board Management to Tester B,
who is closest to it. Do not spread D's sets across everyone — that reproduces the sampling
problem above.

**Each tester needs their own login.** Shared logins make follow-up impossible ("who saw that?")
and hide permission problems, which for a sign-off is a gap that matters — a tester who can see
everything cannot tell you that a colleague will not be able to.

---

## 6. Before anyone tests

### ✅ Resolved — the sandbox now has realistic data

This was the biggest risk to the whole exercise and it is closed. The sandbox held 8 contacts
and 13 gifts; searching, duplicate handling, list views, segmentation and reports were all
untestable at that volume — and worse, they *looked* fine, because with eight contacts
everything works.

| | Before | Now |
|---|---|---|
| Constituents | 8 | **180** |
| Accounts (incl. households) | 18 | **210** |
| Gifts | 13 | **443** |
| Pledge installments | 7 | **127** |
| Campaigns | 8 | **16** |
| Tags / affiliations / relationships | ~0 | **220 / 64 / 60** |

The data is **invented**, per JCRC's decision — no real donor PII in a sandbox that has a public
webhook endpoint. Some properties worth knowing, because testers will ask:

- **Names are assembled, not copied.** Any resemblance to a real donor is coincidence. Two
  constituents share a name on purpose, as a duplicate-handling fixture.
- **No seeded donor can receive email.** Every address is at `example.com`, reserved by RFC 2606
  and holding no MX record. The org has live email automation; this is deliberate.
- **The giving pyramid is realistic.** 15 donors reach a giving society — 2 President's,
  3 Governor's, 4 Senate, 6 Congressional in each of the last two fiscal years — against a long
  tail of $18–$250 gifts. Roughly 9% major donors, which is what a real file looks like.
- **Pledges are in five different states**: on schedule, fully paid, overdue, partly written off,
  not yet started. 30 installments are overdue, totalling $120,750.
- **Coverage is deliberately patchy.** About a third of constituents have no tags and two thirds
  have no employer, because a real database is uneven and testers should meet thin records too.

### 🟠 Donor emails arrive in the spam folder

DKIM is not yet active on `jcrcny.org`, so mail from Salesforce is spam-foldered. It sends and
arrives — in spam. A tester who does not know this will record a **Fail** on any email
acknowledgment or installment notification, and under a sign-off model that Fail blocks
acceptance of two feature sets.

**Do one of these before round 3:** finish DKIM, or state it plainly in the scripts and ask
testers to check spam. Leaving it unsaid is the worst option.

### 🟠 Two client decisions block their own feature sets

- **Gala** — no levels, prices or deductible splits supplied, so there is nothing meaningful to
  test. `Gala_Level__c` holds one placeholder.
- **Website donations** — designations need to resolve to either a GAU or a Campaign. Until JCRC
  decides, gifts arrive correctly but the money is not allocated to a fund.

### 🟡 Constant Contact has no test population

The CC sandbox reports "no contact match" for ~2,300 addresses every hour. The seeded
constituents do not exist in Constant Contact, so this remains blocked.

### 🟡 One activation still outstanding

The **Development Home** page must be activated in the Lightning App Builder. Page activation is
a UI setting that does not travel in metadata, so it needs doing by hand in the sandbox.

---

## 7. Suggested sequence

Order matters. Later sets depend on records created in earlier ones, which is deliberate — it is
how the seams get tested.

| Round | Sets | Why here |
|---|---|---|
| **1** | 1 Constituents · 2 Everyday Giving | Everything else needs donors and gifts. Also the fastest way to learn whether the basics feel right before anyone invests a day. |
| **2** | 3 Pledges · 5 Complex Gifts · 6 Tributes | The gift types carrying the most policy — deductibility, credit, who gets told |
| **3** | 7 Thank-Yous · 8 Board | Both consume what rounds 1–2 created. Thank-yous especially: they only make sense once gifts of different kinds exist to acknowledge. |
| **4** | 4 Grants · 10 Website Donations | More specialised, fewer testers |
| **5** | 9 Gala · 11 Email Marketing | Once unblocked |

**Round 1 should be reviewed before round 2 starts.** If the basics are wrong, everything
downstream is testing on a bad foundation, and re-testing costs more than the pause.

---

## 8. Capturing what they find

Non-technical testers stop reporting when reporting is work.

| Option | Good | Bad |
|---|---|---|
| **A results table inside each script** (recommended) | Zero new tools; context sits next to the question; the verdict and the sign-off live in one document | Manual to collate |
| A shared spreadsheet, one row per scenario | Collates easily; several testers at once | One more place to go; sign-off has no natural home |
| A Salesforce object for feedback | Lives with the work; reportable | Testers must be in Salesforce to report a Salesforce problem, which fails exactly when the problem is "I could not log in" |
| Jira direct | Straight into the backlog | Too much for this audience — would suppress reporting |

**Recommendation:** the in-document table. Under a sign-off model it is clearly right — the
evidence and the signature belong in the same artefact, and that document is the record of what
JCRC accepted.

Ask for **three fixed things** on anything that is not a Pass — *what you tried, what you
expected, what happened* — because a report missing any one of those cannot be acted on.

---

## 9. Decisions still needed

Three of the original six questions are answered: testing is for **sign-off**, by **3–4 JCRC
testers**, against **invented data**. What remains:

1. **Who are the four people, and which archetype does each match?** §5 needs real names.
2. **How much time do they have, and over what period?** Roughly 2–2½ hours each across
   9 testable sets. The rounds in §7 exist so this can be staged.
3. **DKIM before round 3, or a note in the scripts?** §6. This one has a deadline attached.
4. **Who signs?** The tester who ran the set, or a manager accepting on their behalf? The
   scripts assume the tester signs, which is the stronger evidence.
5. **What is the fix-and-retest loop?** A Blocker found in round 1 needs a route back into
   testing. Worth agreeing before, not during.

---

## 10. What exists so far

- **This plan** — `Testing/JCRC_UAT_Testing_Plan.md`
- **Example script** — `Testing/Test_Script_08_Board_Management.md`, written in full as the
  format proposal. Board Management was chosen because it is fully built, spans two stories, and
  is blocked by neither DKIM nor any pending client decision — so it can go out as soon as the
  format is approved.
- **Seed scripts** — `Testing/seed/`, five re-runnable Apex files that built the data in §6.
  Kept in the repo so the sandbox can be rebuilt, or a fresh one populated, without redoing
  the work.

The remaining eight scripts follow once the format and the questions in §9 are settled.
