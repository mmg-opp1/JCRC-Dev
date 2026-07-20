/**
 * @description Tests for the JSI-107 Constant Contact inbound poller (client + queueable +
 *   schedulable) using HttpCalloutMock — no live auth required. Covers: opt-out fetch with
 *   pagination and Salesforce-Id custom-field resolution, email-fallback matching, the hourly
 *   schedulable enqueuing the worker, the incremental cursor, and callout-failure logging.
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: coverage for opt-out poller against mocked CC responses.
 */
@isTest
private class ConstantContactPollerTest {

    // Returns a custom-fields list, a page-1 contact (matched by Salesforce Id) with a next link,
    // and a page-2 contact (matched by email only, no next).
    private class CCMock implements HttpCalloutMock {
        Id sfId; String email1; String email2;
        CCMock(Id sfId, String email1, String email2) { this.sfId = sfId; this.email1 = email1; this.email2 = email2; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String ep = req.getEndpoint();
            if (ep.contains('/contact_custom_fields')) {
                res.setBody('{"custom_fields":[{"custom_field_id":"cf-sfid","label":"Salesforce ID","name":"salesforce_id"}]}');
            } else if (ep.contains('cursor=')) {
                res.setBody('{"contacts":[{"contact_id":"cc-2","email_address":{"address":"' + email2 +
                    '","opt_out_date":"2026-07-20T10:00:00Z","permission_to_send":"unsubscribed"}}],"_links":{}}');
            } else if (ep.contains('/contacts')) {
                res.setBody('{"contacts":[{"contact_id":"cc-1","email_address":{"address":"' + email1 +
                    '","opt_out_date":"2026-07-20T09:00:00Z","permission_to_send":"unsubscribed"},' +
                    '"custom_fields":[{"custom_field_id":"cf-sfid","value":"' + sfId + '"}]}],' +
                    '"_links":{"next":{"href":"/v3/contacts?cursor=ABC123&limit=500"}}}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error_key":"unauthorized","error_message":"token invalid"}');
            return res;
        }
    }

