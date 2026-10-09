/**
 * @description Tests for QuickBooksWebhookReceiver - the public QuickBooks webhook endpoint (JSI-121).
 *
 *              Security first: the cases that must never regress are the rejections (no signature, wrong
 *              signature, signed with another token, switched off, oversized), and each asserts that NOTHING
 *              was stored, not just the status code. Then the CloudEvents parsing, retries and the
 *              company check.
 *
 *              Signatures are computed here the way Intuit does: base64(HMAC-SHA256(body, verifier token)).
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5a).
 * 2026-09-24 - Jason Ott - Guards the guest user's field access: a new field the receiver writes without
 *                          guest FLS makes every real delivery fail with a 500 (it happened).
 */
@IsTest
private class QuickBooksWebhookReceiverTest {

    private static final String TOKEN = 'test-verifier-token-0123456789abcdef';
    private static final String REALM = '9341455912345678';

    private static void configure(Boolean enabled, String token, String realm, Integer maxBytes) {
        insert new QuickBooks_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Enabled__c = enabled,
            Verifier_Token__c = token, Realm_Id__c = realm, Max_Payload_Bytes__c = maxBytes);
    }

    private static String sign(String body, String token) {
        return EncodingUtil.base64Encode(Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(token)));
    }

    private static QuickBooksWebhookReceiver.Result post(String body, String headerName, String signature) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/qbo/webhook';
        req.httpMethod = 'POST';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        if (headerName != null) {
            req.headers.put(headerName, signature);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return QuickBooksWebhookReceiver.receive();
    }

    private static String event(String id, String type, String entityId, String realm) {
        return '{"specversion":"1.0","id":"' + id + '","source":"intuit.abc=","type":"' + type + '",'
            + '"datacontenttype":"application/json","time":"2026-09-17T14:05:25.179Z",'
            + '"intuitentityid":"' + entityId + '","intuitaccountid":"' + realm + '","data":{}}';
    }

    // ---- rejections -----------------------------------------------------------------------------

    @IsTest
    static void missingSignatureIsRejectedAndNothingStored() {
        configure(true, TOKEN, REALM, null);
        String body = '[' + event('e1', 'qbo.deposit.created.v1', '1234', REALM) + ']';
        QuickBooksWebhookReceiver.Result r = post(body, null, null);
        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals('unauthorized', r.status);
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void wrongSignatureIsRejectedAndNothingStored() {
        configure(true, TOKEN, REALM, null);
        String body = '[' + event('e1', 'qbo.deposit.created.v1', '1234', REALM) + ']';
        post(body, 'intuit-signature', sign(body, 'some-other-token'));
        System.assertEquals(401, RestContext.response.statusCode);
        // A valid signature for a DIFFERENT body must not pass either.
        post(body, 'intuit-signature', sign(body + ' ', TOKEN));
        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void switchedOffOrUnconfiguredAnswers503SoIntuitRetries() {
        String body = '[' + event('e1', 'qbo.deposit.created.v1', '1234', REALM) + ']';
        post(body, 'intuit-signature', sign(body, TOKEN));
        System.assertEquals(503, RestContext.response.statusCode, 'no settings record');
        configure(false, TOKEN, REALM, null);
        post(body, 'intuit-signature', sign(body, TOKEN));
        System.assertEquals(503, RestContext.response.statusCode, 'switched off');
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void emptyAndOversizedBodiesAreRejected() {
        configure(true, TOKEN, REALM, 200);
        post(null, 'intuit-signature', 'x');
        System.assertEquals(400, RestContext.response.statusCode);
        String big = '[' + event('e1', 'qbo.deposit.created.v1', '1234', REALM) + ']';
        post(big, 'intuit-signature', sign(big, TOKEN));
        System.assertEquals(413, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    // ---- accepted -------------------------------------------------------------------------------

    @IsTest
    static void validDeliveryStoresOneRowPerEvent() {
        configure(true, TOKEN, REALM, null);
        String body = '[' + event('evt-1', 'qbo.deposit.created.v1', '1234', REALM) + ','
            + event('evt-2', 'qbo.salesreceipt.updated.v1', '88', REALM) + ']';

        Test.startTest();
        // Header capitalisation varies by proxy; it must not matter.
        QuickBooksWebhookReceiver.Result r = post(body, 'Intuit-Signature', sign(body, TOKEN));
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('received', r.status);
        QuickBooks_Event__c e = [SELECT Event_Type__c, Entity_Name__c, Operation__c, Entity_Id__c, Entity_Key__c,
                                        Realm_Id__c, Event_Time__c, Received_At__c, Payload__c, Status__c
                                 FROM QuickBooks_Event__c WHERE Event_Id__c = 'evt-1'];
        System.assertEquals('qbo.deposit.created.v1', e.Event_Type__c);
        System.assertEquals('deposit', e.Entity_Name__c);
        System.assertEquals('created', e.Operation__c);
        System.assertEquals('1234', e.Entity_Id__c);
        System.assertEquals('deposit-1234', e.Entity_Key__c);
        System.assertEquals(REALM, e.Realm_Id__c);
        System.assertEquals('2026-09-17 14:05:25', e.Event_Time__c.formatGmt('yyyy-MM-dd HH:mm:ss'), 'time parsed');
        System.assertNotEquals(null, e.Received_At__c);
        System.assert(e.Payload__c.contains('"intuitentityid":"1234"'), e.Payload__c);
        System.assertEquals('Received', e.Status__c);
        System.assertEquals('updated', [SELECT Operation__c FROM QuickBooks_Event__c WHERE Event_Id__c = 'evt-2'].Operation__c);
    }

    @IsTest
    static void retriedDeliveryIsNotStoredTwice() {
        configure(true, TOKEN, REALM, null);
        String body = '[' + event('evt-9', 'qbo.payment.created.v1', '55', REALM) + ']';
        post(body, 'intuit-signature', sign(body, TOKEN));
        post(body, 'intuit-signature', sign(body, TOKEN));
        System.assertEquals(200, RestContext.response.statusCode, 'a retry is acknowledged so Intuit stops');
        System.assertEquals(1, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void eventFromAnotherCompanyIsStoredAsIgnored() {
        configure(true, TOKEN, REALM, null);
        String body = '[' + event('evt-x', 'qbo.deposit.created.v1', '7', '1111') + ']';
        post(body, 'intuit-signature', sign(body, TOKEN));
        System.assertEquals(200, RestContext.response.statusCode);
        QuickBooks_Event__c e = [SELECT Status__c, Error_Message__c FROM QuickBooks_Event__c];
        System.assertEquals('Ignored', e.Status__c);
        System.assert(e.Error_Message__c.contains('1111'));
    }

    @IsTest
    static void unreadableBodiesAreKeptAsFailedNotLost() {
        configure(true, TOKEN, '', null);
        // Old (pre-CloudEvents) format: an object, not an array.
        String legacy = '{"eventNotifications":[{"realmId":"1","dataChangeEvent":{"entities":[{"name":"Deposit","id":"9","operation":"Create"}]}}]}';
        post(legacy, 'intuit-signature', sign(legacy, TOKEN));
        System.assertEquals(200, RestContext.response.statusCode);
        post(legacy, 'intuit-signature', sign(legacy, TOKEN));
        QuickBooks_Event__c f = [SELECT Status__c, Payload__c, Error_Message__c FROM QuickBooks_Event__c];
        System.assertEquals('Failed', f.Status__c);
        System.assert(f.Payload__c.contains('eventNotifications'));
        System.assert(f.Error_Message__c.contains('CloudEvents'));

        // An array with a malformed entry and an entry missing its type.
        String odd = '["not an object", {"id":"evt-no-type","intuitaccountid":"1"}]';
        post(odd, 'intuit-signature', sign(odd, TOKEN));
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(3, [SELECT COUNT() FROM QuickBooks_Event__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void timeParsingIsTolerant() {
        System.assertEquals(null, QuickBooksWebhookReceiver.parseTime('not a time'));
        System.assertEquals(null, QuickBooksWebhookReceiver.parseTime(null));
        System.assertNotEquals(null, QuickBooksWebhookReceiver.parseTime('2026-09-17T14:05:25Z'));
    }

    /**
     * The endpoint runs as the hooks Site guest user. A field the receiver sets that the guest cannot write makes
     * EVERY delivery fail with a 500 - Intuit retries, then gives up, and webhooks stop silently. That happened on
     * 2026-09-24 after Discovered By was added, so this test fails the moment the two drift apart.
     */
    @IsTest(SeeAllData=true)
    static void guestUserCanWriteEveryFieldTheReceiverSets() {
        Set<String> needed = new Set<String>{
            'QuickBooks_Event__c.Discovered_By__c', 'QuickBooks_Event__c.Entity_Id__c', 'QuickBooks_Event__c.Entity_Key__c',
            'QuickBooks_Event__c.Entity_Name__c', 'QuickBooks_Event__c.Error_Message__c', 'QuickBooks_Event__c.Event_Id__c',
            'QuickBooks_Event__c.Event_Time__c', 'QuickBooks_Event__c.Event_Type__c', 'QuickBooks_Event__c.Operation__c',
            'QuickBooks_Event__c.Payload__c', 'QuickBooks_Event__c.Realm_Id__c', 'QuickBooks_Event__c.Received_At__c',
            'QuickBooks_Event__c.Status__c' };
        Set<String> writable = new Set<String>();
        for (FieldPermissions fp : [SELECT Field FROM FieldPermissions
                                    WHERE SobjectType = 'QuickBooks_Event__c' AND PermissionsEdit = true
                                      AND Parent.Profile.Name = 'hooks Profile']) {
            writable.add(fp.Field);
        }
        needed.removeAll(writable);
        System.assertEquals(new Set<String>(), needed,
            'the hooks guest profile cannot write these fields, so live webhooks would fail: ' + needed);
    }
}