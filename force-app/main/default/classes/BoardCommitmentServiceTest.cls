/**
 * @description Tests for BoardCommitmentService — commitment derivation (base tiers, $10k elevation via
 *              committee chair / Exec Committee, honorary $0, manual override) and before-save stamping
 *              (Counts Toward Limit, keys). JSI-123 Board Tracking.
 * @author Jason Ott
 * @created 2026-07-28
 */
@isTest
private class BoardCommitmentServiceTest {

    private static final Date FY = Date.newInstance(2026, 7, 1);

    private static Board__c board(String name, Decimal commitment, Integer termLen, Boolean observer) {
        return new Board__c(Name = name, Default_Annual_Commitment__c = commitment,
            Default_Term_Length_Years__c = termLen, Is_Observer__c = observer, Active__c = true);
    }

    private static Board_Membership_Year__c bmy(Id termId, Id contactId, String role) {
        return new Board_Membership_Year__c(Board_Term__c = termId, Contact__c = contactId,
            Role__c = role, FY_Start__c = FY);
    }

    private static Annual_Giving_Summary__c agsFor(Id contactId) {
        return [SELECT Board_Commitment__c, Board_Commitment_Override__c
                FROM Annual_Giving_Summary__c WHERE Contact__c = :contactId AND FY_Start__c = :FY LIMIT 1];
    }

    @isTest
    static void baseTiersAndElevation() {
        Board__c jcrc = board('JCRC Board T', 5000, 6, false);
        Board__c obs  = board('UJA Observer T', 1800, 1, true);
        insert new List<Board__c>{ jcrc, obs };
        Committee__c exec = new Committee__c(Name = 'Executive T', Category__c = 'Board Committee',
            Is_Executive_Committee__c = true, Active__c = true);
        Committee__c dev = new Committee__c(Name = 'Development T', Category__c = 'Board Committee',
            Is_Executive_Committee__c = false, Active__c = true);
        insert new List<Committee__c>{ exec, dev };

        Contact cJcrc = new Contact(LastName = 'JCRC Member');
        Contact cObs = new Contact(LastName = 'Observer Member');
        Contact cChair = new Contact(LastName = 'Committee Chair');
        Contact cExec = new Contact(LastName = 'Exec Member');
        insert new List<Contact>{ cJcrc, cObs, cChair, cExec };

        List<Board_Term__c> terms = new List<Board_Term__c>{
            new Board_Term__c(Contact__c = cJcrc.Id, Board__c = jcrc.Id, Status__c = 'Active', Start_Date__c = FY),
            new Board_Term__c(Contact__c = cObs.Id, Board__c = obs.Id, Status__c = 'Active', Start_Date__c = FY),
            new Board_Term__c(Contact__c = cChair.Id, Board__c = jcrc.Id, Status__c = 'Active', Start_Date__c = FY),
            new Board_Term__c(Contact__c = cExec.Id, Board__c = jcrc.Id, Status__c = 'Active', Start_Date__c = FY)
        };
        insert terms;

        Test.startTest();
        // membership years trigger commitment creation
        insert new List<Board_Membership_Year__c>{
            bmy(terms[0].Id, cJcrc.Id, 'Member'),
            bmy(terms[1].Id, cObs.Id, 'Member'),
            bmy(terms[2].Id, cChair.Id, 'Member'),
            bmy(terms[3].Id, cExec.Id, 'Member')
        };
        // committee assignments raise chair + exec to $10k
        insert new List<Committee_Assignment__c>{
            new Committee_Assignment__c(Contact__c = cChair.Id, Committee__c = dev.Id,
                Committee_Role__c = 'Chair', FY_Start__c = FY, Active__c = true),
            new Committee_Assignment__c(Contact__c = cExec.Id, Committee__c = exec.Id,
                Committee_Role__c = 'Member', FY_Start__c = FY, Active__c = true)
        };
        Test.stopTest();

        System.assertEquals(5000, agsFor(cJcrc.Id).Board_Commitment__c, 'JCRC board base = $5k');
        System.assertEquals(1800, agsFor(cObs.Id).Board_Commitment__c, 'Observer base = $1.8k');
        System.assertEquals(10000, agsFor(cChair.Id).Board_Commitment__c, 'committee chair -> $10k');
        System.assertEquals(10000, agsFor(cExec.Id).Board_Commitment__c, 'Exec Committee member -> $10k');
    }

    @isTest
    static void honoraryAndOverrideAndStamping() {
        Board__c jcrc = board('JCRC Board H', 5000, 6, false);
        insert jcrc;
        Contact cPast = new Contact(LastName = 'Past President');
        Contact cReg = new Contact(LastName = 'Regular Member');
        insert new List<Contact>{ cPast, cReg };
        Board_Term__c tPast = new Board_Term__c(Contact__c = cPast.Id, Board__c = jcrc.Id, Status__c = 'Active', Start_Date__c = FY);
        Board_Term__c tReg = new Board_Term__c(Contact__c = cReg.Id, Board__c = jcrc.Id, Status__c = 'Active', Start_Date__c = FY);
        insert new List<Board_Term__c>{ tPast, tReg };

        Test.startTest();
        Board_Membership_Year__c pastYr = bmy(tPast.Id, cPast.Id, 'Past President');
        Board_Membership_Year__c regYr = bmy(tReg.Id, cReg.Id, 'Member');
        Board_Membership_Year__c offYr = bmy(tReg.Id, cReg.Id, 'President'); // officer year, different key not needed here
        offYr.FY_Start__c = Date.newInstance(2027, 7, 1);
        insert new List<Board_Membership_Year__c>{ pastYr, regYr, offYr };
        Test.stopTest();

        // honorary = $0
        System.assertEquals(0, agsFor(cPast.Id).Board_Commitment__c, 'Past President = $0 commitment');
        // regular = $5k
        System.assertEquals(5000, agsFor(cReg.Id).Board_Commitment__c, 'regular member = $5k');

        // Counts Toward Limit stamping
        Board_Membership_Year__c member = [SELECT Counts_Toward_Limit__c, Fiscal_Year_Label__c, Year_Key__c
            FROM Board_Membership_Year__c WHERE Id = :regYr.Id];
        System.assertEquals(true, member.Counts_Toward_Limit__c, 'Member year counts toward limit');
        System.assertEquals('FY2027', member.Fiscal_Year_Label__c, 'label derived from FY start');
        System.assertNotEquals(null, member.Year_Key__c, 'year key stamped');
        Board_Membership_Year__c officer = [SELECT Counts_Toward_Limit__c FROM Board_Membership_Year__c WHERE Id = :offYr.Id];
        System.assertEquals(false, officer.Counts_Toward_Limit__c, 'officer (President) year does not count');

        // Override: manual value is not overwritten by re-derivation
        Annual_Giving_Summary__c ags = agsFor(cReg.Id);
        ags.Board_Commitment_Override__c = true;
        ags.Board_Commitment__c = 7777;
        update ags;
        update regYr; // re-fires recompute
        System.assertEquals(7777, agsFor(cReg.Id).Board_Commitment__c, 'override preserved');
    }
}
