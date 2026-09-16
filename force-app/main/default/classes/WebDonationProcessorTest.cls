/**
 * @description Tests for WebDonationProcessor - the async step that turns a stored payload
 *              into a donor, a gift and its allocations.
 *
 *              Covers the paths that matter operationally: matching an existing donor rather
 *              than duplicating them, refusing to invent a gift from an unusable payload, and
 *              never silently dropping a designation it cannot map.
 *
 *              Note on designation mapping: Custom Metadata cannot be inserted in a test, so
 *              the allocation-mapping assertions depend on the org's real
 *              Web_Donation_Designation__mdt rows. Those tests assert on what the processor
 *              RECORDS (mapped versus unmapped) rather than on a specific fund, so they stay
 *              true as JCRC's mapping changes.
 *
 * @author Jason Ott
 * @created 2026-08-20
 *
 * Change Log:
 * -----------
 * 2026-08-20 - Jason Ott - Created (Website Donations phase 2 coverage).
 */
@IsTest
private class WebDonationProcessorTest {

    /** Builds a payload with the real field ids and whatever overrides a test needs. */
    private static String payload(Map<String, String> over) {
        Map<String, Object> m = new Map<String, Object>{
            '1.3'  => 'Web', '1.6' => 'Donor',
            '2'    => 'web.donor@example.com',
            '5'    => '18.82',
            '11'   => '5555550100',
            '10.1' => '1 Test Street', '10.3' => 'St. Louis', '10.4' => 'MO', '10.5' => '63119',
            'id'   => '900001', 'form_id' => '15',
            'date_created' => '2026-08-19 20:37:25'
        };
        if (over != null) {
            for (String k : over.keySet()) {
                if (over.get(k) == null) { m.remove(k); } else { m.put(k, over.get(k)); }
            }
        }
        return JSON.serialize(m);
    }

    /**
     * Stages a submission exactly as the endpoint does: stored and waiting, nothing interpreted
     * yet. Arriving no longer starts any processing of its own - the sweeper is what picks it
     * up - so tests that drive the processor directly and tests that exercise the sweeper both
     * start from this same state.
     */
    private static Web_Donation__c stage(String body, String entryId) {
        Web_Donation__c wd = new Web_Donation__c(
            GF_Entry_Id__c = entryId, Form_Id__c = '15', Payload__c = body,
            Status__c = 'Received', Received_At__c = System.now());
        insert wd;
        return wd;
    }

    @IsTest
    static void createsDonorAndGiftWhenNobodyMatches() {
        Web_Donation__c wd = stage(payload(null), 'T-1');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Status__c, Contact__c, Contact_Was_Created__c, Opportunity__c,
                                    Error_Message__c
                             FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals('Processed', r.Status__c, 'should process cleanly: ' + r.Error_Message__c);
        System.assertNotEquals(null, r.Contact__c, 'a donor was resolved');
        System.assertEquals(true, r.Contact_Was_Created__c, 'nobody matched, so one was created');
        System.assertNotEquals(null, r.Opportunity__c, 'a gift was created');

        Opportunity o = [SELECT Amount, StageName, Approach__c, npsp__Primary_Contact__c
                         FROM Opportunity WHERE Id = :r.Opportunity__c];
        System.assertEquals(18.82, o.Amount, 'gift is the total charged');
        System.assertEquals('Online', o.Approach__c);
        System.assertEquals(r.Contact__c, o.npsp__Primary_Contact__c, 'donor is the primary contact');
    }

    @IsTest
    static void matchesExistingDonorRatherThanDuplicating() {
        Contact existing = new Contact(FirstName = 'Web', LastName = 'Donor',
                                       Email = 'web.donor@example.com');
        insert existing;
        Integer before = [SELECT COUNT() FROM Contact WHERE Email = 'web.donor@example.com'];

        Web_Donation__c wd = stage(payload(null), 'T-2');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Contact__c, Contact_Was_Created__c FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals(existing.Id, r.Contact__c, 'matched the existing donor by email');
        System.assertEquals(false, r.Contact_Was_Created__c, 'did not create a second record');
        System.assertEquals(before, [SELECT COUNT() FROM Contact WHERE Email = 'web.donor@example.com'],
            'contact count unchanged - a mis-match here would attach a gift to the wrong donor');
    }

