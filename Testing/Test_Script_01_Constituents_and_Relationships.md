# Script 1: Constituents and Relationships

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

Everything to do with the people and organizations in the database:

- Finding someone who is already in there
- Adding a new individual or organization
- Households, and who belongs to one
- Where someone works or worships, and what they do there
- Family and personal relationships between constituents
- Tagging people so you can find groups of them later

**Not in scope:** gifts of any kind, thank-you letters, and board service. Those have their own scripts.

## How it works

| | |
|---|---|
| **Stories covered** | **JSI-122** Tagging and segmentation |
| **Also touches** | **JSI-89** Duplicate handling, and the NPSP household model |

Every person is a **Contact**, and every Contact sits inside an **Account**. For an
individual donor that Account is their **household**, and Salesforce creates it for you when you
create the person. Organizations are Accounts too, with a record type of Organization or Fund.

A person's link to an organization is an **Affiliation**, which carries their role and whether it
is current. A link between two people is a **Relationship**. When you record one side of a
relationship, the system writes the other side for you.

**Tags** are a controlled list, grouped into categories such as Geographic, Skills, Employment,
and Interest. They live on the Contact record and are what you use to pull a group together
later.

You do not need to understand any of this to test it.

## Before you start

1. Log in to the **Salesforce Sandbox** using the link and password sent separately. Please use your own login rather than a shared one, so we can follow up with you on what you find.
2. Top-left, use the **App Launcher** (the grid of dots) and choose **Development**.
3. The tabs you need are **Contacts** and **Accounts**.
4. There are about **180 invented people** in here already, with two years of giving history. Every name is made up; any resemblance to a real donor is coincidence. Two of them share a name on purpose.

## Recording your feedback

Use the **JCRC Implementation Testing Feedback Log**, the shared spreadsheet on SharePoint, on
the **Sprint 1** tab. There is an example row at the top showing the kind of thing we are after.
One row per item.

Please fill in these columns:

- **Testing Script**: put "Constituents and Relationships", so we can tell which part of the system your feedback is about
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

### Scenario 1: Find someone who is already in the database

**The situation.** Someone calls and you need to pull up their record while they are on the phone.

**What to do.** Use the search box at the very top of the screen. Try a surname you have seen on the **Contacts** tab, then try only part of a name, then try an email address.

**What you should see.** The person, quickly, without you having to know which tab to be on first. Tell us if search finds them by some things and not others.

---

### Scenario 2: Add a new individual donor

**The situation.** A check arrives from someone who has never given before.

**What to do.** Go to the **Contacts** tab and click **New**. Fill in a name and a mailing address. Save.

**What you should see.** You are never asked to create a household. Open the new person and look at their Account: a household should already exist for them, named after them. Tell us if the household name is not what JCRC would call it.

---

### Scenario 3: Add an organization and connect someone to it

**The situation.** A foundation has made contact, and you know who your contact there is.

**What to do.** Go to the **Accounts** tab and click **New**. Choose the **Organization** record type. Save it, then open a Contact and use the **Affiliations** related list to link them to the organization, with a role and a start date.

**What you should see.** The affiliation shows on both the person and the organization. Mark it Former and see whether it stops counting as current.

---

### Scenario 4: Record a family relationship

**The situation.** You learn that two of your donors are married.

**What to do.** Open one of them, find the **Relationships** related list, and add the other with the appropriate type.

**What you should see.** You should only have to enter this once. Open the other person and check that the matching relationship is already there, pointing back the other way, without you creating it.

---

### Scenario 5: Tag a constituent

**The situation.** You have learned that a donor is a Hebrew speaker, sits on another board, and lives in Queens.

**What to do.** Open their Contact record and find the tagging panel. Use **Add a tag**, pick a **Category**, then the tag itself. Add two or three.

**What you should see.** The tags stick to the person and are visible at a glance next time you open them. Tell us if a tag you need does not exist, or if the categories are not how JCRC thinks about people.

---

### Scenario 6: Pull together everyone who shares a tag

**The situation.** You are planning an event and want everyone tagged for a particular interest or neighbourhood.

**What to do.** Go to the **Reports** tab and build or find a report on tagged constituents. Group it by tag or by category.

**What you should see.** A list you could actually work from. If it is hard to get from a tag to a list of people, that is exactly what we want to hear about.

---

# Part 2: Try to break it

Part 1 covered what we expect people to do. This part is about everything else.

Pick a fight with it. Do what a distracted person does at 4:45 on a Friday. Take the strangest
real situation you can remember and throw it at the system. Anything you find here is worth more
to us than a clean run through Part 1.

You do not need to stick to the suggestions below.

### Create a duplicate on purpose

Enter someone who is already in the database, using a slightly different spelling or a nickname. See whether the system warns you, and see what happens if you push past the warning. Then try to work out how you would merge them back together.

### The household that is not a household

Two people at one address who are not a couple. A donor who gives from a personal account and a business account. A family where the check comes from one person but the recognition should go to both. Try to model those and see where it fights you.

### Someone whose details change

A donor moves. Someone changes their surname. A contact leaves the organization you had them affiliated with. Make those changes and see whether the old information is kept where it should be and dropped where it should not.

### The thin record

Create someone with almost nothing filled in, then try to find them again a few minutes later. About a third of the people in here deliberately have no tags and no employer, so go looking for those too.

### Your messiest real constituent

The one whose record nobody can ever keep straight. Try to build them here.

---

## Questions

If anything is unclear, or you want a hand getting started, contact **Jason Ott**. Please do not
spend more than a few minutes stuck on any one thing.

Thank you. Your time on this makes a real difference to what you end up working with every day.
