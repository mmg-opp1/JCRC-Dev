/**
 * @description Scheduled starter for QuickBooks event processing (JSI-121 Phase 5b).
 *
 *              Starts QuickBooksEventProcessor over any QuickBooks events waiting to be processed. Scheduled as
 *              twelve jobs, one per five-minute offset ('QuickBooks Sweeper 00' .. '55'), because Apex cron
 *              rejects a comma list in the minutes field (see WebDonationSweeper). They run as whoever schedules
 *              them, so schedule them as an administrator with access to the QuickBooks Named Credential.
 *
 *              DELIBERATELY TINY, AND IT NAMES THE PROCESSOR ONLY AS A STRING. Salesforce refuses to deploy a
 *              class that a scheduled job depends on while the job is queued (the WebDonationSweeper lesson).
 *              Looking the processor up with Type.forName keeps it out of that dependency, so the processor
 *              can be changed and redeployed without unscheduling anything; this class should rarely change.
 *
 *              Does nothing while a previous run is still going, so runs never overlap.
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5b).
 */
public without sharing class QuickBooksSweeper implements Schedulable {

    @TestVisible private static final String PROCESSOR = 'QuickBooksEventProcessor';

    public void execute(SchedulableContext ctx) {
        run();
    }

    /** Starts the processor if there is work and it isn't already running. Returns the batch job id, or null. */
    public static Id run() {
        Integer running = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE JobType = 'BatchApex' AND ApexClass.Name = :PROCESSOR
              AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        if (running > 0) {
            return null;
        }
        Integer waiting = [SELECT COUNT() FROM QuickBooks_Event__c WHERE Status__c = 'Received'];
        if (waiting == 0) {
            return null;
        }
        Database.Batchable<SObject> processor = (Database.Batchable<SObject>) Type.forName(PROCESSOR).newInstance();
        // Scope 1: each event's callouts and writes stand alone.
        return Database.executeBatch(processor, 1);
    }
}