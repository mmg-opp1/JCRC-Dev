/**
 * @description Auto-fills the term End Date (before) and generates the per-fiscal-year Board Membership Year
 *              records (after) for a Board Term. Also keeps Contact.Current_Board_Member__c in step, which
 *              the JSI-87 acknowledgment router uses to choose the board thank-you letter.
 *              JSI-123 Board Tracking / JSI-87. Author: Jason Ott.
 */
trigger BoardTermTrigger on Board_Term__c (before insert, before update,
                                           after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        BoardTermService.setEndDates(Trigger.new);
    } else {
        if (Trigger.new != null) {
            BoardTermService.generateMembershipYears(Trigger.new);
        }
        // Collect contacts on both sides so reassigning a term refreshes the old contact too.
        Set<Id> contactIds = new Set<Id>();
        if (Trigger.new != null) {
            for (Board_Term__c t : Trigger.new) { if (t.Contact__c != null) contactIds.add(t.Contact__c); }
        }
        if (Trigger.old != null) {
            for (Board_Term__c t : Trigger.old) { if (t.Contact__c != null) contactIds.add(t.Contact__c); }
        }
        BoardTermService.refreshBoardFlags(contactIds);
    }
}
