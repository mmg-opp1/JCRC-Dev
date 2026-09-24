/**
 * @description Tests for GalaSponsorReceiver - the public gala sponsorship endpoint.
 *
 *              Security first: no secret, wrong secret, oversized body - each asserts that NOTHING was stored.
 *              Then storage, the resend case, and the guard that the Site guest user can write every field the
 *              endpoint sets (a field it cannot write makes every live submission fail with a 500 - that happened
 *              on the QuickBooks endpoint on 2026-09-24).
 * @author Jason Ott
 * @created 2026-09-24
 *
 * Change Log:
 * -----------
 * 2026-09-24 - Jason Ott - Created with the endpoint.
 */
@IsTest
private class GalaSponsorReceiverTest {

    private static final String SECRET = 'gala-test-secret-0123456789';

    private static void configure(String secret) {
        insert new Webhook_Config__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Gala_Shared_Secret__c = secret, Shared_Secret__c = 'other-form-secret', Max_Payload_Bytes__c = 5000);
    }

    private static GalaSponsorReceiver.Result post(String body, String headerName, String headerValue) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/gala/sponsor';
        req.httpMethod = 'POST';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        if (headerName != null) {
            req.headers.put(headerName, headerValue);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return GalaSponsorReceiver.receive();
    }

    private static String submission(String entryId, String payOption) {
        return '{"entry_id":"' + entryId + '","form_id":"21","pay_option":"' + payOption + '",'
            + '"name":"Rachel Sponsor","email":"Rachel@Example.com","amount":"$15,000.00",'
            + '"transaction_id":"pi_3QabcSTRIPE","level":"Advocate","listing_name":"The Sponsor Family"}';
    }

    // ---- rejections -------------------------------------------------------------------------------

    @IsTest
    static void missingOrWrongSecretStoresNothing() {
        configure(SECRET);
        post(submission('1001', 'Pay Now'), null, null);
        System.assertEquals(401, RestContext.response.statusCode);
        post(submission('1001', 'Pay Now'), 'X-JCRC-Signature', 'not-the-secret');
        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Gala_Submission__c]);
    }

    @IsTest
    static void withNoSecretConfiguredEverythingIsRejected() {
        configure(null);
        post(submission('1002', 'Pay Now'), 'X-JCRC-Signature', 'anything');
        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Gala_Submission__c]);
    }

    @IsTest
    static void emptyAndOversizedBodiesAreRejected() {
        configure(SECRET);
        post(null, 'X-JCRC-Signature', SECRET);
        System.assertEquals(400, RestContext.response.statusCode);
        String big = '{"entry_id":"1003","padding":"' + 'x'.repeat(6000) + '"}';
        post(big, 'X-JCRC-Signature', SECRET);
        System.assertEquals(413, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Gala_Submission__c]);
    }

    // ---- accepted ---------------------------------------------------------------------------------

    @IsTest
    static void storesTheSubmissionAndWhatItNeedsToFileIt() {
        configure(SECRET);
        Test.startTest();
        // Header capitalisation varies by host; it must not matter.
        GalaSponsorReceiver.Result r = post(submission('1004', 'Pay Now'), 'x-jcrc-signature', SECRET);
        Test.stopTest();

        System.assertEquals('received', r.status);
        System.assertEquals(200, RestContext.response.statusCode);
        Gala_Submission__c s = [SELECT Entry_Id__c, Form_Id__c, Pay_Option__c, Payer_Name__c, Payer_Email__c,
                                       Amount__c, Payment_Reference__c, Status__c, Payload__c, Received_At__c
                                FROM Gala_Submission__c];
        System.assertEquals('1004', s.Entry_Id__c);
        System.assertEquals('21', s.Form_Id__c);
        System.assertEquals('Pay Now', s.Pay_Option__c);
        System.assertEquals('Rachel Sponsor', s.Payer_Name__c);
        System.assertEquals('rachel@example.com', s.Payer_Email__c, 'Salesforce lower-cases email');
        System.assertEquals(15000.00, s.Amount__c, 'currency text is read');
        System.assertEquals('pi_3QabcSTRIPE', s.Payment_Reference__c);
        System.assertEquals('Received', s.Status__c);
        System.assert(s.Payload__c.contains('"listing_name"'), 'everything else is kept raw for the mapping');
        System.assertNotEquals(null, s.Received_At__c);
    }

    @IsTest
    static void aResendIsAcknowledgedAndNotStoredTwice() {
        configure(SECRET);
        post(submission('1005', 'Pay Later'), 'X-JCRC-Signature', SECRET);
        GalaSponsorReceiver.Result again = post(submission('1005', 'Pay Later'), 'X-JCRC-Signature', SECRET);
        System.assertEquals('duplicate ignored', again.status);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Gala_Submission__c]);
    }

    @IsTest
    static void unreadableBodiesAreStillKept() {
        configure(SECRET);
        post('not json at all', 'X-JCRC-Signature', SECRET);
        System.assertEquals(200, RestContext.response.statusCode);
        Gala_Submission__c s = [SELECT Entry_Id__c, Payload__c, Status__c FROM Gala_Submission__c];
        System.assertEquals(null, s.Entry_Id__c);
        System.assertEquals('not json at all', s.Payload__c, 'nothing is thrown away');
    }

    @IsTest
    static void currencyTextIsReadOrLeftAlone() {
        System.assertEquals(1500, GalaSponsorReceiver.safeDecimal('$1,500.00'));
        System.assertEquals(null, GalaSponsorReceiver.safeDecimal('lots'));
    }

    /** The endpoint runs as the guest user; a field it cannot write makes every live submission fail with a 500. */
    @IsTest(SeeAllData=true)
    static void guestUserCanWriteEveryFieldTheReceiverSets() {
        Set<String> needed = new Set<String>{
            'Gala_Submission__c.Amount__c', 'Gala_Submission__c.Entry_Id__c', 'Gala_Submission__c.Form_Id__c',
            'Gala_Submission__c.Pay_Option__c', 'Gala_Submission__c.Payer_Email__c', 'Gala_Submission__c.Payer_Name__c',
            'Gala_Submission__c.Payload__c', 'Gala_Submission__c.Payment_Reference__c',
            'Gala_Submission__c.Received_At__c', 'Gala_Submission__c.Status__c' };
        Set<String> writable = new Set<String>();
        for (FieldPermissions fp : [SELECT Field FROM FieldPermissions
                                    WHERE SobjectType = 'Gala_Submission__c' AND PermissionsEdit = true
                                      AND Parent.Profile.Name = 'hooks Profile']) {
            writable.add(fp.Field);
        }
        needed.removeAll(writable);
        System.assertEquals(new Set<String>(), needed,
            'the hooks guest profile cannot write these, so live submissions would fail: ' + needed);
    }
}
