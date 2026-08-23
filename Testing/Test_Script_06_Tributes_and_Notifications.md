# Script 6: Tributes and Notifications

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

Gifts given in honour or in memory of somebody, and telling the right person about them:

- Recording that a gift is in honour of, or in memory of, someone
- Handling an honoree who is already in the database, and one who is not
- Notifying the honoree or the family, and recording that you did
- Seeing all the gifts connected to one honoree

**Not in scope:** the thank-you letter to the donor themselves, which is covered in the acknowledgments script.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-89** Tribute gifts and notifications |

A tribute is recorded on the gift itself: the **tribute type**, which is honour or memory,
and who the tribute is for.

Where the honoree already exists in the database, the gift links to their record, so you can see
everything given in their name over time. Where the name is typed in free, the system flags the
gift for review so somebody can decide whether it is a person already known to JCRC.

Separately from thanking the donor, there is a **notification** to the honoree or the family, with
its own status and date, so you can tell at a glance who still needs to be told.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Opportunities** and **Reports**. Tribute reports are in the **Tribute Gifts Reports** folder.
4. There is only **one tribute gift** in the sandbox, so most of this script has you creating them. That is deliberate.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Tributes and Notifications", so we can tell which part of the system your feedback is about
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

### Scenario 1: Record a gift in honour of someone

**The situation.** A donor gives in honour of a friend's milestone birthday, and the friend is already a JCRC constituent.

**What to do.** Create a gift and set the tribute type to honour, then connect it to the honoree's existing record.

**What you should see.** The tribute recorded against the gift, and visible from the honoree's record too.

---

### Scenario 2: Record a gift in memory of someone

**The situation.** A donor gives in memory of a relative who is not in the database.

**What to do.** Create the gift and record the tribute with the name typed in.

**What you should see.** The gift saved without forcing you to create a Contact for the deceased. It should be flagged for review so somebody can check later whether that person is already known to JCRC.

---

### Scenario 3: Tell the family

**The situation.** You need to write to the family to let them know a gift was made in their relative's memory, without telling them the amount.

**What to do.** Go to **Reports**, open **Tribute Gifts Reports**, and run **Tributes To Be Notified**. Work one of them and mark it notified.

**What you should see.** A working list that shrinks as you clear it. Check carefully that nothing in what you would send exposes the gift amount unless JCRC wants it to.

---

### Scenario 4: See everything given in one person's name

**The situation.** A family asks how much has been given in memory of their relative.

**What to do.** Run **Tribute Gifts by Honoree**.

**What you should see.** All the gifts grouped by the person honoured, including ones where the name was typed in rather than linked. Tell us if free-typed names splinter into several groups when they should be one.

---

### Scenario 5: Clean up a flagged tribute

**The situation.** A tribute name was typed in, and it turns out that person is in the database after all.

**What to do.** Find the flagged gift and connect it to the right Contact.

**What you should see.** The gift joins that honoree's history, and the flag clears.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### The honoree who is also the donor

Somebody gives in honour of themselves, or in honour of their own late spouse who is also in the database as a former donor. See what the system does.

### Names that do not quite match

Enter the same honoree three times with slightly different spellings, a nickname, and a title. Then try to answer how much has been given in their name.

### Nobody to notify

A tribute where you have no address for the family, or where the family has asked not to be contacted. Make sure there is a way to record that so nobody writes to them by mistake.

### Many gifts, one honoree

A well-known person dies and thirty gifts arrive in a fortnight. Record several and then work out how you would notify the family once rather than thirty times.

### Your most sensitive real example

Tributes are the area where getting it wrong hurts most. Try the situation you would most dread handling badly.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
