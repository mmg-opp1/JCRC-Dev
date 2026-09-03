/**
 * @description Tests for PaymentMethodService - the Payment Method entered on a gift reaching the
 *              payments underneath it, both the ones NPSP creates and the ones already there.
 * @author Jason Ott
 * @created 2026-09-03
 */
@isTest
private class PaymentMethodServiceTest {

    private static Id recordTypeId(String developerName) {
        return Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    /** A closed-won gift, which is what NPSP builds a payment for. */
    private static Opportunity gift(String name, String paymentMethod, Decimal amount) {
        Opportunity o = new Opportunity(
            Name = name,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = amount,
            Payment_Method__c = paymentMethod);
        insert o;
        return o;
    }

    /**
     * The case this exists for: a gift is entered with a payment method, NPSP creates the payment on
     * its own, and nobody ever opens it. The method must already be there.
     */
    @isTest
    static void npspCreatedPaymentPicksUpTheMethodFromTheGift() {
        Test.startTest();
        Opportunity o = gift('Auto Payment Gift', 'Check', 500);
        Test.stopTest();

        List<npe01__OppPayment__c> payments = [
            SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];
        System.assert(!payments.isEmpty(), 'NPSP created a payment for the closed-won gift');
        for (npe01__OppPayment__c p : payments) {
            System.assertEquals('Check', p.npe01__Payment_Method__c,
                'the payment carries the method entered on the gift, with nobody opening it');
        }
    }

    /** A payment inserted directly, the way an import or a manual schedule would. */
    @isTest
    static void manuallyCreatedPaymentPicksUpTheMethod() {
        Opportunity o = gift('Manual Payment Gift', 'Credit Card', 300);
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];

        Test.startTest();
        npe01__OppPayment__c p = new npe01__OppPayment__c(
            npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 300,
            npe01__Scheduled_Date__c = Date.today());
        insert p;
        Test.stopTest();

        System.assertEquals('Credit Card',
            [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c WHERE Id = :p.Id]
                .npe01__Payment_Method__c,
            'a payment created by hand is filled in from the gift too');
    }

    /** A method deliberately put on the payment is data entry, not a gap to fill. */
    @isTest
    static void anExplicitMethodOnThePaymentIsNotOverwrittenOnInsert() {
        Opportunity o = gift('Split Gift', 'Credit Card', 400);
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];

        Test.startTest();
        npe01__OppPayment__c p = new npe01__OppPayment__c(
            npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 400,
            npe01__Scheduled_Date__c = Date.today(),
            npe01__Payment_Method__c = 'Check');
        insert p;
        Test.stopTest();

