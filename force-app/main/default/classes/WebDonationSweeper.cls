/**
 * @description Turns website donations that have arrived into real gifts, on a schedule.
 *
 *              WHY THIS EXISTS RATHER THAN A TRIGGER. The obvious design - the staging record's
 *              trigger enqueues the work - cannot succeed here, and did not: async Apex runs as
 *              the user who enqueued it, and the only user who ever inserts one of these is the
 *              website's anonymous Site Guest User. That user cannot read back the record it
 *              just created (the object is Private and the platform reassigns guest-created
 *              records away from the guest), cannot read the configuration metadata, holds no
 *              field-level security on anything the mapping writes, and - the wall that ended
 *              the approach - cannot execute NPSP's own allocation flow when the Opportunity is
 *              inserted. Making all of that work would mean granting an internet-facing
 *              anonymous profile broad access across NPSP's object model.
 *
 *              So the guest user's job stops at storing the payload, which is all it was ever
 *              well suited to. This class does the interpreting, running as whoever scheduled
 *              it - a real, licensed, internal user - which is the context the processing was
 *              written against and is verified to work in.
 *
 *              ONE RECORD PER TRANSACTION (batch scope 1), deliberately. Each donation fires
 *              NPSP allocation and rollup logic of its own, so sharing a transaction between
 *              two donations invites limit failures; worse, one malformed payload would take
 *              down every gift batched alongside it. At scope 1 a bad submission fails alone
 *              and is marked Failed with its reason, and the next donation is unaffected.
 *
 *              ONLY EVER PICKS UP 'Received'. A donation the processor has already marked
 *              Failed is left alone rather than retried on a loop - it needs a human to look at
 *              the reason and replay it from the Web Donation record.
 *
 *              SCHEDULED AS TWELVE JOBS, one per five-minute offset - 'Web Donation Sweeper 00'
 *              through '... 55'. Not a stylistic choice: Apex cron rejects a comma list in the
 *              minutes field ("Seconds and minutes must be specified as integers"), so an
 *              every-five-minutes cadence has to be expressed as twelve hourly expressions:
 *
 *                for (Integer m = 0; m < 60; m += 5) {
 *                    System.schedule('Web Donation Sweeper ' + m, '0 ' + m + ' * * * ?',
 *                                    new WebDonationSweeper());
 *                }
 *
 *              They run as whoever schedules them, so schedule them as an administrator.
 *
 * @author Jason Ott
 * @created 2026-09-10
 *
 * Change Log:
 * -----------
 * 2026-09-10 - Jason Ott - Created. Replaces WebDonationTrigger's enqueue, which could never
 *                          have worked from the guest-user context it ran in.
 */
public without sharing class WebDonationSweeper implements Schedulable, Database.Batchable<SObject> {

    /** Entry point for the scheduled job. Hands straight off to the batch. */
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new WebDonationSweeper(), 1);
    }

    /**
     * Everything still waiting to be interpreted, oldest first so a backlog is worked through
     * in the order the donations were actually made.
     */
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Web_Donation__c
            WHERE Status__c = 'Received'
            ORDER BY Received_At__c ASC
        ]);
    }

    /**
     * Scope is 1, so this runs once per donation. process() handles its own failure - it rolls
     * back and marks the record Failed with the reason - so nothing here needs to catch, and
     * nothing it does can affect the next donation.
     */
    public void execute(Database.BatchableContext ctx, List<Web_Donation__c> scope) {
        for (Web_Donation__c wd : scope) {
            WebDonationProcessor.process(wd.Id);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Nothing to do. Each donation records its own outcome on its own record.
    }
}
