# Script 9: Gala and Event Gifts

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

The annual gala, from tables and tickets through to who is sitting where:

- Setting up what a table or a ticket costs, and what portion is deductible
- Recording a table purchase or an individual ticket
- Adding the guests who will sit at a table
- Turning a guest into a proper constituent record
- Meal choices and dietary requirements

**Not in scope:** ordinary gifts and pledges, and the thank-you letter for a gala gift. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **Gala Event Gifts**: levels, tables, guests, and deductibility |

A **Gala Level** is what somebody can buy: a table or a ticket at a given price, with a
stated non-deductible portion, because part of what a guest pays is the value of the dinner they
receive rather than a donation.

A purchase creates a gift, and a **Gala Table** hangs off it with a capacity. **Gala Guests** sit
against a table, each with a name, a meal choice, and dietary notes.

A guest is often not yet a constituent. Marking a guest to be added as a contact creates one, and
where the name looks like somebody already in the database, it is flagged for a human to check
rather than merged automatically.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Opportunities**, **Campaigns**, and **Reports**. Gala levels, tables, and guests are reached from the gala gift itself.
4. There is an **FY26 Gala** campaign in the sandbox with invented gifts against it.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Gala and Event Gifts", so we can tell which part of the system your feedback is about
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

---

### Scenario 1: Set up what JCRC actually sells

**The situation.** Planning has settled the price list for this year's gala.

**What to do.** Create the gala levels JCRC really uses: the table levels, the individual ticket levels, what each costs, how many seats it includes, and how much of it is not tax deductible.

**What you should see.** **This is the most valuable scenario in this script.** Only a placeholder level exists today, because we have not been given the real numbers. What you enter here is what we will build from, so please use JCRC's actual levels, prices, seat counts, and non-deductible amounts.

---

### Scenario 2: Record a table purchase

**The situation.** A donor buys a full table at the gala.

**What to do.** Record the gift against the gala campaign at the level they bought, and create the table that goes with it.

**What you should see.** A gift for the full amount, a table with the right number of seats, and a clear split between the deductible and non-deductible portions.

---

### Scenario 3: Fill the table with guests

**The situation.** The table host sends you the names of the people who will be sitting with them.

**What to do.** Add the guests to the table, with meal choices and any dietary requirements.

**What you should see.** Seats filled and seats remaining keeping count as you go. Try to add one more guest than the table holds and see what happens.

---

### Scenario 4: Turn a guest into a constituent

**The situation.** One of the guests is somebody JCRC will want to cultivate afterwards.

**What to do.** Mark that guest to be added as a contact.

**What you should see.** A Contact created from the guest. If the name resembles somebody already in the database, it should be flagged for you to check rather than quietly creating a duplicate or quietly merging.

---

### Scenario 5: Work the room list

**The situation.** It is the week of the event and you need the seating plan and the kitchen numbers.

**What to do.** Pull together who is sitting at which table, and the meal choices across the whole event.

**What you should see.** Something you could hand to the venue. Tell us what is missing from it.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### The guest list that will not sit still

Guests swap tables. A host gives up two seats. Somebody brings a partner nobody told you about. Two people at one table have the same name. Try all of it a week before the event.

### Money that is not a simple ticket

Somebody buys a table and adds a donation on top. Somebody sponsors a table for guests they will never meet. Somebody pays for half a table. See how the deductible split behaves.

### The guest who is already a donor

Add a guest whose name matches somebody in the database exactly, and another whose name is close but not identical. See which gets flagged and whether you agree with the judgment.

### Cancellations and refunds

A table cancels after paying. A guest drops out and is replaced. Record it and see whether the numbers and the seat counts stay honest.

### Tell us how JCRC really runs the gala

This part of the system is the least settled, because we are still waiting on the real levels and prices. Anything you can tell us about how the gala actually works is more useful here than a defect.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