        System.assertEquals('Check',
            [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c WHERE Id = :p.Id]
                .npe01__Payment_Method__c,
            'what somebody typed on the payment stands');
    }

    /** Setting the method on a gift that already has payments reaches all of them. */
    @isTest
    static void settingTheMethodOnTheGiftReachesExistingPayments() {
        Opportunity o = gift('Later Method Gift', null, 900);
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];
        insert new List<npe01__OppPayment__c>{
            new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 300,
                npe01__Scheduled_Date__c = Date.today()),
            new npe01__OppPayment__c(npe01__Opportunity__c = o.Id, npe01__Payment_Amount__c = 600,
                npe01__Scheduled_Date__c = Date.today().addMonths(1))
        };

        Test.startTest();
        o.Payment_Method__c = 'PayPal';
        update o;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c = :o.Id AND npe01__Payment_Method__c = 'PayPal'],
            'every payment on the gift picked the method up');
    }

    /**
     * The picklists disagree on exactly one value: the gift says "ACH/Wire", the payment says "ACH".
     * The Payment picklist is unrestricted, so an untranslated write would silently store a value the
     * picklist does not offer.
     */
    @isTest
    static void achWireIsTranslatedToTheValueThePaymentPicklistOffers() {
        Opportunity o = gift('Wire Gift', null, 2500);

        Test.startTest();
        o.Payment_Method__c = 'ACH/Wire';
        update o;
        Test.stopTest();

        List<npe01__OppPayment__c> payments = [
            SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :o.Id];
        System.assert(!payments.isEmpty(), 'there is a payment to check');
        for (npe01__OppPayment__c p : payments) {
            System.assertEquals('ACH', p.npe01__Payment_Method__c,
                'ACH/Wire is stored as the value the payment picklist actually has');
        }
    }

    /** Every value the gift offers must land somewhere valid on the payment - no silent strays. */
    @isTest
    static void everyOpportunityValueMapsToAValidPaymentValue() {
        Set<String> paymentValues = new Set<String>();
        for (Schema.PicklistEntry e :
                npe01__OppPayment__c.npe01__Payment_Method__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) { paymentValues.add(e.getValue()); }
        }

        Test.startTest();
        for (Schema.PicklistEntry e :
                Opportunity.Payment_Method__c.getDescribe().getPicklistValues()) {
            if (!e.isActive()) { continue; }
            String mapped = PaymentMethodService.toPaymentValue(e.getValue());
            System.assertNotEquals(null, mapped,
                'no translation for gift payment method "' + e.getValue()
                + '" - it would be dropped rather than written');
            System.assert(paymentValues.contains(mapped),
                '"' + e.getValue() + '" maps to "' + mapped + '", which the payment picklist does not offer');
        }
        Test.stopTest();
    }

    /** Clearing the method on the gift is not an instruction to forget how the money arrived. */
    @isTest
    static void clearingTheMethodOnTheGiftLeavesPaymentsAlone() {
        Opportunity o = gift('Cleared Gift', 'Cash', 150);
        System.assertEquals('Cash', [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c = :o.Id LIMIT 1].npe01__Payment_Method__c, 'set up: payment has Cash');

        Test.startTest();
        o.Payment_Method__c = null;
        update o;
        Test.stopTest();

        System.assertEquals('Cash', [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c = :o.Id LIMIT 1].npe01__Payment_Method__c,
            'the payment keeps what it had');
    }

    /** An edit that does not touch the method must not rewrite the payments. */
    @isTest
    static void anUnrelatedEditDoesNotDisturbThePayments() {
        Opportunity o = gift('Untouched Gift', 'Check', 200);
        npe01__OppPayment__c p = [SELECT Id FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c = :o.Id LIMIT 1];
        update new npe01__OppPayment__c(Id = p.Id, npe01__Payment_Method__c = 'DAF');

        Test.startTest();
        o.Description = 'renamed, nothing to do with payment method';
        update o;
        Test.stopTest();

        System.assertEquals('DAF', [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
            WHERE Id = :p.Id].npe01__Payment_Method__c,
            'an unrelated save leaves the payment method where it was');
    }

    /** Bulk-safe: no per-record queries or DML in a loop. */
    @isTest
    static void handlesABulkOfGiftsAtOnce() {
        List<Opportunity> gifts = new List<Opportunity>();
        for (Integer i = 0; i < 50; i++) {
            gifts.add(new Opportunity(Name = 'Bulk Gift ' + i, StageName = 'Closed Won',
                CloseDate = Date.today(), Amount = 100 + i, Payment_Method__c = 'Check'));
        }
        insert gifts;

        Test.startTest();
        for (Opportunity o : gifts) { o.Payment_Method__c = 'Credit Card'; }
        update gifts;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c IN :gifts AND npe01__Payment_Method__c != 'Credit Card'],
            'all 50 gifts pushed their new method down');
    }

    /** Pledges are out: the method belongs on each instalment, not on the gift. */
    @isTest
    static void pledgePaymentsAreLeftAlone() {
        Opportunity pledge = new Opportunity(Name = 'Pledge Gift', StageName = 'Pledged',
            CloseDate = Date.today(), Amount = 1200, Payment_Method__c = 'Check',
            RecordTypeId = recordTypeId('Pledge'));
        insert pledge;
        insert new npe01__OppPayment__c(npe01__Opportunity__c = pledge.Id,
            npe01__Payment_Amount__c = 600, npe01__Scheduled_Date__c = Date.today());

        Test.startTest();
        pledge.Payment_Method__c = 'Credit Card';
        update pledge;
        npe01__OppPayment__c second = new npe01__OppPayment__c(npe01__Opportunity__c = pledge.Id,
            npe01__Payment_Amount__c = 600, npe01__Scheduled_Date__c = Date.today().addMonths(1));
        insert second;
        Test.stopTest();

        for (npe01__OppPayment__c p : [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
                                       WHERE npe01__Opportunity__c = :pledge.Id]) {
            System.assertEquals(null, p.npe01__Payment_Method__c,
                'a pledge never pushes its method onto its instalments');
        }
    }

    /** Grants are out for the same reason. */
    @isTest
    static void grantPaymentsAreLeftAlone() {
        Opportunity grant = new Opportunity(Name = 'Grant Gift', StageName = 'Closed Won',
            CloseDate = Date.today(), Amount = 5000, Payment_Method__c = 'Check',
            RecordTypeId = recordTypeId('Grant'));
        insert grant;
        insert new npe01__OppPayment__c(npe01__Opportunity__c = grant.Id,
            npe01__Payment_Amount__c = 5000, npe01__Scheduled_Date__c = Date.today());

        Test.startTest();
        grant.Payment_Method__c = 'ACH/Wire';
        update grant;
        Test.stopTest();

        System.assertEquals(null, [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
            WHERE npe01__Opportunity__c = :grant.Id LIMIT 1].npe01__Payment_Method__c,
            'a grant never pushes its method onto its payments');
    }

    /** The exclusion is by developer name, so a rename must break loudly rather than silently. */
    @isTest
    static void bothExcludedRecordTypesResolve() {
        Test.startTest();
        Set<Id> excluded = PaymentMethodService.excludedRecordTypeIds();
        Test.stopTest();

        System.assertEquals(2, excluded.size(),
            'both Pledge and Grant resolved - if this drops, a record type was renamed and the '
            + 'exclusion silently stopped applying');
        System.assert(excluded.contains(recordTypeId('Pledge')), 'Pledge is excluded');
        System.assert(excluded.contains(recordTypeId('Grant')), 'Grant is excluded');
    }

    /** A record type that is not excluded still works, so the guard is not over-broad. */
    @isTest
    static void anOrdinaryDonationStillSyncs() {
        Opportunity o = new Opportunity(Name = 'Ordinary Donation', StageName = 'Closed Won',
            CloseDate = Date.today(), Amount = 250, Payment_Method__c = 'Cash',
            RecordTypeId = recordTypeId('NPSP_Default'));
        insert o;

        Test.startTest();
        o.Payment_Method__c = 'PayPal';
        update o;
        Test.stopTest();

        for (npe01__OppPayment__c p : [SELECT npe01__Payment_Method__c FROM npe01__OppPayment__c
                                       WHERE npe01__Opportunity__c = :o.Id]) {
            System.assertEquals('PayPal', p.npe01__Payment_Method__c,
                'a standard donation still carries the method down');
        }
    }
}
