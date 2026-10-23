# Script 2: Everyday Giving

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

Recording an ordinary gift and making sure it lands in the right place:

- Entering a gift from an individual or an organization
- Splitting one gift across more than one fund
- Giving somebody credit for a gift they did not personally write the check for
- Seeing a donor's history and what giving society they have reached
- Entering several gifts in one sitting

**Not in scope:** pledges paid over time, grants, non-cash gifts, tributes, and thank-you letters. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-80** Gift entry, **JSI-85** Contact roles and credit, **JSI-86** Gift designations |
| **Also touches** | **JSI-90** Annual Giving Summary and giving societies |

A gift is an **Opportunity**. The **Donation** record type is the everyday one. Each gift
has a primary contact, an amount, a close date, and usually a campaign.

Where the money is designated is recorded as a **GAU Allocation**, so one gift can be split
across several funds. Who gets credit is recorded as **Contact Roles** and **Soft Credits**, which
is how a gift from a family foundation can still show against the individual behind it.

Behind the scenes, every gift updates an **Annual Giving Summary** for that donor and fiscal
year. That is what decides whether someone has reached a giving society.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Opportunities**, **Contacts**, **Accounts**, **General Accounting Units**, and **Gift Entry**.
4. There are about **180 invented people** with **443 gifts** already recorded across the last two fiscal years, so reports and donor histories have something real in them.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Everyday Giving", so we can tell which part of the system your feedback is about
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

### Scenario 1: Record a gift from an individual

**The situation.** A check for $500 arrives from an existing donor.

**What to do.** Open the donor's Contact record and use the **New Contact Donation** button. Set the amount, the date it arrived, and a campaign. Save.

**What you should see.** The gift on the donor's record straight away. Check that it is credited to the person you expected and not only to their household.

---

### Scenario 2: Record a gift from an organization

**The situation.** A foundation sends a grant-like gift, and you know which person there arranged it.

**What to do.** Open the organization's Account and use **New Account Donation**. Record the gift, then add the individual as a contact role on it.

**What you should see.** The gift counts for the organization, and the individual is still visibly connected to it. Tell us whether the credit lands where JCRC would want it.

---

### Scenario 3: Split a gift across two funds

**The situation.** A donor gives $10,000 and asks that half go to security and half to general operations.

**What to do.** Open the gift and find the **GAU Allocations** related list. Split it across two General Accounting Units.

**What you should see.** The two allocations add up to the gift. Try making them not add up and see whether the system stops you.

---

### Scenario 4: Give someone soft credit

**The situation.** A gift arrives from a family fund, and the individual behind it should get recognition for it.

**What to do.** Open the gift and use **Manage Soft Credits** to credit the individual.

**What you should see.** The gift shows on the individual's record as a soft credit without double-counting the money. Check their total giving before and after.

---

### Scenario 5: Check a donor's giving history and society

**The situation.** You are preparing for a meeting and need to know what someone has given and where they stand.

**What to do.** Open a donor who has given a lot. Look at their giving history and their **Annual Giving Summary** records, one per fiscal year.

**What you should see.** Totals per year, and a giving society where they have reached one. There are donors in here at Congressional, Senate, Governor's, and President's level in both years. Tell us if the level names, thresholds, or the way it is displayed are wrong.

---

### Scenario 6: Enter several gifts in one sitting

**The situation.** The morning post has brought a dozen checks.

**What to do.** Go to the **Gift Entry** tab, at the end of the row of tabs, and work through entering a few gifts as a batch.

**What you should see.** Something faster than opening each donor separately. Tell us honestly whether you would use this or go back to entering them one at a time.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### Put a gift on the wrong donor, then fix it

Enter a gift against the wrong person and then move it. See whether the totals on both donors end up correct, and whether anything is left behind on the first one.

### The gift that changes after you save it

Change the amount. Change the date to last fiscal year. Change the designation after allocations exist. Watch what happens to the donor's totals and their giving society each time.

### Credit that is not obvious

A gift from a couple's joint account. A gift from a business owned by a donor. A gift where the check and the intent come from different people. Try to record those so the right person gets thanked and the right entity gets the receipt.

### The year boundary

The giving year runs July to June. Enter gifts dated the last week of June and the first week of July and see which year they count in.

### The biggest and smallest gift you can imagine

A $5 gift and a seven-figure gift. See whether anything rounds oddly, formats badly, or breaks a report.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
