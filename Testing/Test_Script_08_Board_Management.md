# Testing & Sign-Off: Board Management

**JCRC-NY Salesforce · Test Script 8 of 11**
Please allow about **60 minutes**. You do not need to finish in one sitting.

| | |
|---|---|
| **Tester** | |
| **Date started** | |
| **Date completed** | |

---

## Why we are asking you to do this

We have built the board tracking part of the new system. This session decides whether JCRC
**accepts it** — so at the end of this document there is a line for you to sign.

That sounds formal, and it should, because signing means something: it means this part of the
system is good enough for JCRC to run on from day one. What we need from you is an honest
answer, not a kind one.

**You are the expert here, not us.** We know what we built. You know what happens when a board
member joins mid-year, or chairs two committees, or misses three meetings in a row. The gap
between those two things is exactly what this session is for.

A few things worth saying plainly:

- **You cannot break anything.** This is a practice copy of Salesforce. Every donor in it is
  invented, nothing is visible outside JCRC, and nothing you do touches live data. Create
  records, delete them, put nonsense in a field — please do.
- **"I couldn't work out how to do that" is a Fail, and it is not your fault.** If a fundraiser
  cannot find the function, we have not delivered the function. Please do not write it off as
  your own unfamiliarity — that is the single most common way useful findings get lost.
- **Saying "no" now is cheap. Saying it after go-live is expensive.** If something is wrong,
  this is the moment it costs least to fix.
- **Please do not only follow the steps below.** Part 2 asks you to wander off on purpose. Under
  a sign-off it matters more, not less: approving a system you have only used along a scripted
  path is how organisations end up accepting something they cannot actually work with.

---

## What this covers

Everything to do with **board service**:

- Who is currently on the board, and what kind of member they are
- Adding a new board member and their term
- Committees and subcommittees, and who sits on them
- Board meetings and who attended
- What each board member has committed to give, and how they are tracking against it
- Ending someone's term and the term-limit rules

**What it does not cover:** general donation entry, thank-you letters, and event gifts. Those
have their own scripts. If you notice something about them while you are in here, please still
tell us.

---

## What is behind this (for the record)

| | |
|---|---|
| **Stories covered** | **JSI-123** — Board Tracking (board terms, member types, per-year history, committees, meetings, attendance, the board console and dashboard) |
| | **JSI-90** — Annual Giving Summary (the giving-year records that board commitments are measured against) |
| **Built by** | Jason Ott, Mission Matters Group |

**How it works, briefly.** Board service is stored as a **term** — a person, a member type and a
start date. When a term is saved, the system works out the end date from the member type's term
length and creates one record for each fiscal year of that term, so every year of service has
its own place to record a role, meeting attendance and giving. Committee roles and Executive
Committee membership feed a calculation that sets each member's annual commitment. Meeting
attendance is counted automatically against the requirement. The **Board Members** screen pulls
all of this into one place so you are not clicking between records.

You do not need to understand any of that to test it. It is here so you know what we think we
built.

---

## Before you start

1. Log in to the **practice Salesforce** using the link and password sent separately. Use
   **your own login**, not a shared one — part of what we are testing is that the right people
   can see the right things.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. In the row of tabs across the top, find **Board Members**.

**What is already in there.** The practice system has been filled with invented data so you are
not testing against an empty screen:

| | |
|---|---|
| **Board members** | Jason Ott, Margaret Ott, Marc Wolf |
| **Member types** | JCRC Recruited ($5,000 · 6-year term) · UJA Appointed ($5,000 · 6-year term) · UJA Observer ($1,800 · 1-year term) |
| **Committees** | Audit · Development · Executive · Finance · Government Affairs · Israel and Jewish Affairs · Israel Parade · Nominating · Shared Society |
| **Constituents to draw on** | About 180 invented people, with two years of giving history |

Every name in the system is made up. Any resemblance to a real donor is coincidence.

