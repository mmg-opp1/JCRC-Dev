/**
 * @description Stamps the Board Meeting dedupe key before save, so the same meeting cannot be created
 *              twice whatever entered it — the console's New Meeting button, a data load or the API.
 *              JSI-123 Board Tracking. Author: Jason Ott.
 */
trigger BoardMeetingTrigger on Board_Meeting__c (before insert, before update) {
    BoardMeetingService.setMeetingKeys(Trigger.new);
}
