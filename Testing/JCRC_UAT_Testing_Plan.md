# JCRC Testing Plan

> **Author:** Jason Ott
> **Written:** 2026-08-21, rewritten 2026-08-23
>
> Internal working document. The scripts themselves are what goes to JCRC.

---

## 1. How this is set up

Eleven scripts, one per area of the system, grouped by **what a fundraiser is trying to do**
rather than by how it was built. Several stories usually combine to deliver one job, and some
stories appear in more than one script, which is exactly why testing story by story would miss
the seams between them.

Every script has the same two halves:

| Part | What it is | What it catches |
|---|---|---|
| **Part 1: Scenarios** | Real work, with a starting point and an expected outcome, but not every click | Does it do the job at all |
| **Part 2: Try to break it** | Challenges rather than instructions. Build the messiest history you can, make the number wrong, throw your weirdest real case at it | The problems scripts never find |

Part 2 is not garnish. A system only ever used along a scripted path is one you find out about
after go-live.

**Feedback goes in the shared log**, not in the document. Testers record anything worth raising
in `JCRC_Implementation_Testing_Feedback_Log.xlsx` on SharePoint, on the Sprint 1 tab, putting the
script name in the Testing Script column. **Saying nothing about a scenario means it worked.**
There is no verdict to record, no box to tick, and nothing to sign. That keeps the log to things
that need action, and means the returned file is the defect list with no collation step.

---

## 2. What the research says, and how it is applied

| Finding | Source | How the scripts apply it |
|---|---|---|
| Write in plain language; describe the workflow, not the UI | Testsigma, TestMonitor | Scripts describe the situation and the goal, then name the button to start from |
| A scenario needs specific data and an observable outcome | UI Zap | Each has one clear "what you should see" |
| Realistic data is a precondition for non-technical testers engaging | TestMonitor | See §4. This was the single biggest risk and it is closed |
| Charters naming a specific risk explore what scripts do not | TestRail, SD Times | Part 2 of every script |
| Scripted tests assume clean state; exploratory finds what odd state does | TestRail | Charters ask testers to revisit and break what they made earlier |
| Model whole workflows, not single functions | PractiTest | Scripts follow a job end to end, including finding it on a report afterwards |

