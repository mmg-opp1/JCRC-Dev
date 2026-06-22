# JSI-80 — Dictated Requirements (Cleaned Up)

> Source: `Story_Dictation.txt` (voice-dictated without punctuation). This is a
> cleaned, punctuated, and lightly organized version. Meaning preserved; no
> requirements added or removed. Reviewed by Jason Ott, 2026-06-18.
>
> **Scope note (added 2026-06-18):** JSI-80 covers the **manual / UI** side only.
> Item 3 below (automatic **QuickBooks/QBO** sync) is tracked in a **separate Jira
> story** and is therefore out of scope for JSI-80. It's retained here only to
> preserve the original dictation. See `JSI-80_Implementation_Plan.md` §1–2.

## Summary

This story is very much an **NPSP Gift Entry** story. The gist: we want a
**batch gift entry tab** in our main application where users can click in and
create new gift batches.

## Requirements as dictated

1. **Batch gift entry tab.** Users open the tab and create new gift batches from
   there.

2. **Multiple batch types, each with its own template.** Different kinds of gift
   batches should be available, for example:
   - A batch of paper checks.
   - A batch of stock certificates that all come in at one time.
   - A batch of ACH / wire transfers.

   Each of these should have a different template.

3. **Automatic sync of gift batches from QuickBooks (QBO).** A primary use case:
   paper checks are entered into QuickBooks first, then we build a process that
   fetches all of the checks entered into QuickBooks for a certain **deposit
   date** and pulls them in as a single batch.
   - Salesforce users then **verify** the data that comes over and **add** any
     data not in QuickBooks — e.g., contact information, demographics, address,
     and so on.

4. **Verification totals on the gift batch.** The batch should:
   - Track a **bank deposit** (or some similar key).
   - Match totals against a **batch header** — e.g., total count of gifts and
     total dollar value in the batch.

## Ask

Evaluate all of this against the standard NPSP documentation and what we need,
and produce an **implementation game plan** — what we'll need to add and how
we'll approach it. **Do not start building yet**; the deliverable is the plan.

> See `JSI-80_Implementation_Plan.md` for the resulting game plan.
