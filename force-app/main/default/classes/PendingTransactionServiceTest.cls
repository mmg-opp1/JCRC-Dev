/**
 * @description Tests for PendingTransactionService and PendingTransactionTrigger (JSI-121).
 *
 *              Three layers:
 *                - the installment rules, exercised as pure logic on in-memory payments;
 *                - evaluation and donor suggestion, through the trigger on real saves;
 *                - commit end to end against real NPSP gifts and pledges: what gets created, stamped
 *                  and deleted, failure isolation, the duplicate guard, and a JCRC - Fundraising user.
 *
 *              Pledges are built with NPSP's auto-created payment removed and four unpaid $3,750
 *              installments added, the shape real JCRC pledges have.
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 2).
 * 2026-09-16 - Jason Ott - Phase 4: manual Source stamp and deleteTransactions.
 */
@IsTest
private class PendingTransactionServiceTest {

    private static final String DONOR_EMAIL = 'rachel.pendingtest@example.invalid';

    @TestSetup
    static void setup() {
        Contact donor = new Contact(FirstName = 'Rachel', LastName = 'Pendingtest', Email = DONOR_EMAIL);
        insertAllowingDuplicates(new List<SObject>{ donor });
        insert new npsp__General_Accounting_Unit__c(Name = 'Pending Test Fund', npsp__Active__c = true);
    }

    // ---- fixtures -----------------------------------------------------------------------------

