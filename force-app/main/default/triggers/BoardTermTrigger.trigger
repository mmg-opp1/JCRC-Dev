/**
 * @description Auto-fills the term End Date (before) and generates the per-fiscal-year Board Membership Year
 *              records (after) for a Board Term. JSI-123 Board Tracking. Author: Jason Ott.
 */
trigger BoardTermTrigger on Board_Term__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        BoardTermService.setEndDates(Trigger.new);
    } else {
        BoardTermService.generateMembershipYears(Trigger.new);
    }
}
