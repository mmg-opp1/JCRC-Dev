/**
 * @description JSI-90 — Tests for GiftAllocationService (reconciler): hard/soft crediting, In-Kind
 *              exclusion, role filtering, fiscal-year placement, accumulation + upgrade, date-achieved
 *              stamping/clearing, inheritance, dedupe, and the change/delete scenarios (amount change,
 *              close-date fiscal-year move, donor change, un-win, delete, soft-credit removal).
 * @author Jason Ott
 * @created 2026-07-01
 *
 * Change Log:
 * -----------
 * 2026-07-01 - Jason Ott - Initial version (JSI-90 Phase 3).
 * 2026-07-01 - Jason Ott - Added reconcile/delete scenario tests. JSI-90 Phase 3.
 */
@isTest
private class GiftAllocationServiceTest {

    @testSetup
    static void setup() {
        insert new List<Giving_Level__c>{
            new Giving_Level__c(Name='Base', Minimum_Amount__c=0, Maximum_Amount__c=5000, Sort_Order__c=1, Active__c=true),
            new Giving_Level__c(Name='Congressional', Minimum_Amount__c=5000, Maximum_Amount__c=10000, Sort_Order__c=2, Active__c=true),
            new Giving_Level__c(Name='Senate', Minimum_Amount__c=10000, Sort_Order__c=3, Active__c=true)
        };
    }

    // ---- helpers ----
    private static Contact makeContact(String last) {
        Contact c = new Contact(LastName=last);
        insert c;
        return [SELECT Id, AccountId FROM Contact WHERE Id=:c.Id];
    }
    private static Opportunity makeGift(Contact primary, Decimal amount, Date closeDate, Id recordTypeId) {
        Opportunity o = new Opportunity(Name='Gift '+last3(primary.Id)+' '+amount, StageName='Posted',
            CloseDate=closeDate, Amount=amount, AccountId=primary.AccountId, npsp__Primary_Contact__c=primary.Id);
        if (recordTypeId != null) o.RecordTypeId = recordTypeId;
        insert o;
        return o;
    }
    private static String last3(Id i){ String s=String.valueOf(i); return s.substring(s.length()-3); }
    private static Id rtId(String dev){ return [SELECT Id FROM RecordType WHERE SobjectType='Opportunity' AND DeveloperName=:dev LIMIT 1].Id; }
    // Reconcile authoritatively (clears the transaction guard first).
    private static void resync(Id oppId){ GiftAllocationService.processedOppIds.clear(); GiftAllocationService.reconcile(new Set<Id>{oppId}); }
    private static Annual_Giving_Summary__c ags(Id contactId, Date fyStart){
        List<Annual_Giving_Summary__c> l = [SELECT Id, Total_Hard_Credit__c, Total_Soft_Credit__c, Total_Giving__c,
            Earned_Level__r.Name, Effective_Level__r.Name, Date_Achieved_Congressional__c, Date_Achieved_Senate__c
            FROM Annual_Giving_Summary__c WHERE Contact__c=:contactId AND FY_Start__c=:fyStart];
        return l.isEmpty() ? null : l[0];
    }
    private static final Date FY27 = Date.newInstance(2026,7,1);
    private static final Date FY26 = Date.newInstance(2025,7,1);

