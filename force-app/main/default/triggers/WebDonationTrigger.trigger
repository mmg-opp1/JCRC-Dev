/**
 * @description Queues asynchronous processing for a newly received website donation.
 *              Enqueues rather than processing inline so nothing here can slow or fail the
 *              HTTP request the website is still waiting on. JSI Website Donations / Jason Ott.
 */
trigger WebDonationTrigger on Web_Donation__c (after insert) {
    for (Web_Donation__c wd : Trigger.new) {
        if (wd.Status__c == 'Received') {
            System.enqueueJob(new WebDonationProcessor(wd.Id));
        }
    }
}
