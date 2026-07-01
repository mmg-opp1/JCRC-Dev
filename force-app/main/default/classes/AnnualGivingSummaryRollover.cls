/**
 * @description JSI-90 — July-1 rollover. Creates each donor's Annual Giving Summary for the new
 *              fiscal year and carries their level forward: the new summary links to the prior year
 *              and inherits its Effective Level (with no gifts yet earned). This makes level
 *              inheritance visible for donors who earned a level last year but have not yet given this
 *              year; once they give, GiftAllocationService recomputes the effective level as the
 *              higher of this year's earned and the inherited level.
 *
 *              Idempotent — skips contacts that already have a summary for the new year. Schedule for
 *              July 1 (e.g. System.schedule('JSI-90 AGS Rollover','0 0 1 1 7 ?', new AnnualGivingSummaryRollover())).
 * @author Jason Ott
 * @created 2026-07-01
 *
 * Change Log:
 * -----------
 * 2026-07-01 - Jason Ott - Initial version (JSI-90 Phase 3).
 */
public with sharing class AnnualGivingSummaryRollover implements Database.Batchable<SObject>, Schedulable {

    private Date newFyStart;   // July 1 of the fiscal year being opened
    private Date newFyEnd;     // June 30 following
    private Date priorFyStart; // July 1 of the prior fiscal year (source of inheritance)

    /**
     * @description Default constructor — rolls over into the fiscal year that contains today.
     */
    public AnnualGivingSummaryRollover() {
        this(fiscalYearStart(Date.today()));
    }

    /**
     * @description Constructor with an explicit new-year start (July 1) — used for tests / re-runs.
     * @param newFiscalYearStart the July 1 of the year to open
     */
    public AnnualGivingSummaryRollover(Date newFiscalYearStart) {
        this.newFyStart = newFiscalYearStart;
        this.newFyEnd = newFiscalYearStart.addYears(1).addDays(-1);
        this.priorFyStart = newFiscalYearStart.addYears(-1);
    }

    /**
     * @description Schedulable entry point — launches the batch.
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AnnualGivingSummaryRollover(this.newFyStart), 200);
    }

    /**
     * @description Batch start — every prior-year summary is a rollover candidate.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Contact__c, Effective_Level__c
            FROM Annual_Giving_Summary__c WHERE FY_Start__c = :priorFyStart AND Contact__c != null
        ]);
    }

    /**
     * @description Creates the new-year summary for each prior-year donor that doesn't have one yet.
     */
    public void execute(Database.BatchableContext bc, List<Annual_Giving_Summary__c> priorSummaries) {
        // Contacts in this batch that already have a new-year summary (skip them).
        Set<Id> contactIds = new Set<Id>();
        for (Annual_Giving_Summary__c a : priorSummaries) contactIds.add(a.Contact__c);
        Set<Id> alreadyRolled = new Set<Id>();
        for (Annual_Giving_Summary__c a : [
            SELECT Contact__c FROM Annual_Giving_Summary__c
            WHERE FY_Start__c = :newFyStart AND Contact__c IN :contactIds
        ]) {
            alreadyRolled.add(a.Contact__c);
        }

        String label = 'FY' + newFyEnd.year() + ' (Jul ' + newFyStart.year() + '-Jun ' + newFyEnd.year() + ')';
        List<Annual_Giving_Summary__c> toCreate = new List<Annual_Giving_Summary__c>();
        for (Annual_Giving_Summary__c prior : priorSummaries) {
            if (alreadyRolled.contains(prior.Contact__c)) continue;
            alreadyRolled.add(prior.Contact__c); // guard against duplicate prior rows for one contact
            toCreate.add(new Annual_Giving_Summary__c(
                Contact__c = prior.Contact__c,
                FY_Start__c = newFyStart, FY_End__c = newFyEnd, Fiscal_Year_Label__c = label,
                Prior_Year_Summary__c = prior.Id,
                Effective_Level__c = prior.Effective_Level__c   // carry the earned/held level forward
            ));
        }
        if (!toCreate.isEmpty()) insert toCreate;
    }

    public void finish(Database.BatchableContext bc) { }

    // JCRC giving year starts July 1. Returns the start (July 1) of the FY containing d.
    @TestVisible
    private static Date fiscalYearStart(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }
}
