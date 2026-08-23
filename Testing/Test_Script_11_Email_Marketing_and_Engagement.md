# Script 11: Email Marketing and Engagement

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

What JCRC sends by email, and what constituents do with it:

- Which mailing lists a constituent is on
- What emails a constituent has been sent, and whether they opened them
- How a send performed overall
- Connecting an email send to a campaign
- Keeping subscriptions and preferences honest

**Not in scope:** acknowledgement emails and installment notifications, which are sent by Salesforce and covered in their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-107**, **JSI-108**, **JSI-109** Constant Contact integration |
| **Also touches** | **JSI-50** and **JSI-55**, which were resolved without a Salesforce build |

JCRC sends its mass email through Constant Contact rather than Salesforce. The integration
brings the results back, so that a fundraiser looking at a donor can see what that donor has been
sent without leaving Salesforce.

Each send comes back as a **CC Email** record with its totals: how many were sent, opened,
clicked, and bounced. Underneath it, one **CC Email Activity** record per constituent records what
that individual did, and links to their Contact.

A constituent's list subscriptions are shown on their Contact record, so you can answer "what is
this person signed up for" in one place. The sync runs every hour.

You do not need to understand any of this to test it.

## Worth knowing before you start

**The sandbox has no Constant Contact data in it yet.** There are no email sends and no
activity records to look at, because the sandbox is not connected to a Constant Contact account
holding real sends.

That is deliberate rather than an oversight, and it does change what this script is for. Please
still work through the scenarios as far as you can, and treat the empty screens as the question:
**what would you expect to see here, and would it be enough to do your job?** Your answer is what
we will build to.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Contacts**, **Campaigns**, and **Reports**. Email records are reached from a Contact or through search.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Email Marketing and Engagement", so we can tell which part of the system your feedback is about
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

### Scenario 1: See what a constituent is signed up for

**The situation.** A donor rings and asks what they are on the mailing list for.

**What to do.** Open their Contact record and find the subscriptions panel.

**What you should see.** The lists they belong to, in language you could read back to them on the phone.

---

### Scenario 2: See what a constituent has been sent

**The situation.** Before a meeting, you want to know what this donor has been hearing from JCRC.

**What to do.** From the Contact record, look at their email activity.

**What you should see.** The emails they were sent, and whether they opened or clicked. Tell us whether this is the level of detail a fundraiser actually wants, or too much.

---

### Scenario 3: Look at how a send performed

**The situation.** The Director asks how last week's newsletter did.

**What to do.** Find the email send record and look at its totals.

**What you should see.** Sends, opens, clicks, and bounces. Tell us which numbers JCRC actually reports on and whether any are missing.

---

### Scenario 4: Connect a send to a campaign

**The situation.** An appeal went out by email and you want to see what it raised.

**What to do.** Link the email send to the campaign it belongs to, then look at the campaign.

**What you should see.** The email and the money it brought in visible together. This is the join most likely to be imperfect, so please push on it.

---

### Scenario 5: Check a preference change

**The situation.** A donor asks to be taken off one list but kept on another.

**What to do.** Work out how you would do that, and what happens next time the hourly sync runs.

**What you should see.** A clear answer about where preferences are actually controlled, in Constant Contact or in Salesforce. If that is not obvious, that is a finding.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### The person on two lists under two email addresses

A constituent signed up with a personal address and a work address. See whether they show as one person or two, and what that does to the numbers.

### Someone who unsubscribes

Follow what happens to a constituent who opts out, and make sure nothing in Salesforce would let somebody email them anyway.

### The bounce

A donor changes jobs and their address stops working. See whether Salesforce shows you that, and whether a fundraiser would notice before sending them something important.

### Numbers that should agree

Compare what Constant Contact says about a send with what Salesforce says. Any difference is worth telling us about, even a small one.

### Tell us what you would want to see

This is the least finished area of the system, so a description of what good would look like is worth more to us than a defect right now.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
