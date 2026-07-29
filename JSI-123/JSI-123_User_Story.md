# JSI-123 — Board Tracking

> **Source:** [JSI-123 in Jira](https://missionmattersgroup.atlassian.net/browse/JSI-123)
> Retrieved from Jira on 2026-07-27 by Jason Ott. The Jira story is a **stub** (one-line
> description, **no Definition of Done** — the client has not yet reviewed it). The DoD below is a
> **PROPOSED, outcome-based draft** authored from Jason's dictation, to put ideas in front of the
> client for feedback. It has **not** been pushed to Jira yet (see Notes). Jira remains the system of record.

## Overview

| Field | Value |
|-------|-------|
| **Key** | JSI-123 |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Medium |
| **Project** | JCRC - Salesforce Implementation (JSI) |
| **Epic / Parent** | JSI-9 — Contact Management |
| **Sprint** | Implementation Sprint 2 (2026-07-10 → 2026-08-10, *future*) |
| **Labels** | _None_ |
| **Feature Owner** | _Not set in Jira_ (no comment) |
| **Reporter** | Jason Ott |
| **Assignee** | Jason Ott |
| **Created** | 2026-07-27 |
| **Updated** | 2026-07-27 |

## User Story

> _(Verbatim from Jira)_
>
> As a development team member, I want to track a board member's **terms**, **term expiration
> dates**, **board roles**, **board subcommittees**, **subcommittee roles by year** so that we can
> ensure proper board participation and giving each year.

Expanded from Jason's dictation: JCRC has a **serious, high-priority board** where every member
carries **fiscal commitments** (a required number and/or value of gifts each fiscal year), must
**participate in committees and subcommittees**, and serves a **defined term** — when the term
expires they **roll off** the board rather than remain indefinitely. The Development team needs to
track all of this, **allocate each member's giving across the fiscal year toward their board
commitment**, and **report on it robustly** — ideally an at-a-glance **dashboard** of board
participation and giving, plus a **board management surface** (a Lightning component on a tab / VF
page in the main navigation) to see all board members and drill into each. This is intended to be
**one of the most robust, extensible features in the system** — build carefully, expect to add on.

## Definition of Done

> ⚠️ **PROPOSED — pending client review.** Written as **user-facing outcomes** (per the JSI-122
> standard); the "how" (objects, junctions, components, automation) lives in the Implementation
> Plan, not here. These are draft ideas to get client feedback, not a settled contract.

- **I can tell at a glance whether a contact is a board member** — board status, current role, and
  term dates show **right on the Contact record** I already work in.
- **I can track each member's term** — start date and **expiration date** — and see **term history**
  when someone has served more than one term. The system makes it obvious **when a term is ending**
  so members are **rolled off on time** rather than left on indefinitely.
- **I can track board roles** (e.g., Chair, Vice-Chair, Treasurer, Secretary, Member) and **which
  committees and subcommittees** each member sits on, **including their role within each committee**,
  **tracked by year** so participation history is preserved.
- **I can track each member's annual fiscal commitment** — the giving they are required to make for
  a given **board/fiscal year** (July–June) — as an amount and/or a number of gifts.
- **I can see giving progress against that commitment** — each member's gifts for the year are
  **allocated toward their board commitment**, and I can see **committed vs. given vs. remaining**
  for the current fiscal year (and prior years).
- **I can report on the board robustly** — pull **who is on the board right now**, their terms and
  expirations, committee/subcommittee participation, and their commitment fulfillment; and view an
  **at-a-glance dashboard** of participation and giving metrics **across all board members** at once.
- **I have a dedicated board management surface** — a place in the **main navigation** (tab) where I
  can see **all board members**, click into any one to **manage them**, and reach the board dashboard.
- **Board tracking respects security** — only authorized team members can see and manage board data.
- **The design is built to extend** — new roles, committees, commitment rules, or a future
  household/organization grain can be added without re-architecting.

## Notes & Context

- **Stub story, no DoD in Jira, no comments.** Unlike prior stories there is **no Feature Owner or
  JCRC/MAF note** to reconcile against — the dictation is currently the only detailed source of intent.
- **Push-to-Jira held.** Per our stub workflow (JSI-122) we normally author the User Story + DoD and
  push them back to Jira. Here Jason explicitly wants to **spec it first to gather client feedback**,
  so this snapshot stays local until reviewed. **Decision pending:** push the proposed DoD to Jira now,
  or after Jason/client review? (see Outstanding Questions).
- **Fiscal year = July 1 – June 30** (JCRC's giving year). Verified in prior stories:
  `Organization.FiscalYearStartMonth = 1` (January) and NPSP rollups are **calendar-based**, so board
  "year" giving **cannot** rely on native NPSP "this year" rollups. **Do not change the org fiscal
  year.** This is the same constraint JSI-90 solved.
- **Strong reuse candidate — JSI-90 (Major Donor Moves / Giving Levels).** JSI-90 already built a
  July–June fiscal-year giving architecture: `Annual_Giving_Summary__c` (per contact, per FY, with
  FY bounds and hard/soft roll-ups) and `Gift_Allocation__c` (each gift's credit allocated to a
  specific year's summary, with reconciliation on amount/date/donor/delete). Board-commitment "giving
  by fiscal year" is the **same problem**; the plan should evaluate **reusing or extending** that
  model rather than building a parallel one.
- **Related existing building blocks to check first (NO GUESSING — verify in Step 3):**
  - **NPSP Affiliations** (`npe5__Affiliation__c`) already model a Contact↔Account relationship with
    a **Role** and **start/end dates** — a candidate for board membership/term if a "Board" account
    is used. To evaluate against a custom Board Term object.
  - **JSI-85** delivered soft-credit / OCR crediting rules; **JSI-90** defined which gifts qualify
    (Closed/Won, exclude In-Kind, hard + soft roles). Board commitment "counting" should reuse those
    rules for consistency.
  - **JSI-122 Tags** could flag "Board Member," but tags don't carry term/role/dates — likely not the
    right home for structured board data.
- **Board management surface** — Jason's proven pattern (JSI-87) is a **Lightning component / screen
  flow embedded on a Visualforce page**, placed on a **tab in the main navigation**, optionally
  surfacing the **board dashboard**.

## Outstanding Questions / Design Decisions

> **Resolved with Jason 2026-07-27:**
> - **Q1 (giving model) → REUSE/EXTEND JSI-90.** Board fiscal-commitment / giving-by-year tracking
>   builds on the existing `Annual_Giving_Summary__c` + `Gift_Allocation__c` (per-contact, per-July–June
>   year) architecture rather than a parallel model. Step 3 must verify current JSI-90 metadata and
>   design the extension (commitment amount + fulfillment) against it.
> - **Q2 (membership grain) → custom `Board_Term__c` spine** (with optional NPSP Primary Affiliation sync).
> - **Q7 (committees) → `Committee__c` config + `Committee_Assignment__c` per fiscal year.**
> - **Q9 (board surface) → `Board_Members` LWC on a custom nav tab + Board Dashboard.**
> - **Q11 (push to Jira) → HOLD.** Keep the proposed DoD local until Jason + client review, then push
>   and re-pull (JSI-122 pattern). Do **not** push now.
>
> **Still open — client input (Jason to relay):** Q3 term length/renewals · Q4 commitment shape ($/# gifts) ·
> Q5 what counts toward commitment · Q6 confirm board year = Jul 1–Jun 30 · Q8 dashboard metrics + any
> confidential board data. Plus Jason design points: D6 roll-off behavior, D11 Primary-Affiliation sync, D12 profiles.

_Remaining items drive Step 3 research and Step 5 forks. **(C)** = likely needs client input; **(J)** = Jason/design._

1. **Giving-model reuse (J):** Reuse/extend **JSI-90's** `Annual_Giving_Summary__c` + `Gift_Allocation__c`
   for board-commitment giving-by-FY, or build a dedicated board-giving model? (Recommend reuse/extend.)
2. **Board membership grain (J):** Model board membership as a **custom `Board_Term__c` junction**
   (Contact + term dates + board role) vs. leaning on **NPSP Affiliations** to a "Board" Account.
3. **Term & roll-off (C/J):** Fixed term length (e.g., 3 years)? Renewable/consecutive terms allowed?
   On expiration, should the system **auto-flag/auto-deactivate** the member (and how — a task, a
   status change, a report), or just surface upcoming expirations for manual roll-off?
4. **Commitment definition (C):** Is the annual commitment a **flat dollar amount**, a **number of
   gifts**, or **both**? Does it **vary by member, role, or year**? Is there a standard default?
5. **What counts toward the commitment (C/J):** Which gifts credit the board commitment — **hard
   credit only**, or **soft credit** (household, matched, DAF) too? Reuse JSI-85/JSI-90 crediting
   rules? Do pledges count when committed or when paid?
6. **"By fiscal year" confirmation (C):** Board year == JCRC fiscal year **July 1 – June 30**, correct?
   (Dictation says yes.) Terms and commitments both keyed to that year.
7. **Committees & subcommittees (C):** Is there a **defined list** of committees/subcommittees and
   the **roles** within them? Should committees be a **configurable object** (admin-maintained) vs. a
   picklist? Are subcommittees children of committees?
8. **Reporting & dashboard scope (C):** What are the **must-see metrics** for the board dashboard
   (current roster, terms expiring, % of commitment met, participation by committee, total board
   giving)? Any confidential board data with restricted visibility?
9. **Board surface placement (J):** Tab-hosted **VF page + Lightning component** listing all board
   members (per dictation), plus the dashboard — confirm navigation placement and who has access.
10. **Security (J):** Per org standard, grant access on the **JCRC\* profiles** (not permission sets).
    Confirm which profiles manage board data.
11. **Push proposed DoD to Jira now or after review (J)?** (see Notes.)

## Client Answers (2026-07-28)

Raw answers received from JCRC. **These expand and partly re-architect the design** — see the
"Design Impact" list below and the revised Implementation Plan. Key points + derived actions:

> **⚠ CLARIFICATIONS (2026-07-28, from `BoardQuestionClarificationsDictation.MD`) — these OVERRIDE the
> raw answers where they conflict:**
> - **Three board-member types:** **JCRC-recruited** (6-yr, **$5k/yr**), **UJA-appointed** (6-yr, **$5k/yr**),
>   **UJA Observer** (young leaders; **1-yr term**, **$1.8k/yr**) — the Observer is the only non-6-year term.
> - **Commitment = the HIGHER of** the board-type base (5k / 1.8k) **vs. $10k** if the person is a **committee
>   chair/co-chair OR on the Executive Committee**.
> - **Only elected OFFICER roles pause the 6-yr board clock:** President, VP, Secretary, Treasurer — each a
>   **3-yr officer term** (so max ~**9 years** = 6 board + 3 officer). **Executive Committee membership and
>   committee chair/co-chair do NOT pause** the clock. At 6 board-member-years you are **forced to roll off**,
>   then **off ≥1 year** before returning (hard rule).
> - **Per-year record is explicitly required** — Board **Term** (multi-year container, e.g. 2025–2031) **plus a
>   per-year record** capturing what they did each fiscal year.
> - **Board meeting attendance IS tracked** (know who attended, to satisfy **3 of 4** annual meetings) — but no
>   meeting notes / not full board management.
> - **eTapestry historical import (board/committee-by-FY 'Group') is NOT in this story's scope** — the per-year
>   model just needs to accommodate imported rows.
> - **Open ambiguity:** is "Chair" (role list) the Board **Chair** (an officer that pauses) or only committee
>   chair? Assume **Board Chair = officer (pauses)** unless told otherwise.

**Terms & roll-off**
- **Term length = 6 years** (not by role). ⚙︎ `Default_Term_Length_Years` → **6**.
- **Term limits:** informal annual check-in on who's returning; **after year 6 you must roll off ≥1 year.**
  Not everyone serves the full 6. **Moving from board → Executive Committee puts the board term ON HOLD**
  (those years don't count against the 6).
- **History granularity: keep history for EACH YEAR of the term** (per-year, not just per-term). → drives a
  **per-year board membership record**.
- **Expiration = flag/report only** (no auto-change). Notify **administrators** + a hoped-for **"Board
  Coordinator" role**; **90-day** window. ⚙︎ already set.
- **Prospects = Contacts flagged as "Board Prospect"**, likely via **Tag Manager (JSI-122)** — not a Board Term.
- **Honorary = Past Presidents, NO financial commitment.**

**Boards (NEW — multiple)**
- Board affiliations tracked: **Board – JCRC, Board – UJA, Board – UJA Observer** (+ **Executive Committee**).
  **Observer vs non-observer changes the commitment.** → reopens the single-board assumption (D13).

**Roles / officers**
- **Board roles: Chair, President, VP, Secretary, Treasurer** (+ Member; + Past President/Honorary).
- **Officer/Exec-Committee roles have their own 3-year terms**, separate from the board term, and **interrupt/
  hold** the 6-year board clock.

**Commitment**
- **Tiers:** Executive Committee **$10k** · Board non-observer **$5k** · Board observer **$1.8k**.
- **Soft credits COUNT.** **In-Kind does NOT count** (already excluded via JSI-90 rollups). Gala tickets = **TBD**.
- **Non-giving requirement: attend 3 of 4 annual board meetings.** No event/committee requirement.
- **Board year = fiscal year July 1–June 30. No proration** for mid-year joins.

**Committees**
- **Board committees + special-event committees** (e.g., 50th Anniversary Steering Committee).
  List: **Executive, Development, Government Affairs, Israel and Jewish Affairs, Finance, Audit, Nominating,
  Shared Society, Israel Parade.** Each has a **Chair and/or Co-Chair.**
- **Committee members can be non-board members** (already supported). **Membership + role only, no attendance.**
- Assignments **carry forward but may change, case-by-case** (per-year, manual — already supported).

**Reporting / access / history**
- **Point-in-time history: YES.** Currently an **eTapestry UDF 'Group' = board membership by fiscal year →
  importable.** Marc's **FRD dashboard** to be shared as reference (last year's differs from this year's).
- **No printable roster** needed (handled outside CRM). → drop that item.
- **Access:** Organization leadership, Exec Admin, Development team.

**Additional new scope (flagged)**
- **Skillsets** (annual survey; defined list: Finance/Accounting, PR, Comms/Social, Policy Analysis, Law,
  Conflict Resolution, Strategic Planning, Middle East/Intl, Gov Relations, K-12, Campuses, Tech/IT, Data,
  Jewish Text/Hebrew, Non-Profit Mgmt, Fundraising, Other) + **job titles**. → candidate for **Tag Manager**.
- **Personal/cultivation info** (significant dates: birth/wedding; children's names; life facts) — **TBD**,
  likely its **own story**.

**Still TBD (client):** do gala tickets count toward commitment? · exact confidential-data sharing (Q19).

---

## Questions for JCRC (client) — ANSWERED 2026-07-28 (see Client Answers above)

_Original questions retained for traceability. 🔴 = blocks build / shapes schema; 🟡 = has a safe default._

**A. Terms & roll-off**
1. 🟡 **⚙︎ Standard term length?** (e.g., 3 years.) Does it vary by role?
2. 🟡 **Term limits?** Max consecutive terms, or can members be re-elected indefinitely?
3. 🟡 **Renewal handling** — a renewed term = a **new** `Board_Term__c` record (keeps history), correct?
4. 🔴 **⚙︎ Roll-off behavior when a term expires** — just **flag/report** for manual roll-off, or **auto-set
   status + create a task/notify staff**? Who gets notified, and how far ahead (the "expiring soon" window)?
5. 🟡 **Prospective / nominee tracking** — track people being *considered* for the board (status
   "Prospective") before they're seated?
6. 🟡 **Emeritus / honorary / lifetime members** — are they counted in the "current board" roster? Do they
   carry a giving commitment?

**B. Board roles & officers**
7. 🔴 **Definitive list of board roles / officer positions** (Chair, Vice-Chair, Treasurer, Secretary,
   Member, President, Immediate Past Chair, Emeritus…). Any that are **one-per-board** (only one Chair)?
8. 🔴 **Do officer roles have their own term, separate from board membership?** (e.g., a 3-year board member
   who is Treasurer for 1 year.) If yes, officer role is tracked **annually**, not just once on the term.

**C. Fiscal commitment**
9. 🔴 **Commitment shape** — a **dollar amount**, a **minimum # of gifts**, or **both**? (Dictation implies both.)
10. 🔴 **⚙︎ Standard vs. variable** — one standard commitment for all (e.g., $10K/yr), or does it vary by
    **member / role / year**? (Do officers commit more?) A standard default can live in `Board_Setting__mdt`.
11. 🔴 **"Give or get"?** — does the commitment count **personal giving only**, or also **funds the member
    raises/solicits** (give-or-get)? This decides whether **soft credits / solicited gifts** count.
12. 🔴 **What counts toward the commitment** — hard credit only, or soft credit (household, matched, DAF)
    too? Do **pledges** count when committed or when paid? Do **event tickets / non-deductible portions /
    in-kind FMV** count?
13. 🟡 **Confirm the board/giving year = July 1 – June 30** (fiscal year), commitments measured per that year.
14. 🟡 **Mid-year join** — is a commitment **prorated** for someone seated mid-year, or full?

**D. Committees & subcommittees**
15. 🔴 **The actual committees & subcommittees** (Finance, Development, Governance/Nominating, Executive,
    Audit…) and their **parent/child** structure.
16. 🔴 **Roles within a committee** (Chair, Vice-Chair, Member, Staff Liaison, Advisor…).
17. 🔴 **Can committee members be non-board members?** (staff, community volunteers, advisors) — decides
    whether a committee assignment requires a board term.
18. 🟡 **Annual reset** — do committee assignments **re-set each fiscal year** (tracked "by year"), or carry
    forward until changed?
19. 🟡 **Committee expectations** — track **attendance/participation** per committee, or just membership+role?

**E. Reporting, dashboard & history**
20. 🔴 **Dashboard must-haves** — the at-a-glance metrics leadership wants (current headcount, terms expiring,
    **% who met commitment**, total board giving vs. total committed, participation by committee, who's behind).
21. 🟡 **Point-in-time history** — need historical rosters ("who was on the board in FY2023"), or mainly current?
22. 🟡 **Roster export / board packet** — need a printable/exportable board roster (JSI-87 print pattern)?

**F. Security & confidential data**
23. 🔴 **Who can see / edit board data**, and is **board giving/commitment sensitive** (visible only to
    Development leadership vs. all staff)?
24. 🟡 **Any confidential board information** (sensitive notes, D&O/compensation, conflict-of-interest) needing
    **restricted sharing** beyond profile-level FLS?

## Related Reference Material

- [`JSI-123_StoryDictationNotes.MD`](./JSI-123_StoryDictationNotes.MD) — Jason's dictation, the
  primary source of intent for this stub story.
- **JSI-90** (`../JSI-90/`) — July–June fiscal-year giving architecture (`Annual_Giving_Summary__c`,
  `Gift_Allocation__c`) and crediting rules; the strongest reuse candidate.
- **JSI-85** (`../JSI-85/`) — soft-credit / OCR crediting rules for "what counts."
- **JSI-122** (`../JSI-122/`) — house format for a stub story authored from dictation; Tag model.
