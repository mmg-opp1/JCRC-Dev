# Script 3: Pledges and Installments

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

A commitment paid over time, from the promise through to the last payment:

- Recording a pledge and the schedule it will be paid on
- Taking a payment against a pledge
- Seeing what is still outstanding and what is overdue
- Writing off an installment that is never going to arrive
- What the donor is told when a payment lands

**Not in scope:** one-off gifts, grants, and thank-you letters for the original pledge. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-82** Pledges, **JSI-125** Paid installment notifications, **JSI-126** Outstanding payment reporting |
| **Also touches** | the Pledge Health dashboard |

A pledge is an **Opportunity** with the **Pledge** record type. Underneath it sit
**Payments**, one per installment, each with a scheduled date, an amount, and a paid flag.

The difference between a scheduled payment and a paid one is what drives every outstanding
report. A payment can also be **written off**, which takes it out of the outstanding figures
without pretending it was received.

When an installment is marked paid, the donor is emailed to confirm it, with the amount, the
total paid so far, and what is left. When the final installment lands, the pledge itself is
completed and a separate message goes out, so a donor paying four installments at once does not
get four completion emails.

You do not need to understand any of this to test it.

## Worth knowing before you start

One of the scenarios below sends an email to a donor. Every invented donor in the
sandbox has an address ending in example.com, which cannot receive anything, so you will not see
those. If you want to watch an email actually arrive, put **your own email address** on a test
contact first and use that person.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Opportunities** and **Reports**. The pledge reports live in the **Pledge and Grant Reports** folder, and there is a **Pledge Health** dashboard.
4. There are **30 pledges** already in here, deliberately in five different states: on schedule, fully paid, overdue, partly written off, and not yet started. About **$120,000** across 30 installments is overdue on purpose.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Pledges and Installments", so we can tell which part of the system your feedback is about
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

### Scenario 1: See what money is outstanding

**The situation.** Someone asks how much pledged money JCRC is still waiting on.

**What to do.** Go to the **Reports** tab, open the **Pledge and Grant Reports** folder, and look at **Outstanding Pledges** and **Overdue Pledges**.

**What you should see.** Figures you would be willing to quote. Check that written-off installments are not being counted as outstanding, because they should not be.

---

### Scenario 2: Record a new pledge with a schedule

**The situation.** A donor commits $20,000 over two years, paid quarterly.

**What to do.** Create a new Opportunity and choose the **Pledge** record type. Set the amount and the date. Then build the installment schedule underneath it.

**What you should see.** A schedule that adds up to the pledge. Tell us if building the schedule takes more effort than it should.

---

### Scenario 3: Take a payment

**The situation.** The first installment cheque arrives.

**What to do.** Open a pledge, find the payment that is due, and mark it paid with the date it arrived.

**What you should see.** The pledge balance drops. The donor is emailed a confirmation with the amount, the total paid to date, and what remains. Check the wording of that email carefully. It goes to donors.

---

### Scenario 4: Finish a pledge

**The situation.** A donor pays off the rest of their pledge in one go.

**What to do.** Find a pledge with more than one installment left and mark them all paid.

**What you should see.** The pledge is recognised as complete. Importantly, the donor should get **one** completion message, not one per installment. Tell us immediately if you see duplicates.

---

### Scenario 5: Write off an installment

**The situation.** A donor has told you they cannot pay the rest of their pledge.

**What to do.** Find an unpaid installment and write it off rather than deleting it.

**What you should see.** It leaves the outstanding figures but the history of the promise stays. Check the **Pledge Write-Offs** report afterwards.

---

### Scenario 6: Plan the year ahead

**The situation.** Finance wants to know what pledge income to expect and when.

**What to do.** Look at **Pledge Payments Due This FY**, **Outstanding Installments by Month**, and **Pledge Payment Aging**.

**What you should see.** Something you could hand to Finance. If the way it buckets months or ages is not how JCRC thinks about it, say so.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### Pay the wrong amount

Record a payment for more than the installment. Record one for less. Record a payment twice. See what the balance does and whether the donor gets told something confusing.

### Change the deal after it is made

Reschedule a pledge that is already part paid. Increase the total. Reduce it below what has already been received. See whether the schedule and the balance keep up.

### Bring a write-off back

Write an installment off, then imagine the donor pays after all. Try to undo it and see whether the reports agree with you afterwards.

### The donor who pays their own way

Someone who pays monthly against a quarterly schedule. Someone who pays a year in advance. Someone who pays a round number that does not match any installment.

### The year boundary

The giving year runs July to June. Put installments either side of 30 June and see which year the reports count them in.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
