/**
 * @description Tests for GalaAutomationService: auto-create tables from a level + stamp the FMV split;
 *              seats-filled maintenance; stamp the guest's Opportunity from its table; and the
 *              Add-as-Contact find-or-create resolver. JSI Gala Event Gifts.
 * @author Jason Ott
 * @created 2026-07-31
 */
@isTest
private class GalaAutomationServiceTest {

    private static String openStage() {
        for (OpportunityStage s : [SELECT MasterLabel FROM OpportunityStage
                WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1]) {
            return s.MasterLabel;
        }
        return 'Prospecting';
    }

    private static Id eventRT() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Event_Registration').getRecordTypeId();
    }

    @isTest
    static void autoCreateTablesAndFmv() {
        Gala_Level__c lvl = new Gala_Level__c(Name = 'Diamond (Test)', Price__c = 20000,
            Seats_Included__c = 20, Tables_Included__c = 2, Non_Deductible_Amount__c = 2000, Active__c = true);
        insert lvl;
        Account a = new Account(Name = 'Sponsor Co');
        insert a;

        Test.startTest();
        Opportunity o = new Opportunity(Name = 'Gala Sponsor', AccountId = a.Id, StageName = openStage(),
            CloseDate = Date.today().addDays(30), Amount = 20000, RecordTypeId = eventRT(), Gala_Level__c = lvl.Id);
        insert o;
        Test.stopTest();

        System.assertEquals(2000, [SELECT Non_Deductible_Amount__c FROM Opportunity WHERE Id = :o.Id]
            .Non_Deductible_Amount__c, 'FMV stamped from the level');
        List<Gala_Table__c> tables = [SELECT Capacity__c FROM Gala_Table__c WHERE Opportunity__c = :o.Id];
        System.assertEquals(2, tables.size(), '2 tables auto-created');
        System.assertEquals(10, tables[0].Capacity__c, '20 seats / 2 tables = 10 each');

        update o; // idempotent — no duplicate tables
        System.assertEquals(2, [SELECT COUNT() FROM Gala_Table__c WHERE Opportunity__c = :o.Id],
            're-save does not duplicate tables');
    }

    @isTest
    static void seatsGuestOppAndResolve() {
        Gala_Level__c lvl = new Gala_Level__c(Name = 'Table (Test)', Price__c = 5000,
            Seats_Included__c = 10, Tables_Included__c = 1, Non_Deductible_Amount__c = 1000, Active__c = true);
        insert lvl;
        Account a = new Account(Name = 'Table Buyer');
        insert a;
        Opportunity o = new Opportunity(Name = 'Gala Table', AccountId = a.Id, StageName = openStage(),
            CloseDate = Date.today().addDays(30), Amount = 5000, RecordTypeId = eventRT(), Gala_Level__c = lvl.Id);
        insert o;
        Gala_Table__c t = [SELECT Id FROM Gala_Table__c WHERE Opportunity__c = :o.Id LIMIT 1];
        Contact existing = new Contact(FirstName = 'Sam', LastName = 'Existing');
        insert existing;

        Test.startTest();
        Gala_Guest__c g1 = new Gala_Guest__c(Gala_Table__c = t.Id, First_Name__c = 'Sam',
            Last_Name__c = 'Existing', Add_as_Contact__c = true);
        Gala_Guest__c g2 = new Gala_Guest__c(Gala_Table__c = t.Id, First_Name__c = 'New',
            Last_Name__c = 'Guest', Add_as_Contact__c = true);
        insert new List<Gala_Guest__c>{ g1, g2 };
        Test.stopTest();

        System.assertEquals(2, [SELECT Seats_Filled__c FROM Gala_Table__c WHERE Id = :t.Id].Seats_Filled__c,
            'seats filled counts guests');
        System.assertEquals(o.Id, [SELECT Opportunity__c FROM Gala_Guest__c WHERE Id = :g1.Id].Opportunity__c,
            'guest opportunity stamped from the table');

        Gala_Guest__c r1 = [SELECT Contact__c, Add_as_Contact__c FROM Gala_Guest__c WHERE Id = :g1.Id];
        System.assertEquals(existing.Id, r1.Contact__c, 'linked to the existing contact');
        System.assertEquals(false, r1.Add_as_Contact__c, 'flag cleared after resolve');
        Gala_Guest__c r2 = [SELECT Contact__c, Add_as_Contact__c FROM Gala_Guest__c WHERE Id = :g2.Id];
        System.assertNotEquals(null, r2.Contact__c, 'new contact created + linked');

        delete g2;
        System.assertEquals(1, [SELECT Seats_Filled__c FROM Gala_Table__c WHERE Id = :t.Id].Seats_Filled__c,
            'seats filled decrements when a guest is removed');
    }

    @isTest
    static void ambiguousMatchFlagsForReview() {
        insert new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Ambiguous'),
            new Contact(FirstName = 'John', LastName = 'Ambiguous')
        };
        Test.startTest();
        Gala_Guest__c g = new Gala_Guest__c(First_Name__c = 'John', Last_Name__c = 'Ambiguous',
            Add_as_Contact__c = true);
        insert g;
        Test.stopTest();

        Gala_Guest__c r = [SELECT Contact__c, Add_as_Contact__c, Contact_Match_Needs_Review__c
            FROM Gala_Guest__c WHERE Id = :g.Id];
        System.assertEquals(null, r.Contact__c, '2+ matches -> lookup left blank');
        System.assertEquals(true, r.Contact_Match_Needs_Review__c, '2+ matches -> flagged for review');
        System.assertEquals(false, r.Add_as_Contact__c, 'flag cleared after handling');
    }
}
