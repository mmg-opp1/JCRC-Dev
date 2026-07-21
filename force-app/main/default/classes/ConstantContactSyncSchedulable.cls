/**
 * @description JSI-107 hourly scheduler for the Constant Contact inbound sync. Kept thin:
 *   scheduled Apex can't safely make callouts directly, so it enqueues the Queueable worker
 *   (Database.AllowsCallouts) which does the CC reads + applies them.
 *
 *   Schedule (once authorized), e.g. hourly:
 *     System.schedule('JSI CC Inbound Sync Hourly', '0 0 * * * ?', new ConstantContactSyncSchedulable());
 *
 *   Enqueues the three inbound syncs as SEPARATE queueables (one transaction each). They can't share a
 *   transaction: each does a callout then DML, so running them back-to-back in one job would trip
 *   "uncommitted work pending" on the second callout. Separate jobs keep each callout→DML clean.
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: hourly scheduler that enqueues the sync worker.
 * 2026-07-21 - Jason Ott - CC auth cleared; enqueue all three inbound syncs (opt-out, preference, engagement) as separate jobs.
 */
public with sharing class ConstantContactSyncSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new ConstantContactSyncQueueable('OPT_OUT'));      // JSI-107
        System.enqueueJob(new ConstantContactSyncQueueable('PREFERENCE'));   // JSI-108
        System.enqueueJob(new ConstantContactSyncQueueable('ENGAGEMENT'));   // JSI-109
    }
}
