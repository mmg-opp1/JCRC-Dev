/**
 * @description JSI-90 — Tests for AnnualGivingSummaryRollover: new-year summaries are created with the
 *              prior-year link and inherited Effective Level, and the batch is idempotent.
 * @author Jason Ott
 * @created 2026-07-01
 *
 * Change Log:
 * -----------
 * 2026-07-01 - Jason Ott - Initial version (JSI-90 Phase 3).
 */
@isTest
private class AnnualGivingSummaryRolloverTest {

    @isTest
    static void testRolloverCarriesLevelForward() {
        Giving_Level__c cong = new Giving_Level__c(Name='Congressional', Minimum_Amount__c=5000, Maximum_Amount__c=10000, Sort_Order__c=2, Active__c=true);
        insert cong;
        Contact c = new Contact(LastName='Rollover Donor'); insert c;
        // Prior-year (FY2026) summary at Congressional.
        insert new Annual_Giving_Summary__c(Contact__c=c.Id, FY_Start__c=Date.newInstance(2025,7,1),
            FY_End__c=Date.newInstance(2026,6,30), Fiscal_Year_Label__c='FY2026', Effective_Level__c=cong.Id);

        Test.startTest();
        Database.executeBatch(new AnnualGivingSummaryRollover(Date.newInstance(2026,7,1)), 200);
        Test.stopTest();

        Annual_Giving_Summary__c newAgs = [
            SELECT FY_Start__c, FY_End__c, Prior_Year_Summary__c, Earned_Level__c, Effective_Level__r.Name
            FROM Annual_Giving_Summary__c WHERE Contact__c=:c.Id AND FY_Start__c=2026-07-01];
        System.assertEquals(Date.newInstance(2027,6,30), newAgs.FY_End__c, 'new FY end');
        System.assertNotEquals(null, newAgs.Prior_Year_Summary__c, 'linked to prior year');
        System.assertEquals(null, newAgs.Earned_Level__c, 'no gifts earned yet this year');
        System.assertEquals('Congressional', newAgs.Effective_Level__r.Name, 'inherited level carried forward');
    }

    @isTest
    static void testIdempotentAndSchedulable() {
        Contact c = new Contact(LastName='Idempotent Donor'); insert c;
        insert new Annual_Giving_Summary__c(Contact__c=c.Id, FY_Start__c=Date.newInstance(2025,7,1),
            FY_End__c=Date.newInstance(2026,6,30), Fiscal_Year_Label__c='FY2026');

        Test.startTest();
        // Run twice — the second run must not create a duplicate.
        Database.executeBatch(new AnnualGivingSummaryRollover(Date.newInstance(2026,7,1)), 200);
        Database.executeBatch(new AnnualGivingSummaryRollover(Date.newInstance(2026,7,1)), 200);
        // Exercise the Schedulable + default constructor path too.
        String cron = '0 0 1 1 7 ? 2030';
        System.schedule('JSI90 Rollover Test', cron, new AnnualGivingSummaryRollover());
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Annual_Giving_Summary__c WHERE Contact__c=:c.Id AND FY_Start__c=2026-07-01],
            'exactly one new-year summary (idempotent)');
    }
}
