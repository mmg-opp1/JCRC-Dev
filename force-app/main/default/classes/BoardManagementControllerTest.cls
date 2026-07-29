/**
 * @description Tests for BoardManagementController (JSI-123 console): create a meeting, list eligible
 *              attendees for its fiscal year, save attendance, and confirm it rolls up (3-of-4 tracking).
 * @author Jason Ott
 * @created 2026-07-29
 */
@isTest
private class BoardManagementControllerTest {

    @isTest
    static void meetingsAndAttendanceFlow() {
        Board_Member_Type__c jcrc = new Board_Member_Type__c(Name = 'JCRC Recruited M',
            Default_Annual_Commitment__c = 5000, Default_Term_Length_Years__c = 6, Active__c = true);
        insert jcrc;
        Contact c = new Contact(LastName = 'Attendee');
        insert c;
        Date fy = Date.today().month() >= 7
            ? Date.newInstance(Date.today().year(), 7, 1)
            : Date.newInstance(Date.today().year() - 1, 7, 1);
        Board_Term__c bt = new Board_Term__c(Contact__c = c.Id, Member_Type__c = jcrc.Id,
            Status__c = 'Active', Start_Date__c = fy);
        insert bt; // auto-generates membership years incl. the current fiscal year

        Test.startTest();
        Id meetingId = BoardManagementController.createMeeting('Q1 Board Meeting', Date.today());
        List<BoardManagementController.AttendeeRow> rows = BoardManagementController.getAttendance(meetingId);
        System.assertEquals(1, rows.size(), 'current-FY board member is an eligible attendee');
        System.assertEquals(false, rows[0].attended, 'not attended by default');
        rows[0].attended = true;
        BoardManagementController.saveAttendance(meetingId, rows);
        Test.stopTest();

        Board_Membership_Year__c y = [SELECT Meetings_Attended__c FROM Board_Membership_Year__c
            WHERE Id = :rows[0].membershipYearId];
        System.assertEquals(1, y.Meetings_Attended__c, 'attendance rolled up to the membership year');

        List<BoardManagementController.MeetingInfo> meetings = BoardManagementController.getMeetings();
        System.assertEquals(1, meetings.size(), 'the created meeting is listed');
        System.assertEquals(1, meetings[0].attendedCount, 'meeting shows 1 attendee');

        // toggling off updates the same record (upsert on key)
        rows[0].attended = false;
        BoardManagementController.saveAttendance(meetingId, rows);
        Board_Membership_Year__c y2 = [SELECT Meetings_Attended__c FROM Board_Membership_Year__c
            WHERE Id = :rows[0].membershipYearId];
        System.assertEquals(0, y2.Meetings_Attended__c, 'un-attend updates, not duplicates');
    }
}
