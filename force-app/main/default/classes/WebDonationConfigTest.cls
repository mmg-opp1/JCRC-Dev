/**
 * @description Tests for WebDonationConfig - turning payload text into each field type, skipping
 *              fields that can't take a value, value translations, and the gala setting defaults.
 * @author Jason Ott
 * @created 2026-10-28
 *
 * Change Log:
 * -----------
 * 2026-10-28 - Jason Ott - Created (coverage for production, plus the gala setting defaults).
 */
@IsTest
private class WebDonationConfigTest {

    @IsTest
    static void convertsPayloadTextToEachFieldType() {
        Account a = new Account();
        System.assert(WebDonationConfig.applyValue(a, 'NumberOfEmployees', ' 1,200 '), 'integer');
        System.assertEquals(1200, a.NumberOfEmployees);
        System.assert(WebDonationConfig.applyValue(a, 'AnnualRevenue', '$54.50'), 'currency');
        System.assertEquals(54.50, a.AnnualRevenue);

        Contact c = new Contact();
        System.assert(WebDonationConfig.applyValue(c, 'DoNotCall', 'Yes'), 'checkbox');
        System.assertEquals(true, c.DoNotCall);
        System.assert(WebDonationConfig.applyValue(c, 'Birthdate', '1970-05-04 10:00:00'), 'date');
        System.assertEquals(Date.newInstance(1970, 5, 4), c.Birthdate);
        System.assert(WebDonationConfig.applyValue(c, 'LastName', '  Rodriguez '), 'text is trimmed');
        System.assertEquals('Rodriguez', c.LastName);

        Task t = new Task();
        System.assert(WebDonationConfig.applyValue(t, 'ReminderDateTime', '2026-10-28 09:30:00'), 'date/time');
        System.assertEquals(Datetime.valueOf('2026-10-28 09:30:00'), t.ReminderDateTime);
    }

    @IsTest
    static void skipsWhatCannotBeWritten() {
        Contact c = new Contact();
        System.assertEquals(false, WebDonationConfig.applyValue(c, 'No_Such_Field__c', 'x'), 'missing field');
        System.assertEquals(false, WebDonationConfig.applyValue(c, 'Name', 'x'), 'compound / calculated');
        System.assertEquals(false, WebDonationConfig.applyValue(c, null, 'x'), 'no field');
        System.assertEquals(false, WebDonationConfig.applyValue(c, 'LastName', null), 'no value');
        System.assertEquals(false, WebDonationConfig.applyValue(c, 'Birthdate', 'not a date'), 'bad value is skipped');
    }

    @IsTest
    static void translationsPreferTheKeySpecificRow() {
        WebDonationConfig.cachedValueMaps = (List<Web_Donation_Value_Map__mdt>) JSON.deserialize(JSON.serialize(
            new List<Object>{
                new Map<String, Object>{ 'Incoming_Value__c' => 'Other', 'Target_Object__c' => 'Literal',
                    'Target_Record_Name__c' => 'generic' },
                new Map<String, Object>{ 'Payload_Key__c' => '28.13', 'Incoming_Value__c' => 'Other:',
                    'Target_Object__c' => 'Literal', 'Target_Record_Name__c' => 'specific' } }),
            List<Web_Donation_Value_Map__mdt>.class);

        System.assertEquals('specific', WebDonationConfig.translate('28.13', ' OTHER: ').Target_Record_Name__c);
        System.assertEquals('generic', WebDonationConfig.translate('23', 'other').Target_Record_Name__c);
        System.assertEquals(null, WebDonationConfig.translate('23', 'Something else'));
        System.assertEquals(null, WebDonationConfig.translate('23', ''));
    }

    @IsTest
    static void resolvesCampaignsAndFundsByName() {
        Campaign camp = new Campaign(Name = 'WDC Test Campaign', IsActive = true);
        insert camp;
        npsp__General_Accounting_Unit__c gau = new npsp__General_Accounting_Unit__c(Name = 'WDC Test Fund', npsp__Active__c = true);
        insert gau;
        System.assertEquals(camp.Id, WebDonationConfig.resolveRecord('Campaign', 'WDC Test Campaign'));
        System.assertEquals(gau.Id, WebDonationConfig.resolveRecord('General Accounting Unit', 'WDC Test Fund'));
        System.assertEquals(null, WebDonationConfig.resolveRecord('Literal', 'anything'));
        System.assertEquals(null, WebDonationConfig.resolveRecord('Campaign', null));
    }

    @IsTest
    static void galaSettingsHaveDefaults() {
        WebDonationConfig.Settings s = WebDonationConfig.settings();
        System.assertNotEquals(null, s.galaToPending);
        System.assert(String.isNotBlank(s.galaWords), 'blank words fall back to Gala');
        System.assert(String.isNotBlank(s.galaPayloadKeys), 'blank fields fall back to 28, 23');
        System.assertEquals(s, WebDonationConfig.settings(), 'read once per transaction');
        System.assertNotEquals(null, WebDonationConfig.mappings());
    }
}