If the member types, commitment amounts, term lengths or committee names are wrong, **that is a
finding** — please note it. Those came from our reading of the requirements, and this is the
moment to correct them.

---

## How to record your answers

Every scenario has a box. Please give each one a verdict:

| Verdict | Use it when |
|---|---|
| ✅ **Pass** | It did what the script said it would. Nothing to raise. |
| 🟨 **Pass with comments** | It worked, but something is off — wording, an extra step, a missing field. Does not block go-live; goes on the list. |
| ❌ **Fail** | It did not work, gave the wrong result, or you could not find how to do it. |

For anything that is **not** a clean Pass, please also mark how serious it is:

| | |
|---|---|
| 🔴 **Blocker** | Something JCRC does routinely is impossible, or the system shows a wrong number someone would act on |
| 🟠 **Major** | Works, but badly or partly. There is a workaround you could live with for a short while |
| 🟡 **Minor** | Wording, layout, convenience, preference |

**A wrong number is always a Blocker**, however small it looks on screen. A commitment figure or
an attendance count that is off by a little still goes to the Chair.

And for anything that is not a Pass, we need three things — **what you tried, what you expected,
what actually happened.** A report missing any one of those cannot be acted on.

---

# Part 1 — Guided scenarios

Each one is a real thing someone at JCRC would do. We have told you **what to achieve** and
**what you should see**, but not which buttons to press — partly because finding your way around
is itself worth testing.

If you get stuck for more than two or three minutes, write that down and move on. Being stuck is
data, and it is a Fail, not a personal failing.

---

### Scenario 1 · See who is on the board today

**The situation.** Someone asks you who is currently serving on the board.

**What to do.** Open the Board Members screen and find the current roster.

**What you should see.** Three current board members, each showing what type of member they are,
when their term runs, and how they are tracking against their giving commitment.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| What actually happened | |
| Is this the information you would want here? What is missing? | |

---

### Scenario 2 · Add a new board member

**The situation.** The Nominating Committee has elected **a new JCRC Recruited board member**,
starting at the beginning of this fiscal year.

**What to do.** Add them. Use any name you like — make one up. You will need to pick an existing
person, so if the name you want does not exist, create the person first.

**What you should see.** Once saved, you should not have to work out the end date yourself — the
system should know a JCRC Recruited term runs six years. You should also see their annual
commitment appear without you typing it.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| What end date did it give them? | |
| What commitment amount did it give them? | |
| Was anything about this confusing? | |

---

### Scenario 3 · Record a board meeting and take attendance

**The situation.** The board met last Tuesday. You have the attendance list and need to record
who was there.

**What to do.** Create the meeting, then mark who attended. Mark **some** members present and at
least one absent.

**What you should see.** Attendance saves without you having to press save on every person
individually, and the meeting shows who was there.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| What actually happened | |
| Is this quicker or slower than how you do it now? | |

---

### Scenario 4 · Put someone on a committee

**The situation.** One of your board members has agreed to **chair the Development Committee**.

**What to do.** Record that.

**What you should see.** Their committee role recorded against the current fiscal year — and
watch their **giving commitment**. Under the rules we were given, chairing a committee raises a
member's commitment to $10,000.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| Did their commitment change? To what? | |
| **Is that rule right?** | |

---

### Scenario 5 · Someone comes off the board

**The situation.** A board member is stepping down at the end of this fiscal year.

**What to do.** End their term.

**What you should see.** They drop off the current roster, but their history of service stays —
you should still be able to see that they served, and for how long.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| Could you still see their service history afterwards? | |
| Is "ending a term" the way you would describe this? What do you call it? | |

---

### Scenario 6 · Report to leadership

**The situation.** The Chair wants to know how the board is doing on its giving commitments, and
who is coming up against their term limit.

**What to do.** Find that out. There is a board dashboard and a set of board reports.

**What you should see.** Numbers you would be willing to put in front of the Chair.