    @isTest
    static void optOutSyncEndToEnd() {
        Contact c1 = new Contact(LastName = 'CCPoll1', Email = 'poll1@example.org');
        Contact c2 = new Contact(LastName = 'CCPoll2', Email = 'poll2@example.org');
        insert new List<Contact>{ c1, c2 };

        Test.setMock(HttpCalloutMock.class, new CCMock(c1.Id, c1.Email, c2.Email));
        Test.startTest();
        ConstantContactSyncService.SyncResult res = new ConstantContactSyncQueueable().runOptOutSync();
        Test.stopTest();

        System.assertEquals(2, res.processed, 'two unsubscribes fetched across two pages');
        System.assertEquals(2, res.updated, 'both applied: ' + res.errors);

        Contact a = [SELECT HasOptedOutOfEmail, CC_Contact_Id__c, CC_Subscription_Status__c FROM Contact WHERE Id = :c1.Id];
        System.assertEquals(true, a.HasOptedOutOfEmail, 'matched by Salesforce Id, opted out');
        System.assertEquals('cc-1', a.CC_Contact_Id__c, 'CC id backfilled');
        System.assertEquals('Unsubscribed', a.CC_Subscription_Status__c, 'status');

        Contact b = [SELECT HasOptedOutOfEmail FROM Contact WHERE Id = :c2.Id];
        System.assertEquals(true, b.HasOptedOutOfEmail, 'matched by email fallback, opted out');

        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
                                WHERE Operation__c = 'Opt-Out Sync' AND Run_Status__c = 'Success']);
    }

    @isTest
    static void schedulableEnqueuesWorker() {
        Contact c1 = new Contact(LastName = 'CCSched', Email = 'sched1@example.org');
        Contact c2 = new Contact(LastName = 'CCSched2', Email = 'sched2@example.org');
        insert new List<Contact>{ c1, c2 };

        Test.setMock(HttpCalloutMock.class, new CCMock(c1.Id, c1.Email, c2.Email));
        Test.startTest();
        new ConstantContactSyncSchedulable().execute(null); // enqueues; runs at stopTest
        Test.stopTest();

        System.assertEquals(true,
            [SELECT HasOptedOutOfEmail FROM Contact WHERE Id = :c1.Id].HasOptedOutOfEmail,
            'schedulable-enqueued worker applied the opt-out');
        System.assert([SELECT COUNT() FROM Integration_Log__c WHERE Operation__c = 'Opt-Out Sync'] >= 1);
    }

    @isTest
    static void calloutFailureIsLogged() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Test.startTest();
        ConstantContactSyncService.SyncResult res = new ConstantContactSyncQueueable().runOptOutSync();
        Test.stopTest();

        System.assertEquals(null, res, 'failed run returns null');
        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
                                WHERE Operation__c = 'Opt-Out Sync' AND Run_Status__c = 'Failed'],
                            'failure logged for the admin');
    }

    @isTest
    static void cursorFallsBackAndAdvances() {
        ConstantContactSyncQueueable q = new ConstantContactSyncQueueable();
        // No prior run -> lookback default (well in the past, < now).
        System.assert(q.getOptOutCursor() < System.now(), 'default cursor is in the past');

        Integration_Log__c log = new Integration_Log__c(
            Integration__c = 'Constant Contact', Operation__c = 'Opt-Out Sync',
            Run_Status__c = 'Success', Run_Start__c = Datetime.newInstance(2026, 7, 19, 8, 0, 0),
            Run_End__c = System.now(), Records_Processed__c = 0, Records_Updated__c = 0, Records_Failed__c = 0);
        insert log;
        System.assertEquals(Datetime.newInstance(2026, 7, 19, 8, 0, 0), q.getOptOutCursor(),
            'cursor advances to last successful run start');
    }

    // JSI-108 preference sync: one contact subscribed to one CC list; a stale membership on
    // another CC list campaign is reconciled to Unsubscribed.
    private class PrefMock implements HttpCalloutMock {
        Id sfId; String email; String listId;
        PrefMock(Id sfId, String email, String listId) { this.sfId = sfId; this.email = email; this.listId = listId; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String ep = req.getEndpoint();
            if (ep.contains('/contact_custom_fields')) {
                res.setBody('{"custom_fields":[{"custom_field_id":"cf-sfid","label":"Salesforce ID","name":"salesforce_id"}]}');
            } else if (ep.contains('/contacts')) {
                res.setBody('{"contacts":[{"contact_id":"cc-9","email_address":{"address":"' + email +
                    '"},"list_memberships":["' + listId + '"],' +
                    '"custom_fields":[{"custom_field_id":"cf-sfid","value":"' + sfId + '"}]}],"_links":{}}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    private static Campaign makeCCListCampaign(String name, String listId) {
        Id rtId = Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName().get('CC_List').getRecordTypeId();
        Campaign camp = new Campaign(Name = name, IsActive = true, RecordTypeId = rtId, CC_List_Id__c = listId);
        insert camp;
        insert new List<CampaignMemberStatus>{
            new CampaignMemberStatus(CampaignId = camp.Id, Label = 'Subscribed', SortOrder = 3, HasResponded = false),
            new CampaignMemberStatus(CampaignId = camp.Id, Label = 'Unsubscribed', SortOrder = 4, HasResponded = false)
        };
        return camp;
    }

    @isTest
    static void preferenceSyncReconcilesMemberships() {
        Campaign subCamp = makeCCListCampaign('Advocacy', 'ccl-100');   // contact WILL be subscribed
        Campaign staleCamp = makeCCListCampaign('Events', 'ccl-200');   // contact has a stale membership here
        Contact c = new Contact(LastName = 'PrefTest', Email = 'pref@example.org');
        insert c;
        insert new CampaignMember(CampaignId = staleCamp.Id, ContactId = c.Id, Status = 'Subscribed');

        Test.setMock(HttpCalloutMock.class, new PrefMock(c.Id, c.Email, 'ccl-100'));
        Test.startTest();
        ConstantContactSyncService.SyncResult res = new ConstantContactSyncQueueable('PREFERENCE').runPreferenceSync();
        Test.stopTest();

        System.assertEquals(1, res.processed, 'one contact processed');
        System.assert(res.updated >= 2, 'new sub + stale unsub: ' + res.errors);

        CampaignMember subbed = [SELECT Status FROM CampaignMember WHERE ContactId = :c.Id AND CampaignId = :subCamp.Id];
        System.assertEquals('Subscribed', subbed.Status, 'subscribed to advocacy');
        CampaignMember stale = [SELECT Status FROM CampaignMember WHERE ContactId = :c.Id AND CampaignId = :staleCamp.Id];
        System.assertEquals('Unsubscribed', stale.Status, 'stale events membership reconciled to unsubscribed');

        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
                                WHERE Operation__c = 'Preference Sync' AND Run_Status__c = 'Success']);
    }

    @isTest
    static void preferenceSyncRunsViaQueueableExecute() {
        Campaign camp = makeCCListCampaign('Newsletter', 'ccl-300');
        Contact c = new Contact(LastName = 'PrefExec', Email = 'prefexec@example.org');
        insert c;

        Test.setMock(HttpCalloutMock.class, new PrefMock(c.Id, c.Email, 'ccl-300'));
        Test.startTest();
        System.enqueueJob(new ConstantContactSyncQueueable('PREFERENCE')); // covers execute() dispatch
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE ContactId = :c.Id AND CampaignId = :camp.Id]);
    }
}
