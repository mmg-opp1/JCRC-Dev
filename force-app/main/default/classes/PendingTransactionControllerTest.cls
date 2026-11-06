/**
 * @description Tests for PendingTransactionController - the server side of the Pending Transactions screen
 *              (JSI-121 Phase 3). The business rules themselves are covered in PendingTransactionServiceTest;
 *              these check what the screen sends and gets back.
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 * 2026-09-16 - Jason Ott - Phase 4: createTransaction and deleteTransaction.
 * 2026-10-09 - Jason Ott - Source tabs: saveQueue / savedQueue, incl. a JCRC - Fundraising user.
 * 2026-10-09 - Jason Ott - Gala: isGala from source or a gala fund; Event Registration on gala rows only.
 * 2026-11-06 - Jason Ott - getUnpaidRegistrations: which of a contact's registrations are offered.
 */
@IsTest
private class PendingTransactionControllerTest {

    private static final String DONOR_EMAIL = 'dana.controllertest@example.invalid';

    @TestSetup
    static void setup() {
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.DuplicateRuleHeader.allowSave = true;
        Database.insert(new Contact(FirstName = 'Dana', LastName = 'Controllertest', Email = DONOR_EMAIL), opts);
        insert new npsp__General_Accounting_Unit__c(Name = 'Controller Test Fund', npsp__Active__c = true);
    }

    private static Contact donor() {
        return [SELECT Id, AccountId FROM Contact WHERE Email = :DONOR_EMAIL LIMIT 1];
    }

