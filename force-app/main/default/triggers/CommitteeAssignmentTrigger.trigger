/**
 * @description Stamps derived fields (before) and recomputes affected members' board commitment (after)
 *              for Committee Assignment — a Chair/Co-Chair or Executive Committee assignment can raise the
 *              commitment to $10k. JSI-123 Board Tracking. Author: Jason Ott.
 */
trigger CommitteeAssignmentTrigger on Committee_Assignment__c (
        before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        BoardCommitmentService.stampCommitteeAssignments(Trigger.new);
    } else {
        BoardCommitmentService.recomputeFromCommitteeAssignments(Trigger.isDelete ? Trigger.old : Trigger.new);
    }
}
