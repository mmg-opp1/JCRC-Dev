/**
 * @description JSI-107 hourly scheduler for the Constant Contact inbound sync. Kept thin:
 *   scheduled Apex can't safely make callouts directly, so it enqueues the Queueable worker
 *   (Database.AllowsCallouts) which does the CC reads + applies them.
 *
 *   Schedule (once authorized), e.g. hourly:
 *     System.schedule('JSI-107 CC Opt-Out Sync', '0 0 * * * ?', new ConstantContactSyncSchedulable());
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: hourly scheduler that enqueues the sync worker.
 */
public with sharing class ConstantContactSyncSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new ConstantContactSyncQueueable());
    }
}
