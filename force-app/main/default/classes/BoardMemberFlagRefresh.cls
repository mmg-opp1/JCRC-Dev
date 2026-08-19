/**
 * @description Nightly refresh of Contact.Current_Board_Member__c.
 *
 *              Needed because Board_Term__c.Is_Current__c is a formula over Start/End dates: a term
 *              stops being current purely through the passage of time, producing no DML for the
 *              trigger to react to. Without this a contact would stay flagged as a board member
 *              until something happened to touch their term record.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (JSI-87 board letter routing).
 */
public with sharing class BoardMemberFlagRefresh implements Schedulable {
    public void execute(SchedulableContext sc) {
        BoardTermService.refreshAllBoardFlags();
    }
}
