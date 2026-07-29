/**
 * @description Stamps derived fields (before) and recomputes the member's board commitment (after)
 *              for Board Membership Year. JSI-123 Board Tracking. Author: Jason Ott.
 */
trigger BoardMembershipYearTrigger on Board_Membership_Year__c (
        before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        BoardCommitmentService.stampMembershipYears(Trigger.new);
    } else {
        BoardCommitmentService.recomputeFromMembershipYears(Trigger.isDelete ? Trigger.old : Trigger.new);
    }
}
