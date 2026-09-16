/**
 * @description Derives the fiscal year and stamps the dedupe key on a Committee Meeting before save,
 *              so the same meeting cannot be created twice whatever entered it — the console's New
 *              Meeting button, a data load or the API. JSI-123 Board Tracking. Author: Jason Ott.
 */
trigger CommitteeMeetingTrigger on Committee_Meeting__c (before insert, before update) {
    CommitteeMeetingService.stampMeetings(Trigger.new);
}