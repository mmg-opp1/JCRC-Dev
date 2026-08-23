# Script 8: Board Management

## What and Why?

You are the expert here, not us. We know what we built. You know the workflows, processes, and
expectations that your organization follows for this functionality. The gap between those two
things is exactly what this session is for.

A few things worth saying plainly:

- **You cannot break anything.** This is a Salesforce Sandbox. All data is fake, and everything
  is internal and contained to this sandbox alone. Create records, delete them, and do it as
  many times as you need to feel comfortable.
- **"I couldn't work out how to do that" is a Fail, and it is not your fault.** If you cannot
  find the function, we have not delivered the function. That said, please allow yourself some
  time to get comfortable with a new system and potentially a new way of doing things. We are
  not rebuilding what you already have. It will take some time to adjust to some new
  click-paths, new language, etc. Ask as many questions as you need to.
- **Please do not only follow the steps below.** Part 2 asks you to wander off on purpose. We
  want to uncover scenarios we haven't thought of. We want to find the edge-cases. We want you
  to get as much exposure to the system and provide as much feedback to make things better.

## Scope

Everything to do with board service:

- Who is currently on the board, and what kind of member they are
- Adding a new board member and their term
- Committees and subcommittees, and who sits on them
- Board meetings and who attended
- What each board member has committed to give, and how they are tracking against it
- Ending someone's term and the term-limit rules

**Not in scope:** general donation entry, thank-you letters, and event gifts. Those have their
own scripts. If you notice something about them while you are in here, please still tell us.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-123** Board Tracking: board terms, member types, per-year history, committees, meetings, attendance, the board console and dashboard |
| **Also touches** | **JSI-90** Annual Giving Summary: the giving-year records that board commitments are measured against |

Board service is stored as a **term**: a person, a member type, and a start date. When a term is
saved, the system works out the end date from the member type's term length. It then creates one
record for each fiscal year of that term, so every year of service has its own place to record a
role, meeting attendance, and giving.

Committee roles and Executive Committee membership feed a calculation that sets each member's
annual commitment. Meeting attendance is counted automatically against the requirement. The
**Board Members** screen pulls all of this into one place so you are not clicking between
records.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use
   your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. In the row of tabs across the top, find **Board Members**.

**What is already in there.** The sandbox has been filled with invented data so you are not
testing against an empty screen:

| | |
|---|---|
| **Board members** | Jason Ott, Margaret Ott, Marc Wolf |
| **Member types** | JCRC Recruited ($5,000, 6-year term), UJA Appointed ($5,000, 6-year term), UJA Observer ($1,800, 1-year term) |
| **Committees** | Audit, Development, Executive, Finance, Government Affairs, Israel and Jewish Affairs, Israel Parade, Nominating, Shared Society |
| **Constituents to draw on** | About 180 invented people, with two years of giving history |

Every name in the system is made up. Any resemblance to a real donor is coincidence.

If the member types, commitment amounts, term lengths, or committee names are wrong, please tell
us. Those came from our reading of the requirements, and this is the moment to correct them.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Board Management", so we can tell which part of the system your
  feedback is about
- **Tester**: your name
- **Feedback Description**: what you were trying to do, what you expected to happen, and what
  actually happened. All three, please. A description missing any one of them is hard to act on.
- **URL of Error/Issue**: copy the address out of your browser bar on the screen where it
  happened. This saves us a great deal of hunting.
- **Screenshot**: insert one as an object if you can. It helps, but do not let the lack of one
  stop you telling us.

Leave **Status**, **MMG Response**, and **JCRC Additional Comments** alone. We use those to reply
to you, so check back on your rows.

**If you have nothing to say about a scenario, leave it out.** Nothing recorded means it worked
the way you expect it to work. There is no box to tick and nothing to sign.

**If you get stuck, ask.** Getting stuck is worth recording, but do not lose an afternoon to it.
Send a message and move on.

---

# Part 1: Scenarios

Each one is meant to be a real thing someone at JCRC would do. We have given you a starting point
and told you what you should see at the end, but not every click in between. If you cannot get
from one to the other, that is worth telling us.

Everything in this part happens on the **Board Members** tab, which has four tabs of its own
across the top: **Dashboard**, **Roster**, **Committees**, and **Meetings & Attendance**.

