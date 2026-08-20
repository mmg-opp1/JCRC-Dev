/**
 * @description Tests for WebDonationReceiver - the public endpoint.
 *
 *              These are security tests as much as functional ones. The endpoint is reachable
 *              by anyone on the internet, so the cases that must never regress are the ones
 *              that REJECT: no secret, wrong secret, oversized body. Each asserts that nothing
 *              was stored, not merely that a 401 came back.
 *
 * @author Jason Ott
 * @created 2026-08-20
 *
 * Change Log:
 * -----------
 * 2026-08-20 - Jason Ott - Created (Website Donations phase 1 coverage).
 */
@IsTest
private class WebDonationReceiverTest {

    private static final String SECRET = 'test-secret-value-0123456789';

    private static void configure(String secret) {
        Webhook_Config__c cfg = new Webhook_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Shared_Secret__c = secret,
            Max_Payload_Bytes__c = 5000);
        insert cfg;
    }

    private static void request(String body, String headerName, String headerValue) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/webdonation';
        req.httpMethod = 'POST';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        if (headerName != null) {
            req.headers.put(headerName, headerValue);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void acceptsAValidSubmission() {
        configure(SECRET);
        request('{"id":"5001","form_id":"15","2":"a@example.com"}', 'X-JCRC-Signature', SECRET);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('received', r.status);
        System.assertEquals(201, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Web_Donation__c WHERE GF_Entry_Id__c = '5001']);
    }

    @IsTest
    static void rejectsMissingSecretAndStoresNothing() {
        configure(SECRET);
        request('{"id":"5002"}', null, null);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('unauthorized', r.status);
        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Web_Donation__c],
            'an unauthenticated caller must not be able to write anything at all');
    }

    @IsTest
    static void rejectsWrongSecretAndStoresNothing() {
        configure(SECRET);
        request('{"id":"5003"}', 'X-JCRC-Signature', 'not-the-secret');

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('unauthorized', r.status);
        System.assertEquals(0, [SELECT COUNT() FROM Web_Donation__c]);
    }

    @IsTest
    static void failsClosedWhenNoSecretIsConfigured() {
        // No Webhook_Config__c row at all. A blank configured secret must never mean
        // "allow everything" - that would leave the endpoint open before setup.
        request('{"id":"5004"}', 'X-JCRC-Signature', 'anything');

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('unauthorized', r.status, 'unconfigured must fail closed');
        System.assertEquals(0, [SELECT COUNT() FROM Web_Donation__c]);
    }

    @IsTest
    static void headerNameIsCaseInsensitive() {
        configure(SECRET);
        request('{"id":"5005"}', 'x-jcrc-signature', SECRET);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('received', r.status,
            'HTTP header names are case-insensitive; the check must not depend on casing');
    }

    @IsTest
    static void rejectsEmptyBody() {
        configure(SECRET);
        request('', 'X-JCRC-Signature', SECRET);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('empty', r.status);
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsOversizedBodyBeforeParsing() {
        configure(SECRET);
        request('{"id":"5006","j":"' + 'x'.repeat(6000) + '"}', 'X-JCRC-Signature', SECRET);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('too large', r.status);
        System.assertEquals(413, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Web_Donation__c]);
    }

    @IsTest
    static void storesMalformedJsonAsEvidence() {
        configure(SECRET);
        request('this is not json', 'X-JCRC-Signature', SECRET);

        Test.startTest();
        WebDonationReceiver.Result r = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('received', r.status,
            'malformed JSON is kept - it is evidence the form changed, not something to discard');
        System.assertEquals(1, [SELECT COUNT() FROM Web_Donation__c]);
    }

    @IsTest
    static void retryOfTheSameEntryIsIgnored() {
        configure(SECRET);
        String body = '{"id":"5007","form_id":"15"}';

        Test.startTest();
        request(body, 'X-JCRC-Signature', SECRET);
        WebDonationReceiver.receive();
        request(body, 'X-JCRC-Signature', SECRET);
        WebDonationReceiver.Result second = WebDonationReceiver.receive();
        Test.stopTest();

        System.assertEquals('duplicate ignored', second.status);
        System.assertEquals(200, RestContext.response.statusCode,
            '200 so Gravity Forms stops retrying rather than escalating');
        System.assertEquals(1, [SELECT COUNT() FROM Web_Donation__c WHERE GF_Entry_Id__c = '5007'],
            'a retry must never create a second gift');
    }
}