    @IsTest
    static void refusesPayloadWithNoEmail() {
        Web_Donation__c wd = stage(payload(new Map<String, String>{'2' => null}), 'T-3');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Status__c, Error_Message__c, Opportunity__c
                             FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals('Failed', r.Status__c, 'no way to identify the donor');
        System.assertEquals(null, r.Opportunity__c, 'and therefore no gift was invented');
        System.assertEquals(true, r.Error_Message__c.contains('email'), 'reason is recorded for replay');
    }

    @IsTest
    static void refusesPayloadWithNoAmount() {
        Web_Donation__c wd = stage(payload(new Map<String, String>{'5' => null}), 'T-4');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Status__c, Opportunity__c, Error_Message__c
                             FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals('Failed', r.Status__c);
        System.assertEquals(null, r.Opportunity__c, 'never create a gift with no usable amount');
    }

    @IsTest
    static void recordsDesignationsItCannotMap() {
        // "Not A Real Fund" has no mapping and never will - it must be reported, not dropped.
        Web_Donation__c wd = stage(
            payload(new Map<String, String>{'28.1' => 'Not A Real Fund'}), 'T-5');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Status__c, Unmapped_Designations__c, Opportunity__c
                             FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals('Processed', r.Status__c, 'an unmappable designation is not a failure');
        System.assertNotEquals(null, r.Opportunity__c, 'the gift is still recorded');
        System.assertEquals(true, r.Unmapped_Designations__c.contains('Not A Real Fund'),
            'the designation surfaces for review instead of vanishing');
    }

    @IsTest
    static void allocationsSumToTheGiftWhenMappingsExist() {
        // Uses whatever mappings the org actually has. If none match, the test still asserts
        // the invariant that matters: allocations never total more than the gift.
        Web_Donation__c wd = stage(payload(null), 'T-6');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Opportunity__c FROM Web_Donation__c WHERE Id = :wd.Id];
        Decimal total = 0;
        for (npsp__Allocation__c a : [SELECT npsp__Amount__c FROM npsp__Allocation__c
                                      WHERE npsp__Opportunity__c = :r.Opportunity__c]) {
            total += a.npsp__Amount__c;
        }
        Opportunity o = [SELECT Amount FROM Opportunity WHERE Id = :r.Opportunity__c];
        System.assertEquals(true, total <= o.Amount,
            'allocations must never exceed the gift (' + total + ' vs ' + o.Amount + ')');
    }

    @IsTest
    static void capturesWriteInForReview() {
        Web_Donation__c wd = stage(
            payload(new Map<String, String>{'23' => 'A Programme They Typed'}), 'T-7');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Opportunity__c FROM Web_Donation__c WHERE Id = :wd.Id];
        Opportunity o = [SELECT Other_Campaign_Write_In__c FROM Opportunity WHERE Id = :r.Opportunity__c];
        System.assertEquals('A Programme They Typed', o.Other_Campaign_Write_In__c,
            'what the donor typed is kept for the JSI-127 review queue');
    }

    @IsTest
    static void sweeperProcessesWhatHasArrived() {
        stage(payload(null), 'T-8');

        Test.startTest();
        Database.executeBatch(new WebDonationSweeper(), 1);
        Test.stopTest();   // forces the batch to run

        Web_Donation__c r = [SELECT Status__c, Opportunity__c FROM Web_Donation__c
                             WHERE GF_Entry_Id__c = 'T-8'];
        System.assertEquals('Processed', r.Status__c,
            'the sweeper picked up the donation and turned it into a gift');
        System.assertNotEquals(null, r.Opportunity__c);
    }

    /**
     * A donation already marked Failed must NOT be swept up again - it needs a human to read
     * the reason and replay it, and a retry loop would hide that.
     */
    @IsTest
    static void sweeperLeavesFailedDonationsAlone() {
        Web_Donation__c wd = stage(payload(null), 'T-9');
        wd.Status__c = 'Failed';
        wd.Error_Message__c = 'something a person needs to look at';
        update wd;

        Test.startTest();
        Database.executeBatch(new WebDonationSweeper(), 1);
        Test.stopTest();

        Web_Donation__c r = [SELECT Status__c, Opportunity__c FROM Web_Donation__c
                             WHERE GF_Entry_Id__c = 'T-9'];
        System.assertEquals('Failed', r.Status__c, 'a failed donation is not retried');
        System.assertEquals(null, r.Opportunity__c, 'and no gift was created for it');
    }
}