---

### Scenario 1: See who is on the board today

**The situation.** Someone asks you who is currently serving on the board.

**What to do.** Open the **Board Members** tab, then the **Roster** tab inside it.

**What you should see.** Three current board members. For each one the roster shows their member
type, their role, the dates their term runs, their giving commitment, and how much of that
commitment they have met so far. It also flags anyone whose term is expiring soon or who must
roll off.

---

### Scenario 2: Add a new board member

**The situation.** The Nominating Committee has elected a new JCRC Recruited board member,
starting at the beginning of this fiscal year (1 July 2026).

**What to do.** On the **Roster** tab, click **New Board Member**. You will be asked for three
things: the person, their Member Type, and the Term Start Date. Pick anyone from the list. If the
person you want does not exist, create them on the **Contacts** tab first, then come back.

**What you should see.** Notice that you are never asked for an end date. Once saved, the new
member appears on the roster with a six-year term already worked out, and a commitment amount
already filled in.

---

### Scenario 3: Record a board meeting and take attendance

**The situation.** The board met last Tuesday. You have the attendance list and need to record
who was there.

**What to do.** Go to the **Meetings & Attendance** tab and click **New Meeting**. Give it a
name, set the meeting date to last Tuesday, and set the fiscal year (any date inside the year you
want will do). Once the meeting is created, the board members appear underneath with an
**Attended** box against each one. Tick some, leave at least one unticked, then click **Save
Attendance**.

**What you should see.** One click of **Save Attendance** records everyone at once, rather than
saving each person separately. Come back to the meeting afterwards and the attendance should
still be there.

---

### Scenario 4: Put someone on a committee

**The situation.** One of your board members has agreed to chair the Development Committee.

**What to do.** Go to the **Committees** tab and find **Development** in the list. On that row,
choose **Manage Members**, then **Add Member**. You will be asked for the person, their role
(Chair, Co-Chair, or Member), and the fiscal year.

**What you should see.** The role recorded against the current fiscal year. Now go back to the
**Roster** tab and look at that person's commitment. Under the rules we were given, chairing a
committee raises a member's commitment to $10,000. If that rule is wrong, tell us.

---

### Scenario 5: Someone comes off the board

**The situation.** A board member is stepping down at the end of this fiscal year.

**What to do.** On the **Roster** tab, find them and use **End Term** on their row. You will be
asked for a new term end date. Use 30 June 2027.

**What you should see.** They come off the current roster, but their history of service stays.
You should still be able to find that they served, and for how long. If the roster no longer
shows them, try their Contact record.

---

### Scenario 6: Report to leadership

**The situation.** The Chair wants to know how the board is doing on its giving commitments, and
who is coming up against their term limit.

**What to do.** There are two places to look. The **Dashboard** tab inside Board Members, and the
**Reports** tab, where the **Board Reports** folder holds **Current Board Roster**, **Board
Commitment Fulfillment**, and **Board Roll-Off Watch**. The board dashboard itself lives in the
**Board Dashboards** folder on the **Dashboards** tab.

**What you should see.** Numbers you would be willing to put in front of the Chair. If you would
not send it as-is, tell us what is missing.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real board situation you can remember and throw it at the system. Anything you find here is
worth more to us than a clean run through Part 1.

Five places to start. You do not need to stick to them.

### The most complicated board history you can think of

People leave and come back. They serve a second term, switch member type, or take a year off.
Build the messiest service history you can and see whether the years add up and the term limit
still makes sense.

### Make the commitment number wrong

A member's commitment moves with their member type, whether they chair a committee, and whether
they sit on the Executive Committee. Try to push it to a number you could not explain to a board
member, or get two screens to disagree about it.

### Break something, then fix it

Record the wrong meeting date. Mark the wrong person present. Put someone on a committee they
are not on. Add a term that should not exist. Then put it all right again and see whether the
system lets you.

### Push the year boundary

The giving year runs July to June. Do things dated the last week of June and the first week of
July, and see whether they land in the year you meant.

### Your weirdest board scenario

The one that always causes trouble. The exception everyone at JCRC knows about. The situation
you had to handle by hand last year. Try it.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
