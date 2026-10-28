/**
 * @description Tests for WebDonationMappingController - the Web Donation Mapping admin screen:
 *              reads, the dry run, the validation that guards what the public endpoint may write,
 *              and the settings round trip including the gala gift settings.
 *
 *              Metadata API deploys can't run in a test, so the save methods return 'TEST-DEPLOY'
 *              once their validation has passed; these tests check the validation and the reads.
 * @author Jason Ott
 * @created 2026-10-28
 *
 * Change Log:
 * -----------
 * 2026-10-28 - Jason Ott - Created (coverage for production, plus the gala gift settings).
 */
@IsTest
private class WebDonationMappingControllerTest {

    private static WebDonationMappingController.MappingRow row(String key, String obj, String field) {
        WebDonationMappingController.MappingRow r = new WebDonationMappingController.MappingRow();
        r.payloadKey = key;
        r.targetObject = obj;
        r.targetField = field;
        r.mappingType = 'Payload';
        r.active = true;
        return r;
    }

    /**
     * True when saving the rows is refused. (An AuraHandledException's getMessage() reads
     * "Script-thrown exception" inside Apex, so the refusal itself is what is asserted.)
     */
    private static Boolean refused(List<WebDonationMappingController.MappingRow> rows) {
        try {
            System.assertEquals('TEST-DEPLOY', WebDonationMappingController.saveMappings(JSON.serialize(rows)));
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    @IsTest
    static void readsTheConfiguration() {
        Test.startTest();
        List<WebDonationMappingController.MappingRow> maps = WebDonationMappingController.getMappings();
        List<String> objects = WebDonationMappingController.getObjects();
        List<WebDonationMappingController.FieldOption> fields = WebDonationMappingController.getFields('Contact');
        List<WebDonationMappingController.ValueMapRow> values = WebDonationMappingController.getValueMaps();
        List<String> lookupObjects = WebDonationMappingController.getLookupObjects();
        Test.stopTest();

        System.assertNotEquals(null, maps);
        System.assertEquals(new List<String>{ 'Contact', 'Opportunity' }, objects);
        Set<String> names = new Set<String>();
        for (WebDonationMappingController.FieldOption f : fields) {
            names.add(f.value.toLowerCase());
        }
        System.assert(names.contains('email'), 'writable fields are offered');
        System.assert(!names.contains('ownerid'), 'the deny list is never offered');
        System.assertNotEquals(null, values);
        System.assert(lookupObjects.contains('General Accounting Unit'));
    }

    @IsTest
    static void refusesAnObjectOutsideTheAllowedList() {
        try {
            WebDonationMappingController.getFields('User');
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            // refused, as expected
        }
    }

    @IsTest
    static void lookupRecordsListCampaignsAndFunds() {
        insert new Campaign(Name = 'WDM Test Campaign', IsActive = true);
        insert new npsp__General_Accounting_Unit__c(Name = 'WDM Test Fund', npsp__Active__c = true);
        System.assert(WebDonationMappingController.getLookupRecords('Campaign').contains('WDM Test Campaign'));
        System.assert(WebDonationMappingController.getLookupRecords('General Accounting Unit').contains('WDM Test Fund'));
        System.assert(WebDonationMappingController.getLookupRecords('Literal').isEmpty());
    }

    @IsTest
    static void dryRunReportsMappedAndUnmappedKeys() {
        WebDonationMappingController.DryRunResult res = WebDonationMappingController.dryRun(
            JSON.serialize(new Map<String, Object>{ '5' => '18.82', 'zz-not-a-field' => 'x' }));
        System.assertEquals(2, res.mapped.size() + res.unmapped.size(), 'every key is accounted for');
        Boolean listedAsUnmapped = false;
        for (WebDonationMappingController.DryRunLine l : res.unmapped) {
            listedAsUnmapped |= l.payloadKey == 'zz-not-a-field';
        }
        System.assert(listedAsUnmapped, 'a new form field announces itself');

        WebDonationMappingController.DryRunResult bad = WebDonationMappingController.dryRun('not json');
        System.assert(bad.problems[0].contains('not valid JSON'), bad.problems[0]);
    }

    @IsTest
    static void saveAcceptsAValidRowAndRefusesUnsafeOnes() {
        System.assertEquals(false, refused(new List<WebDonationMappingController.MappingRow>{
            row('2', 'Contact', 'Email') }), 'a valid row is accepted');

        WebDonationMappingController.MappingRow noKey = row(null, 'Contact', 'Email');
        System.assert(refused(new List<WebDonationMappingController.MappingRow>{ noKey }), 'needs a payload key');

        WebDonationMappingController.MappingRow staticBlank = row(null, 'Opportunity', 'StageName');
        staticBlank.mappingType = 'Static';
        System.assert(refused(new List<WebDonationMappingController.MappingRow>{ staticBlank }), 'static value');

        System.assert(refused(new List<WebDonationMappingController.MappingRow>{
            row('2', 'User', 'Email') }), 'Not an allowed target object');
        System.assert(refused(new List<WebDonationMappingController.MappingRow>{
            row('2', 'Contact', null) }), 'Choose a target field');
        System.assert(refused(new List<WebDonationMappingController.MappingRow>{
            row('2', 'Contact', 'OwnerId') }), 'cannot be a mapping target');
        System.assert(refused(new List<WebDonationMappingController.MappingRow>{
            row('2', 'Contact', 'No_Such_Field__c') }), 'does not exist');

        System.assertEquals('Succeeded', WebDonationMappingController.getSaveStatus('TEST-DEPLOY'));
        System.assertEquals('Pending', WebDonationMappingController.getSaveStatus('0Af000000000001'));
    }

    @IsTest
    static void valueTranslationsAreValidated() {
        WebDonationMappingController.ValueMapRow v = new WebDonationMappingController.ValueMapRow();
        v.incomingValue = '50th Anniversary Gala';
        v.targetObject = 'General Accounting Unit';
        v.targetRecordName = 'Gala Fund';
        System.assertEquals('TEST-DEPLOY', WebDonationMappingController.saveValueMaps(
            JSON.serialize(new List<WebDonationMappingController.ValueMapRow>{ v })));

        v.targetRecordName = null;
        try {
            WebDonationMappingController.saveValueMaps(JSON.serialize(new List<WebDonationMappingController.ValueMapRow>{ v }));
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            // refused, as expected
        }
        v.incomingValue = null;
        try {
            WebDonationMappingController.saveValueMaps(JSON.serialize(new List<WebDonationMappingController.ValueMapRow>{ v }));
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            // refused, as expected
        }
    }

    @IsTest
    static void settingsRoundTripIncludingGala() {
        WebDonationMappingController.Settings s = WebDonationMappingController.getSettings();
        System.assertNotEquals(null, s.contactMatchRule);

        s.galaToPending = true;
        s.galaWords = 'Gala, Dinner';
        s.galaPayloadKeys = '28, 23';
        System.assertEquals('TEST-DEPLOY', WebDonationMappingController.saveSettings(JSON.serialize(s)));

        s.accountHandling = 'MatchOrganization';
        s.organizationPayloadKey = null;
        try {
            WebDonationMappingController.saveSettings(JSON.serialize(s));
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            // refused, as expected
        }
    }
}
