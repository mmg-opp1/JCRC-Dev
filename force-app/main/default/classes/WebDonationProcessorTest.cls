/**
 * @description Tests for WebDonationProcessor - the async step that turns a stored payload
 *              into a donor, a gift and its allocations.
 *
 *              Covers the paths that matter operationally: matching an existing donor rather
 *              than duplicating them, refusing to invent a gift from an unusable payload, and
 *              never silently dropping a designation it cannot map.
 *
 *              Note on configuration: Custom Metadata cannot be inserted in a test. The older tests
 *              use the org's real rows and assert on what the processor RECORDS rather than on a
 *              specific fund. Newer tests supply their own settings and translations through
 *              WebDonationConfig's @TestVisible caches, so they don't depend on the org's rows.
 *
 * @author Jason Ott
 * @created 2026-08-20
 *
 * Change Log:
 * -----------
 * 2026-08-20 - Jason Ott - Created (Website Donations phase 2 coverage).
 * 2026-10-28 - Jason Ott - Gala gifts go to Pending Transactions: gala only, gala + other, write-in,
 *                          whole word, routing off, custom words, replay, already committed. Plus the
 *                          donor match rules and account handling settings. American spelling.
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
            payload(new Map<String, String>{'23' => 'A Program They Typed'}), 'T-7');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = [SELECT Opportunity__c FROM Web_Donation__c WHERE Id = :wd.Id];
        Opportunity o = [SELECT Other_Campaign_Write_In__c FROM Opportunity WHERE Id = :r.Opportunity__c];
        System.assertEquals('A Program They Typed', o.Other_Campaign_Write_In__c,
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

    // ---- configuration supplied by the test --------------------------------------------------

    /** Settings for this test, in place of the org's record (defaults = Email match, create). */
    private static WebDonationConfig.Settings useSettings() {
        WebDonationConfig.Settings cfg = new WebDonationConfig.Settings();
        WebDonationConfig.cachedSettings = cfg;
        return cfg;
    }

    /**
     * The form's translations, in place of the org's rows: Other -> a campaign (which also marks
     * field 28 as the designation group), and three designations -> funds created here.
     */
    private static void useTranslations() {
        insert new List<npsp__General_Accounting_Unit__c>{
            new npsp__General_Accounting_Unit__c(Name = 'WD Test Gala Fund', npsp__Active__c = true),
            new npsp__General_Accounting_Unit__c(Name = 'WD Test General Fund', npsp__Active__c = true),
            new npsp__General_Accounting_Unit__c(Name = 'WD Test Israel Fund', npsp__Active__c = true) };
        insert new Campaign(Name = 'WD Test Other Campaign', IsActive = true);
        List<Object> rows = new List<Object>{
            translation('28.13', 'Other:', 'Campaign', 'WD Test Other Campaign'),
            translation(null, '50th Anniversary Gala', 'General Accounting Unit', 'WD Test Gala Fund'),
            translation(null, 'General JCRC-NY', 'General Accounting Unit', 'WD Test General Fund'),
            translation(null, 'Israel Affairs', 'General Accounting Unit', 'WD Test Israel Fund') };
        WebDonationConfig.cachedValueMaps = (List<Web_Donation_Value_Map__mdt>)
            JSON.deserialize(JSON.serialize(rows), List<Web_Donation_Value_Map__mdt>.class);
    }

    private static Map<String, Object> translation(String key, String value, String target, String name) {
        return new Map<String, Object>{ 'Payload_Key__c' => key, 'Incoming_Value__c' => value,
            'Target_Object__c' => target, 'Target_Record_Name__c' => name, 'Active__c' => true };
    }

    private static Web_Donation__c reloadDonation(Id wdId) {
        return [SELECT Status__c, Error_Message__c, Contact__c, Opportunity__c, Pending_Transaction__c,
                       Unmapped_Designations__c
                FROM Web_Donation__c WHERE Id = :wdId];
    }

    private static Pending_Transaction__c pendingRow(Id ptId) {
        return [SELECT Source__c, External_Id__c, External_Type__c, Amount__c, Payment_Method__c,
                       Contact__c, Match_Status__c, Fund__c, Fund__r.Name, Campaign__r.Name, Memo__c,
                       Import_Note__c, Raw_Data__c, Transaction_Date__c
                FROM Pending_Transaction__c WHERE Id = :ptId];
    }

    // ---- gala gifts -----------------------------------------------------------------------------

    @IsTest
    static void galaGiftGoesToPendingTransactionsWithTheGalaFund() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '28.2' => '50th Anniversary Gala' }), 'G-1');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Processed', r.Status__c, 'error: ' + r.Error_Message__c);
        System.assertEquals(null, r.Opportunity__c, 'no gift - it waits in Pending Transactions');
        System.assertEquals(0, [SELECT COUNT() FROM Opportunity], 'no gift created at all');
        System.assertNotEquals(null, r.Contact__c, 'the donor is still matched or created');
        Pending_Transaction__c p = pendingRow(r.Pending_Transaction__c);
        System.assertEquals('JCRC Website - Gala', p.Source__c, 'lands on the Gala tab');
        System.assertEquals('gf-G-1', p.External_Id__c);
        System.assertEquals('Website Donation', p.External_Type__c);
        System.assertEquals(18.82, p.Amount__c, 'same amount the gift would have had');
        System.assertEquals('Credit Card', p.Payment_Method__c);
        System.assertEquals(Date.newInstance(2026, 8, 19), p.Transaction_Date__c);
        System.assertEquals(r.Contact__c, p.Contact__c);
        System.assertEquals('Confirmed', p.Match_Status__c);
        System.assertEquals('WD Test Gala Fund', p.Fund__r.Name, 'only the gala was ticked');
        System.assertEquals(null, p.Import_Note__c);
        System.assert(p.Memo__c.contains('50th Anniversary Gala'), p.Memo__c);
        System.assert(p.Raw_Data__c.contains('"28.2"'), 'the whole submission is kept');
    }

    @IsTest
    static void galaPlusAnotherDesignationLeavesTheFundToStaff() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.1' => 'General JCRC-NY', '28.2' => '50th Anniversary Gala' }), 'G-2');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Pending_Transaction__c p = pendingRow(reloadDonation(wd.Id).Pending_Transaction__c);
        System.assertEquals('JCRC Website - Gala', p.Source__c, 'still gala');
        System.assertEquals(null, p.Fund__c, 'staff decide');
        System.assert(p.Import_Note__c.contains('choose the fund'), p.Import_Note__c);
        System.assert(p.Import_Note__c.contains('General JCRC-NY; 50th Anniversary Gala'), p.Import_Note__c);
    }

    @IsTest
    static void galaInTheOtherWriteInCounts() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.13' => 'Other:', '23' => 'Table at the gala for my family' }), 'G-3');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertNotEquals(null, r.Pending_Transaction__c, 'error: ' + r.Error_Message__c);
        Pending_Transaction__c p = pendingRow(r.Pending_Transaction__c);
        System.assertEquals(null, p.Fund__c, '"Other" is not a fund');
        System.assertEquals('WD Test Other Campaign', p.Campaign__r.Name, 'campaign as the gift would have had');
        System.assert(p.Memo__c.contains('Table at the gala'), p.Memo__c);
    }

    @IsTest
    static void galaMustBeAWholeWord() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.13' => 'Other:', '23' => 'Galanti Family Foundation' }), 'G-4');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals(null, r.Pending_Transaction__c, 'Galanti is not the gala');
        System.assertNotEquals(null, r.Opportunity__c, 'an ordinary gift');
    }

    @IsTest
    static void galaRoutingSwitchedOffCreatesTheGift() {
        useSettings().galaToPending = false;
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '28.2' => '50th Anniversary Gala' }), 'G-5');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals(null, r.Pending_Transaction__c);
        System.assertNotEquals(null, r.Opportunity__c, 'gift created as before');
        System.assertEquals('WD Test Gala Fund', [SELECT npsp__General_Accounting_Unit__r.Name FROM npsp__Allocation__c
            WHERE npsp__Opportunity__c = :r.Opportunity__c].npsp__General_Accounting_Unit__r.Name);
    }

    @IsTest
    static void galaWordsAndFieldsComeFromSettings() {
        WebDonationConfig.Settings cfg = useSettings();
        cfg.galaWords = 'Dinner, Benefit';
        cfg.galaPayloadKeys = '23';
        useTranslations();
        // The gala checkbox is outside the fields checked, so only the write-in decides.
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.2' => '50th Anniversary Gala', '23' => 'annual DINNER' }), 'G-6');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        System.assertNotEquals(null, reloadDonation(wd.Id).Pending_Transaction__c, 'Dinner, any capitalization');
        System.assertEquals(false, WebDonationProcessor.mentionsGala(
            WebDonationProcessor.galaAnswers(new Map<String, Object>{ '28.2' => '50th Anniversary Gala' }, '23'),
            'Dinner, Benefit'), 'a field not listed is not checked');
    }

    @IsTest
    static void replayingAGalaGiftNeverAddsASecondRow() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '28.2' => '50th Anniversary Gala' }), 'G-7');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c WHERE External_Id__c = 'gf-G-7']);
        System.assertEquals('Processed', reloadDonation(wd.Id).Status__c);
    }

    @IsTest
    static void galaGiftAlreadyCommittedIsNotSentAgain() {
        useSettings();
        useTranslations();
        insert new Opportunity(Name = 'Committed gala gift', StageName = 'Closed Won', Amount = 18.82,
            CloseDate = Date.newInstance(2026, 8, 19), Source_Transaction_Id__c = 'gf-G-8');
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '28.2' => '50th Anniversary Gala' }), 'G-8');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Failed', r.Status__c);
        System.assert(r.Error_Message__c.contains('already committed'), r.Error_Message__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
    }

    @IsTest
    static void galaGiftWithNoAmountFails() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.2' => '50th Anniversary Gala', '5' => null }), 'G-9');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Failed', r.Status__c);
        System.assert(r.Error_Message__c.contains('amount'), r.Error_Message__c);
    }

    @IsTest
    static void twoDesignationsSplitTheGift() {
        useSettings();
        useTranslations();
        Web_Donation__c wd = stage(payload(new Map<String, String>{
            '28.1' => 'General JCRC-NY', '28.3' => 'Israel Affairs' }), 'G-10');

        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();

        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals(null, r.Unmapped_Designations__c, 'both translate now');
        Decimal total = 0;
        for (npsp__Allocation__c a : [SELECT npsp__Amount__c FROM npsp__Allocation__c
                                      WHERE npsp__Opportunity__c = :r.Opportunity__c]) {
            total += a.npsp__Amount__c;
        }
        System.assertEquals(18.82, total, 'split two ways, summing to the gift');
    }

    // ---- donor match rules ------------------------------------------------------------------------

    @IsTest
    static void matchRuleNoneCreatesTheDonor() {
        // (A duplicate already in the org would be stopped by the Contact duplicate rule instead.)
        useSettings().contactMatchRule = 'None';
        Web_Donation__c wd = stage(payload(null), 'M-1');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        Web_Donation__c r = [SELECT Status__c, Error_Message__c, Contact_Was_Created__c FROM Web_Donation__c WHERE Id = :wd.Id];
        System.assertEquals('Processed', r.Status__c, 'error: ' + r.Error_Message__c);
        System.assertEquals(true, r.Contact_Was_Created__c, 'no lookup at all');
    }

    @IsTest
    static void noMatchCanBeHeldForReview() {
        useSettings().onNoMatch = 'Fail';
        Web_Donation__c wd = stage(payload(null), 'M-2');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Failed', r.Status__c);
        System.assert(r.Error_Message__c.contains('No existing contact matched'), r.Error_Message__c);
    }

    @IsTest
    static void emailOrNameFallsBackToTheName() {
        useSettings().contactMatchRule = 'EmailOrFirstLast';
        Contact existing = new Contact(FirstName = 'Web', LastName = 'Donor', Email = 'old.address@example.com');
        insert existing;
        Web_Donation__c wd = stage(payload(null), 'M-3');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        System.assertEquals(existing.Id, reloadDonation(wd.Id).Contact__c, 'matched on first + last name');
    }

    @IsTest
    static void firstLastEmailNeedsAllThree() {
        useSettings().contactMatchRule = 'FirstLastEmail';
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '1.3' => null }), 'M-4');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        System.assertEquals('Failed', reloadDonation(wd.Id).Status__c);
    }

    @IsTest
    static void severalMatchesCanBeHeldOrTakeTheNewest() {
        insert new List<Contact>{
            new Contact(FirstName = 'Web', LastName = 'Donor', Email = 'web.donor@example.com'),
            new Contact(FirstName = 'Web', LastName = 'Donor', Email = 'web.donor@example.com') };
        useSettings().multipleMatchRule = 'Fail';
        Web_Donation__c held = stage(payload(null), 'M-5');
        Web_Donation__c newest = stage(payload(null), 'M-6');

        Test.startTest();
        WebDonationProcessor.process(held.Id);
        WebDonationConfig.cachedSettings.multipleMatchRule = 'Newest';
        WebDonationProcessor.process(newest.Id);
        Test.stopTest();

        System.assert(reloadDonation(held.Id).Error_Message__c.contains('contacts match'));
        System.assertEquals('Processed', reloadDonation(newest.Id).Status__c);
    }

    @IsTest
    static void contactRoleIsSetOnTheGift() {
        useSettings().contactRole = 'Donor';
        Web_Donation__c wd = stage(payload(null), 'M-7');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Donor', [SELECT Role FROM OpportunityContactRole
            WHERE OpportunityId = :r.Opportunity__c AND ContactId = :r.Contact__c LIMIT 1].Role);
    }

    // ---- account handling -----------------------------------------------------------------------

    @IsTest
    static void existingOrganizationIsUsed() {
        WebDonationConfig.Settings cfg = useSettings();
        cfg.accountHandling = 'MatchOrganization';
        cfg.organizationPayloadKey = '9';
        // An Organization account - NPSP refuses a gift on a household the donor isn't in.
        Account org = new Account(Name = 'WD Existing Org', RecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Organization').getRecordTypeId());
        insert org;
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '9' => 'WD Existing Org' }), 'A-2');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        Web_Donation__c r = reloadDonation(wd.Id);
        System.assertEquals('Processed', r.Status__c, 'error: ' + r.Error_Message__c);
        System.assertEquals(org.Id, [SELECT AccountId FROM Opportunity WHERE Id = :r.Opportunity__c].AccountId);
    }

    @IsTest
    static void unknownOrganizationCanBeHeld() {
        WebDonationConfig.Settings cfg = useSettings();
        cfg.accountHandling = 'MatchOrganization';
        cfg.organizationPayloadKey = '9';
        cfg.onOrganizationNoMatch = 'Fail';
        Web_Donation__c wd = stage(payload(new Map<String, String>{ '9' => 'Nobody Inc' }), 'A-3');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        System.assert(reloadDonation(wd.Id).Error_Message__c.contains('No Account named'));
    }

    @IsTest
    static void alwaysOrganizationNeedsACompany() {
        WebDonationConfig.Settings cfg = useSettings();
        cfg.accountHandling = 'AlwaysOrganization';
        cfg.organizationPayloadKey = '9';
        Web_Donation__c wd = stage(payload(null), 'A-4');
        Test.startTest();
        WebDonationProcessor.process(wd.Id);
        Test.stopTest();
        System.assert(reloadDonation(wd.Id).Error_Message__c.contains('no company name'));
    }
}