    private static Pending_Transaction__c stage(Decimal amount) {
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks', External_Id__c = 'CT-' + amount,
            Payer_Name__c = 'DANA CONTROLLERTEST', Amount__c = amount, Transaction_Date__c = Date.today(),
            Payment_Method__c = 'ACH/Wire');
        insert row;
        return row;
    }

    private static Opportunity pledge(Contact c) {
        Opportunity p = new Opportunity(Name = 'Controller Pledge', StageName = 'Pledged', Amount = 6000,
            CloseDate = Date.today(), AccountId = c.AccountId, npsp__Primary_Contact__c = c.Id,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pledge').getRecordTypeId());
        insert p;
        delete [SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :p.Id];
        insert new List<npe01__OppPayment__c>{
            new npe01__OppPayment__c(npe01__Opportunity__c = p.Id, npe01__Payment_Amount__c = 3000, npe01__Scheduled_Date__c = Date.today()),
            new npe01__OppPayment__c(npe01__Opportunity__c = p.Id, npe01__Payment_Amount__c = 3000, npe01__Scheduled_Date__c = Date.today().addMonths(1))
        };
        return p;
    }

    @IsTest
    static void workspaceReturnsRowsWithProblemsAndOptions() {
        stage(125);
        Test.startTest();
        PendingTransactionController.Workspace ws = PendingTransactionController.getWorkspace();
        Test.stopTest();

        System.assertEquals(1, ws.rows.size());
        PendingTransactionController.RowInfo r = ws.rows[0];
        System.assertEquals(125, r.amount);
        System.assertEquals('QuickBooks', r.source);
        System.assertEquals('Needs Review', r.status);
        System.assert(!r.problems.isEmpty(), 'problems explain why it is not ready');
        System.assert(!ws.paymentMethods.isEmpty());
        System.assert(!ws.approaches.isEmpty());
        System.assertEquals('NPSP_Default', ws.defaultGiftRecordType);
        Boolean hasInKind = false;
        for (PendingTransactionController.Option o : ws.giftRecordTypes) {
            hasInKind = hasInKind || o.value == 'In_Kind_Gift';
        }
        System.assert(!hasInKind, 'in-kind is not offered for cash');
        Boolean hasFund = false;
        for (PendingTransactionController.Option o : ws.funds) {
            hasFund = hasFund || o.label == 'Controller Test Fund';
        }
        System.assert(hasFund);
        System.assertEquals(false, ws.truncated);
    }

    @IsTest
    static void saveTransactionAppliesEditsAndReevaluates() {
        Contact c = donor();
        Pending_Transaction__c row = stage(80);
        npsp__General_Accounting_Unit__c fund = [SELECT Id FROM npsp__General_Accounting_Unit__c WHERE Name = 'Controller Test Fund'];
        Map<String, Object> edits = new Map<String, Object>{
            'id' => row.Id, 'amount' => '95.50', 'transactionDate' => '2026-09-10', 'contactId' => c.Id,
            'accountId' => null, 'fundId' => fund.Id, 'approach' => 'Other', 'giftName' => '  ', 'notes' => 'wire memo',
            'notAllowed' => 'ignored'
        };
        Test.startTest();
        PendingTransactionController.RowInfo saved = PendingTransactionController.saveTransaction(JSON.serialize(edits));
        Test.stopTest();

        System.assertEquals(95.50, saved.amount);
        System.assertEquals(Date.newInstance(2026, 9, 10), saved.transactionDate);
        System.assertEquals(c.Id, saved.contactId);
        System.assertEquals(c.AccountId, saved.accountId, 'household filled from the contact');
        System.assertEquals('Confirmed', saved.matchStatus);
        System.assertEquals(fund.Id, saved.fundId);
        System.assertEquals(null, saved.giftName, 'blank text clears');
        System.assertEquals('Ready', saved.status);
        System.assert(saved.problems.isEmpty(), saved.problems);
    }

    @IsTest
    static void saveTransactionReportsFriendlyError() {
        Pending_Transaction__c row = stage(10);
        try {
            PendingTransactionController.saveTransaction(JSON.serialize(new Map<String, Object>{
                'id' => row.Id, 'paymentMethod' => 'Not A Method' }));
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
    }

    @IsTest
    static void suggestedDonorCanBeConfirmedSingleAndBulk() {
        Contact c = donor();
        Pending_Transaction__c a = new Pending_Transaction__c(Source__c = 'QuickBooks', Payer_Email__c = DONOR_EMAIL,
            Amount__c = 20, Transaction_Date__c = Date.today());
        Pending_Transaction__c b = new Pending_Transaction__c(Source__c = 'QuickBooks', Payer_Email__c = DONOR_EMAIL,
            Amount__c = 30, Transaction_Date__c = Date.today());
        insert new List<Pending_Transaction__c>{ a, b };

        Test.startTest();
        PendingTransactionController.RowInfo one = PendingTransactionController.confirmDonor(a.Id);
        Integer n = PendingTransactionController.confirmDonors(new List<Id>{ a.Id, b.Id });
        Test.stopTest();

        System.assertEquals(c.Id, one.contactId);
        System.assertEquals('Confirmed', one.matchStatus);
        System.assertEquals('Ready', one.status);
        System.assertEquals(1, n, 'only b was still suggested');
        System.assertEquals('Confirmed', [SELECT Match_Status__c FROM Pending_Transaction__c WHERE Id = :b.Id].Match_Status__c);
    }

    @IsTest
    static void bulkUpdateSetsOnlyTheGivenFields() {
        Pending_Transaction__c a = stage(1);
        Pending_Transaction__c b = stage(2);
        update new List<Pending_Transaction__c>{
            new Pending_Transaction__c(Id = a.Id, Approach__c = 'Phone', Notes__c = 'keep me'),
            new Pending_Transaction__c(Id = b.Id, Approach__c = 'Phone') };
        Test.startTest();
        Integer n = PendingTransactionController.bulkUpdate(new List<Id>{ a.Id, b.Id },
            JSON.serialize(new Map<String, Object>{ 'giftRecordType' => 'Major_Gift', 'approach' => null, 'notes' => 'nope' }));
        Test.stopTest();
        System.assertEquals(2, n);
        for (Pending_Transaction__c r : [SELECT Gift_Record_Type__c, Approach__c, Notes__c FROM Pending_Transaction__c]) {
            System.assertEquals('Major_Gift', r.Gift_Record_Type__c);
            System.assertEquals(null, r.Approach__c, 'sent empty = cleared');
        }
        System.assertEquals('keep me', [SELECT Notes__c FROM Pending_Transaction__c WHERE Id = :a.Id].Notes__c,
            'notes are not bulk-editable');
    }

    @IsTest
    static void pledgesPreviewAndCommitThroughController() {
        Contact c = donor();
        Opportunity p = pledge(c);
        Pending_Transaction__c row = stage(4000);
        PendingTransactionController.saveTransaction(JSON.serialize(new Map<String, Object>{
            'id' => row.Id, 'contactId' => c.Id, 'applyAs' => 'Pledge Payment', 'pledgeId' => p.Id }));
        // The payer name already suggested this donor; choosing the same contact again is not a
        // confirmation, so the user presses "Yes, confirm" as they would on screen.
        System.assertEquals('Suggested', [SELECT Match_Status__c FROM Pending_Transaction__c WHERE Id = :row.Id].Match_Status__c);
        PendingTransactionController.confirmDonor(row.Id);

        Test.startTest();
        List<PendingTransactionController.PledgeInfo> pledges = PendingTransactionController.getOpenPledges(c.Id, null);
        PendingTransactionController.PreviewInfo preview = PendingTransactionController.previewPledgePayment(p.Id, 4000);
        List<PendingTransactionController.ResultInfo> results =
            PendingTransactionController.commitTransactions(new List<Id>{ row.Id });
        Test.stopTest();

        System.assertEquals(1, pledges.size());
        System.assertEquals(6000, pledges[0].outstanding);
        System.assertEquals(2, pledges[0].unpaidCount);
        System.assertEquals(2, pledges[0].unpaid.size());
        System.assert(preview.allowed);
        System.assertEquals(2, preview.steps.size());
        System.assertEquals(1, results.size());
        System.assert(results[0].success, results[0].message);
        System.assertEquals(p.Id, results[0].recordId);
        System.assertEquals(2000, [SELECT npe01__Amount_Outstanding__c FROM Opportunity WHERE Id = :p.Id].npe01__Amount_Outstanding__c);
    }

    @IsTest
    static void commitOverLimitSurfacesAsAuraError() {
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i <= PendingTransactionService.MAX_ROWS_PER_COMMIT; i++) {
            ids.add((Id) (Pending_Transaction__c.SObjectType.getDescribe().getKeyPrefix() + '000000000' + String.valueOf(i).leftPad(3, '0')));
        }
        try {
            PendingTransactionController.commitTransactions(ids);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('at most'), e.getMessage());
        }
    }

    @IsTest
    static void createContactOffersDuplicatesThenCreatesOnRequest() {
        String sameName = JSON.serialize(new Map<String, Object>{ 'firstName' => 'Dana', 'lastName' => 'Controllertest' });
        String fresh = JSON.serialize(new Map<String, Object>{
            'firstName' => 'Brand', 'lastName' => 'Newdonor-Ctl', 'email' => 'brand.new@example.invalid',
            'street' => '1 Main St', 'city' => 'New York', 'state' => 'NY', 'postalCode' => '10001' });

        Test.startTest();
        PendingTransactionController.ContactResult dupes = PendingTransactionController.createContact(sameName, false);
        PendingTransactionController.ContactResult forced = PendingTransactionController.createContact(sameName, true);
        PendingTransactionController.ContactResult created = PendingTransactionController.createContact(fresh, false);
        Test.stopTest();

        System.assertEquals(null, dupes.contactId);
        System.assertEquals(1, dupes.possibleDuplicates.size(), 'fuzzy name rule finds the existing Dana');
        System.assertEquals(donor().Id, dupes.possibleDuplicates[0].value);
        System.assertNotEquals(null, forced.contactId, 'going ahead anyway creates the contact');
        System.assertNotEquals(null, created.contactId);
        Contact c = [SELECT AccountId, MailingCity FROM Contact WHERE Id = :created.contactId];
        System.assertNotEquals(null, c.AccountId, 'NPSP household created');
        System.assertEquals('New York', c.MailingCity);
    }

    @IsTest
    static void createContactRequiresLastName() {
        try {
            PendingTransactionController.createContact(JSON.serialize(new Map<String, Object>{ 'firstName' => 'Only' }), true);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('last name'), e.getMessage());
        }
    }

    @IsTest
    static void createTransactionWithDonorIsManualAndReady() {
        Contact c = donor();
        Test.startTest();
        PendingTransactionController.RowInfo row = PendingTransactionController.createTransaction(JSON.serialize(
            new Map<String, Object>{ 'amount' => '750', 'transactionDate' => '2026-09-15', 'paymentMethod' => 'Check',
                'referenceNumber' => 'CHK 1042', 'contactId' => c.Id, 'notes' => 'hand-delivered',
                'applyAs' => 'Pledge Payment', 'giftName' => 'not settable here' }));
        Test.stopTest();
        System.assertEquals('Manual', row.source);
        System.assertEquals(750, row.amount);
        System.assertEquals('Check', row.paymentMethod);
        System.assertEquals(c.AccountId, row.accountId);
        System.assertEquals('Confirmed', row.matchStatus);
        System.assertEquals('Ready', row.status);
        System.assertEquals('New Gift', row.applyAs, 'routing is chosen in the editor, not the Add form');
        System.assertEquals(null, row.giftName);
    }

    @IsTest
    static void createTransactionFromPayerNameSuggestsDonor() {
        Test.startTest();
        PendingTransactionController.RowInfo row = PendingTransactionController.createTransaction(JSON.serialize(
            new Map<String, Object>{ 'amount' => '60', 'transactionDate' => '2026-09-15', 'payerName' => 'Dana Controllertest' }));
        Test.stopTest();
        System.assertEquals('Dana Controllertest', row.payerName);
        System.assertEquals(donor().Id, row.contactId);
        System.assertEquals('Suggested', row.matchStatus);
        System.assertEquals('Needs Review', row.status);
    }

    @IsTest
    static void createTransactionReportsBadInput() {
        try {
            PendingTransactionController.createTransaction(JSON.serialize(new Map<String, Object>{ 'amount' => 'lots' }));
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
    }

    @IsTest
    static void deleteTransactionRemovesRow() {
        Pending_Transaction__c row = stage(33);
        Test.startTest();
        PendingTransactionController.deleteTransaction(row.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c WHERE Id = :row.Id]);
    }

    /** A user who never chose a tab opens on All; a chosen tab comes back on the next load. */
    @IsTest
    static void savedQueueRoundTrips() {
        System.assertEquals('all', PendingTransactionController.getWorkspace().savedQueue);

        Test.startTest();
        PendingTransactionController.saveQueue('gala');
        Test.stopTest();

        System.assertEquals('gala', PendingTransactionController.getWorkspace().savedQueue);
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction_Preference__c
                                WHERE SetupOwnerId = :UserInfo.getUserId()], 'One record per user');
    }

    /** Choosing again updates the same record rather than adding another. */
    @IsTest
    static void saveQueueUpdatesInPlace() {
        PendingTransactionController.saveQueue('gala');
        PendingTransactionController.saveQueue('quickbooks');
        System.assertEquals('quickbooks', PendingTransactionController.getWorkspace().savedQueue);
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction_Preference__c
                                WHERE SetupOwnerId = :UserInfo.getUserId()]);
    }

    /** Anything that is not one of the tabs is refused. */
    @IsTest
    static void saveQueueRejectsUnknownTab() {
        try {
            PendingTransactionController.saveQueue('everything');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction_Preference__c]);
    }

    /** An org-wide default is ignored: only a person's own choice decides their tab. */
    @IsTest
    static void orgDefaultDoesNotSetEveryonesTab() {
        insert new Pending_Transaction_Preference__c(SetupOwnerId = UserInfo.getOrganizationId(), Queue__c = 'manual');
        System.assertEquals('all', PendingTransactionController.getWorkspace().savedQueue);
    }

    /**
     * A fundraiser (not an admin) can save their own tab. Guards the profile grant: the org restricts
     * custom settings to profiles granted them, and without the grant this fails with "Access to
     * entity 'Pending_Transaction_Preference__c' denied".
     */
    @IsTest
    static void fundraiserCanSaveOwnTab() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'JCRC - Fundraising' LIMIT 1];
        User fundraiser = new User(
            ProfileId = p.Id, LastName = 'Queuefundraiser', Email = 'pt.queue@example.com',
            Username = 'pt.queue.' + String.valueOf(System.now().getTime()) + '@example.com.jcrctest',
            Alias = 'ptqueue', TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert fundraiser;

        Test.startTest();
        System.runAs(fundraiser) {
            PendingTransactionController.saveQueue('gala');
            System.assertEquals('gala', PendingTransactionController.getWorkspace().savedQueue);
        }
        Test.stopTest();
        System.assertEquals('all', PendingTransactionController.getWorkspace().savedQueue,
                            'A fundraiser choosing Gala does not change the admin tab');
    }

    // ---- Gala ---------------------------------------------------------------------------------

    private static Event_Registration__c registration() {
        Event__c gala = new Event__c(Name = 'Controller Gala');
        insert gala;
        Event_Registration__c reg = new Event_Registration__c(Event__c = gala.Id, Donor_Last_Name__c = 'Galatest');
        insert reg;
        return reg;
    }

    private static PendingTransactionController.RowInfo rowFrom(PendingTransactionController.Workspace ws, Id rowId) {
        for (PendingTransactionController.RowInfo r : ws.rows) {
            if (r.id == rowId) {
                return r;
            }
        }
        return null;
    }

    /** A gala-source row takes a registration; the screen gets it back with isGala and the gala fund ids. */
    @IsTest
    static void galaRowTakesEventRegistration() {
        npsp__General_Accounting_Unit__c galaFund = new npsp__General_Accounting_Unit__c(Name = 'Controller Gala Fund',
            npsp__Active__c = true, Gala__c = true);
        insert galaFund;
        Event_Registration__c reg = registration();
        Pending_Transaction__c row = stage(250);
        row.Source__c = 'Gala Website';
        update row;

        Test.startTest();
        PendingTransactionController.saveTransaction(JSON.serialize(new Map<String, Object>{
            'id' => row.Id, 'eventRegistrationId' => reg.Id }));
        PendingTransactionController.Workspace ws = PendingTransactionController.getWorkspace();
        Test.stopTest();

        PendingTransactionController.RowInfo info = rowFrom(ws, row.Id);
        System.assert(info.isGala, 'Gala Website is gala');
        System.assertEquals(reg.Id, info.eventRegistrationId);
        System.assertNotEquals(null, info.eventRegistrationName);
        System.assert(ws.galaFundIds.contains(galaFund.Id), 'Gala funds listed for the editor');
    }

    /** A QuickBooks row becomes gala through a gala fund - and only then may it take a registration. */
    @IsTest
    static void quickBooksRowIsGalaOnlyWithGalaFund() {
        npsp__General_Accounting_Unit__c galaFund = new npsp__General_Accounting_Unit__c(Name = 'QB Gala Fund',
            npsp__Active__c = true, Gala__c = true);
        insert galaFund;
        Event_Registration__c reg = registration();
        Pending_Transaction__c row = stage(300);

        // Not gala yet: the registration is refused and nothing is saved.
        try {
            PendingTransactionController.saveTransaction(JSON.serialize(new Map<String, Object>{
                'id' => row.Id, 'eventRegistrationId' => reg.Id }));
            System.assert(false, 'expected the gala-only rule to refuse');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('gala'), e.getMessage());
        }
        System.assertEquals(null, [SELECT Event_Registration__c FROM Pending_Transaction__c WHERE Id = :row.Id].Event_Registration__c);

        // With the gala fund, the same save goes through and the row is gala.
        Test.startTest();
        PendingTransactionController.RowInfo info = PendingTransactionController.saveTransaction(JSON.serialize(
            new Map<String, Object>{ 'id' => row.Id, 'fundId' => galaFund.Id, 'eventRegistrationId' => reg.Id }));
        Test.stopTest();
        System.assert(info.isGala, 'QuickBooks + gala fund is gala');
        System.assertEquals(reg.Id, info.eventRegistrationId);
    }

    /**
     * Only the contact's unpaid registrations for a Gala event that can still take money are offered:
     * not paid ones, not other events (Galaxy is not Gala), not one claimed by another pending
     * transaction, not one whose gift is already settled. One with an open pledge carries the pledge.
     */
    @IsTest
    static void unpaidRegistrationsOffersOnlyWhatCanTakeThisMoney() {
        Contact c = donor();
        Event__c gala = new Event__c(Name = '2027 Gala');
        Event__c dinner = new Event__c(Name = 'Annual Dinner');
        Event__c galaxy = new Event__c(Name = 'Galaxy Night');
        insert new List<Event__c>{ gala, dinner, galaxy };
        Opportunity p = pledge(c);
        Opportunity settled = new Opportunity(Name = 'Settled gift', StageName = 'Posted', CloseDate = Date.today(),
            Amount = 100, AccountId = c.AccountId);
        insert settled;
        Pending_Transaction__c row = stage(500);
        Pending_Transaction__c other = stage(600);

        Event_Registration__c open = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id,
            Sponsorship_Level__c = 'Friend', Number_of_Tickets__c = 1, Sponsorship_Donation_Amount__c = 1500);
        Event_Registration__c withPledge = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id,
            Opportunity__c = p.Id, Sponsorship_Donation_Amount__c = 6000);
        Event_Registration__c ownClaim = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id,
            Pending_Transaction__c = row.Id);
        Event_Registration__c paid = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id, Paid__c = true);
        Event_Registration__c notGala = new Event_Registration__c(Event__c = dinner.Id, Contact__c = c.Id);
        Event_Registration__c galaxyReg = new Event_Registration__c(Event__c = galaxy.Id, Contact__c = c.Id);
        Event_Registration__c giftSettled = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id,
            Opportunity__c = settled.Id);
        Event_Registration__c claimedByOther = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id);
        Event_Registration__c claimedOnRegistration = new Event_Registration__c(Event__c = gala.Id, Contact__c = c.Id,
            Pending_Transaction__c = other.Id);
        insert new List<Event_Registration__c>{ open, withPledge, ownClaim, paid, notGala, galaxyReg, giftSettled,
            claimedByOther, claimedOnRegistration };
        update new Pending_Transaction__c(Id = other.Id, Source__c = 'Gala Website', Event_Registration__c = claimedByOther.Id);

        Test.startTest();
        List<PendingTransactionController.RegistrationInfo> offered =
            PendingTransactionController.getUnpaidRegistrations(row.Id, c.Id);
        List<PendingTransactionController.RegistrationInfo> nobody =
            PendingTransactionController.getUnpaidRegistrations(row.Id, null);
        Test.stopTest();

        Map<Id, PendingTransactionController.RegistrationInfo> byId = new Map<Id, PendingTransactionController.RegistrationInfo>();
        for (PendingTransactionController.RegistrationInfo r : offered) {
            byId.put(r.id, r);
        }
        System.assertEquals(new Set<Id>{ open.Id, withPledge.Id, ownClaim.Id }, byId.keySet());
        PendingTransactionController.RegistrationInfo o = byId.get(open.Id);
        System.assertEquals('2027 Gala', o.eventName);
        System.assertEquals('Friend', o.level);
        System.assertEquals(1500, o.amount);
        System.assertEquals(null, o.pledgeId, 'No gift yet - a new gift');
        System.assert(o.summary.contains('2027 Gala') && o.summary.endsWith('Unpaid'), o.summary);
        System.assertEquals(p.Id, byId.get(withPledge.Id).pledgeId, 'Open pledge - pay it instead');
        System.assertEquals(6000, byId.get(withPledge.Id).pledgeOutstanding);
        System.assert(nobody.isEmpty(), 'No contact, nothing to offer');
    }
}
