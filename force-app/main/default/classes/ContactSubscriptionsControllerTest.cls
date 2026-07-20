/**
 * @description Tests for ContactSubscriptionsController (JSI-108 view-only subscriptions LWC).
 * @author Jason Ott
 * @created 2026-07-20
 *
 * Change Log:
 * -----------
 * 2026-07-20 - Jason Ott - JSI-108: coverage for reading CC List campaign memberships.
 */
@isTest
private class ContactSubscriptionsControllerTest {

    @isTest
    static void returnsCCListSubscriptions() {
        Id rtId = Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName()
                    .get('CC_List').getRecordTypeId();
        Campaign camp = new Campaign(Name = 'Newsletter', IsActive = true,
                                     RecordTypeId = rtId, CC_List_Id__c = 'cc-list-1');
        insert camp;
        insert new CampaignMemberStatus(CampaignId = camp.Id, Label = 'Subscribed',
                                        SortOrder = 3, HasResponded = false);

        Contact c = new Contact(LastName = 'SubTest', Email = 'sub@example.org');
        insert c;
        insert new CampaignMember(CampaignId = camp.Id, ContactId = c.Id, Status = 'Subscribed');

        Test.startTest();
        List<ContactSubscriptionsController.Subscription> subs =
            ContactSubscriptionsController.getSubscriptions(c.Id);
        Test.stopTest();

        System.assertEquals(1, subs.size(), 'one CC List subscription');
        System.assertEquals('Newsletter', subs[0].topic, 'topic = campaign name');
        System.assertEquals('Subscribed', subs[0].status, 'status');
        System.assertEquals(camp.Id, subs[0].campaignId, 'campaign id');
    }

    @isTest
    static void emptyWhenNoSubscriptions() {
        Contact c = new Contact(LastName = 'NoSub');
        insert c;
        System.assertEquals(0, ContactSubscriptionsController.getSubscriptions(c.Id).size(),
            'no subscriptions → empty list');
        System.assertEquals(0, ContactSubscriptionsController.getSubscriptions(null).size(),
            'null contact → empty list');
    }
}
