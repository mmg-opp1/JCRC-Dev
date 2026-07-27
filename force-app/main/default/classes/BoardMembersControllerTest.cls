/**
 * @description Tests for BoardMembersController — verifies the current-board roster and commitment
 *              progress, and that non-current terms are excluded. JSI-123 Board Tracking.
 * @author Jason Ott
 * @created 2026-07-27
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
}