| | |
|---|---|
| **Verdict** | ☐ Pass  ☐ Pass with comments  ☐ Fail |
| **Severity** (if not a Pass) | ☐ Blocker  ☐ Major  ☐ Minor |
| **Would you send this to the Chair as-is?** If not, what is missing? | |

---

# Part 2 — Before you sign

**Please do not skip this half.**

Below are four things we are genuinely unsure about. We are not going to tell you how to test
them, because the moment we do, you will do it our way and we will learn nothing.

Spend **five to ten minutes on each**. Try to break it. Do the thing a distracted person does at
4:45pm on a Friday. Anything you find here should shape the verdict you give at the end — that
is what this half is for.

---

### Charter A · Someone who has served before

> **What worries us:** board members leave and come back, or serve a second term. We are not
> confident the system handles a person with more than one term cleanly, or that their years of
> service add up correctly toward the term limit.

| | |
|---|---|
| What did you try, and what did you find? | |
| Anything here that should affect sign-off? | |

---

### Charter B · The commitment amount

> **What worries us:** a member's commitment can change because of their member type, because
> they chair a committee, or because they sit on the Executive Committee. We think it may be
> unclear on screen **why** someone's number is what it is — and if a fundraiser cannot explain
> the number to the board member, the number is useless.

| | |
|---|---|
| Could you always tell where the figure came from? | |
| Anything here that should affect sign-off? | |

---

### Charter C · Fixing a mistake

> **What worries us:** we have tested people doing things correctly. We have barely tested people
> undoing things. Recording the wrong meeting date, marking the wrong person present, putting
> someone on the wrong committee, adding a term that should not exist.

| | |
|---|---|
| What did you try, and what did you find? | |
| Anything here that should affect sign-off? | |

---

### Charter D · The year boundary

> **What worries us:** JCRC's giving year runs July to June, and board service is tracked per
> year. Anything involving dates near the end of June or the start of July is where we would
> expect this to go wrong.

| | |
|---|---|
| What did you try, and what did you find? | |
| Anything here that should affect sign-off? | |

---

# Anything else

Please use this space for anything that does not fit above — wording that is wrong, a screen
that felt cluttered, a step that took longer than it should, a term JCRC does not actually use,
or something you expected to be there and was not.

**Small things are worth writing down.** "We call that a 'trustee', not a 'board member'" is a
genuinely useful finding.

| |
|---|
| |

---

# Sign-off

Please complete this once you have finished both parts.

### Summary of what you found

| Severity | How many | List them |
|---|---|---|
| 🔴 **Blocker** | | |
| 🟠 **Major** | | |
| 🟡 **Minor** | | |

### Your decision

Tick one:

- ☐ **Accepted** — Board Management is fit for JCRC to use from day one. No Blockers, no Majors.

- ☐ **Accepted with conditions** — no Blockers, but the Major items above must be fixed. Please
  say by when:

  | | |
  |---|---|
  | Conditions | |
  | Needed by | |

- ☐ **Not accepted** — one or more Blockers. This part of the system is not ready.

### Signature

| | |
|---|---|
| **Name** | |
| **Role at JCRC** | |
| **Date** | |
| **Signature** | |

> **What you are signing.** That you have worked through both parts of this document, and that
> in your judgement board tracking either is — or is not — ready for JCRC to rely on. You are not
> signing that the system is perfect, and you are not signing away the right to raise something
> later. If you are not comfortable signing, say so and tell us why; that is a legitimate
> outcome and we would rather have it than a reluctant tick.

---

# How to send this back

Fill in the boxes above and send the document to **Jason Ott**.

For anything that went wrong, the three things we need are:

1. **What you were trying to do**
2. **What you expected to happen**
3. **What actually happened**

If you can add a screenshot, that helps a great deal — but do not let the lack of one stop you
telling us.

**Thank you.** This is genuinely the part of the project where your time makes the most
difference to what you end up living with.
