/**
 * @description Tests for PaymentAmountService (Original Payment Amount) and the Underpayment__c formula on
 *              NPSP Payments.
 * @author Jason Ott
 * @created 2026-10-12
 *
 * Change Log:
 * -----------
 * 2026-10-12 - Jason Ott - Initial version.
 */
@IsTest
private class PaymentAmountServiceTest {

    /**
     * A pledge for a real donor (NPSP creates the household), with NPSP's auto-created payment removed so
     * each test controls its own payments.
     */
    private static Opportunity pledge() {
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.DuplicateRuleHeader.allowSave = true;
        Contact c = new Contact(FirstName = 'Una', LastName = 'Underpaymenttest', Email = 'una.underpayment@example.invalid');
        Database.insert(c, opts);
        c = [SELECT Id, AccountId FROM Contact WHERE Id = :c.Id];
        Opportunity o = new Opportunity(Name = 'Underpayment Test Pledge', AccountId = c.AccountId,
            npsp__Primary_Contact__c = c.Id, StageName = 'Pledged', CloseDate = Date.today(), Amount = 1000,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pledge').getRecordTypeId());
        insert o;
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];
        return o;
    }

    private static npe01__OppPayment__c reload(Id paymentId) {
        return [SELECT npe01__Payment_Amount__c, Original_Payment_Amount__c, Underpayment__c, npe01__Paid__c
                FROM npe01__OppPayment__c WHERE Id = :paymentId];
    }

    /** The amount a payment is created with is kept as the original, and an amount change leaves it alone. */
    @IsTest
    static void originalIsCopiedOnceAndNeverChanged() {
        Opportunity o = pledge();
        npe01__OppPayment__c p = new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 250,
            npe01__Scheduled_Date__c = Date.today());
        insert p;
        System.assertEquals(250, reload(p.Id).Original_Payment_Amount__c);

        p.npe01__Payment_Amount__c = 300;
        update p;
        System.assertEquals(250, reload(p.Id).Original_Payment_Amount__c, 'Original never changes after insert');
    }

    /** Paid for less: the shortfall shows. */
    @IsTest
    static void paidForLessShowsUnderpayment() {
        Opportunity o = pledge();
        npe01__OppPayment__c p = new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 250,
            npe01__Scheduled_Date__c = Date.today());
        insert p;

        Test.startTest();
        p.npe01__Payment_Amount__c = 200;
        p.npe01__Paid__c = true;
        p.npe01__Payment_Date__c = Date.today();
        update p;
        Test.stopTest();

        System.assertEquals(50, reload(p.Id).Underpayment__c);
    }

    /** No underpayment while unpaid, when paid in full, when paid more, or with no original. */
    @IsTest
    static void noUnderpaymentOtherwise() {
        Opportunity o = pledge();
        List<npe01__OppPayment__c> ps = new List<npe01__OppPayment__c>();
        for (Integer i = 0; i < 4; i++) {
            ps.add(new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 250,
                npe01__Scheduled_Date__c = Date.today().addMonths(i)));
        }
        insert ps;

        ps[0].npe01__Payment_Amount__c = 200;                        // lowered but not paid
        ps[1].npe01__Paid__c = true;                                // paid in full
        ps[1].npe01__Payment_Date__c = Date.today();
        ps[2].npe01__Payment_Amount__c = 300;                        // paid more
        ps[2].npe01__Paid__c = true;
        ps[2].npe01__Payment_Date__c = Date.today();
        update new List<npe01__OppPayment__c>{ ps[0], ps[1], ps[2] };

        System.assertEquals(null, reload(ps[0].Id).Underpayment__c, 'Not paid yet');
        System.assertEquals(null, reload(ps[1].Id).Underpayment__c, 'Paid in full');
        System.assertEquals(null, reload(ps[2].Id).Underpayment__c, 'Paid more');
    }

    /** An original supplied on insert (e.g. a data load) is kept rather than overwritten. */
    @IsTest
    static void suppliedOriginalIsKept() {
        Opportunity o = pledge();
        npe01__OppPayment__c p = new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 200,
            Original_Payment_Amount__c = 250, npe01__Scheduled_Date__c = Date.today());
        insert p;
        System.assertEquals(250, reload(p.Id).Original_Payment_Amount__c);
    }

    /** Bulk: 200 payments in one insert are all stamped. */
    @IsTest
    static void bulkInsertStampsEveryPayment() {
        Opportunity o = pledge();
        List<npe01__OppPayment__c> ps = new List<npe01__OppPayment__c>();
        for (Integer i = 0; i < 200; i++) {
            ps.add(new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 5,
                npe01__Scheduled_Date__c = Date.today()));
        }
        Test.startTest();
        insert ps;
        Test.stopTest();
        System.assertEquals(200, [SELECT COUNT() FROM npe01__OppPayment__c
                                  WHERE npe01__Opportunity__c = :o.Id AND Original_Payment_Amount__c = 5]);
    }
}