    // ---- creation / crediting ----
    @isTest
    static void testHardAndSoftAllocations() {
        Contact donor=makeContact('Donor'), hh=makeContact('HH'), infl=makeContact('Infl');
        Opportunity o = makeGift(donor, 5000, Date.newInstance(2026,11,25), null);
        insert new List<OpportunityContactRole>{
            new OpportunityContactRole(OpportunityId=o.Id, ContactId=hh.Id, Role='Household Member'),
            new OpportunityContactRole(OpportunityId=o.Id, ContactId=infl.Id, Role='Influencer')};
        Test.startTest(); resync(o.Id); Test.stopTest();

        Annual_Giving_Summary__c d = ags(donor.Id, FY27);
        System.assertEquals(5000, d.Total_Hard_Credit__c, 'donor hard');
        System.assertEquals('Congressional', d.Earned_Level__r.Name, 'donor level');
        System.assertEquals(Date.newInstance(2026,11,25), d.Date_Achieved_Congressional__c, 'date achieved');
        System.assertEquals(5000, ags(hh.Id, FY27).Total_Soft_Credit__c, 'hh soft');
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Contact__c=:infl.Id], 'influencer excluded');
    }

    @isTest
    static void testInKindExcluded() {
        Contact donor=makeContact('InKind');
        Opportunity o = makeGift(donor, 5000, Date.newInstance(2026,11,25), rtId('In_Kind_Gift'));
        Test.startTest(); resync(o.Id); Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id], 'in-kind excluded');
    }

    @isTest
    static void testAccumulateUpgradeInheritanceAndInvocable() {
        Contact donor=makeContact('Big');
        Opportunity o1 = makeGift(donor, 5000, Date.newInstance(2026,9,1), null);
        Opportunity o2 = makeGift(donor, 6000, Date.newInstance(2026,12,1), null);
        Test.startTest();
        resync(o1.Id); resync(o2.Id);
        // exercise the invocable entry point too
        GiftAllocationService.processedOppIds.clear();
        GiftAllocationService.Request req = new GiftAllocationService.Request(); req.opportunityId=o1.Id;
        GiftAllocationService.syncGiftAllocations(new List<GiftAllocationService.Request>{req});
        Test.stopTest();
        Annual_Giving_Summary__c a = ags(donor.Id, FY27);
        System.assertEquals(11000, a.Total_Hard_Credit__c, 'accumulated');
        System.assertEquals('Senate', a.Earned_Level__r.Name, 'upgraded');
        System.assertNotEquals(null, a.Date_Achieved_Congressional__c, 'congressional date');
        System.assertNotEquals(null, a.Date_Achieved_Senate__c, 'senate date');
        System.assertEquals(2, [SELECT COUNT() FROM Gift_Allocation__c WHERE Contact__c=:donor.Id], 'no duplicates');
    }

    @isTest
    static void testInheritanceFromPriorYear() {
        Contact donor=makeContact('Loyal');
        Giving_Level__c cong=[SELECT Id FROM Giving_Level__c WHERE Name='Congressional' LIMIT 1];
        insert new Annual_Giving_Summary__c(Contact__c=donor.Id, FY_Start__c=FY26, FY_End__c=Date.newInstance(2026,6,30),
            Fiscal_Year_Label__c='FY2026', Effective_Level__c=cong.Id);
        Opportunity o = makeGift(donor, 1000, Date.newInstance(2026,9,1), null);
        Test.startTest(); resync(o.Id); Test.stopTest();
        Annual_Giving_Summary__c a = ags(donor.Id, FY27);
        System.assertEquals('Base', a.Earned_Level__r.Name, 'earned base');
        System.assertEquals('Congressional', a.Effective_Level__r.Name, 'inherited congressional');
    }

    @isTest
    static void testFiscalYearFirstHalf() {
        Contact donor=makeContact('Spring');
        Opportunity o = makeGift(donor, 5000, Date.newInstance(2026,3,15), null);
        Test.startTest(); resync(o.Id); Test.stopTest();
        System.assertNotEquals(null, ags(donor.Id, FY26), 'Jan-Jun close -> prior July FY');
    }

    // ---- change / delete scenarios ----
    @isTest
    static void testAmountChangeClearsLevelAndDate() {
        Contact donor=makeContact('AmtChg');
        Opportunity o = makeGift(donor, 5000, Date.newInstance(2026,11,25), null);
        resync(o.Id);
        System.assertEquals('Congressional', ags(donor.Id, FY27).Earned_Level__r.Name, 'starts Congressional');
        Test.startTest();
        o.Amount = 1000; update o;
        resync(o.Id);
        Test.stopTest();
        Annual_Giving_Summary__c a = ags(donor.Id, FY27);
        System.assertEquals(1000, a.Total_Hard_Credit__c, 'amount updated');
        System.assertEquals('Base', a.Earned_Level__r.Name, 'downgraded to Base');
        System.assertEquals(null, a.Date_Achieved_Congressional__c, 'congressional date cleared on downgrade');
    }

    @isTest
    static void testCloseDateMovesFiscalYear() {
        Contact donor=makeContact('DateMove');
        Opportunity o = makeGift(donor, 6000, Date.newInstance(2026,11,25), null); // FY2027
        resync(o.Id);
        System.assertEquals(6000, ags(donor.Id, FY27).Total_Hard_Credit__c, 'starts in FY2027');
        Test.startTest();
        o.CloseDate = Date.newInstance(2025,11,25); update o; // -> FY2026
        resync(o.Id);
        Test.stopTest();
        System.assertEquals(6000, ags(donor.Id, FY26).Total_Hard_Credit__c, 'moved to FY2026');
        System.assertEquals(0, ags(donor.Id, FY27).Total_Hard_Credit__c, 'FY2027 emptied');
        Gift_Allocation__c ga = [SELECT Annual_Giving_Summary__r.FY_Start__c FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id];
        System.assertEquals(FY26, ga.Annual_Giving_Summary__r.FY_Start__c, 'allocation reparented to FY2026');
    }

    @isTest
    static void testDonorChange() {
        Contact a=makeContact('DonorA'), b=makeContact('DonorB');
        Opportunity o = makeGift(a, 6000, Date.newInstance(2026,11,25), null);
        resync(o.Id);
        System.assertEquals(6000, ags(a.Id, FY27).Total_Hard_Credit__c, 'A credited first');
        Test.startTest();
        o.npsp__Primary_Contact__c = b.Id; update o;
        resync(o.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Contact__c=:a.Id], 'A allocation removed');
        System.assertEquals(6000, ags(b.Id, FY27).Total_Hard_Credit__c, 'B now credited');
    }

    @isTest
    static void testUnwinRemovesAllocations() {
        Contact donor=makeContact('Unwin');
        Opportunity o = makeGift(donor, 6000, Date.newInstance(2026,11,25), null);
        resync(o.Id);
        System.assertEquals(1, [SELECT COUNT() FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id], 'credited while won');
        Test.startTest();
        o.StageName = 'Prospecting'; update o; // no longer won
        resync(o.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id], 'allocations removed on un-win');
        System.assertEquals(0, ags(donor.Id, FY27).Total_Hard_Credit__c, 'total zeroed');
    }

    @isTest
    static void testDeleteRemovesAllocations() {
        Contact donor=makeContact('Del');
        Opportunity o = makeGift(donor, 6000, Date.newInstance(2026,11,25), null);
        resync(o.Id);
        System.assertEquals(1, [SELECT COUNT() FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id], 'credited');
        Test.startTest();
        GiftAllocationService.Request req = new GiftAllocationService.Request();
        req.opportunityId=o.Id; req.isDelete=true;
        GiftAllocationService.syncGiftAllocations(new List<GiftAllocationService.Request>{req});
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Opportunity__c=:o.Id], 'allocations deleted');
        System.assertEquals(0, ags(donor.Id, FY27).Total_Hard_Credit__c, 'total zeroed on delete');
    }

    @isTest
    static void testSoftCreditRemovedOnResync() {
        Contact donor=makeContact('SoftDonor'), hh=makeContact('SoftHH');
        Opportunity o = makeGift(donor, 6000, Date.newInstance(2026,11,25), null);
        OpportunityContactRole ocr = new OpportunityContactRole(OpportunityId=o.Id, ContactId=hh.Id, Role='Household Member');
        insert ocr;
        resync(o.Id);
        System.assertEquals(6000, ags(hh.Id, FY27).Total_Soft_Credit__c, 'hh soft credited');
        Test.startTest();
        delete ocr;
        resync(o.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Gift_Allocation__c WHERE Contact__c=:hh.Id], 'soft allocation removed');
        System.assertEquals(0, ags(hh.Id, FY27).Total_Soft_Credit__c, 'hh soft zeroed');
    }
}
