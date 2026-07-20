/**
 * @description JSI-108 controller for the view-only `contactListSubscriptions` LWC. Returns a
 *   contact's Constant Contact list/topic subscriptions — their CampaignMembers on CC List
 *   record-type Campaigns (topic = Campaign = CC list). Read-only + cacheable; the LWC never
 *   edits, so there is no write method here by design (preferences change in CC and sync back).
 * @author Jason Ott
 * @created 2026-07-20
 *
 * Change Log:
 * -----------
 * 2026-07-20 - Jason Ott - JSI-108: read a contact's CC List campaign memberships for the LWC.
 */
public with sharing class ContactSubscriptionsController {

    /** One topic subscription for the LWC. */
    public class Subscription {
        @AuraEnabled public String topic { get; set; }      // Campaign (topic) name
        @AuraEnabled public String status { get; set; }     // CampaignMember status (e.g. Subscribed)
        @AuraEnabled public Id campaignId { get; set; }
    }

    /**
     * @description The contact's subscriptions across CC List campaigns, topic-sorted.
     * @param contactId the Contact whose subscriptions to load
     * @return list of Subscription (empty if none)
     */
    @AuraEnabled(cacheable=true)
    public static List<Subscription> getSubscriptions(Id contactId) {
        List<Subscription> results = new List<Subscription>();
        if (contactId == null) return results;
        for (CampaignMember cm : [
            SELECT Campaign.Name, Status, CampaignId
            FROM CampaignMember
            WHERE ContactId = :contactId
              AND Campaign.RecordType.DeveloperName = 'CC_List'
            WITH USER_MODE
            ORDER BY Campaign.Name
        ]) {
            Subscription s = new Subscription();
            s.topic = cm.Campaign.Name;
            s.status = cm.Status;
            s.campaignId = cm.CampaignId;
            results.add(s);
        }
        return results;
    }
}
