/**
 * @description JSI-107 inbound sync worker. Runs the Constant Contact reads that require
 *   HTTP callouts (a Queueable so callouts are allowed) and feeds the results to the
 *   ConstantContactSyncService applier. Currently runs the opt-out sync (DoD #4);
 *   bounce/engagement will be added here once their reporting fetches are built.
 *
 *   The incremental cursor is derived from the last successful/partial 'Opt-Out Sync'
 *   Integration_Log__c run (no extra state object); first run looks back DEFAULT_LOOKBACK_HOURS.
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: opt-out sync orchestration + incremental cursor.
 * 2026-07-20 - Jason Ott - JSI-108: PREFERENCE mode (topic membership sync).
 * 2026-07-20 - Jason Ott - JSI-109: ENGAGEMENT mode (email + per-recipient activity sync).
 */
public with sharing class ConstantContactSyncQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible private static final Integer DEFAULT_LOOKBACK_HOURS = 25; // > 24h SLA on first run

    // Which read(s) this run performs. 'OPT_OUT' (default), 'PREFERENCE' (JSI-108),
    // 'ENGAGEMENT' (JSI-109), or 'ALL'.
    private String mode = 'OPT_OUT';

    public ConstantContactSyncQueueable() {}
    public ConstantContactSyncQueueable(String mode) {
        if (String.isNotBlank(mode)) this.mode = mode;
    }

    public void execute(QueueableContext qc) {
        if (mode == 'OPT_OUT' || mode == 'ALL') runOptOutSync();
        if (mode == 'PREFERENCE' || mode == 'ALL') runPreferenceSync();
        if (mode == 'ENGAGEMENT' || mode == 'ALL') runEngagementSync();
    }

    /** Fetch unsubscribes since the cursor and apply them; log a Failed run if the callout throws. */
    public ConstantContactSyncService.SyncResult runOptOutSync() {
        Datetime since = getOptOutCursor();
        List<ConstantContactSyncService.ContactUpdate> updates;
        try {
            updates = new ConstantContactClient().getUnsubscribes(since);
        } catch (Exception e) {
            logFailure('Opt-Out Sync', e);
            return null;
        }
        return new ConstantContactSyncService().apply(updates, 'Opt-Out Sync');
    }

    /** JSI-108: fetch each contact's CC list memberships and reconcile their CampaignMembers. */
    public ConstantContactSyncService.SyncResult runPreferenceSync() {
        Datetime since = getCursor('Preference Sync');
        List<ConstantContactSyncService.TopicMembership> memberships;
        try {
            memberships = new ConstantContactClient().getListMemberships(since);
        } catch (Exception e) {
            logFailure('Preference Sync', e);
            return null;
        }
        return new ConstantContactSyncService().applyTopicMemberships(memberships);
    }

    /** JSI-109: fetch CC emails + per-recipient engagement and apply them (CC_Email__c / CC_Email_Activity__c). */
    public ConstantContactSyncService.SyncResult runEngagementSync() {
        Datetime since = getCursor('Engagement Sync');
        List<ConstantContactSyncService.EmailCampaignDTO> campaigns;
        try {
            campaigns = new ConstantContactClient().getEmailCampaigns(since);
        } catch (Exception e) {
            logFailure('Engagement Sync', e);
            return null;
        }
        return new ConstantContactSyncService().applyEmailActivity(campaigns);
    }

    /** Cursor = start of the most recent successful/partial opt-out run; else now - lookback. */
    @TestVisible
    private Datetime getOptOutCursor() {
        return getCursor('Opt-Out Sync');
    }

    /** Generic incremental cursor for an operation: last successful/partial Run_Start, else now - lookback. */
    private Datetime getCursor(String operation) {
        List<Integration_Log__c> last = [
            SELECT Run_Start__c FROM Integration_Log__c
            WHERE Operation__c = :operation
              AND Run_Status__c IN ('Success', 'Partial')
              AND Run_Start__c != null
            ORDER BY Run_Start__c DESC LIMIT 1
        ];
        return last.isEmpty() ? System.now().addHours(-DEFAULT_LOOKBACK_HOURS) : last[0].Run_Start__c;
    }

    /** Record a failed run so the admin sees callout/auth failures in Integration_Log__c. */
    private void logFailure(String operation, Exception e) {
        try {
            insert new Integration_Log__c(
                Integration__c = 'Constant Contact',
                Operation__c = operation,
                Run_Status__c = 'Failed',
                Run_Start__c = System.now(),
                Run_End__c = System.now(),
                Records_Processed__c = 0,
                Records_Updated__c = 0,
                Records_Failed__c = 0,
                Message__c = e.getTypeName() + ': ' + e.getMessage()
            );
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR, 'Failed to log CC sync failure: ' + ignored.getMessage());
        }
    }
}
