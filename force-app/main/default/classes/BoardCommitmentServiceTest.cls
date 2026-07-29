/**
 * @description Tests for the board automation (JSI-123): Board Term auto-fills End Date and generates one
 *              Board Membership Year per fiscal year; commitment auto-derives from member type + $10k
 *              chair/exec elevation (honorary $0, override respected); Board Years Served counts only started
 *              non-officer years and trips Must Roll Off at the term length.
 * @author Jason Ott
 * @created 2026-07-28
 */
@isTest
private class BoardCommitmentServiceTest {

    private static Board_Member_Type__c mtype(String name, Decimal commitment, Integer len, Boolean obs) {
        return new Board_Member_Type__c(Name = name, Default_Annual_Commitment__c = commitment,
            Default_Term_Length_Years__c = len, Is_Observer__c = obs, Active__c = true);
    }

    private static Date curFyStart() {
        Date d = Date.today();
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }

    private static Decimal commitmentFor(Id contactId, Date fyStart) {
        return [SELECT Board_Commitment__c FROM Annual_Giving_Summary__c
                WHERE Contact__c = :contactId AND FY_Start__c = :fyStart LIMIT 1].Board_Commitment__c;
    }

    @isTest
    static void autoGeneratesScheduleAndBaseCommitment() {
        Board_Member_Type__c jcrc = mtype('JCRC Recruited T', 5000, 6, false);
        Board_Member_Type__c obs = mtype('UJA Observer T', 1800, 1, true);
        insert new List<Board_Member_Type__c>{ jcrc, obs };
        Contact c = new Contact(LastName = 'JCRC Mbr');
        Contact o = new Contact(LastName = 'Observer Mbr');
        insert new List<Contact>{ c, o };
        Date start = curFyStart();

        Test.startTest();
        Board_Term__c bt = new Board_Term__c(Contact__c = c.Id, Member_Type__c = jcrc.Id,
            Status__c = 'Active', Start_Date__c = start);
        insert bt;
        Board_Term__c bto = new Board_Term__c(Contact__c = o.Id, Member_Type__c = obs.Id,
            Status__c = 'Active', Start_Date__c = start);
        insert bto;
        Test.stopTest();

        Board_Term__c bt2 = [SELECT End_Date__c, Board_Years_Served__c FROM Board_Term__c WHERE Id = :bt.Id];
        System.assertEquals(start.addYears(6).addDays(-1), bt2.End_Date__c, 'End Date = Start + 6y - 1d');
        System.assertEquals(6, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Board_Term__c = :bt.Id],
            '6 membership years auto-generated');
        System.assertEquals(1, [SELECT COUNT() FROM Board_Membership_Year__c WHERE Board_Term__c = :bto.Id],
            'observer term generates 1 year');
        System.assertEquals(5000, commitmentFor(c.Id, start), 'JCRC base commitment $5k for the current year');
        System.assertEquals(1800, commitmentFor(o.Id, start), 'observer base commitment $1.8k');
        System.assertEquals(1, bt2.Board_Years_Served__c, 'only the started (current) year counts yet');
    }

    @isTest
    static void elevationAndMustRollOff() {
        Board_Member_Type__c jcrc = mtype('JCRC Recruited E', 5000, 6, false);
        insert jcrc;
        Committee__c exec = new Committee__c(Name = 'Executive E', Category__c = 'Board Committee',
            Is_Executive_Committee__c = true, Active__c = true);
        insert exec;
        Contact c = new Contact(LastName = 'Exec Mbr');
        insert c;
        Date start = curFyStart().addYears(-5); // 6-yr term, all 6 years started (last = current)

        Test.startTest();
        Board_Term__c bt = new Board_Term__c(Contact__c = c.Id, Member_Type__c = jcrc.Id,
            Status__c = 'Active', Start_Date__c = start);
        insert bt;
        insert new Committee_Assignment__c(Contact__c = c.Id, Committee__c = exec.Id,
            Committee_Role__c = 'Member', FY_Start__c = curFyStart(), Active__c = true);
        Test.stopTest();

        Board_Term__c bt2 = [SELECT Board_Years_Served__c, Must_Roll_Off__c FROM Board_Term__c WHERE Id = :bt.Id];
        System.assertEquals(6, bt2.Board_Years_Served__c, 'all 6 started years count');
        System.assertEquals(true, bt2.Must_Roll_Off__c, '6 >= term length 6 => must roll off');
        System.assertEquals(10000, commitmentFor(c.Id, curFyStart()),
            'Exec Committee member this year => $10k');
    }

    @isTest
    static void yearAdvanceFlipsStartedYears() {
        Board_Member_Type__c jcrc = mtype('JCRC Recruited A', 5000, 6, false);
        insert jcrc;
        Contact c = new Contact(LastName = 'Advance Mbr');
        insert c;
        Board_Term__c bt = new Board_Term__c(Contact__c = c.Id, Member_Type__c = jcrc.Id,
            Status__c = 'Active', Start_Date__c = curFyStart().addYears(-2));
        insert bt;
        // make a started year an officer year so it currently does NOT count -> gives the advance a row to touch
        Board_Membership_Year__c started = [SELECT Id, Role__c FROM Board_Membership_Year__c
            WHERE Board_Term__c = :bt.Id AND FY_Start__c <= :Date.today() ORDER BY FY_Start__c LIMIT 1];
        started.Role__c = 'President';
        update started;

        Test.startTest();
        BoardYearAdvance.run();
        System.schedule('BoardYearAdvance Test JSI123', '0 0 0 1 7 ?', new BoardYearAdvance());
        Test.stopTest();

        // officer year still excluded; the two non-officer started years count
        Board_Term__c bt2 = [SELECT Board_Years_Served__c FROM Board_Term__c WHERE Id = :bt.Id];
        System.assertEquals(2, bt2.Board_Years_Served__c, '2 non-officer started years count; officer year excluded');
    }

    @isTest
    static void pastPresidentZeroAndOverride() {
        Board_Member_Type__c jcrc = mtype('JCRC Recruited P', 5000, 6, false);
        insert jcrc;
        Contact c = new Contact(LastName = 'Past Pres');
        insert c;
        Date start = curFyStart();
        Board_Term__c bt = new Board_Term__c(Contact__c = c.Id, Member_Type__c = jcrc.Id,
            Status__c = 'Active', Start_Date__c = start);
        insert bt;

        Board_Membership_Year__c cur = [SELECT Id, Role__c FROM Board_Membership_Year__c
            WHERE Board_Term__c = :bt.Id AND FY_Start__c = :start LIMIT 1];

        Test.startTest();
        cur.Role__c = 'Past President';
        update cur;
        Test.stopTest();

        System.assertEquals(0, commitmentFor(c.Id, start), 'Past President => $0 commitment');

        Annual_Giving_Summary__c ags = [SELECT Id, Board_Commitment__c, Board_Commitment_Override__c
            FROM Annual_Giving_Summary__c WHERE Contact__c = :c.Id AND FY_Start__c = :start];
        ags.Board_Commitment_Override__c = true;
        ags.Board_Commitment__c = 7777;
        update ags;
        update cur; // re-fires recompute
        System.assertEquals(7777, [SELECT Board_Commitment__c FROM Annual_Giving_Summary__c WHERE Id = :ags.Id]
            .Board_Commitment__c, 'override preserved');
    }
}
