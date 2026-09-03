/**
 * @description Tests for BoardMembersController — verifies the current-board roster and commitment
 *              progress, and that non-current terms are excluded. JSI-123 Board Tracking.
 * @author Jason Ott
 * @created 2026-07-27
 *
 * Change Log:
 * -----------
 * 2026-09-01 - Jason Ott - Cover the double-click duplicate guard on createBoardTerm.
 * 2026-09-01 - Jason Ott - Cover deleteBoardMember: the attendance block, the Contact surviving,
 *                          and giving summaries surviving.
 * 2026-09-01 - Jason Ott - Cover the Status roll-off once a term's End Date has passed.
 */
@isTest
private class BoardMembersControllerTest {

    private static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }

    @isTest
    static void returnsCurrentRosterWithCommitment() {
        Contact c = new Contact(LastName = 'Board Member Test');
        insert c;
        insert new Board_Term__c(Contact__c = c.Id, Status__c = 'Active', Board_Role__c = 'Chair',
            Start_Date__c = Date.today().addDays(-10), End_Date__c = Date.today().addDays(30));

        Date fyStart = fyStartFor(Date.today());
        insert new Annual_Giving_Summary__c(Contact__c = c.Id, FY_Start__c = fyStart,
            FY_End__c = fyStart.addYears(1).addDays(-1), Fiscal_Year_Label__c = 'TEST FY',
            Board_Commitment__c = 10000);

        Test.startTest();
        List<BoardMembersController.BoardMemberRow> rows = BoardMembersController.getCurrentBoardMembers();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'one current board member expected');
        System.assertEquals('Chair', rows[0].role, 'role should be Chair');
        System.assertEquals(true, rows[0].expiringSoon, 'End +30d is within the 90-day window');
        System.assertEquals(10000, rows[0].commitment, 'commitment should come from the current-year AGS');
        System.assertEquals(c.Id, rows[0].contactId, 'contactId should be populated for navigation');
    }

    @isTest
    static void excludesNonCurrentTerms() {
        Contact c = new Contact(LastName = 'Former Board Member');
        insert c;
        insert new Board_Term__c(Contact__c = c.Id, Status__c = 'Rolled Off', Board_Role__c = 'Member',
            Start_Date__c = Date.today().addDays(-400), End_Date__c = Date.today().addDays(-30));

        Test.startTest();
        List<BoardMembersController.BoardMemberRow> rows = BoardMembersController.getCurrentBoardMembers();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'rolled-off / expired term should be excluded');
    }

    @isTest
    static void addMemberEndTermAndSummaryLink() {
        Board_Member_Type__c jcrc = new Board_Member_Type__c(Name = 'JCRC Recruited R',
            Default_Annual_Commitment__c = 5000, Default_Term_Length_Years__c = 6, Active__c = true);
        insert jcrc;
        Contact c = new Contact(LastName = 'Roster Add');
        insert c;
        Date fy = fyStartFor(Date.today());

        Test.startTest();
        List<BoardMembersController.PicklistOption> types = BoardMembersController.getMemberTypes();
        System.assert(!types.isEmpty(), 'member types listed for the dropdown');
        Id termId = BoardMembersController.createBoardTerm(c.Id, jcrc.Id, fy);
        Test.stopTest();

        System.assertEquals(6, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Board_Term__c = :termId],
            'creating a term auto-generates 6 board years');
        // #5: the started (current) year is auto-linked to its Annual Giving Summary
        Board_Membership_Year__c cur = [SELECT Annual_Giving_Summary__c FROM Board_Membership_Year__c
            WHERE Board_Term__c = :termId AND FY_Start__c = :fy LIMIT 1];
        System.assertNotEquals(null, cur.Annual_Giving_Summary__c, 'current board year linked to its AGS');

        // #4: ending the term at the current fiscal-year end removes the future board years
        BoardMembersController.endBoardTerm(termId, fy.addYears(1).addDays(-1));
        System.assertEquals(1, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Board_Term__c = :termId],
            'only the current board year remains after ending the term');
    }

    /**
     * The reported UAT defect: a second Add Member click for the same person, type and start date
     * must be refused with a readable message, and must leave exactly one term behind.
     */
    @isTest
    static void secondIdenticalAddIsRefused() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'UJA Appointed T',
            Default_Annual_Commitment__c = 5000, Default_Term_Length_Years__c = 6, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'Double Click');
        insert c;
        Date fy = fyStartFor(Date.today());

        BoardMembersController.createBoardTerm(c.Id, mt.Id, fy);

        String caught = null;
        Test.startTest();
        try {
            BoardMembersController.createBoardTerm(c.Id, mt.Id, fy);
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'the second identical add is rejected');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'the rejected click leaves exactly one board term');
    }

    /**
     * The database-level backstop, independent of the controller: Term_Key__c is unique, so a duplicate
     * term inserted by any other route (data load, API, a flow) is rejected too.
     */
    @isTest
    static void termKeyBlocksDuplicateInsert() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'Key Backstop T',
            Default_Annual_Commitment__c = 1000, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'Key Backstop');
        insert c;
        Date start = fyStartFor(Date.today());

        insert new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id,
            Status__c = 'Active', Start_Date__c = start);

        Boolean blocked = false;
        Test.startTest();
        try {
            insert new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id,
                Status__c = 'Active', Start_Date__c = start);
        } catch (DmlException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'the unique Term Key rejects the duplicate term');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'only the first term survives');
    }

    /**
     * Term_Key__c is deliberately read-only (edit = false) on every profile, and createBoardTerm
     * inserts in USER_MODE. This org has been bitten before by that combination — a USER_MODE write
     * that touches a read-only field throws FLS for ordinary users while passing for an administrator,
     * so an admin-only test proves nothing. Runs the real add as a fundraiser to close that gap.
     */
    @isTest
    static void fundraiserCanAddBoardMember() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'Fundraiser Run T',
            Default_Annual_Commitment__c = 2500, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'Fundraiser Added');
        insert c;
        Date fy = fyStartFor(Date.today());

        Profile p = [SELECT Id FROM Profile WHERE Name = 'JCRC - Fundraising' LIMIT 1];
        User fundraiser = new User(
            ProfileId = p.Id, LastName = 'Fundraiser', Email = 'uat.fundraiser@example.com',
            Username = 'uat.fundraiser.' + String.valueOf(System.now().getTime()) + '@example.com.jcrctest',
            Alias = 'uatfr', TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert fundraiser;

        Id termId;
        Test.startTest();
        System.runAs(fundraiser) {
            termId = BoardMembersController.createBoardTerm(c.Id, mt.Id, fy);
        }
        Test.stopTest();

        System.assertNotEquals(null, termId, 'a fundraiser can add a board member in USER_MODE');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'exactly one term created');
    }

    /** Builds a contact with a board term and returns them, for the delete tests below. */
    private static Contact makeBoardMember(String lastName, String typeName) {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = typeName,
            Default_Annual_Commitment__c = 1000, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = lastName);
        insert c;
        BoardMembersController.createBoardTerm(c.Id, mt.Id, fyStartFor(Date.today()));
        return c;
    }

    /**
     * The accident case this exists for: someone added by mistake, no attendance anywhere, so the
     * whole board record goes - terms and the board years beneath them - and the person stays.
     */
    @isTest
    static void deleteRemovesBoardRecordButKeepsTheContact() {
        Contact c = makeBoardMember('Added By Mistake', 'Delete Case T');
        System.assertEquals(3, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Contact__c = :c.Id],
            'board years generated before the delete');

        Test.startTest();
        BoardMembersController.DeleteImpact impact = BoardMembersController.getDeleteImpact(c.Id);
        System.assertEquals(false, impact.blocked, 'nothing stands in the way');
        System.assertEquals(1, impact.termCount, 'one term to remove');
        System.assertEquals(3, impact.yearCount, 'three board years to remove');
        BoardMembersController.deleteBoardMember(c.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'every term deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Contact__c = :c.Id],
            'board years cascaded away with their term');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Id = :c.Id],
            'the person themselves is NOT deleted');
        System.assertEquals(false, [SELECT Current_Board_Member__c FROM Contact WHERE Id = :c.Id]
            .Current_Board_Member__c, 'no longer flagged as a current board member');
    }

    /** Every term goes, not just the current one, so a re-appointed member leaves nothing behind. */
    @isTest
    static void deleteRemovesEveryTermNotJustTheCurrentOne() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'Multi Term T',
            Default_Annual_Commitment__c = 1000, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'Two Terms');
        insert c;
        Date fy = fyStartFor(Date.today());
        insert new List<Board_Term__c>{
            new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id, Status__c = 'Active',
                Start_Date__c = fy.addYears(-9), End_Date__c = fy.addYears(-6)),
            new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id, Status__c = 'Active',
                Start_Date__c = fy)
        };

        Test.startTest();
        BoardMembersController.DeleteImpact impact = BoardMembersController.getDeleteImpact(c.Id);
        System.assertEquals(2, impact.termCount, 'both the old and the current term are counted');
        BoardMembersController.deleteBoardMember(c.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'the expired term is deleted too, not just the current one');
    }

    /**
     * Attendance blocks the delete, and blocks it on ANY row - a member marked absent still counts,
     * because the row is a record that the meeting considered them. Nothing may be deleted.
     */
    @isTest
    static void attendanceBlocksTheDeleteEvenWhenMarkedAbsent() {
        Contact c = makeBoardMember('Has Attendance', 'Attendance Block T');
        Id meetingId = BoardManagementController.createMeeting('Blocking Meeting', Date.today());
        List<BoardManagementController.AttendeeRow> rows = BoardManagementController.getAttendance(meetingId);
        System.assert(!rows.isEmpty(), 'the new board member is an eligible attendee');
        for (BoardManagementController.AttendeeRow r : rows) {
            r.attended = false;      // marked ABSENT - still an attendance record
        }
        BoardManagementController.saveAttendance(meetingId, JSON.serialize(rows));

        String caught = null;
        Test.startTest();
        BoardMembersController.DeleteImpact impact = BoardMembersController.getDeleteImpact(c.Id);
        try {
            BoardMembersController.deleteBoardMember(c.Id);
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, impact.blocked, 'the screen is told the delete is blocked');
        System.assertEquals(1, impact.meetingCount, 'one meeting reported back');
        System.assertNotEquals(null, caught, 'the server refuses the delete as well as the screen');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Term__c WHERE Contact__c = :c.Id],
            'the term is still there');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Id = :c.Id], 'and so is the person');
    }

    /** Giving history is a lookup with SetNull, so summaries survive a deleted board record. */
    @isTest
    static void deleteLeavesGivingSummariesBehind() {
        Contact c = makeBoardMember('Has Giving', 'Giving Survives T');
        Date fy = fyStartFor(Date.today());
        Integer before = [SELECT COUNT() FROM Annual_Giving_Summary__c WHERE Contact__c = :c.Id
            AND FY_Start__c = :fy];
        // Guard the baseline: with no summary to begin with, the assertion below would pass
        // whatever the delete did to summaries, and prove nothing.
        System.assert(before > 0, 'there is a giving summary to survive the delete');

        Test.startTest();
        BoardMembersController.deleteBoardMember(c.Id);
        Test.stopTest();

        System.assertEquals(before, [SELECT COUNT() FROM Annual_Giving_Summary__c
            WHERE Contact__c = :c.Id AND FY_Start__c = :fy],
            'the annual giving summary is not deleted with the board record');
    }

    /**
     * The reported UAT case, end to end: ending a term on a date that has already passed must take
     * the member off the roster AND stop the term describing itself as Active.
     */
    @isTest
    static void endingATermInThePastRollsItOff() {
        Contact c = makeBoardMember('Ended In The Past', 'Roll Off T');
        Board_Term__c term = [SELECT Id, Status__c FROM Board_Term__c WHERE Contact__c = :c.Id LIMIT 1];
        System.assertEquals('Active', term.Status__c, 'active while the term is running');

        Test.startTest();
        BoardMembersController.endBoardTerm(term.Id, Date.today().addDays(-30));
        Test.stopTest();

        Board_Term__c after = [SELECT Status__c, Is_Current__c, End_Date__c
            FROM Board_Term__c WHERE Id = :term.Id];
        System.assertEquals('Rolled Off', after.Status__c,
            'a term that ended a month ago no longer reads as Active');
        System.assertEquals(false, after.Is_Current__c, 'and it is off the current roster');
        System.assertEquals(Date.today().addDays(-30), after.End_Date__c, 'the end date is kept');
        System.assertEquals(false, [SELECT Current_Board_Member__c FROM Contact WHERE Id = :c.Id]
            .Current_Board_Member__c, 'the contact is no longer a current board member');
        System.assertEquals(0, BoardMembersController.getCurrentBoardMembers().size(),
            'and they are gone from the roster the console reads');
    }

    /** An end date still in the future leaves the term running - this is not a roll-off. */
    @isTest
    static void endingATermInTheFutureLeavesItActive() {
        Contact c = makeBoardMember('Ends Next Year', 'Future End T');
        Board_Term__c term = [SELECT Id FROM Board_Term__c WHERE Contact__c = :c.Id LIMIT 1];

        Test.startTest();
        BoardMembersController.endBoardTerm(term.Id, Date.today().addMonths(10));
        Test.stopTest();

        Board_Term__c after = [SELECT Status__c, Is_Current__c FROM Board_Term__c WHERE Id = :term.Id];
        System.assertEquals('Active', after.Status__c, 'still active until the date arrives');
        System.assertEquals(true, after.Is_Current__c, 'and still on the roster');
        System.assertEquals(true, [SELECT Current_Board_Member__c FROM Contact WHERE Id = :c.Id]
            .Current_Board_Member__c, 'still flagged as a current board member');
    }

    /**
     * The nightly job, over an expired term.
     *
     * Note what this does and does not prove. The before-trigger now rolls a term off on the way in,
     * so the broken state the sweep exists to repair - Status "Active" sitting on a past End Date -
     * can no longer be written through normal DML, and therefore cannot be staged here. What this
     * covers is that the job runs clean and leaves term and contact consistent. The repair path
     * itself was verified by running rollOffExpiredTerms against the real records in JCRC-Dev that
     * were already in that state.
     */
    @isTest
    static void nightlyJobLeavesExpiredTermsConsistent() {
        Contact c = makeBoardMember('Nightly Case', 'Nightly Sweep T');
        Board_Term__c term = [SELECT Id FROM Board_Term__c WHERE Contact__c = :c.Id LIMIT 1];
        term.End_Date__c = Date.today().addDays(-5);
        update term;

        Test.startTest();
        new BoardMemberFlagRefresh().execute(null);
        Test.stopTest();

        System.assertEquals('Rolled Off', [SELECT Status__c FROM Board_Term__c WHERE Id = :term.Id]
            .Status__c, 'the expired term reads as rolled off after the nightly job');
        System.assertEquals(false, [SELECT Current_Board_Member__c FROM Contact WHERE Id = :c.Id]
            .Current_Board_Member__c, 'and the contact flag is clear');
    }

    /** A historical term entered with dates in the past is recognised as over on the way in. */
    @isTest
    static void aTermEnteredWithPastDatesIsBornRolledOff() {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = 'Historic T',
            Default_Annual_Commitment__c = 1000, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = 'Served Long Ago');
        insert c;

        Test.startTest();
        // No End Date given - setEndDates derives 3 years on from the start, still well in the past.
        Board_Term__c old = new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id,
            Status__c = 'Active', Start_Date__c = Date.today().addYears(-12));
        insert old;
        Test.stopTest();

        System.assertEquals('Rolled Off', [SELECT Status__c FROM Board_Term__c WHERE Id = :old.Id]
            .Status__c, 'a term that ran twelve years ago is not Active');
        System.assertEquals(false, [SELECT Current_Board_Member__c FROM Contact WHERE Id = :c.Id]
            .Current_Board_Member__c, 'and does not make them a current board member');
    }

    /** Nothing to delete is an answered question, not a silent no-op. */
    @isTest
    static void deletingSomeoneWithNoBoardRecordIsRefused() {
        Contact c = new Contact(LastName = 'Never On The Board');
        insert c;

        String caught = null;
        Test.startTest();
        BoardMembersController.DeleteImpact impact = BoardMembersController.getDeleteImpact(c.Id);
        try {
            BoardMembersController.deleteBoardMember(c.Id);
        } catch (AuraHandledException e) {
            caught = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(0, impact.termCount, 'no terms reported');
        System.assertEquals(false, impact.blocked, 'not blocked - just nothing to do');
        System.assertNotEquals(null, caught, 'the caller is told there is no board record');
    }
}
