/**
 * @description Deletes old QuickBooks events so the log doesn't grow forever (JSI-121 Phase 5c).
 *
 *              Every webhook Salesforce receives is kept as a QuickBooks Event. They are useful - they are the
 *              record of what has already been imported, and the raw payload for troubleshooting - but they are
 *              not needed indefinitely, and Salesforce counts roughly 2 KB per record whatever it holds.
 *
 *              WHAT IS KEPT, AND WHY:
 *                - Processed and Failed events: Event Retention Days (180 by default). These carry the import
 *                  memory that stops a line staff deleted from being re-created, so they are kept far beyond the
 *                  30 days in which QuickBooks could still send an update about the same record. Committed money
 *                  is protected independently - the processor also checks the source id stamped on the gift or
 *                  payment - so a purge can never resurrect a committed transaction.
 *                - Ignored events (other entities, other companies, money that isn't ACH/wire): Ignored Event
 *                  Retention Days (30 by default). They carry no memory, so they can go sooner.
 *                - Received events are NEVER deleted, however old: they are still waiting to be processed.
 *
 *              Deleted rows are emptied from the Recycle Bin, the same as committed pending transactions.
 * @author Jason Ott
 * @created 2026-09-23
 *
 * Change Log:
 * -----------
 * 2026-09-23 - Jason Ott - Initial version (JSI-121 Phase 5c).
 */
public without sharing class QuickBooksEventPurge implements Schedulable, Database.Batchable<SObject> {

    @TestVisible private static final Integer DEFAULT_RETENTION_DAYS = 180;
    @TestVisible private static final Integer DEFAULT_IGNORED_RETENTION_DAYS = 30;
    /** Never purge anything younger than this, whatever the settings say. */
    @TestVisible private static final Integer MINIMUM_RETENTION_DAYS = 31;

    private Integer deleted = 0;

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new QuickBooksEventPurge(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();
        Datetime keptSince = System.now().addDays(-retentionDays(cfg));
        Datetime ignoredKeptSince = System.now().addDays(-ignoredRetentionDays(cfg));
        return Database.getQueryLocator([
            SELECT Id FROM QuickBooks_Event__c
            WHERE (Status__c IN ('Processed', 'Failed') AND Received_At__c < :keptSince)
               OR (Status__c = 'Ignored' AND Received_At__c < :ignoredKeptSince)
            ORDER BY Received_At__c ASC
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<QuickBooks_Event__c> scope) {
        delete scope;
        deleted += scope.size();
        try {
            Database.emptyRecycleBin(scope);
        } catch (Exception e) {
            // Housekeeping only; the rows are already deleted.
            System.debug(LoggingLevel.WARN, 'QuickBooks events not purged from the Recycle Bin: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.INFO, 'QuickBooks event purge removed ' + deleted + ' event(s).');
    }

    /** At least MINIMUM_RETENTION_DAYS, so a mis-set value can't throw away the import memory QuickBooks still needs. */
    @TestVisible
    private static Integer retentionDays(QuickBooks_Settings__c cfg) {
        Integer days = (cfg == null || cfg.Event_Retention_Days__c == null)
            ? DEFAULT_RETENTION_DAYS : Integer.valueOf(cfg.Event_Retention_Days__c);
        return Math.max(days, MINIMUM_RETENTION_DAYS);
    }

    @TestVisible
    private static Integer ignoredRetentionDays(QuickBooks_Settings__c cfg) {
        Integer days = (cfg == null || cfg.Ignored_Event_Retention_Days__c == null)
            ? DEFAULT_IGNORED_RETENTION_DAYS : Integer.valueOf(cfg.Ignored_Event_Retention_Days__c);
        return Math.max(days, 1);
    }
}
