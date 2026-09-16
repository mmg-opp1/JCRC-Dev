/**
 * @description Backs the Replay quick action on a Web Donation.
 *
 *              Replay is the payoff for storing the raw payload: when a submission fails - a
 *              missing mapping, a bad value, a since-fixed bug - the gift is not lost, and
 *              once the cause is fixed the same payload can be run again. Without a button
 *              that means anonymous Apex, which is not something to hand to staff.
 *
 *              Refuses to replay a submission that already produced a gift, so a stray click
 *              cannot create a second Opportunity for the same donation.
 *
 * @author Jason Ott
 * @created 2026-08-20
 *
 * Change Log:
 * -----------
 * 2026-08-20 - Jason Ott - Created (Website Donations - replay).
 */
public with sharing class WebDonationReplayController {

    @AuraEnabled
    public static String replay(Id recordId) {
        Web_Donation__c wd = [
            SELECT Id, Status__c, Opportunity__c, GF_Entry_Id__c
            FROM Web_Donation__c WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ];

        if (wd.Opportunity__c != null) {
            throw new AuraHandledException(
                'This submission already created a gift. Delete that gift first if you really '
                + 'need to reprocess, otherwise replaying would create a duplicate.');
        }

        // Processing is deliberately synchronous here. The caller is a person watching a
        // spinner, not a webhook waiting on a response, so they should see the outcome
        // immediately rather than have to refresh and guess whether it worked.
        WebDonationProcessor.process(wd.Id);

        Web_Donation__c after = [
            SELECT Status__c, Error_Message__c, Opportunity__c, Unmapped_Designations__c
            FROM Web_Donation__c WHERE Id = :recordId LIMIT 1
        ];

        if (after.Status__c == 'Processed') {
            String msg = 'Processed successfully.';
            if (String.isNotBlank(after.Unmapped_Designations__c)) {
                msg += ' Note: some designations still have no mapping, so no allocation was '
                     + 'created for them.';
            }
            return msg;
        }
        throw new AuraHandledException(
            'Still failing: ' + String.valueOf(after.Error_Message__c).abbreviate(200));
    }
}