/**
 * @description Tests for QuickBooksCatchUp and QuickBooksEventPurge (JSI-121 Phase 5c).
 *
 *              The mock serves QuickBooks change tracking in the shape the sandbox returned on 2026-09-23:
 *              {"CDCResponse":[{"QueryResponse":[{}, {"Deposit":[...]}, {"Payment":[...]}]}]} - one entry per
 *              entity, empty when that entity has no changes.
 * @author Jason Ott
 * @created 2026-09-23
 *
 * Change Log:
 * -----------
 * 2026-09-23 - Jason Ott - Initial version (JSI-121 Phase 5c).
 */
@IsTest
private class QuickBooksCatchUpTest {

    private static final String REALM = '9341457933630133';

    private class MockCdc implements HttpCalloutMock {
        List<Object> perEntity = new List<Object>();
        Integer status = 200;
        String lastEndpoint;

        MockCdc add(String entity, List<Object> records) {
            perEntity.add(new Map<String, Object>{ entity => records });
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            lastEndpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(status);
            if (status != 200) {
                res.setBody('{"Fault":{"Error":[{"Message":"Service unavailable"}]}}');
                return res;
            }
            List<Object> responses = new List<Object>{ new Map<String, Object>() }; // an entity with no changes
            responses.addAll(perEntity);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'CDCResponse' => new List<Object>{ new Map<String, Object>{ 'QueryResponse' => responses } } }));
            return res;
        }
    }

    private static Map<String, Object> record(String id, String created, String updated, String status) {
        Map<String, Object> r = new Map<String, Object>{
            'Id' => id, 'TxnDate' => '2026-09-17', 'TotalAmt' => 180.00,
            'MetaData' => new Map<String, Object>{ 'CreateTime' => created, 'LastUpdatedTime' => updated } };
        if (status != null) {
            r.put('status', status);
        }
        return r;
    }

    @TestSetup
    static void setup() {
        insert new QuickBooks_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Enabled__c = true,
            Verifier_Token__c = 'x', Realm_Id__c = REALM);
    }

    private static QuickBooks_Settings__c settings() {
        return QuickBooks_Settings__c.getOrgDefaults();
    }

    private static QuickBooks_Event__c seenEvent(String entityKey, Datetime moment) {
        QuickBooks_Event__c e = new QuickBooks_Event__c(Event_Id__c = 'seen-' + entityKey + '-' + moment.getTime(),
            Entity_Name__c = entityKey.substringBefore('-'), Entity_Id__c = entityKey.substringAfter('-'),
            Entity_Key__c = entityKey, Operation__c = 'created', Realm_Id__c = REALM, Event_Time__c = moment,
            Received_At__c = moment, Status__c = 'Processed', Discovered_By__c = 'Webhook');
        insert e;
        return e;
    }

    // ---- catch-up ---------------------------------------------------------------------------------

    @IsTest
    static void createsEventsForChangesNoWebhookBroughtIn() {
        MockCdc mock = new MockCdc()
            .add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-17T07:43:17-07:00', null) })
            .add('Payment', new List<Object>{ record('146', '2026-09-17T07:53:42-07:00', '2026-09-18T09:00:00-07:00', null) });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Integer created = QuickBooksCatchUp.run();
        Test.stopTest();

        System.assertEquals(2, created);
        Map<String, QuickBooks_Event__c> byKey = new Map<String, QuickBooks_Event__c>();
        for (QuickBooks_Event__c e : [SELECT Entity_Key__c, Event_Type__c, Operation__c, Status__c, Discovered_By__c,
                                             Event_Time__c, Payload__c, Realm_Id__c FROM QuickBooks_Event__c]) {
            byKey.put(e.Entity_Key__c, e);
        }
        QuickBooks_Event__c deposit = byKey.get('deposit-145');
        System.assertEquals('qbo.deposit.created.v1', deposit.Event_Type__c, 'created and updated times match');
        System.assertEquals('Received', deposit.Status__c, 'the normal processor picks it up');
        System.assertEquals('Catch-up', deposit.Discovered_By__c);
        System.assertEquals(REALM, deposit.Realm_Id__c);
        System.assert(deposit.Payload__c.contains('"Id":"145"'), 'change tracking returns the whole record');
        System.assertEquals('qbo.payment.updated.v1', byKey.get('payment-146').Event_Type__c, 'edited after creation');
        System.assertNotEquals(null, settings().Last_Catch_Up__c, 'window moves on after a good run');
        System.assert(mock.lastEndpoint.contains('entities=Deposit%2CPayment%2CSalesReceipt'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('Z'), 'timestamp must end Z - QuickBooks rejects -0000');
    }

    @IsTest
    static void recordsAlreadySeenAreLeftAlone() {
        seenEvent('deposit-145', Datetime.newInstanceGmt(2026, 9, 17, 15, 0, 0));
        Test.setMock(HttpCalloutMock.class, new MockCdc()
            .add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-17T07:43:17-07:00', null) }));
        Test.startTest();
        Integer created = QuickBooksCatchUp.run();
        Test.stopTest();
        System.assertEquals(0, created, 'the webhook already covered this version');
        System.assertEquals(1, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void aRecordEditedSinceTheLastEventIsPickedUp() {
        seenEvent('deposit-145', Datetime.newInstanceGmt(2026, 9, 17, 14, 43, 17));
        Test.setMock(HttpCalloutMock.class, new MockCdc()
            .add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-20T11:00:00-07:00', null) }));
        Test.startTest();
        Integer created = QuickBooksCatchUp.run();
        Test.stopTest();
        System.assertEquals(1, created);
        QuickBooks_Event__c e = [SELECT Operation__c, Discovered_By__c FROM QuickBooks_Event__c
                                 WHERE Discovered_By__c = 'Catch-up'];
        System.assertEquals('updated', e.Operation__c);
    }

    @IsTest
    static void deletedRecordsBecomeDeleteEvents() {
        Test.setMock(HttpCalloutMock.class, new MockCdc()
            .add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-21T08:00:00-07:00', 'Deleted') }));
        Test.startTest();
        QuickBooksCatchUp.run();
        Test.stopTest();
        QuickBooks_Event__c e = [SELECT Operation__c, Event_Type__c FROM QuickBooks_Event__c];
        System.assertEquals('deleted', e.Operation__c);
        System.assertEquals('qbo.deposit.deleted.v1', e.Event_Type__c);
    }

    @IsTest
    static void aFailedRunChangesNothingSoTomorrowCoversIt() {
        MockCdc mock = new MockCdc().add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-17T07:43:17-07:00', null) });
        mock.status = 500;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Integer created = QuickBooksCatchUp.run();
        Test.stopTest();
        System.assertEquals(0, created);
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
        System.assertEquals(null, settings().Last_Catch_Up__c, 'the window is not advanced past an outage');
    }

    @IsTest
    static void switchedOffDoesNothing() {
        QuickBooks_Settings__c cfg = settings();
        cfg.Enabled__c = false;
        update cfg;
        Test.setMock(HttpCalloutMock.class, new MockCdc());
        System.assertEquals(0, QuickBooksCatchUp.run());
        System.assertEquals(0, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void theWindowOverlapsAndNeverExceedsThirtyDays() {
        Datetime now = Datetime.newInstanceGmt(2026, 9, 23, 3, 0, 0);
        QuickBooks_Settings__c cfg = settings();

        // First ever run: the lookback setting.
        cfg.Catch_Up_Lookback_Days__c = 3;
        System.assertEquals(now.addDays(-3), QuickBooksCatchUp.windowStart(cfg, now));

        // Normal run: an hour of overlap before the last run.
        cfg.Last_Catch_Up__c = now.addHours(-24);
        System.assertEquals(now.addHours(-25), QuickBooksCatchUp.windowStart(cfg, now));

        // After a long outage: clamped to what QuickBooks keeps.
        cfg.Last_Catch_Up__c = now.addDays(-90);
        System.assertEquals(now.addDays(-30), QuickBooksCatchUp.windowStart(cfg, now));

        // A silly lookback is clamped too.
        cfg.Last_Catch_Up__c = null;
        cfg.Catch_Up_Lookback_Days__c = 400;
        System.assertEquals(now.addDays(-30), QuickBooksCatchUp.windowStart(cfg, now));
        System.assertEquals(null, QuickBooksCatchUp.parseTimestamp('nonsense'));
    }

    @IsTest
    static void theSchedulableEntryPointRuns() {
        Test.setMock(HttpCalloutMock.class, new MockCdc()
            .add('Deposit', new List<Object>{ record('145', '2026-09-17T07:43:17-07:00', '2026-09-17T07:43:17-07:00', null) }));
        Test.startTest();
        new QuickBooksCatchUp().execute(null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM QuickBooks_Event__c]);
    }

    @IsTest
    static void bothNightlyJobsCanBeScheduled() {
        Test.startTest();
        String catchUpId = System.schedule('QuickBooks Catch-Up TEST', '0 0 3 * * ?', new QuickBooksCatchUp());
        String purgeId = System.schedule('QuickBooks Event Purge TEST', '0 30 3 * * ?', new QuickBooksEventPurge());
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM CronTrigger WHERE Id IN (:catchUpId, :purgeId)]);
    }

    // ---- purge ------------------------------------------------------------------------------------

    private static QuickBooks_Event__c aged(String suffix, String status, Integer daysOld) {
        return new QuickBooks_Event__c(Event_Id__c = 'age-' + suffix, Entity_Key__c = 'deposit-' + suffix,
            Entity_Name__c = 'deposit', Entity_Id__c = suffix, Realm_Id__c = REALM, Status__c = status,
            Received_At__c = System.now().addDays(-daysOld), Discovered_By__c = 'Webhook',
            Imported_External_Ids__c = status == 'Processed' ? 'qbo-deposit-' + suffix + '-l1' : null);
    }

    @IsTest
    static void purgeKeepsRecentAndUnprocessedEventsAndDeletesOldOnes() {
        insert new List<QuickBooks_Event__c>{
            aged('old-processed', 'Processed', 200),
            aged('old-failed', 'Failed', 200),
            aged('old-ignored', 'Ignored', 45),
            aged('recent-processed', 'Processed', 30),
            aged('recent-ignored', 'Ignored', 10),
            aged('ancient-received', 'Received', 400)
        };

        Test.startTest();
        Database.executeBatch(new QuickBooksEventPurge(), 200);
        Test.stopTest();

        Set<String> left = new Set<String>();
        for (QuickBooks_Event__c e : [SELECT Event_Id__c FROM QuickBooks_Event__c]) {
            left.add(e.Event_Id__c);
        }
        System.assertEquals(new Set<String>{ 'age-recent-processed', 'age-recent-ignored', 'age-ancient-received' }, left,
            'old processed/failed/ignored go; recent stay; anything still waiting stays whatever its age');
    }

    @IsTest
    static void retentionHasAFloorSoTheImportMemoryIsNeverLost() {
        QuickBooks_Settings__c cfg = settings();
        cfg.Event_Retention_Days__c = 5; // shorter than QuickBooks' own 30 days of change history
        cfg.Ignored_Event_Retention_Days__c = 0;
        update cfg;
        System.assertEquals(31, QuickBooksEventPurge.retentionDays(cfg), 'floor applies');
        System.assertEquals(1, QuickBooksEventPurge.ignoredRetentionDays(cfg));

        insert aged('within-floor', 'Processed', 20);
        Test.startTest();
        new QuickBooksEventPurge().execute(null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM QuickBooks_Event__c], 'kept - inside the floor');
    }

    @IsTest
    static void purgeDefaultsApplyWithoutSettings() {
        System.assertEquals(180, QuickBooksEventPurge.retentionDays(null));
        System.assertEquals(30, QuickBooksEventPurge.ignoredRetentionDays(null));
    }
}