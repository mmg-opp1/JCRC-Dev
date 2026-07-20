/**
 * @description JSI-109 tests for the Constant Contact engagement sync: the applier
 *   (ConstantContactSyncService.applyEmailActivity) directly, and the full poller path
 *   (ConstantContactClient.getEmailCampaigns via ConstantContactSyncQueueable) with an
 *   HttpCalloutMock. Covers CC_Email__c / CC_Email_Activity__c upsert, CC_List resolution,
 *   Contact 90-day counter refresh, idempotent re-runs, unmatched recipients, and callout failure.
 * @author Jason Ott
 * @created 2026-07-20
 *
 * Change Log:
 * -----------
 * 2026-07-20 - Jason Ott - JSI-109: engagement sync tests.
 */
@isTest
private class ConstantContactEngagementTest {

    private static Contact makeContact(String ccId, String email) {
        Contact c = new Contact(LastName = 'Test ' + ccId, Email = email, CC_Contact_Id__c = ccId);
        insert c;
        return c;
    }

    private static Id ccListRecordTypeId() {
        return [SELECT Id FROM RecordType
                WHERE SObjectType = 'Campaign' AND DeveloperName = 'CC_List' LIMIT 1].Id;
    }

    /** Applier: one campaign, one matched recipient → email + activity + Contact counters. */
    @isTest
    static void testApplyEmailActivity_direct() {
        Contact c = makeContact('cc-1', 'donor1@example.org');
        Campaign lst = new Campaign(Name = 'Newsletter List', RecordTypeId = ccListRecordTypeId(),
            CC_List_Id__c = 'list-abc', IsActive = true);
        insert lst;

        ConstantContactSyncService.EmailCampaignDTO em = new ConstantContactSyncService.EmailCampaignDTO();
        em.ccCampaignActivityId = 'ca-1';
        em.name = 'July Newsletter';
        em.subject = 'This week at JCRC';
        em.sentDate = System.now();
        em.ccListIds.add('list-abc');
        ConstantContactSyncService.ContactActivityDTO a = new ConstantContactSyncService.ContactActivityDTO();
        a.ccContactId = 'cc-1';
        a.email = 'donor1@example.org';
        a.opened = true; a.clicked = true; a.openCount = 3; a.clickCount = 1;
        a.firstOpen = System.now().addHours(-2);
        a.lastOpen = System.now().addHours(-1);
        a.lastClick = System.now();
        em.activities.add(a);

        Test.startTest();
        ConstantContactSyncService.SyncResult res = new ConstantContactSyncService()
            .applyEmailActivity(new List<ConstantContactSyncService.EmailCampaignDTO>{ em });
        Test.stopTest();

        System.assertEquals(1, res.updated, 'one activity applied');
        System.assertEquals(0, res.failed, String.valueOf(res.errors));

        CC_Email__c e = [SELECT CC_List__c FROM CC_Email__c WHERE CC_Campaign_Activity_Id__c = 'ca-1'];
        System.assertEquals(lst.Id, e.CC_List__c, 'CC_List resolved from the sent-to list id');

        CC_Email_Activity__c act = [SELECT Status__c, Open_Count__c, Contact__c
            FROM CC_Email_Activity__c WHERE Activity_Key__c = 'ca-1|cc-1'];
        System.assertEquals('Clicked', act.Status__c, 'clicked outranks opened');
        System.assertEquals(3, act.Open_Count__c);
        System.assertEquals(c.Id, act.Contact__c);

        Contact refreshed = [SELECT Email_Opens_Last_90_Days__c, Email_Clicks_Last_90_Days__c, Email_Last_Open__c
            FROM Contact WHERE Id = :c.Id];
        System.assertEquals(3, refreshed.Email_Opens_Last_90_Days__c, '90-day opens');
        System.assertEquals(1, refreshed.Email_Clicks_Last_90_Days__c, '90-day clicks');
        System.assertNotEquals(null, refreshed.Email_Last_Open__c, 'last open stamped');

        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
            WHERE Operation__c = 'Engagement Sync' AND Run_Status__c = 'Success']);
    }

    /** Re-run is idempotent (no dup rows); an unmatched recipient is counted as failed, not created. */
    @isTest
    static void testApplyEmailActivity_idempotentAndNoMatch() {
        makeContact('cc-2', 'donor2@example.org');
        ConstantContactSyncService.EmailCampaignDTO em = new ConstantContactSyncService.EmailCampaignDTO();
        em.ccCampaignActivityId = 'ca-2';
        em.subject = 'Appeal';
        em.sentDate = System.now();
        ConstantContactSyncService.ContactActivityDTO hit = new ConstantContactSyncService.ContactActivityDTO();
        hit.ccContactId = 'cc-2'; hit.opened = true; hit.openCount = 1;
        em.activities.add(hit);
        ConstantContactSyncService.ContactActivityDTO miss = new ConstantContactSyncService.ContactActivityDTO();
        miss.ccContactId = 'cc-nope'; miss.email = 'ghost@example.org'; miss.bounced = true;
        em.activities.add(miss);

        Test.startTest();
        ConstantContactSyncService svc = new ConstantContactSyncService();
        svc.applyEmailActivity(new List<ConstantContactSyncService.EmailCampaignDTO>{ em });
        ConstantContactSyncService.SyncResult res2 =
            svc.applyEmailActivity(new List<ConstantContactSyncService.EmailCampaignDTO>{ em });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM CC_Email__c WHERE CC_Campaign_Activity_Id__c = 'ca-2'],
            'no duplicate email on re-run');
        System.assertEquals(1, [SELECT COUNT() FROM CC_Email_Activity__c
            WHERE CC_Email__r.CC_Campaign_Activity_Id__c = 'ca-2'], 'no dup activity; unmatched skipped');
        System.assertEquals(1, res2.failed, 'unmatched recipient counted as failed');
    }

    /** Full poller path through the client parsing with a mocked CC API. */
    @isTest
    static void testEngagementPoller_mock() {
        Contact c = makeContact('cc-9', 'm@example.org');
        Campaign lst = new Campaign(Name = 'XYZ List', RecordTypeId = ccListRecordTypeId(),
            CC_List_Id__c = 'list-xyz', IsActive = true);
        insert lst;

        Test.setMock(HttpCalloutMock.class, new CCMock());
        Test.startTest();
        ConstantContactSyncService.SyncResult res =
            new ConstantContactSyncQueueable('ENGAGEMENT').runEngagementSync();
        Test.stopTest();

        System.assertNotEquals(null, res, 'poller ran');
        CC_Email__c e = [SELECT Subject__c, CC_List__c FROM CC_Email__c WHERE CC_Campaign_Activity_Id__c = 'ca-9'];
        System.assertEquals('Mock Subject', e.Subject__c, 'subject parsed from activity detail');
        System.assertEquals(lst.Id, e.CC_List__c, 'CC_List resolved from contact_list_ids');

        CC_Email_Activity__c act = [SELECT Status__c, Opened__c, Clicked__c
            FROM CC_Email_Activity__c WHERE Activity_Key__c = 'ca-9|cc-9'];
        System.assertEquals(true, act.Opened__c, 'open tracked');
        System.assertEquals(true, act.Clicked__c, 'click tracked');
        System.assertEquals('Clicked', act.Status__c);
    }

    /** A callout failure logs a Failed run and returns null (admin visibility). */
    @isTest
    static void testEngagementPoller_failureLogged() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Test.startTest();
        ConstantContactSyncService.SyncResult res =
            new ConstantContactSyncQueueable('ENGAGEMENT').runEngagementSync();
        Test.stopTest();

        System.assertEquals(null, res, 'callout failure returns null');
        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
            WHERE Operation__c = 'Engagement Sync' AND Run_Status__c = 'Failed']);
    }

    /** Mocks the CC v3 email + tracking endpoints. */
    private class CCMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String iso = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            if (url.contains('/emails/activities/')) {
                res.setBody('{"campaign_activity_id":"ca-9","subject":"Mock Subject","contact_list_ids":["list-xyz"]}');
            } else if (url.contains('/emails')) {
                res.setBody('{"campaigns":[{"campaign_id":"cid-9","name":"Mock Email","last_sent_date":"'
                    + iso + '","campaign_activities":[{"campaign_activity_id":"ca-9","role":"primary_email"}]}]}');
            } else if (url.contains('/tracking/')) {
                // sends / opens / clicks / bounces — same recipient row for simplicity
                res.setBody('{"tracking_activities":[{"contact_id":"cc-9","email_address":"m@example.org","created_time":"'
                    + iso + '"}]}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"boom"}');
            return res;
        }
    }
}
