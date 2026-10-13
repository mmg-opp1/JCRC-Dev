/**
 * @description Tests for the Board Term role sync (BoardTermService.syncRolesFromYears / syncCurrentRoles /
 *              syncAllCurrentRoles): Board Role (Current) on the term follows the Role on the term's current
 *              Board Membership Year. JSI-123 Board Tracking.
 * @author Jason Ott
 * @created 2026-10-13
 *
 * Change Log:
 * -----------
 * 2026-10-13 - Jason Ott - Initial version.
 */
@isTest
private class BoardTermRoleSyncTest {

    private static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }

    /** A 3-year term starting on the given date; the trigger generates its membership years. */
    private static Board_Term__c makeTerm(String lastName, Date start, String role) {
        Board_Member_Type__c mt = new Board_Member_Type__c(Name = lastName + ' Type',
            Default_Annual_Commitment__c = 1000, Default_Term_Length_Years__c = 3, Active__c = true);
        insert mt;
        Contact c = new Contact(LastName = lastName);
        insert c;
        Board_Term__c t = new Board_Term__c(Contact__c = c.Id, Member_Type__c = mt.Id,
            Status__c = 'Active', Start_Date__c = start, Board_Role__c = role);
        insert t;
        return t;
    }

    private static Board_Membership_Year__c yearStarting(Id termId, Date fyStart) {
        return [SELECT Id, Role__c FROM Board_Membership_Year__c
                WHERE Board_Term__c = :termId AND FY_Start__c = :fyStart];
    }

    private static String termRole(Id termId) {
        return [SELECT Board_Role__c FROM Board_Term__c WHERE Id = :termId].Board_Role__c;
    }

    @isTest
    static void currentYearRoleChangeUpdatesTerm() {
        Date thisFy = fyStartFor(Date.today());
        Board_Term__c t = makeTerm('Sync Current', thisFy, 'Member');

        Board_Membership_Year__c y = yearStarting(t.Id, thisFy);
        y.Role__c = 'Treasurer';
        Test.startTest();
        update y;
        Test.stopTest();

        System.assertEquals('Treasurer', termRole(t.Id), 'the current year\'s role is copied to the term');
    }

    @isTest
    static void futureYearRoleChangeLeavesTermAlone() {
        Date thisFy = fyStartFor(Date.today());
        Board_Term__c t = makeTerm('Sync Future', thisFy, 'Member');

        Board_Membership_Year__c y = yearStarting(t.Id, thisFy.addYears(1));
        y.Role__c = 'Treasurer';
        Test.startTest();
        update y;
        Test.stopTest();

        System.assertEquals('Member', termRole(t.Id), 'a future year does not change the current role');
    }

    @isTest
    static void newTermKeepsTheRoleItWasEnteredWith() {
        Date thisFy = fyStartFor(Date.today());
        Test.startTest();
        Board_Term__c t = makeTerm('Sync Seed', thisFy, 'Secretary');
        Test.stopTest();

        System.assertEquals('Secretary', termRole(t.Id), 'the term is not reset to Member');
        System.assertEquals('Secretary', yearStarting(t.Id, thisFy).Role__c,
            'the current year was seeded with the term\'s role');
        System.assertEquals('Member', yearStarting(t.Id, thisFy.addYears(1)).Role__c,
            'later years start as Member');
    }

    @isTest
    static void termNotStartedYetFollowsItsFirstYear() {
        Date nextFy = fyStartFor(Date.today()).addYears(1);
        Board_Term__c t = makeTerm('Sync Not Started', nextFy, 'Member');

        Board_Membership_Year__c first = yearStarting(t.Id, nextFy);
        first.Role__c = 'Vice President';
        Test.startTest();
        update first;
        Test.stopTest();

        System.assertEquals('Vice President', termRole(t.Id), 'no year has started, so the first year counts');
    }

    @isTest
    static void deletingCurrentYearFallsBackToLastYearServed() {
        Date lastFy = fyStartFor(Date.today()).addYears(-1);
        Board_Term__c t = makeTerm('Sync Delete', lastFy, 'Member');

        Board_Membership_Year__c prior = yearStarting(t.Id, lastFy);
        prior.Role__c = 'Chair';
        update prior;
        Board_Membership_Year__c current = yearStarting(t.Id, lastFy.addYears(1));
        current.Role__c = 'President';
        update current;
        System.assertEquals('President', termRole(t.Id), 'setup: the current year drives the term');

        Test.startTest();
        delete current;
        Test.stopTest();

        System.assertEquals('Chair', termRole(t.Id), 'with the current year gone, the last year served counts');
        System.assertEquals(0, [SELECT COUNT() FROM Board_Membership_Year__c
                                WHERE Board_Term__c = :t.Id AND FY_Start__c = :lastFy.addYears(1)],
            'the role copy does not regenerate the deleted year');
    }

    @isTest
    static void nightlySweepCorrectsDrift() {
        Date thisFy = fyStartFor(Date.today());
        Board_Term__c t = makeTerm('Sync Nightly', thisFy, 'Member');
        // Simulate the term going stale (as on July 1, when a different year becomes current).
        update new Board_Term__c(Id = t.Id, Board_Role__c = 'Treasurer');

        Test.startTest();
        BoardTermService.syncAllCurrentRoles();
        Test.stopTest();

        System.assertEquals('Member', termRole(t.Id), 'the sweep puts the current year\'s role back');
    }

    /** The person editing the year is a fundraiser; the term must still follow. */
    @isTest
    static void fundraiserYearEditUpdatesTerm() {
        Date thisFy = fyStartFor(Date.today());
        Board_Term__c t = makeTerm('Sync Fundraiser', thisFy, 'Member');
        Board_Membership_Year__c y = yearStarting(t.Id, thisFy);

        Profile p = [SELECT Id FROM Profile WHERE Name = 'JCRC - Fundraising' LIMIT 1];
        User fundraiser = new User(
            ProfileId = p.Id, LastName = 'Fundraiser', Email = 'role.sync.fundraiser@example.com',
            Username = 'role.sync.fr.' + String.valueOf(System.now().getTime()) + '@example.com.jcrctest',
            Alias = 'rsfr', TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert fundraiser;

        Test.startTest();
        System.runAs(fundraiser) {
            update new Board_Membership_Year__c(Id = y.Id, Role__c = 'Chair');
        }
        Test.stopTest();

        System.assertEquals('Chair', termRole(t.Id), 'a fundraiser\'s edit to the year reaches the term');
    }
}
