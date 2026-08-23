# Script 7: Thank-Yous and Acknowledgments

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

Getting the right letter to the right person, saying the right thing, quickly:

- Finding the gifts that still need to be thanked
- Seeing the letter a gift will produce
- Sending a letter to print, and sending one by email
- The different letters for different kinds of donor and different campaigns
- Keeping an eye on how quickly gifts are being acknowledged

**Not in scope:** the tribute notification to an honoree, which is covered in the tributes script.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-87** Acknowledgement letters and routing |
| **Also touches** | **JSI-124** Donor advised fund approval gate |

Every gift carries an acknowledgement **status**, a **channel** of print or email, and the
name of the **template** it should use.

A routing rule decides which template a gift gets, based on things like the campaign it belongs
to, whether the donor is a current board member, and whether the gift is tax deductible. Campaign
templates win over donor templates, so a board member giving to the parade gets the parade letter.

The letter itself is generated on the gift record, on JCRC letterhead, ready to print. Email
acknowledgements go through Salesforce using the JCRC development address.

There are six letters in total: a standard one, a parade one, and a board one, each in a
deductible and a non-deductible version.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Opportunities** and **Reports**. Acknowledgement reports are in the **Acknowledgment Reports** folder.
4. There are around **17 gifts waiting to be acknowledged** in the sandbox, and about 400 already marked done, so the queue looks like a normal working Monday rather than a backlog.
5. The invented donors all have addresses ending in example.com, which cannot receive email. If you want to see an email actually arrive, put **your own address** on a test contact and use that person.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Thank-Yous and Acknowledgments", so we can tell which part of the system your feedback is about
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

### Scenario 1: See what still needs thanking

**The situation.** It is Monday morning and you want to clear the acknowledgement queue.

**What to do.** Go to **Reports**, open the **Acknowledgment Reports** folder, and run **Gifts Pending Acknowledgment**.

**What you should see.** A working list of gifts waiting. Tell us if it is missing information you would need to work through it efficiently.

---

### Scenario 2: Look at the letter a gift will produce

**The situation.** Before sending anything, you want to see what the donor will actually receive.

**What to do.** Open one of the waiting gifts and scroll down the record page. The letter is generated there, on the page.

**What you should see.** A one-page letter on JCRC letterhead, addressed properly, with the right amount and date. **Read the wording closely.** The copy came from the templates JCRC supplied, and this is the moment to correct it.

---

### Scenario 3: Send a letter to print and mark it done

**The situation.** You have printed the letters and put them in envelopes.

**What to do.** Print or save the letter from the gift record, then mark the gift as acknowledged.

**What you should see.** The gift leaves the pending list and carries the date it was acknowledged.

---

### Scenario 4: Send a thank-you by email instead

**The situation.** A donor gave online and would rather be thanked by email.

**What to do.** Set the gift's acknowledgement channel to email and use the **Email Acknowledgment** button. Use a contact with your own address on it so you can see what arrives.

**What you should see.** An email that reads well, comes from the right address, and does not land in spam. Check it on your phone as well as your computer.

---

### Scenario 5: Check that the right people get the right letter

**The situation.** Different donors should get different letters, and you want to be sure the rules are right.

**What to do.** Compare three gifts: an ordinary donor's gift, a gift to the **FY27 Israel Parade** campaign, and a gift from one of the three board members. Look at the letter each one produces.

**What you should see.** Three different letters. A board member who gives to the parade should get the **parade** letter, because campaign wins over donor type. Tell us if that priority is wrong for JCRC.

---

### Scenario 6: Check how quickly gifts are being thanked

**The situation.** JCRC has a standard for how fast donors are thanked and you want to see whether it is being met.

**What to do.** Run **Acknowledgment SLA Over 48 Business Hours**.

**What you should see.** Anything that has been sitting too long. Tell us whether 48 business hours is the right target.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### Change the gift after you have thanked for it

Thank a donor, then change the amount, the campaign, or the donor on that gift. Should it go back in the queue? See what actually happens and tell us what you would want.

### The letter that does not fit

A very long name. An organization with no individual contact. A donor with no address. An anonymous gift. Generate letters for each and see which ones come out wrong.

### A gift that should never be thanked

A refund, a duplicate entry, a gift from a fund that has already been thanked. Find the way to take it out of the queue without pretending you sent something.

### Clear the whole queue

Work every gift in the pending list as fast as you can, as if it were a real Monday. Tell us how long it took and where you lost time.

### The letter you would never send

Look hard at the wording of all six letters and tell us anything JCRC would not put its name to.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
