# Script 10: Website Donations

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

A gift given on jcrcny.org arriving correctly in Salesforce, without anyone retyping it:

- Seeing what came in from the website
- Checking that it became the right gift, for the right donor
- Handling a donor who chose Other and typed their own campaign
- Finding submissions that failed, and sending them through again
- Deciding where the money should be designated

**Not in scope:** gifts entered by hand, and the thank-you letter the donor receives. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **Website Donations** integration, **JSI-127** Other campaigns from the website |

When somebody donates on the website, the form sends the submission straight to Salesforce.
It is stored first as a **Web Donation** record, exactly as it arrived, before anything is
interpreted. That way nothing is ever lost, even if the interpretation later turns out to be
wrong.

The submission is then turned into a gift using a **mapping** that says which field on the form
becomes which field in Salesforce, how to find an existing donor rather than creating a duplicate,
and what to do when no match is found. That mapping is configurable on screen, so adding a new
question to the form does not need a developer.

If a submission fails, it stays on the Web Donation record with the reason, and can be sent
through again once the problem is fixed.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **JCRC Administration**.
3. The tabs you need are **Web Donations** and **Web Donation Mapping**, plus **Reports**. Website reports are in the **Website Donation Reports** folder.
4. You will also want the **Development** app open to look at the gifts that come out of the other end.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Website Donations", so we can tell which part of the system your feedback is about
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

### Scenario 1: Look at what came in from the website

**The situation.** You want to see the donations that have arrived online since yesterday.

**What to do.** Open the **Web Donations** tab and look at the list. Open one.

**What you should see.** The submission as the donor filled it in, and its status. Tell us whether the list shows enough for you to spot a problem at a glance.

---

### Scenario 2: Follow a submission through to the gift

**The situation.** You want to be confident the online gift became the right record.

**What to do.** From a processed Web Donation, follow the link to the gift it created, and to the donor it was matched to.

**What you should see.** A gift with the right amount, date, and donor. Check especially that an existing donor was matched rather than a second copy of them being created.

---

### Scenario 3: Handle an Other campaign write-in

**The situation.** A donor picked Other on the form and typed in what they wanted to support.

**What to do.** Go to **Reports**, open **Website Donation Reports**, and run **Other Campaign Write-Ins to Review**. Work one of them onto the right campaign.

**What you should see.** A short list of gifts needing a human decision, rather than those gifts silently going somewhere wrong. Tell us how often you think this will happen in practice.

---

### Scenario 4: Find and fix a failure

**The situation.** Somebody mentions a donation that never appeared.

**What to do.** Run **Web Donations Failed**. Open one, read why it failed, and use the **Replay** button on the record to send it through again.

**What you should see.** A clear reason, and a gift created on replay once the cause is fixed. Tell us whether the failure message is understandable to somebody who is not a developer.

---

### Scenario 5: See where the money should go

**The situation.** A donor chose a specific programme to support on the form.

**What to do.** Run **Web Donations Unmapped Designations**.

**What you should see.** **This is the scenario we most need your input on.** Right now website gifts arrive correctly but the designation the donor chose is not yet allocated to a fund, because JCRC has not settled whether those should map to a General Accounting Unit or to a Campaign. Look at what donors are choosing on the form and tell us where each one should land. That answer is what unblocks this.

---

### Scenario 6: Look at the mapping screen

**The situation.** A new question has been added to the donation form and it needs to reach Salesforce.

**What to do.** Open the **Web Donation Mapping** tab and look through the tabs across it: the field mapping, the value translation, the donor and account rules, and the dry run.

**What you should see.** Something you could imagine an administrator at JCRC maintaining without calling us. If it looks like something only a developer could touch, say so plainly.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### Send the same gift twice

A donor double-clicks the submit button, or refreshes and submits again. See whether you end up with one gift or two, and which you would want.

### The donor the system half recognises

Somebody who gives online using a different email from the one you hold, or a nickname, or their work address. See whether they are matched, duplicated, or left in limbo.

### A gift from an organization

Somebody donates on behalf of their company or their family foundation through the public form. See where that money lands and whether it is where JCRC would want it.

### Awkward text

Accented characters, an apostrophe in a surname, a very long write-in, an emoji in the notes field. See what survives the trip.

### Tell us what the form should ask

Now that you can see how a submission arrives, tell us anything the website form should be capturing that it does not.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
