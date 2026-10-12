# Open Items — things left to revisit

> Running list kept by Jason Ott. Started 2026-10-09 after the Jotform pivot and the full-org UI refresh
> (`8ed04a5`). Strike items through (or delete them) as they close; add the date and commit.

## Gala / Jotform / contact matching

1. ~~**`EventRegistration_CheckForContact` is still Draft.**~~ DONE 2026-10-09 - Jason activated it.
13. **PT <-> Event Registration link depends on creation order.** `PendingTransaction_UpdateEventRegistration`
    (Jason, active 2026-10-09 19:37) runs on PT create and matches `External_Id__c` (the Jotform submission
    id). Tested 2026-10-09 with rollback: registration created first -> both lookups linked; PT created
    first -> NOT linked and never retried. Fix: a mirror flow on Event Registration create (recommended), or
    make sure the Jotform creates the registration before the PT. Until then a PT can commit without
    linking its registration.
2. **Jotform integration user access.** The Salesforce user Jotform connects as needs Apex class access to
   `ContactMatcher` / `ContactMatch` and access to `Event_Registration__c`. Need its profile name.
3. **JCRC - Fundraising: "Edit Read Only Fields" is OFF in JCRC-Dev**, but was granted for NPSP Gift Entry
   in JSI-80 (`d81dc04`). Setup Audit Trail: turned off 2026-10-08 17:07, one minute after Becca Zebovitz
   moved from System Administrator to JCRC - Fundraising. Intentional? See item 12 for what it broke.
4. **Old Gravity Forms endpoint** — `GalaSponsorReceiver` + `Gala_Submission__c` (`a5044ff`) are live and
   public but never used since the move to Jotform. Remove or keep?
5. **Gala money side not designed.** Jotform Pay Now → Pending Transaction; Pay Later → Pledge. Must also
   settle how a Stripe payout that lands in QuickBooks is not double-counted (same risk for website
   donations).

## Pending Transactions / QuickBooks (JSI-121)

6. **Fund map empty** — `QuickBooks_Fund_Map__mdt` needs Finance's list of QuickBooks income accounts;
   funds currently arrive blank.
7. **Finance's six questions unanswered** (`JSI-121/JSI-121_QuickBooks_Setup_Guide.md` §2). Import currently
   relies on the deposit line's payment method being "Wire-Transfer" (deposit 148 was skipped: no method).
8. **D12 to confirm:** a short pledge payment's unpaid remainder keeps the original installment's date.
9. **Sandbox clean-up:** SAMPLE-PT-1..5 and demo deposits PT-00012..15 still on the screen.
10. **Production not started:** Intuit production-keys questionnaire; `hooks` site does not exist in prod;
    QuickBooks credentials + scheduled jobs; website donations also not in prod, and
    `WebDonationProcessor` coverage (62.3%) blocks that deploy.

12. **Fundraisers cannot commit Pending Transactions (JCRC-Dev, since 2026-10-08).**
    `PendingTransactionServiceTest.fundraisingUserCanCommitGiftsAndPaymentsOnPledgesOwnedByOthers` now
    fails: as a JCRC - Fundraising user, the commit's plain `insert`/`update` on Opportunity, Payment and
    Pending Transaction are refused ("fields being inaccessible"). Passed 2026-09-16 (52/52); the only
    change to the profile since is item 3. Proven on 2026-10-09 with the tab-preference save: plain
    `upsert` was refused for a fundraiser, `Database.upsert(..., AccessLevel.SYSTEM_MODE)` worked.
    Fix options: make the commit Writer's DML explicitly SYSTEM_MODE, or re-enable the permission.
    2026-10-09: Jason - "ignore that for now". Its test is the one known failure (89/90 in the Pending
    Transactions + QuickBooks + payment suites); Pending Transactions deploys run tests separately until fixed.

## Payments (underpayment)

14. **Existing payments have no Original Payment Amount** (field added 2026-10-12, stamped only on new
    payments), so they can never show an Underpayment. Option: backfill UNPAID payments with their current
    amount (safe); paid ones can't be known for sure.
15. **Underpayment also shows on short payments committed from Pending Transactions**, whose remainder the
    commit already rescheduled as a new unpaid payment (JSI-121 rule 3). Decide whether that is wanted, or
    whether the remainder logic should become the one place underpayments are handled.
16. **Nothing yet acts on Underpayment** - spreading the shortfall over the remaining payments was not part
    of this request.

## Repo

11. **Unpushed commits** on `main` (18 as of the underpayment commit).
