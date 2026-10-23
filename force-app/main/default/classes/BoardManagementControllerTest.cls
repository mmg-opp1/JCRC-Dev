/**
 * @description Tests for BoardManagementController (JSI-123 console): create a meeting, list eligible
 *              attendees for its fiscal year, save attendance, and confirm it rolls up (3-of-4 tracking).
 * @author Jason Ott
 * @created 2026-07-29
 *
 * Change Log:
 * -----------
 * 2026-09-01 - Jason Ott - Cover the double-click duplicate guards on createMeeting and saveAssignment.
 * 2026-09-02 - Jason Ott - Cover committee meetings and their attendance.
 * 2026-10-23 - Jason Ott - American spelling throughout (no behavior change).
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
        BoardManagementController.saveAttendance(meetingId, JSON.serialize(rows));
        Test.stopTest();

        Board_Membership_Year__c y = [SELECT Meetings_Attended__c FROM Board_Membership_Year__c
            WHERE Id = :rows[0].membershipYearId];
        System.assertEquals(1, y.Meetings_Attended__c, 'attendance rolled up to the membership year');

        List<BoardManagementController.MeetingInfo> meetings = BoardManagementController.getMeetings();
        System.assertEquals(1, meetings.size(), 'the created meeting is listed');
        System.assertEquals(1, meetings[0].attendedCount, 'meeting shows 1 attendee');

        // toggling off updates the same record (upsert on key)
        rows[0].attended = false;
        BoardManagementController.saveAttendance(meetingId, JSON.serialize(rows));
        Board_Membership_Year__c y2 = [SELECT Meetings_Attended__c FROM Board_Membership_Year__c
            WHERE Id = :rows[0].membershipYearId];
        System.assertEquals(0, y2.Meetings_Attended__c, 'un-attend updates, not duplicates');
    }

    @isTest
    static void committeesAndAssignments() {
        Test.startTest();
        Id cid = BoardManagementController.saveCommittee(null, 'Finance X', 'Board Committee', false, null, true);
        System.assertNotEquals(null, cid, 'committee created');
        BoardManagementController.saveCommittee(cid, 'Finance X2', 'Board Committee', true, null, true);

        Contact c = new Contact(LastName = 'Committee Member');
        insert c;
        BoardManagementController.saveAssignment(cid, c.Id, 'Chair', Date.today());
        Test.stopTest();

        List<BoardManagementController.CommitteeInfo> comms = BoardManagementController.getCommittees();
        Boolean found = false;
        for (BoardManagementController.CommitteeInfo ci : comms) {
            if (ci.id == cid) {
                found = true;
                System.assertEquals('Finance X2', ci.name, 'edit persisted');
                System.assertEquals(true, ci.isExecutive, 'exec flag persisted');
            }
        }
        System.assert(found, 'committee listed');

        List<BoardManagementController.AssignmentInfo> asgs = BoardManagementController.getAssignments(cid);
        System.assertEquals(1, asgs.size(), 'one assignment');
        System.assertEquals('Chair', asgs[0].role, 'role saved');
        BoardManagementController.removeAssignment(asgs[0].id);
        System.assertEquals(0, BoardManagementController.getAssignments(cid).size(), 'assignment removed');
    }

    /**
     * A second New Meeting click for the same name and date must be refused rather than create the
     * meeting twice, and the message must be readable rather than the platform's field-and-id error.
     */
    @isTest
    static void secondIdenticalMeetingIsRefused() {
        Date held = Date.today();
        BoardManagementController.createMeeting('Annual Retreat', held);

        String caught = null;
        Test.startTest();
        try {
            BoardManagementController.createMeeting('Annual Retreat', held);
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'the second identical meeting is rejected');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Meeting__c WHERE Meeting_Date__c = :held
            AND Name = 'Annual Retreat'], 'the rejected click leaves exactly one meeting');
    }

    /** The key is case- and whitespace-insensitive, so sloppy re-typing is caught as a duplicate too. */
    @isTest
    static void meetingKeyIgnoresCaseAndSpacing() {
        Date held = Date.today().addDays(7);
        BoardManagementController.createMeeting('Finance Review', held);

        Boolean blocked = false;
        Test.startTest();
        try {
            BoardManagementController.createMeeting('  finance review ', held);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'same meeting re-typed in a different case is still a duplicate');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Meeting__c WHERE Meeting_Date__c = :held],
            'only one meeting on that date');
    }

    /**
     * A second Add Member click on a committee must be refused. Assignment_Key__c already made this
     * impossible at the database level; what is new is that the user is told why in plain words.
     */
    @isTest
    static void secondIdenticalAssignmentIsRefused() {
        Id cid = BoardManagementController.saveCommittee(null, 'Governance Y', 'Board Committee',
            false, null, true);
        Contact c = new Contact(LastName = 'Committee Double Click');
        insert c;

        BoardManagementController.saveAssignment(cid, c.Id, 'Member', Date.today());

        String caught = null;
        Test.startTest();
        try {
            BoardManagementController.saveAssignment(cid, c.Id, 'Member', Date.today());
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'the second identical assignment is rejected');
        System.assertEquals(1, BoardManagementController.getAssignments(cid).size(),
            'the rejected click leaves exactly one assignment');
    }

    /**
     * The list a committee's member screen reads must reflect a write that just happened. This is the
     * behavior that broke when getAssignments was cacheable: the added member was not in the result.
     */
    @isTest
    static void addedMemberIsInTheNextRead() {
        Id cid = BoardManagementController.saveCommittee(null, 'Fresh Read Z', 'Board Committee',
            false, null, true);
        Contact c = new Contact(LastName = 'Freshly Added');
        insert c;

        Test.startTest();
        System.assertEquals(0, BoardManagementController.getAssignments(cid).size(),
            'the committee starts empty');
        BoardManagementController.saveAssignment(cid, c.Id, 'Member', Date.today());
        List<BoardManagementController.AssignmentInfo> after =
            BoardManagementController.getAssignments(cid);
        Test.stopTest();

        System.assertEquals(1, after.size(), 'the member just added is in the very next read');
        System.assertEquals(c.Id, after[0].contactId, 'and it is the right person');

        BoardManagementController.removeAssignment(after[0].id);
        System.assertEquals(0, BoardManagementController.getAssignments(cid).size(),
            'and a removal is gone from the next read too');
    }

    /**
     * A meeting saved without a date has nothing to key on, so it gets no key and is not blocked.
     * Nulls do not collide in a unique field, so more than one such draft can exist.
     */
    @isTest
    static void meetingWithoutADateGetsNoKey() {
        Test.startTest();
        Board_Meeting__c a = new Board_Meeting__c(Name = 'Undated Draft');
        Board_Meeting__c b = new Board_Meeting__c(Name = 'Undated Draft');
        insert new List<Board_Meeting__c>{ a, b };
        Test.stopTest();

        for (Board_Meeting__c m : [SELECT Meeting_Key__c FROM Board_Meeting__c
                WHERE Id IN :new List<Id>{ a.Id, b.Id }]) {
            System.assertEquals(null, m.Meeting_Key__c, 'no date means no key');
        }
        System.assertEquals(2, [SELECT COUNT() FROM Board_Meeting__c WHERE Name = 'Undated Draft'],
            'undated drafts are not treated as duplicates of each other');
    }

    // ---------------------------------------------------------------------------------------
    // Committee meetings and attendance
    // ---------------------------------------------------------------------------------------

    private static Date fyStart() {
        Date t = Date.today();
        return (t.month() >= 7) ? Date.newInstance(t.year(), 7, 1) : Date.newInstance(t.year() - 1, 7, 1);
    }

    /** A committee with one member whose assignment carries the current fiscal year. */
    private static Id committeeWithMember(String committeeName, String lastName, Date fyDate) {
        Id cid = BoardManagementController.saveCommittee(null, committeeName, 'Board Committee',
            false, null, true);
        Contact c = new Contact(LastName = lastName);
        insert c;
        BoardManagementController.saveAssignment(cid, c.Id, 'Member', fyDate);
        return cid;
    }

    /** Create a meeting, take attendance, and see it counted - the whole loop the console drives. */
    @isTest
    static void committeeMeetingAttendanceFlow() {
        Id cid = committeeWithMember('Finance CM', 'Committee Attendee', Date.today());

        Test.startTest();
        Id meetingId = BoardManagementController.createCommitteeMeeting(cid, 'Q1 Finance', Date.today());
        List<BoardManagementController.CommitteeAttendeeRow> rows =
            BoardManagementController.getCommitteeAttendance(meetingId);
        System.assertEquals(1, rows.size(), 'the committee member is an eligible attendee');
        System.assertEquals(false, rows[0].attended, 'not attended by default');
        rows[0].attended = true;
        BoardManagementController.saveCommitteeAttendance(meetingId, JSON.serialize(rows));
        Test.stopTest();

        List<BoardManagementController.CommitteeMeetingInfo> meetings =
            BoardManagementController.getCommitteeMeetings(cid);
        System.assertEquals(1, meetings.size(), 'the meeting is listed for its committee');
        System.assertEquals(1, meetings[0].attendedCount, 'the meeting shows one attendee');
        System.assertEquals('Q1 Finance', meetings[0].name, 'name kept');

        // re-saving updates the same row rather than stacking duplicates
        rows = BoardManagementController.getCommitteeAttendance(meetingId);
        System.assertEquals(true, rows[0].attended, 'the tick is read back');
        rows[0].attended = false;
        BoardManagementController.saveCommitteeAttendance(meetingId, JSON.serialize(rows));
        System.assertEquals(1, [SELECT COUNT() FROM Committee_Meeting_Attendance__c
            WHERE Committee_Meeting__c = :meetingId], 'un-attending updates, it does not duplicate');
        System.assertEquals(0, BoardManagementController.getCommitteeMeetings(cid)[0].attendedCount,
            'and the count comes back down');
    }

    /** The eligibility rule Jason chose: the meeting's fiscal year, plus assignments with no year. */
    @isTest
    static void attendanceSheetIncludesBlankFiscalYearsAndExcludesOtherYears() {
        Id cid = committeeWithMember('Eligibility CM', 'This Year', Date.today());

        // someone assigned for a different fiscal year - should not be on this meeting's sheet
        Contact past = new Contact(LastName = 'Different Year');
        insert past;
        BoardManagementController.saveAssignment(cid, past.Id, 'Member', Date.today().addYears(-3));

        // someone whose assignment has no fiscal year at all - must still appear
        Contact blank = new Contact(LastName = 'No Year');
        insert blank;
        insert new Committee_Assignment__c(Committee__c = cid, Contact__c = blank.Id,
            Committee_Role__c = 'Member', Active__c = true);

        Test.startTest();
        Id meetingId = BoardManagementController.createCommitteeMeeting(cid, 'Eligibility Test', Date.today());
        List<BoardManagementController.CommitteeAttendeeRow> rows =
            BoardManagementController.getCommitteeAttendance(meetingId);
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (BoardManagementController.CommitteeAttendeeRow r : rows) { names.add(r.name); }
        System.assertEquals(2, rows.size(), 'this year plus the blank one, not the old assignment');
        System.assert(names.contains('This Year'), 'the current-year member is on the sheet');
        System.assert(names.contains('No Year'), 'a blank fiscal year does not drop someone silently');
        System.assert(!names.contains('Different Year'), 'another year is not on this sheet');
    }

    /** A committee member who is not a board member can still have attendance taken. */
    @isTest
    static void aNonBoardMemberCanBeMarkedPresent() {
        Id cid = committeeWithMember('Non Board CM', 'Not On The Board', Date.today());
        Contact c = [SELECT Id, Current_Board_Member__c FROM Contact WHERE LastName = 'Not On The Board'];
        System.assertEquals(false, c.Current_Board_Member__c, 'set up: this person is not on the board');

        Test.startTest();
        Id meetingId = BoardManagementController.createCommitteeMeeting(cid, 'Open Meeting', Date.today());
        List<BoardManagementController.CommitteeAttendeeRow> rows =
            BoardManagementController.getCommitteeAttendance(meetingId);
        rows[0].attended = true;
        BoardManagementController.saveCommitteeAttendance(meetingId, JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Committee_Meeting_Attendance__c
            WHERE Committee_Meeting__c = :meetingId AND Attended__c = true],
            'a non-board committee member is recorded as present');
    }

    /** Committee attendance must never touch the board attend-3-of-4 count. */
    @isTest
    static void committeeAttendanceDoesNotCountTowardTheBoardRequirement() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'Both Roles T',
            Default_Annual_Commitment__c = 5000, Default_Term_Length_Years__c = 6, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'On Board And Committee');
        insert c;
        insert new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id, Status__c = 'Active',
            Start_Date__c = fyStart());
        Id cid = BoardManagementController.saveCommittee(null, 'Overlap CM', 'Board Committee',
            false, null, true);
        BoardManagementController.saveAssignment(cid, c.Id, 'Member', Date.today());

        Test.startTest();
        Id meetingId = BoardManagementController.createCommitteeMeeting(cid, 'Committee Only', Date.today());
        List<BoardManagementController.CommitteeAttendeeRow> rows =
            BoardManagementController.getCommitteeAttendance(meetingId);
        rows[0].attended = true;
        BoardManagementController.saveCommitteeAttendance(meetingId, JSON.serialize(rows));
        Test.stopTest();

        Board_Membership_Year__c y = [SELECT Meetings_Attended__c FROM Board_Membership_Year__c
            WHERE Contact__c = :c.Id AND FY_Start__c = :fyStart() LIMIT 1];
        System.assertEquals(0, y.Meetings_Attended__c,
            'attending a committee meeting is not attending a board meeting');
        System.assertEquals(1, [SELECT Meetings_Attended__c FROM Committee_Assignment__c
            WHERE Committee__c = :cid AND Contact__c = :c.Id].Meetings_Attended__c,
            'it counts on the committee assignment instead');
    }

    /** Two clicks on New Meeting must not give the committee the same meeting twice. */
    @isTest
    static void secondIdenticalCommitteeMeetingIsRefused() {
        Id cid = committeeWithMember('Dupe CM', 'Dupe Member', Date.today());
        Date held = Date.today();
        BoardManagementController.createCommitteeMeeting(cid, 'Budget Review', held);

        String caught = null;
        Test.startTest();
        try {
            BoardManagementController.createCommitteeMeeting(cid, '  budget review ', held);
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'the duplicate is refused, case and spacing ignored');
        System.assertEquals(1, BoardManagementController.getCommitteeMeetings(cid).size(),
            'the committee has one meeting');
    }

    /** Two committees keep their own meetings; one committee's list never shows another's. */
    @isTest
    static void meetingsAreScopedToTheirCommittee() {
        Id a = committeeWithMember('Alpha CM', 'Alpha Person', Date.today());
        Id b = committeeWithMember('Beta CM', 'Beta Person', Date.today());

        Test.startTest();
        BoardManagementController.createCommitteeMeeting(a, 'Alpha Meeting', Date.today());
        BoardManagementController.createCommitteeMeeting(b, 'Beta Meeting', Date.today());
        Test.stopTest();

        List<BoardManagementController.CommitteeMeetingInfo> alpha =
            BoardManagementController.getCommitteeMeetings(a);
        System.assertEquals(1, alpha.size(), 'Alpha sees only its own meeting');
        System.assertEquals('Alpha Meeting', alpha[0].name, 'and it is the right one');
    }

    /** Deleting a meeting takes its attendance with it, and leaves the committee alone. */
    @isTest
    static void deletingAMeetingRemovesItsAttendance() {
        Id cid = committeeWithMember('Delete CM', 'Delete Attendee', Date.today());
        Id meetingId = BoardManagementController.createCommitteeMeeting(cid, 'Doomed', Date.today());
        List<BoardManagementController.CommitteeAttendeeRow> rows =
            BoardManagementController.getCommitteeAttendance(meetingId);
        rows[0].attended = true;
        BoardManagementController.saveCommitteeAttendance(meetingId, JSON.serialize(rows));
        System.assertEquals(1, [SELECT COUNT() FROM Committee_Meeting_Attendance__c
            WHERE Committee_Meeting__c = :meetingId], 'set up: attendance exists');

        Test.startTest();
        BoardManagementController.deleteCommitteeMeeting(meetingId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Committee_Meeting__c WHERE Id = :meetingId],
            'the meeting is gone');
        System.assertEquals(0, [SELECT COUNT() FROM Committee_Meeting_Attendance__c
            WHERE Committee_Meeting__c = :meetingId], 'and its attendance went with it');
        System.assertEquals(1, [SELECT COUNT() FROM Committee__c WHERE Id = :cid],
            'the committee itself is untouched');
    }
}