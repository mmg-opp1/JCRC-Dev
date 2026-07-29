/**
 * @description Annual advance (schedule for July 1): flips Counts Toward Limit to true on Board Membership
 *              Year records whose fiscal year has now begun (non-officer, non-Past-President), so a member's
 *              "board years served" only ever reflects years actually served — future pre-created years are
 *              excluded until they start. Updating each record re-fires the before-save stamping in
 *              BoardCommitmentService, and the Board Term "Board Years Served" roll-up recalculates.
 * @author Jason Ott
 * @created 2026-07-28
 */
public with sharing class BoardYearAdvance implements Schedulable {

    public void execute(SchedulableContext ctx) {
        run();
    }

    public static void run() {
        List<Board_Membership_Year__c> started = [
            SELECT Id FROM Board_Membership_Year__c
            WHERE Counts_Toward_Limit__c = false AND FY_Start__c != null AND FY_Start__c <= TODAY
        ];
        if (!started.isEmpty()) {
            // The Board Membership Year before-save trigger recomputes Counts Toward Limit on update.
            update started;
        }
    }
}
