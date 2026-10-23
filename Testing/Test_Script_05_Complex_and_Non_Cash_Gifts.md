# Script 5: Complex and Non-Cash Gifts

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

The gifts that are not simply a check, and the tax questions that come with them:

- Gifts of goods or services rather than money
- Gifts of stock
- Employer matching gifts
- Gifts that arrive through a donor advised fund
- What portion of each of these is tax deductible

**Not in scope:** ordinary cash gifts, pledges, grants, and gala tickets. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-84** In-kind and non-cash gifts, **JSI-86** Designations, **JSI-124** Donor advised fund acknowledgements |
| **Also touches** | **JSI-85** Contact roles and credit |

Each of these is an **Opportunity** with its own record type: **In-Kind Gift**, **Securities
Gift**, and **Matching Gift**.

An in-kind gift carries its worth in **Fair Market Value** rather than Amount, so that goods and
services do not inflate cash income. A securities gift records the shares.

A donor advised fund gift is different again. The money legally comes from the fund, so the
**Account** on the gift is the fund itself, with a record type of Fund. The individual who advised
the gift is the primary contact and receives soft credit. Because a DAF gift cannot legally carry
a benefit back to the donor, its acknowledgement is held for approval rather than going out
automatically.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tab you need is **Opportunities**, plus **Reports** for the **Acknowledgment Reports** folder.
4. There are in-kind and matching gifts in the sandbox already. **There are no securities gifts and no DAF gifts yet**, so you will create those yourself, which is the point.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Complex and Non-Cash Gifts", so we can tell which part of the system your feedback is about
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

### Scenario 1: Record a gift of goods

**The situation.** A caterer donates food for an event, worth about $3,000.

**What to do.** Create an Opportunity with the **In-Kind Gift** record type. Record what was given and what it was worth.

**What you should see.** The value recorded as fair market value, not as cash income. Check the donor's total giving before and after: their cash total should not move. Tell us if that is not how JCRC wants it counted.

---

### Scenario 2: Record a gift of stock

**The situation.** A donor transfers shares to JCRC.

**What to do.** Create an Opportunity with the **Securities Gift** record type. Record the number of shares and the value.

**What you should see.** Enough detail that Finance could reconcile it against the brokerage statement. Tell us what is missing for that.

---

### Scenario 3: Record a matching gift

**The situation.** A donor's employer matches their gift.

**What to do.** Find an existing gift from an individual, then use **Find Matched Gifts** on it, or create an Opportunity with the **Matching Gift** record type linked to the original.

**What you should see.** The match connected to the original gift and credited to the employer, while the donor still gets recognition for prompting it.

---

### Scenario 4: Record a gift from a donor advised fund

**The situation.** A gift arrives from a family fund, advised by one of your donors.

**What to do.** First create the fund as an Account with the **Fund** record type if it does not exist. Then create the gift with the fund as the account, the individual as the primary contact, and tick the **DAF Gift** box.

**What you should see.** The money credited to the fund, with the individual soft credited. The acknowledgement should **not** go out on its own: it should be waiting for approval.

---

### Scenario 5: Approve a DAF acknowledgement

**The situation.** You need to check the DAF gifts waiting to be thanked before anything is sent.

**What to do.** Go to **Reports**, open the **Acknowledgment Reports** folder, and run **DAF Gifts Pending Approval**. Open one and approve it.

**What you should see.** Nothing goes to the donor until you approve it. Tell us whether this gate is in the right place, and whether the right person would be the one approving.

---

### Scenario 6: Answer a deductibility question

**The situation.** A donor's accountant calls in January and asks what is deductible from last year.

**What to do.** Pull together what that donor gave, across all of these gift types.

**What you should see.** Something you could read down the phone with confidence. This is the scenario most likely to expose a gap, so please be hard on it.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### The in-kind gift nobody can value

Donated legal advice. A venue lent for free. Something whose worth is genuinely unclear. Record it and see whether the system forces you to invent a number.

### The DAF gift where you do not know the donor

A fund sends money and the advisor is not in your database, or is listed only as the fund's name. Try to record it so the right person can be thanked next time.

### The match that does not match

An employer matches at a different ratio, matches late, matches a pledge rather than a gift, or matches only part. See how far the matching gift record bends.

### Deductibility edge cases

A gift that is part goods and part cash. A stock gift that changes value between the promise and the transfer. Anything where the receipt figure and the recorded figure would differ.

### An open question we would like your view on

If a donor advised fund pays for a gala ticket, part of that ticket is a benefit back to the donor, which DAF rules do not allow. JCRC has not settled how to handle that. Try it in the system and tell us what you think should happen.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
