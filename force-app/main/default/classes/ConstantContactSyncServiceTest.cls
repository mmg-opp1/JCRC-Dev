/**
 * @description Tests for ConstantContactSyncService — the JSI-107 reverse-sync applier.
 *   Exercises Salesforce-Id and email matching, field application, the no-match and
 *   empty-input paths, and Integration_Log__c logging. No HTTP: the applier is
 *   CC-API-agnostic, so tests build ContactUpdate DTOs directly.
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: initial coverage for the applier.
 */
@isTest
private class ConstantContactSyncServiceTest {

    @isTest
    static void appliesUpdatesByIdAndEmail() {
        List<Contact> cons = new List<Contact>{
            new Contact(LastName = 'ReverseSyncA', Email = 'a@example.org'),
            new Contact(LastName = 'ReverseSyncB', Email = 'b@example.org')
        };
        insert cons;

        List<ConstantContactSyncService.ContactUpdate> ups =
            new List<ConstantContactSyncService.ContactUpdate>();

        // Match by pushed Salesforce Id; opt-out + hard bounce + engagement.
        ConstantContactSyncService.ContactUpdate u1 = new ConstantContactSyncService.ContactUpdate();
        u1.salesforceId = cons[0].Id;
        u1.ccContactId  = 'cc-uuid-1';
        u1.optedOut     = true;
        u1.optOutDate   = Date.today();
        u1.hardBounce   = true;
        u1.bounceDate   = Date.today();
        u1.lastOpen     = Date.today().addDays(-2);
        u1.opens90      = 5;
        ups.add(u1);

        // Match by email (mixed case → case-insensitive); re-subscribe + click.
        ConstantContactSyncService.ContactUpdate u2 = new ConstantContactSyncService.ContactUpdate();
        u2.email    = 'B@example.org';
        u2.optedOut = false;
        u2.lastClick = Date.today();
        ups.add(u2);

        Test.startTest();
        ConstantContactSyncService.SyncResult res =
            new ConstantContactSyncService().apply(ups, 'Full Sync');
        Test.stopTest();

        System.assertEquals(2, res.processed, 'both processed');
        System.assertEquals(2, res.updated, 'both updated: ' + res.errors);
        System.assertEquals(0, res.failed, 'none failed');

        Contact a = [SELECT HasOptedOutOfEmail, CC_Contact_Id__c, CC_Subscription_Status__c,
                            Email_Hard_Bounce__c, Email_Last_Bounce_Date__c,
                            Email_Last_Open__c, Email_Opens_Last_90_Days__c
                     FROM Contact WHERE Id = :cons[0].Id];
        System.assertEquals(true, a.HasOptedOutOfEmail, 'opt-out set');
        System.assertEquals('Unsubscribed', a.CC_Subscription_Status__c, 'status');
        System.assertEquals('cc-uuid-1', a.CC_Contact_Id__c, 'CC id backfilled');
        System.assertEquals(true, a.Email_Hard_Bounce__c, 'hard bounce');
        System.assertEquals(Date.today(), a.Email_Last_Bounce_Date__c, 'bounce date');
        System.assertEquals(5, a.Email_Opens_Last_90_Days__c, 'opens count');

        Contact b = [SELECT HasOptedOutOfEmail, CC_Subscription_Status__c, Email_Last_Click__c
                     FROM Contact WHERE Id = :cons[1].Id];
        System.assertEquals(false, b.HasOptedOutOfEmail, 're-subscribed');
        System.assertEquals('Subscribed', b.CC_Subscription_Status__c, 'status');
        System.assertEquals(Date.today(), b.Email_Last_Click__c, 'click date');

        System.assertEquals(1, [SELECT COUNT() FROM Integration_Log__c
                                WHERE Operation__c = 'Full Sync' AND Run_Status__c = 'Success'],
                            'one success log');
    }

    @isTest
    static void handlesNoMatchAndEmpty() {
        ConstantContactSyncService svc = new ConstantContactSyncService();

        // Empty input still logs a Success run.
        ConstantContactSyncService.SyncResult empty =
            svc.apply(new List<ConstantContactSyncService.ContactUpdate>(), 'Opt-Out Sync');
        System.assertEquals(0, empty.processed, 'nothing processed');

        // Unmatched email → counted as failed, error captured, run logged.
        ConstantContactSyncService.ContactUpdate u = new ConstantContactSyncService.ContactUpdate();
        u.email = 'nobody@example.org';
        u.optedOut = true;
        ConstantContactSyncService.SyncResult res =
            svc.apply(new List<ConstantContactSyncService.ContactUpdate>{ u }, 'Opt-Out Sync');

        System.assertEquals(1, res.processed, 'one processed');
        System.assertEquals(0, res.updated, 'none updated');
        System.assertEquals(1, res.failed, 'one failed');
        System.assert(res.errors.size() > 0, 'error captured');

        System.assertEquals(2, [SELECT COUNT() FROM Integration_Log__c
                                WHERE Operation__c = 'Opt-Out Sync'], 'two logs written');
    }
}