    private static void insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.DuplicateRuleHeader.allowSave = true;
        for (Database.SaveResult sr : Database.insert(records, opts)) {
            System.assert(sr.isSuccess(), 'fixture insert failed: ' + sr.getErrors());
        }
    }

    private static Contact donor() {
        return [SELECT Id, AccountId FROM Contact WHERE Email = :DONOR_EMAIL LIMIT 1];
    }

    private static Id rtId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    /** $15,000 pledge with four unpaid $3,750 installments, a month apart. */
    private static Opportunity pledge(Contact c) {
        Opportunity p = new Opportunity(Name = 'Test Pledge', RecordTypeId = rtId('Pledge'), StageName = 'Pledged',
            CloseDate = Date.today().addMonths(-1), Amount = 15000, AccountId = c.AccountId,
            npsp__Primary_Contact__c = c.Id);
        insert p;
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :p.Id];
        List<npe01__OppPayment__c> installments = new List<npe01__OppPayment__c>();
        for (Integer i = 0; i < 4; i++) {
            installments.add(new npe01__OppPayment__c(npe01__Opportunity__c = p.Id, npe01__Payment_Amount__c = 3750,
                npe01__Scheduled_Date__c = Date.today().addMonths(i), npe01__Paid__c = false));
        }
        insert installments;
        return p;
    }

    private static List<npe01__OppPayment__c> schedule(Id pledgeId) {
        return [SELECT Id, npe01__Payment_Amount__c, npe01__Paid__c, npe01__Scheduled_Date__c, npe01__Payment_Date__c,
                       npe01__Check_Reference_Number__c, npsp__Batch_Number__c, Source_Transaction_Id__c
                FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :pledgeId
                ORDER BY npe01__Paid__c DESC, npe01__Scheduled_Date__c ASC NULLS LAST, CreatedDate ASC];
    }

    private static Pending_Transaction__c readyRow(Contact c, Decimal amount) {
        return new Pending_Transaction__c(Source__c = 'Manual', Amount__c = amount, Transaction_Date__c = Date.today(),
            Contact__c = c.Id, Payment_Method__c = 'ACH/Wire', Reference_Number__c = 'ACH-123',
            Deposit_Reference__c = 'DEP-0916');
    }

    private static List<npe01__OppPayment__c> fourInstallments() {
        List<npe01__OppPayment__c> out = new List<npe01__OppPayment__c>();
        for (Integer i = 0; i < 4; i++) {
            out.add(new npe01__OppPayment__c(npe01__Payment_Amount__c = 3750,
                npe01__Scheduled_Date__c = Date.newInstance(2026, 7 + i, 1)));
        }
        return out;
    }

    // ---- installment rules (pure) -------------------------------------------------------------

    @IsTest
    static void planExactMarksOldestPaid() {
        List<npe01__OppPayment__c> s = fourInstallments();
        PendingTransactionService.PaymentPlan plan = PendingTransactionService.planPledgePayment(3750, 15000, s);
        System.assert(plan.allowed);
        System.assertEquals(s[0], plan.paid);
        System.assertEquals(true, s[0].npe01__Paid__c);
        System.assertEquals(3750, s[0].npe01__Payment_Amount__c);
        System.assertEquals(null, plan.remainder);
        System.assert(plan.reduced.isEmpty() && plan.removed.isEmpty());
    }

    @IsTest
    static void planShortSchedulesRemainderOnSameDate() {
        List<npe01__OppPayment__c> s = fourInstallments();
        PendingTransactionService.PaymentPlan plan = PendingTransactionService.planPledgePayment(1000, 15000, s);
        System.assertEquals(1000, s[0].npe01__Payment_Amount__c);
        System.assertEquals(2750, plan.remainder.npe01__Payment_Amount__c);
        System.assertEquals(Date.newInstance(2026, 7, 1), plan.remainder.npe01__Scheduled_Date__c);
        System.assertEquals(false, plan.remainder.npe01__Paid__c);
        System.assert(plan.steps[0].contains('$1,000.00'), plan.steps);
    }

    @IsTest
    static void planOverTakesExtraOffLastInstallment() {
        // Jason's worked example: ACH of $5,000 against 4 x $3,750.
        List<npe01__OppPayment__c> s = fourInstallments();
        PendingTransactionService.PaymentPlan plan = PendingTransactionService.planPledgePayment(5000, 15000, s);
        System.assertEquals(5000, s[0].npe01__Payment_Amount__c);
        System.assertEquals(1, plan.reduced.size());
        System.assertEquals(s[3], plan.reduced[0]);
        System.assertEquals(2500, s[3].npe01__Payment_Amount__c);
        System.assertEquals(3750, s[1].npe01__Payment_Amount__c);
        System.assert(plan.removed.isEmpty());
    }

    @IsTest
    static void planOverWorksBackwardsWhenExtraExceedsLast() {
        // D11 example: ACH of $10,000 -> installment 4 removed, installment 3 drops to $1,250.
        List<npe01__OppPayment__c> s = fourInstallments();
        PendingTransactionService.PaymentPlan plan = PendingTransactionService.planPledgePayment(10000, 15000, s);
        System.assertEquals(10000, s[0].npe01__Payment_Amount__c);
        System.assertEquals(new List<npe01__OppPayment__c>{ s[3] }, plan.removed);
        System.assertEquals(new List<npe01__OppPayment__c>{ s[2] }, plan.reduced);
        System.assertEquals(1250, s[2].npe01__Payment_Amount__c);
        System.assertEquals(3750, s[1].npe01__Payment_Amount__c);
    }

    @IsTest
    static void planRefusesMoreThanOutstanding() {
        PendingTransactionService.PaymentPlan plan =
            PendingTransactionService.planPledgePayment(15000.01, 15000, fourInstallments());
        System.assertEquals(false, plan.allowed);
        System.assert(plan.refusal.contains('$15,000.00 outstanding'), plan.refusal);
    }

    @IsTest
    static void planWithoutInstallmentsAddsPaidPayment() {
        PendingTransactionService.PaymentPlan plan =
            PendingTransactionService.planPledgePayment(500, 2000, new List<npe01__OppPayment__c>());
        System.assert(plan.allowed);
        System.assertEquals(500, plan.newPaid.npe01__Payment_Amount__c);
        System.assertEquals(null, plan.paid);
    }

    @IsTest
    static void moneyAlwaysHasTwoDecimals() {
        System.assertEquals('$1,250.00', PendingTransactionService.money(1250));
        System.assertEquals('$4,166.70', PendingTransactionService.money(4166.7));
        System.assertEquals('$0.00', PendingTransactionService.money(null));
    }

    // ---- evaluation + suggestion (trigger) ----------------------------------------------------

    @IsTest
    static void incompleteRowNeedsReviewAndCompleteRowIsReady() {
        Contact c = donor();
        Pending_Transaction__c blank = new Pending_Transaction__c(Source__c = 'Manual');
        Pending_Transaction__c full = readyRow(c, 250);
        insert new List<Pending_Transaction__c>{ blank, full };

        blank = [SELECT Status__c FROM Pending_Transaction__c WHERE Id = :blank.Id];
        full = [SELECT Status__c, Match_Status__c, Account__c FROM Pending_Transaction__c WHERE Id = :full.Id];
        System.assertEquals('Needs Review', blank.Status__c);
        System.assertEquals('Ready', full.Status__c);
        System.assertEquals('Confirmed', full.Match_Status__c, 'a donor chosen by a person is confirmed');
        System.assertEquals(c.AccountId, full.Account__c, 'account filled from the contact');

        Pending_Transaction__c reloaded = [SELECT Id, Name, Amount__c, Transaction_Date__c, Contact__c, Account__c,
            Match_Status__c, Apply_As__c, Pledge__c, Gift_Record_Type__c, External_Id__c
            FROM Pending_Transaction__c WHERE Id = :blank.Id];
        List<String> issues = PendingTransactionService.problems(reloaded,
            new PendingTransactionService.Context(new List<Pending_Transaction__c>{ reloaded }));
        System.assert(issues.contains('Enter an amount greater than zero.'), issues);
        System.assert(issues.contains('Enter the date the money was received.'), issues);
        System.assert(issues.contains('Choose the donor.'), issues);
    }

    @IsTest
    static void payerEmailSuggestsDonorWhichMustBeConfirmed() {
        Contact c = donor();
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks', External_Id__c = 'QBO-1',
            Payer_Name__c = 'R PENDINGTEST', Payer_Email__c = DONOR_EMAIL.toUpperCase(), Amount__c = 100,
            Transaction_Date__c = Date.today());
        insert row;
        row = [SELECT Contact__c, Account__c, Match_Status__c, Status__c FROM Pending_Transaction__c WHERE Id = :row.Id];
        System.assertEquals(c.Id, row.Contact__c);
        System.assertEquals(c.AccountId, row.Account__c);
        System.assertEquals('Suggested', row.Match_Status__c);
        System.assertEquals('Needs Review', row.Status__c, 'a suggestion is not committable until confirmed');

        Test.startTest();
        PendingTransactionService.confirmDonors(new Set<Id>{ row.Id });
        Test.stopTest();
        row = [SELECT Match_Status__c, Status__c FROM Pending_Transaction__c WHERE Id = :row.Id];
        System.assertEquals('Confirmed', row.Match_Status__c);
        System.assertEquals('Ready', row.Status__c);
    }

    @IsTest
    static void sharedEmailLeavesDonorBlankAsMultipleMatches() {
        insertAllowingDuplicates(new List<SObject>{
            new Contact(FirstName = 'Other', LastName = 'Householdmember', Email = DONOR_EMAIL) });
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks', Payer_Email__c = DONOR_EMAIL,
            Amount__c = 100, Transaction_Date__c = Date.today());
        insert row;
        row = [SELECT Contact__c, Match_Status__c, Status__c FROM Pending_Transaction__c WHERE Id = :row.Id];
        System.assertEquals(null, row.Contact__c);
        System.assertEquals('Multiple Matches', row.Match_Status__c);
        System.assertEquals('Needs Review', row.Status__c);
    }

    @IsTest
    static void exactAccountNameSuggestsOrganization() {
        Account org = new Account(Name = 'Pendingtest Family Foundation',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Organization').getRecordTypeId());
        insert org;
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks',
            Payer_Name__c = 'PENDINGTEST FAMILY FOUNDATION', Amount__c = 100, Transaction_Date__c = Date.today());
        insert row;
        row = [SELECT Account__c, Contact__c, Match_Status__c FROM Pending_Transaction__c WHERE Id = :row.Id];
        System.assertEquals(org.Id, row.Account__c);
        System.assertEquals(null, row.Contact__c);
        System.assertEquals('Suggested', row.Match_Status__c);
    }

    @IsTest
    static void unmatchedPayerIsNoMatch() {
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks',
            Payer_Name__c = 'Zzqx Nobodyknown', Amount__c = 100, Transaction_Date__c = Date.today());
        insert row;
        row = [SELECT Contact__c, Account__c, Match_Status__c FROM Pending_Transaction__c WHERE Id = :row.Id];
        System.assertEquals(null, row.Contact__c);
        System.assertEquals(null, row.Account__c);
        System.assertEquals('No Match', row.Match_Status__c);
    }

    @IsTest
    static void inKindRecordTypeIsNotCommittable() {
        Pending_Transaction__c row = readyRow(donor(), 100);
        row.Gift_Record_Type__c = 'In_Kind_Gift';
        insert row;
        System.assertEquals('Needs Review', [SELECT Status__c FROM Pending_Transaction__c WHERE Id = :row.Id].Status__c);
    }

    @IsTest
    static void pledgePaymentOverOutstandingNeedsReview() {
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c row = readyRow(c, 20000);
        row.Apply_As__c = 'Pledge Payment';
        row.Pledge__c = p.Id;
        insert row;
        System.assertEquals('Needs Review', [SELECT Status__c FROM Pending_Transaction__c WHERE Id = :row.Id].Status__c);
    }

    // ---- open pledges -------------------------------------------------------------------------

    @IsTest
    static void openPledgesListsPledgeWithUnpaidInstallmentsOnly() {
        Contact c = donor();
        Opportunity p = pledge(c);
        insert new Opportunity(Name = 'Plain gift', RecordTypeId = rtId('NPSP_Default'), StageName = 'Posted',
            CloseDate = Date.today(), Amount = 50, AccountId = c.AccountId, npsp__Primary_Contact__c = c.Id);

        Test.startTest();
        List<PendingTransactionService.OpenPledge> byContact = PendingTransactionService.getOpenPledges(c.Id, null);
        List<PendingTransactionService.OpenPledge> byAccount = PendingTransactionService.getOpenPledges(null, c.AccountId);
        List<PendingTransactionService.OpenPledge> nobody = PendingTransactionService.getOpenPledges(null, null);
        Test.stopTest();

        System.assertEquals(1, byContact.size());
        System.assertEquals(p.Id, byContact[0].id);
        System.assertEquals(15000, byContact[0].outstanding);
        System.assertEquals(4, byContact[0].unpaid.size());
        System.assertEquals(Date.today(), byContact[0].unpaid[0].scheduledDate);
        System.assertEquals(1, byAccount.size());
        System.assertEquals(0, nobody.size());

        PendingTransactionService.PaymentPlan preview = PendingTransactionService.previewPledgePayment(p.Id, 5000);
        System.assert(preview.allowed);
        System.assertEquals(4, schedule(p.Id).size(), 'preview changes nothing');
        System.assertEquals(3750, schedule(p.Id)[0].npe01__Payment_Amount__c);
    }

    // ---- commit -------------------------------------------------------------------------------

    @IsTest
    static void commitNewGiftCreatesStampsAndDeletes() {
        Contact c = donor();
        npsp__General_Accounting_Unit__c fund = [SELECT Id FROM npsp__General_Accounting_Unit__c WHERE Name = 'Pending Test Fund'];
        Pending_Transaction__c row = readyRow(c, 1800);
        row.Source__c = 'QuickBooks';
        row.External_Id__c = 'QBO-DEP-77';
        row.Fund__c = fund.Id;
        row.Approach__c = 'Other';
        row.Notes__c = 'Wire from the family account';
        insert row;

        Test.startTest();
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].success, results[0].message);
        Opportunity gift = [SELECT Amount, StageName, CloseDate, AccountId, npsp__Primary_Contact__c, RecordType.DeveloperName,
                                   Approach__c, Description, Source_Transaction_Id__c, Payment_Method__c,
                                   (SELECT npe01__Payment_Amount__c, npe01__Paid__c, npe01__Check_Reference_Number__c,
                                           npsp__Batch_Number__c, npe01__Payment_Method__c FROM npe01__OppPayment__r),
                                   (SELECT npsp__General_Accounting_Unit__c, npsp__Percent__c FROM npsp__Allocations__r)
                            FROM Opportunity WHERE Id = :results[0].recordId];
        System.assertEquals(1800, gift.Amount);
        System.assertEquals('Posted', gift.StageName);
        System.assertEquals(Date.today(), gift.CloseDate);
        System.assertEquals(c.AccountId, gift.AccountId);
        System.assertEquals(c.Id, gift.npsp__Primary_Contact__c);
        System.assertEquals('NPSP_Default', gift.RecordType.DeveloperName);
        System.assertEquals('QBO-DEP-77', gift.Source_Transaction_Id__c, 'D4 stamp on the gift');
        System.assertEquals('Wire from the family account', gift.Description);
        System.assertEquals('ACH/Wire', gift.Payment_Method__c);
        System.assertEquals(1, gift.npe01__OppPayment__r.size());
        System.assertEquals(true, gift.npe01__OppPayment__r[0].npe01__Paid__c);
        System.assertEquals('ACH-123', gift.npe01__OppPayment__r[0].npe01__Check_Reference_Number__c);
        System.assertEquals('DEP-0916', gift.npe01__OppPayment__r[0].npsp__Batch_Number__c);
        System.assertEquals(1, gift.npsp__Allocations__r.size(), 'fund allocation replaces the default');
        System.assertEquals(fund.Id, gift.npsp__Allocations__r[0].npsp__General_Accounting_Unit__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c WHERE Id = :row.Id], 'holding row deleted');
        // emptyRecycleBin is also called, but Salesforce purges in the background, so ALL ROWS still
        // returns the row (IsDeleted = true) inside the same transaction - not assertable here.
    }

    @IsTest
    static void commitKeepsGiftNameTheUserTyped() {
        Pending_Transaction__c row = readyRow(donor(), 75);
        row.Gift_Name__c = 'Kaplan wire - annual appeal';
        insert row;
        Test.startTest();
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();
        System.assert(results[0].success, results[0].message);
        System.assertEquals('Kaplan wire - annual appeal', [SELECT Name FROM Opportunity WHERE Id = :results[0].recordId].Name);
    }

    @IsTest
    static void commitPledgePaymentOverAppliesRulesAndStampsPayment() {
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c row = readyRow(c, 5000);
        row.Apply_As__c = 'Pledge Payment';
        row.Pledge__c = p.Id;
        row.External_Id__c = 'QBO-PMT-5000';
        insert row;
        System.assertEquals('Ready', [SELECT Status__c FROM Pending_Transaction__c WHERE Id = :row.Id].Status__c);

        Test.startTest();
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();

        System.assert(results[0].success, results[0].message);
        System.assertEquals(p.Id, results[0].recordId);
        List<npe01__OppPayment__c> s = schedule(p.Id);
        System.assertEquals(4, s.size());
        System.assertEquals(true, s[0].npe01__Paid__c);
        System.assertEquals(5000, s[0].npe01__Payment_Amount__c);
        System.assertEquals(Date.today(), s[0].npe01__Payment_Date__c);
        System.assertEquals('QBO-PMT-5000', s[0].Source_Transaction_Id__c, 'D4 stamp on the payment');
        System.assertEquals('ACH-123', s[0].npe01__Check_Reference_Number__c);
        System.assertEquals('DEP-0916', s[0].npsp__Batch_Number__c);
        System.assertEquals(3750, s[1].npe01__Payment_Amount__c);
        System.assertEquals(3750, s[2].npe01__Payment_Amount__c);
        System.assertEquals(2500, s[3].npe01__Payment_Amount__c);
        System.assertEquals(10000, [SELECT npe01__Amount_Outstanding__c FROM Opportunity WHERE Id = :p.Id].npe01__Amount_Outstanding__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
    }

    @IsTest
    static void commitPledgePaymentShortAddsRemainder() {
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c row = readyRow(c, 1000);
        row.Apply_As__c = 'Pledge Payment';
        row.Pledge__c = p.Id;
        insert row;

        Test.startTest();
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();

        System.assert(results[0].success, results[0].message);
        List<npe01__OppPayment__c> s = schedule(p.Id);
        System.assertEquals(5, s.size());
        System.assertEquals(1000, s[0].npe01__Payment_Amount__c);
        System.assertEquals(true, s[0].npe01__Paid__c);
        Decimal unpaidTotal = 0;
        Integer onFirstDate = 0;
        for (npe01__OppPayment__c x : s) {
            if (!x.npe01__Paid__c) {
                unpaidTotal += x.npe01__Payment_Amount__c;
                if (x.npe01__Scheduled_Date__c == Date.today()) {
                    onFirstDate++;
                    System.assertEquals(2750, x.npe01__Payment_Amount__c);
                }
            }
        }
        System.assertEquals(14000, unpaidTotal);
        System.assertEquals(1, onFirstDate, 'remainder scheduled on the original date');
    }

    @IsTest
    static void failedRowRollsBackAloneAndKeepsItsError() {
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c good = readyRow(c, 3750);
        good.Apply_As__c = 'Pledge Payment';
        good.Pledge__c = p.Id;
        Pending_Transaction__c alsoGood = readyRow(c, 12000);
        alsoGood.Apply_As__c = 'Pledge Payment';
        alsoGood.Pledge__c = p.Id;
        insert new List<Pending_Transaction__c>{ good, alsoGood };

        Test.startTest();
        // Each is fine alone; together they exceed the pledge. The second must fail on its own.
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ good.Id, alsoGood.Id });
        Test.stopTest();

        Map<Id, PendingTransactionService.CommitResult> byRow = new Map<Id, PendingTransactionService.CommitResult>();
        for (PendingTransactionService.CommitResult r : results) {
            byRow.put(r.rowId, r);
        }
        System.assert(byRow.get(good.Id).success, byRow.get(good.Id).message);
        System.assertEquals(false, byRow.get(alsoGood.Id).success);
        Pending_Transaction__c left = [SELECT Status__c, Error_Message__c FROM Pending_Transaction__c WHERE Id = :alsoGood.Id];
        System.assertEquals('Error', left.Status__c);
        System.assert(left.Error_Message__c.contains('$11,250.00 outstanding'), left.Error_Message__c);
        System.assertEquals(11250, [SELECT npe01__Amount_Outstanding__c FROM Opportunity WHERE Id = :p.Id].npe01__Amount_Outstanding__c,
            'only the successful row touched the pledge');

        // A user edit clears the error and re-evaluates.
        left.Amount__c = 1000;
        update left;
        left = [SELECT Status__c, Error_Message__c FROM Pending_Transaction__c WHERE Id = :alsoGood.Id];
        System.assertEquals('Ready', left.Status__c);
        System.assertEquals(null, left.Error_Message__c);
    }

    @IsTest
    static void alreadyCommittedSourceIdIsBlocked() {
        Contact c = donor();
        insert new Opportunity(Name = 'Earlier gift', RecordTypeId = rtId('NPSP_Default'), StageName = 'Posted',
            CloseDate = Date.today(), Amount = 90, AccountId = c.AccountId, Source_Transaction_Id__c = 'QBO-DUP-1');
        Pending_Transaction__c row = readyRow(c, 90);
        row.External_Id__c = 'qbo-dup-1';
        insert row;
        System.assertEquals('Needs Review', [SELECT Status__c FROM Pending_Transaction__c WHERE Id = :row.Id].Status__c);

        Test.startTest();
        List<PendingTransactionService.CommitResult> results =
            PendingTransactionService.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('already committed as gift'), results[0].message);
        System.assertEquals(1, [SELECT COUNT() FROM Opportunity WHERE Source_Transaction_Id__c = 'QBO-DUP-1']);
    }

    @IsTest
    static void commitRefusesOversizedBatch() {
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i <= PendingTransactionService.MAX_ROWS_PER_COMMIT; i++) {
            ids.add((Id) (Pending_Transaction__c.SObjectType.getDescribe().getKeyPrefix() + '000000000' + String.valueOf(i).leftPad(3, '0')));
        }
        try {
            PendingTransactionService.commitTransactions(ids);
            System.assert(false, 'expected refusal');
        } catch (PendingTransactionService.PendingTransactionException e) {
            System.assert(e.getMessage().contains('at most'), e.getMessage());
        }
        System.assertEquals(0, PendingTransactionService.commitTransactions(new List<Id>()).size());
    }

    @IsTest
    static void fundraisingUserCanCommitGiftsAndPaymentsOnPledgesOwnedByOthers() {
        // Rows and the pledge are created (and owned) by the running admin, the way the QuickBooks sync
        // user and other staff would own them in production.
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c giftRow = readyRow(c, 360);
        Pending_Transaction__c paymentRow = readyRow(c, 3750);
        paymentRow.Apply_As__c = 'Pledge Payment';
        paymentRow.Pledge__c = p.Id;
        insert new List<Pending_Transaction__c>{ giftRow, paymentRow };

        Profile prof = [SELECT Id FROM Profile WHERE Name = 'JCRC - Fundraising'];
        User u = new User(ProfileId = prof.Id, LastName = 'Fundraiser', Alias = 'ptfund',
            Email = 'ptfund@example.invalid', Username = 'ptfund' + DateTime.now().getTime() + '@example.invalid',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US');
        insert u;

        List<PendingTransactionService.CommitResult> results;
        Test.startTest();
        System.runAs(u) {
            results = PendingTransactionService.commitTransactions(new List<Id>{ giftRow.Id, paymentRow.Id });
        }
        Test.stopTest();
        for (PendingTransactionService.CommitResult r : results) {
            System.assert(r.success, r.rowName + ': ' + r.message);
        }
        System.assertEquals(11250, [SELECT npe01__Amount_Outstanding__c FROM Opportunity WHERE Id = :p.Id].npe01__Amount_Outstanding__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
    }

    // ---- Phase 4: manual rows and delete ------------------------------------------------------

    private static User userWithProfile(String profileName, String alias) {
        User u = new User(ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName].Id, LastName = alias,
            Alias = alias, Email = alias + '@example.invalid',
            Username = alias + DateTime.now().getTime() + '@example.invalid', TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert u;
        return u;
    }

    @IsTest
    static void rowWithoutSourceIsManual() {
        Pending_Transaction__c row = new Pending_Transaction__c(Amount__c = 10, Transaction_Date__c = Date.today());
        insert row;
        System.assertEquals('Manual', [SELECT Source__c FROM Pending_Transaction__c WHERE Id = :row.Id].Source__c);
    }

    @IsTest
    static void fundraisingUserDeletesRowsOwnedByOthers() {
        Pending_Transaction__c a = readyRow(donor(), 10);
        Pending_Transaction__c b = readyRow(donor(), 20);
        insert new List<Pending_Transaction__c>{ a, b };
        User u = userWithProfile('JCRC - Fundraising', 'ptdel');
        Integer n;
        Test.startTest();
        System.runAs(u) {
            n = PendingTransactionService.deleteTransactions(new Set<Id>{ a.Id, b.Id });
        }
        Test.stopTest();
        System.assertEquals(2, n);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
        System.assertEquals(0, PendingTransactionService.deleteTransactions(new Set<Id>()));
    }

    @IsTest
    static void userWithoutAccessCannotDelete() {
        Pending_Transaction__c row = readyRow(donor(), 10);
        insert row;
        User u = userWithProfile('Standard User', 'ptnoacc');
        Test.startTest();
        System.runAs(u) {
            try {
                PendingTransactionService.deleteTransactions(new Set<Id>{ row.Id });
                System.assert(false, 'expected refusal');
            } catch (PendingTransactionService.PendingTransactionException e) {
                System.assert(e.getMessage().contains('do not have access'), e.getMessage());
            }
        }
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c]);
    }
}
