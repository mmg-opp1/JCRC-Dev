# Open Items â€” things left to revisit

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
4. **Old Gravity Forms endpoint** â€” `GalaSponsorReceiver` + `Gala_Submission__c` (`a5044ff`) are live and
   public but never used since the move to Jotform. Remove or keep?
5. **Gala money side not designed.** Jotform Pay Now â†’ Pending Transaction; Pay Later â†’ Pledge. Must also
   settle how a Stripe payout that lands in QuickBooks is not double-counted (same risk for website
   donations).

## Pending Transactions / QuickBooks (JSI-121)

6. ~~**Fund map empty**~~ REPLACED 2026-10-23 - the fund now comes from the QuickBooks class (Jason: accounts no
   longer used). One record: `Development:Dinner` → Gala Fund (gala). Other classes arrive with fund blank + note;
   add records if Finance wants more classes mapped.
7. **Finance's six questions unanswered** (`JSI-121/JSI-121_QuickBooks_Setup_Guide.md` Â§2). Import currently
   relies on the deposit line's payment method being "Wire-Transfer" (deposit 148 was skipped: no method).
8. **D12 to confirm:** a short pledge payment's unpaid remainder keeps the original installment's date.
9. **Sandbox clean-up:** SAMPLE-PT-1..5 and demo deposits PT-00012..15 still on the screen.
10. **Production not started:** Intuit production-keys questionnaire; `hooks` site does not exist in prod;
    QuickBooks credentials + scheduled jobs; website donations also not in prod, and
    `WebDonationProcessor` coverage (62.3%) blocks that deploy.
23. **Checks import like ACH/wire (built 2026-10-23).** Default check methods Amazon Smile, Benevity, Check,
    E-Check (all become Check); large-deposit safeguard built. Check deposit seen live 2026-10-23 (deposit 151 ->
    PT-00028/29, Check). Open: a Receive Payment against an invoice with a class, then deposited - confirm the row
    and its fund.
24. **Test coverage blocks production deploys of four classes (found 2026-10-23).** WebDonationMappingController 0%,
    ThankYouLetterController 0%, WebDonationConfig 73.8%, WebDonationProcessor 62.3% (also item 10). The spelling
    sweep went to JCRC-Dev with NoTestRun (sandbox only) after 152/152 tests passed; production needs tests first.
25. **Test Script 03 Word file still says "cheque" / "recognised".** It was open in Word during the American
    spelling sweep, so only its .md was fixed. Rebuild it with `Testing/tools/md_to_docx.py` once closed
    (it has no hand edits; 01/02/08 do, and needed no change).
26. **Production for fund-from-class (built 2026-10-23).** Create fund "Gala Fund" and tick Gala (needs item 20's
    `Gala__c` deploy first); turn on class tracking in the production QuickBooks company with the classes
    Development and Development:Dinner; deploy `QuickBooks_Fund_Map.Development_Dinner` with the code. If the
    production fund is named differently, change the record's Fund (GAU) Name to match.

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

## Flow modal launcher

17. **`flowModalLauncher` buttons are Jason's to set up.** Component built and deployed (`ace40b5`); no
    list buttons point at it yet. First intended use: `Screen_BulkAddTickets` from Event Registration.
    Known limit (platform): the record page is not visible behind the modal.

## Board Management (JSI-123)

18. ~~**Manage Members: names not clickable.**~~ DONE 2026-10-13 - committee member names link to the
    contact record, same as the Roster tab. Client to confirm.
19. **Same gap elsewhere?** Names on the board-meeting and committee-meeting attendance sheets are still
    plain text. Not requested; ask the client whether they want those linked too.

22. **Board Role sync is one-way (built 2026-10-13).** Roster's Role = Board Term "Board Role (Current)",
    now copied from the Role on the term's current Board Membership Year (on save + nightly 2 AM).
    Editing Board Role directly on the term is overwritten by the next sync. Options: make the term
    field read-only on the JCRC profiles / remove it from the term page, or leave it. Also: the
    field's picklist values are still the PLACEHOLDER set from client Q7.

## Production / release

20. **Nothing from 2026-10-09 onward is in production.** Needs a prod deploy once tested: `ContactMatcher`
    + `ContactMatch` + `Nickname_Group__mdt` (83 records); Pending Transactions source tabs / gala rule /
    Event Registration link (incl. `Gala__c` on Fund and Campaign, `Pending_Transaction_Preference__c`,
    profile changes); Jason's gala flows; `flowModalLauncher`; Payment Original Amount / Underpayment;
    Board Management member links. Blocked behind item 10 for the Pending Transactions pieces.
21. **Gala flags are data, not metadata.** In JCRC-Dev only the fund "Gala Fund" and 4 campaigns ("2027 Gala"
    x2, "FY27 Gala", "FY26 Gala") are ticked Gala. Production funds/campaigns must be ticked by hand, or QuickBooks
    gala gifts will land on the general tabs only.

## Repo

11. **Unpushed commits** on `main` (24 after fund-from-class).
