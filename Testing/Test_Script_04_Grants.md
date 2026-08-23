# Script 4: Grants

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

A grant from application through to the final report:

- Recording a grant and the period it covers
- Tracking deadlines and what has to be delivered
- Recording payments against a grant
- Renewing a grant, and keeping the history of previous years
- Reporting on the grant pipeline

**Not in scope:** ordinary gifts, pledges from individuals, and thank-you letters. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-120** Grant lifecycle management |

A grant is an **Opportunity** with the **Grant** record type. Alongside the usual amount
and date it carries the contract number, the contract date, the grant period start and end, and
the program area.

Deadlines are tracked as **Grant Deadlines** underneath the grant, so reporting requirements and
interim submissions each have their own due date. A renewal points back at the grant it came
from, which is how a funder relationship stays visible across years.

Grant money that arrives in stages uses the same **Payments** mechanism as pledges.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tab you need is **Opportunities**, plus **Reports** for the **Pledge and Grant Reports** folder.
4. **There are no grants in the sandbox yet.** You will be creating them from scratch in this script, which is deliberate. Tell us if anything about setting one up feels wrong or missing.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Grants", so we can tell which part of the system your feedback is about
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

### Scenario 1: Record a new grant

**The situation.** A foundation has awarded JCRC a two-year grant.

**What to do.** Create a new Opportunity and choose the **Grant** record type. Set the funder as the account, the amount, the contract number and date, and the grant period start and end. Pick a program area.

**What you should see.** A grant record that holds everything you would need to answer a question about it a year from now. Tell us about any field JCRC tracks that is not there, or any field here that JCRC would never fill in.

---

### Scenario 2: Add the reporting deadlines

**The situation.** The grant agreement requires an interim report at six months and a final report at the end.

**What to do.** On the grant, find the deadlines and add both, each with its due date.

**What you should see.** The deadlines listed against the grant, with the next one due surfaced on the grant itself.

---

### Scenario 3: Record the money arriving in stages

**The situation.** Half the grant is paid on signature and half on the interim report.

**What to do.** Set up two payments against the grant with their expected dates, then mark the first one received.

**What you should see.** The grant shows what has been received and what is still to come.

---

### Scenario 4: Renew a grant

**The situation.** The funder has renewed for another year.

**What to do.** Create the new year's grant and link it back to the previous one, marking it as a renewal.

**What you should see.** A chain you can follow backwards. From the new grant you should be able to get to last year's, and see the history of the relationship.

---

### Scenario 5: See the grant picture

**The situation.** Leadership asks what grant income is committed and what is coming up.

**What to do.** Go to **Reports** and look in the **Pledge and Grant Reports** folder, then build or adapt a report for grants specifically.

**What you should see.** A view of the grant pipeline. This area has fewer ready-made reports than the others, so tell us what you would want to see and we will build it.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### The grant that does not fit the shape

A grant paid in one lump. A grant with no end date. A grant that spans three fiscal years. A grant that is really a sponsorship. Try each and see where the record type fights you.

### Miss a deadline

Set a deadline in the past and see whether anything surfaces it. If an overdue grant report can be missed silently, that is worth knowing now.

### The grant that gets cut

The funder awards less than requested, or pays part and cancels the rest. Record that and see whether the numbers stay honest.

### The renewal chain

Build three years of renewals and then try to answer: how much has this funder given us in total, and how long have they supported us? See how hard that is.

### Your most complicated real grant

The one with the awkward reporting requirements or the strange payment terms. Try it here.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
