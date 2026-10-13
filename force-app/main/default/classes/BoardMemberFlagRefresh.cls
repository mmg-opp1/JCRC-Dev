/**
 * @description Nightly upkeep of the things that go stale purely through the passage of time:
 *              Board Term Status, then Contact.Current_Board_Member__c.
 *
 *              Needed because Board_Term__c.Is_Current__c is a formula over Start/End dates: a term
 *              stops being current purely through the passage of time, producing no DML for the
 *              trigger to react to. Without this a contact would stay flagged as a board member
 *              until something happened to touch their term record, and an expired term would keep
 *              describing itself as Active.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (JSI-87 board letter routing).
 * 2026-09-01 - Jason Ott - Also roll off terms whose End Date has passed (UAT: an ended term still
 *                          read as Active on the record).
 * 2026-10-13 - Jason Ott - Also re-sync each term's Board Role (Current) from its current year.
 */
public with sharing class BoardMemberFlagRefresh implements Schedulable {
    public void execute(SchedulableContext sc) {
        // Status first: rolling a term off is itself DML on Board Term, which refreshes the flags
        // for those contacts on the way through. The sweep below then catches everyone else.
        BoardTermService.rollOffExpiredTerms();
        BoardTermService.refreshAllBoardFlags();
        // On July 1 a new year becomes current with no DML to react to; pick up its role.
        BoardTermService.syncAllCurrentRoles();
    }
}