**Sources:**
[Testsigma](https://testsigma.com/blog/uat-test-scripts/) ·
[TestMonitor](https://www.testmonitor.com/blog/5-tips-for-making-user-acceptance-testing-easier-for-non-technical-users) ·
[UI Zap](https://blog.uizap.com/uat-scenario-writing-guide/) ·
[TestRail](https://www.testrail.com/blog/perform-exploratory-testing/) ·
[SD Times](https://sdtimes.com/test/exploratory-testing-for-uat/) ·
[PractiTest](https://www.practitest.com/resource-center/article/what-is-uat-testing/)

---

## 3. The eleven scripts

All are written and converted to Word. Each runs 4 to 5 pages.

| # | Script | Stories covered | Notes |
|---|---|---|---|
| **1** | Constituents and Relationships | JSI-122, JSI-89, NPSP households | |
| **2** | Everyday Giving | JSI-80, JSI-85, JSI-86, JSI-90 | |
| **3** | Pledges and Installments | JSI-82, JSI-125, JSI-126 | Tells testers to use their own email address to see a notification arrive |
| **4** | Grants | JSI-120 | No seeded grants, so testers create them |
| **5** | Complex and Non-Cash Gifts | JSI-84, JSI-86, JSI-124, JSI-85 | No seeded securities or DAF gifts, so testers create them. Asks their view on the gala-plus-DAF question |
| **6** | Tributes and Notifications | JSI-89 | One seeded tribute; testers create the rest |
| **7** | Thank-Yous and Acknowledgments | JSI-87, JSI-124 | Asks testers to correct the letter copy |
| **8** | Board Management | JSI-123, JSI-90 | |
| **9** | Gala and Event Gifts | Gala Gifts | Scenario 1 asks testers to enter JCRC's real levels and prices |
| **10** | Website Donations | Website Donations, JSI-127 | Scenario 5 asks where designations should map |
| **11** | Email Marketing and Engagement | JSI-107, JSI-108, JSI-109 | No Constant Contact data; asks what they would expect to see |

**Deliberately not a script:** reports and dashboards. Reporting is how a fundraiser checks their
own work, so it is tested inside each script rather than as an abstract exercise.

---

## 4. State of the sandbox

### Resolved

- **Test data.** The sandbox held 8 contacts and 13 gifts, at which volume searching, duplicate
  handling, list views, segmentation and reports are all untestable and all *look* fine. It now
  holds 180 constituents, 443 gifts, 127 installments, 363 giving summaries, and 220 tag
  assignments. Names are assembled rather than copied, and every address ends in example.com,
  which is reserved and cannot deliver, because the org has live email automation.
- **DKIM** is active on jcrcny.org, so acknowledgement emails and installment notifications reach
  the inbox.
- **The Development home page** is activated.

### Open questions, turned into scenarios

Rather than hold scripts back waiting on decisions, the open question is stated inside the script
and put to the tester:

- **Gala levels and prices.** Only a placeholder level exists. Script 9 scenario 1 asks testers to
  enter JCRC's real levels, prices, seat counts and non-deductible amounts, and says plainly that
  what they enter is what we will build from.
- **Website designations.** Gifts arrive correctly but the donor's chosen designation is not
  allocated, because the GAU-versus-Campaign decision is open. Script 10 scenario 5 puts that
  question directly to the tester.
- **Gala plus DAF.** Whether a donor advised fund can pay for a gala ticket, given the benefit
  rules. Raised in script 5 Part 2.
- **Letter copy.** The six acknowledgement letters use the wording JCRC supplied. Script 7
  scenario 2 asks testers to read it closely and correct it.

### Thin, and said so in the script

- **Constant Contact** has no sends or activity in the sandbox. Script 11 states this at the top
  and reframes the empty screens as a question: what would you expect to see here, and would it be
  enough to do your job?
- **Grants, securities, DAF, and tributes** have few or no seeded records, so those scripts have
  testers create them. Creating the record is itself worth testing.

---

## 5. Suggested sequence

Later scripts use records created in earlier ones, which is deliberate. It is how the seams get
tested.

| Round | Scripts | Why here |
|---|---|---|
| **1** | 1 Constituents, 2 Everyday Giving | Everything else needs donors and gifts to exist. Also the fastest way to learn whether the basics feel right |
| **2** | 3 Pledges, 5 Complex Gifts, 6 Tributes | The gift types carrying the most policy: deductibility, credit, who gets told |
| **3** | 7 Thank-Yous, 8 Board | Both consume what rounds 1 and 2 created |
| **4** | 4 Grants, 9 Gala, 10 Website Donations | The three where we are asking for decisions as much as defects |
| **5** | 11 Email Marketing | Least finished; most useful once people know the rest of the system |

**Review round 1 before round 2 starts.** If the basics are wrong, everything downstream is
testing on a bad foundation, and re-testing costs more than the pause.

---

## 6. Open items

1. **How much time do testers have, and over what period?** Each script is roughly 45 to 60
   minutes. The rounds above exist so this can be staged.
2. **What is the fix-and-retest loop?** Something found in round 1 needs a route back into
   testing. Worth agreeing before, not during.
3. **Who watches the log?** The Status and MMG Response columns imply somebody triages and
   replies. Testers are told to check back on their rows.

---

## 7. What exists

- **This plan**, `Testing/JCRC_UAT_Testing_Plan.md`
- **Eleven scripts**, `Testing/Test_Script_01..11_*.md` with a `.docx` alongside each. The Word
  files are what go to testers.
- **Converter**, `Testing/tools/md_to_docx.py`. Edit the markdown, re-run it, and the Word file
  is rebuilt. Empty table cells become shaded answer boxes, and numbered lists restart properly.
- **Seed scripts**, `Testing/seed/*.apex`, five re-runnable files that built the data in §4. Kept
  so the sandbox can be rebuilt or a fresh one populated without redoing the work.
