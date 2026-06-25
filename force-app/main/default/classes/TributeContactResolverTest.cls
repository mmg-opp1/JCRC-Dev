/**
 * @description Tests for TributeContactResolver (JSI-89). Exercises the create (no match),
 *              link (single match, fill-blank-only), and ambiguous (2+ matches → flag) paths,
 *              plus name parsing and the recursion guard. Relies on the org's active Contact
 *              duplicate rule for matching; assertions key on exact name/email so matching is
 *              deterministic.
 * @author Jason Ott
 * @created 2026-06-24
 *
 * Change Log:
 * -----------
 * 2026-06-24 - Jason Ott - Initial tests.
 */
@isTest
private class TributeContactResolverTest {

    private static Opportunity newTributeOpp(String honoreeName, String recipName, String recipEmail, String tributeType) {
        return new Opportunity(
            Name = 'Test Gift',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            npsp__Tribute_Type__c = tributeType,
            npsp__Honoree_Name__c = honoreeName,
            npsp__Notification_Recipient_Name__c = recipName,
            npsp__Notification_Recipient_Email__c = recipEmail
        );
    }

    @isTest
    static void parseName_splitsLastTokenAsLastName() {
        System.assertEquals(new String[]{ 'Mary Jane', 'Watson' },
            TributeContactResolver.parseName('  Mary   Jane  Watson '), 'multi-token name');
        System.assertEquals(new String[]{ '', 'Cher' },
            TributeContactResolver.parseName('Cher'), 'single token -> last name only');
        // The case Jason raised: middle name, last token is the surname.
        System.assertEquals(new String[]{ 'Mary Grace', 'Ott' },
            TributeContactResolver.parseName('Mary Grace Ott'), 'Mary Grace Ott');
    }

    @isTest
    static void parseName_stripsSuffixesAndKeepsParticles() {
        // Suffixes (from Name_Parse_Token__mdt) are stripped before the split.
        System.assertEquals(new String[]{ 'John', 'Smith' },
            TributeContactResolver.parseName('John Smith Jr'), 'Jr suffix stripped');
        System.assertEquals(new String[]{ 'John', 'Smith' },
            TributeContactResolver.parseName('John Smith, MD'), 'MD credential + comma');
        // Particles mark where the last name begins → multi-word last names stay intact.
        System.assertEquals(new String[]{ 'Maria', 'van der Berg' },
            TributeContactResolver.parseName('Maria van der Berg'), 'Dutch particle');
        System.assertEquals(new String[]{ 'Robert', 'De La Cruz' },
            TributeContactResolver.parseName('Robert De La Cruz'), 'Spanish particle');
    }

    @isTest
    static void noMatch_createsContactAndLinks() {
        Opportunity opp = newTributeOpp('Zillah Quixotic', 'Yorick Nevermatch', 'yorick.nevermatch@example.org', 'Honor');
        insert opp;

        Test.startTest();
        TributeContactResolver.processOpportunities(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity res = [SELECT npsp__Honoree_Contact__c, npsp__Notification_Recipient_Contact__c,
                                  Tribute_Contact_Needs_Review__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, res.npsp__Honoree_Contact__c, 'honoree contact created/linked');
        System.assertNotEquals(null, res.npsp__Notification_Recipient_Contact__c, 'recipient contact created/linked');
        System.assertEquals(false, res.Tribute_Contact_Needs_Review__c, 'no ambiguity expected');

        Contact recip = [SELECT Email FROM Contact WHERE Id = :res.npsp__Notification_Recipient_Contact__c];
        System.assertEquals('yorick.nevermatch@example.org', recip.Email, 'email set on created recipient');
    }

    @isTest
    static void memorialHonoree_createdAsDeceased() {
        Opportunity opp = newTributeOpp('Departed Soul', null, null, 'Memorial');
        insert opp;

        Test.startTest();
        TributeContactResolver.processOpportunities(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity res = [SELECT npsp__Honoree_Contact__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, res.npsp__Honoree_Contact__c, 'memorial honoree created');
        Contact honoree = [SELECT npsp__Deceased__c FROM Contact WHERE Id = :res.npsp__Honoree_Contact__c];
        System.assertEquals(true, honoree.npsp__Deceased__c, 'memorial honoree flagged Deceased');
    }

    @isTest
    static void singleMatch_linksExistingAndFillsBlankEmail() {
        Contact existing = new Contact(FirstName = 'Grace', LastName = 'Hopper');
        insert existing;

        Opportunity opp = newTributeOpp(null, 'Grace Hopper', 'grace.hopper@example.org', 'Honor');
        insert opp;

        Test.startTest();
        TributeContactResolver.processOpportunities(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity res = [SELECT npsp__Notification_Recipient_Contact__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(existing.Id, res.npsp__Notification_Recipient_Contact__c, 'linked the existing contact');
        Contact updated = [SELECT Email FROM Contact WHERE Id = :existing.Id];
        System.assertEquals('grace.hopper@example.org', updated.Email, 'blank email filled from gift data');
    }

    @isTest
    static void ambiguousMatch_flagsForReview() {
        // Two contacts with the same name → fuzzy rule returns multiple candidates.
        insert new List<Contact>{
            new Contact(FirstName = 'Ada', LastName = 'Lovelace'),
            new Contact(FirstName = 'Ada', LastName = 'Lovelace')
        };

        Opportunity opp = newTributeOpp('Ada Lovelace', null, null, 'Honor');
        insert opp;

        Test.startTest();
        TributeContactResolver.processOpportunities(new List<Id>{ opp.Id });
        Test.stopTest();

        Opportunity res = [SELECT npsp__Honoree_Contact__c, Tribute_Contact_Needs_Review__c
                           FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, res.npsp__Honoree_Contact__c, 'ambiguous → lookup left blank');
        System.assertEquals(true, res.Tribute_Contact_Needs_Review__c, 'ambiguous → flagged for review');
    }

    @isTest
    static void recursionGuard_skipsProcessedOpps() {
        // Insert with NO tribute names so the record-triggered flow does not fire on insert.
        Opportunity opp = new Opportunity(Name = 'Guard Test', StageName = 'Prospecting', CloseDate = Date.today());
        insert opp;
        // Pre-seed the guard, then add a honoree name and update: the flow fires on update but the
        // guard short-circuits, so no Contact is resolved.
        TributeContactResolver.processedOppIds.add(opp.Id);
        opp.npsp__Honoree_Name__c = 'Solo Honoree';

        Test.startTest();
        update opp;
        Test.stopTest();

        Opportunity res = [SELECT npsp__Honoree_Contact__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, res.npsp__Honoree_Contact__c, 'already-processed opp is skipped by the guard');
    }
}
