/**
 * @description Tests for QuickBooksEventProcessor, QuickBooksApi and QuickBooksSweeper (JSI-121 Phase 5b).
 *
 *              The mock QuickBooks serves the shapes of the real sandbox records captured on 2026-09-17:
 *              deposit 145 (a direct Wire-Transfer line from Diego Rodriguez), payment 146 (in Undeposited
 *              Funds, paying invoice 67) deposited by deposit 147, and invoice 67 whose two lines carry two
 *              different classes (Development:Dinner and Development, as in deposit 151 of 2026-10-23). Variations cover check and cash lines, a payment deposited straight to the
 *              bank, updates, deletes, retries and the customer link.
 *
 *              Each test processes ONE event after Test.startTest(): Salesforce refuses a callout after a
 *              database write in the same transaction, and a test is one transaction (the real batch gives every
 *              event its own). Earlier history - pending rows, earlier events - is inserted before startTest.
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5b).
 * 2026-09-23 - Jason Ott - Phase 5c: a committed line is never re-created.
 * 2026-10-23 - Jason Ott - Checks are imported like ACH/wire: check line, deposited check payment, default and setting
 *                          method names, large-deposit bulk reads and callout-budget failure; the mock answers queries;
 *                          and cash still skipped (replaces checkLineIsSkipped).
 * 2026-10-23 - Jason Ott - Fund from the QuickBooks class: fixtures carry ClassRef, the fund map is keyed by class
 *                          name; new tests for case-insensitive matching, a line with no class, the sales
 *                          receipt's own class and an unclassified item line.
 */
@IsTest
private class QuickBooksEventProcessorTest {

    private static final String REALM = '9341457933630133';

    // ---- mock QuickBooks ------------------------------------------------------------------------

    private class MockQuickBooks implements HttpCalloutMock {
        Map<String, String> bodies = new Map<String, String>();
        Map<String, Map<String, Object>> records = new Map<String, Map<String, Object>>();
        Integer forcedStatus;
        Integer calls = 0;
        Integer queries = 0;

        MockQuickBooks put(String entityPath, Map<String, Object> record) {
            String entity = entityPath.substringBefore('/');
            String root = entity == 'deposit' ? 'Deposit' : entity == 'payment' ? 'Payment'
                : entity == 'salesreceipt' ? 'SalesReceipt' : entity == 'invoice' ? 'Invoice'
                : entity == 'customer' ? 'Customer' : entity == 'account' ? 'Account' : 'PaymentMethod';
            bodies.put('/' + entityPath + '?', JSON.serialize(new Map<String, Object>{ root => record }));
            records.put(entityPath, record);
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            System.assert(req.getEndpoint().startsWith('callout:Quickbooks/v3/company/' + REALM + '/'), req.getEndpoint());
            if (forcedStatus != null) {
                res.setStatusCode(forcedStatus);
                res.setBody('{"Fault":{"Error":[{"Message":"Service unavailable"}]}}');
                return res;
            }
            // "select * from Payment where Id in ('146', '147') ..." answers with the stored records it names.
            if (req.getEndpoint().contains('/query?query=')) {
                queries++;
                String q = EncodingUtil.urlDecode(req.getEndpoint().substringAfter('query=').substringBefore('&'), 'UTF-8');
                String entity = q.substringAfter('from ').substringBefore(' ');
                List<Object> found = new List<Object>();
                for (String id : q.substringBetween('(', ')').split(',')) {
                    Map<String, Object> rec = records.get(entity.toLowerCase() + '/' + id.trim().remove('\''));
                    if (rec != null) {
                        found.add(rec);
                    }
                }
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'QueryResponse' => new Map<String, Object>{ entity => found } }));
                return res;
            }
            for (String key : bodies.keySet()) {
                if (req.getEndpoint().contains(key)) {
                    res.setStatusCode(200);
                    res.setBody(bodies.get(key));
                    return res;
                }
            }
            res.setStatusCode(400);
            res.setBody('{"Fault":{"Error":[{"Message":"Object Not Found"}],"type":"ValidationFault"}}');
            return res;
        }
    }

    private static Map<String, Object> ref(String value, String name) {
        Map<String, Object> m = new Map<String, Object>{ 'value' => value };
        if (name != null) {
            m.put('name', name);
        }
        return m;
    }

    /** Deposit 145: one direct Wire-Transfer line from customer 4, class Development:Dinner. */
    private static Map<String, Object> deposit145(Decimal amount, String methodName) {
        return new Map<String, Object>{
            'Id' => '145', 'TxnDate' => '2026-09-17', 'TotalAmt' => amount, 'DepositToAccountRef' => ref('35', 'Checking'),
            'Line' => new List<Object>{ new Map<String, Object>{
                'Id' => '1', 'LineNum' => 1, 'Description' => 'TEST TRANSACTION', 'Amount' => amount,
                'DetailType' => 'DepositLineDetail',
                'DepositLineDetail' => new Map<String, Object>{
                    'Entity' => new Map<String, Object>{ 'value' => '4', 'name' => 'Diego Rodriguez', 'type' => 'CUSTOMER' },
                    'AccountRef' => ref('85', 'Billable Expense Income'),
                    'ClassRef' => ref('1000000003', 'Development:Dinner'),
                    'PaymentMethodRef' => ref(methodName == 'Check' ? '2' : '1000000001', methodName),
                    'CheckNum' => '123456' } } } };
    }

    /** Payment 146 in Undeposited Funds, paying invoice 67; deposit 147 deposits it (payment method as id only). */
    private static MockQuickBooks realSandbox() {
        MockQuickBooks m = new MockQuickBooks();
        m.put('deposit/145', deposit145(180.00, 'Wire-Transfer'));
        m.put('payment/146', new Map<String, Object>{
            'Id' => '146', 'TxnDate' => '2026-09-17', 'TotalAmt' => 239.00, 'PaymentRefNum' => '12345',
            'CustomerRef' => ref('1', 'Amy\'s Bird Sanctuary'), 'DepositToAccountRef' => ref('4', null),
            'PaymentMethodRef' => ref('1000000001', null),
            'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => '147', 'TxnType' => 'Deposit' } },
            'Line' => new List<Object>{ new Map<String, Object>{ 'Amount' => 239.00,
                'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => '67', 'TxnType' => 'Invoice' } } } } });
        m.put('deposit/147', new Map<String, Object>{
            'Id' => '147', 'TxnDate' => '2026-09-17', 'TotalAmt' => 239.00, 'DepositToAccountRef' => ref('35', 'Checking'),
            'Line' => new List<Object>{ new Map<String, Object>{ 'Description' => 'test memo', 'Amount' => 239.00,
                'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => '146', 'TxnType' => 'Payment', 'TxnLineId' => '0' } },
                'DepositLineDetail' => new Map<String, Object>{ 'PaymentMethodRef' => ref('1000000001', null), 'CheckNum' => '12345' } } } });
        m.put('invoice/67', new Map<String, Object>{
            'Id' => '67', 'CustomerRef' => ref('1', 'Amy\'s Bird Sanctuary'),
            'Line' => new List<Object>{
                new Map<String, Object>{ 'Amount' => 150, 'DetailType' => 'SalesItemLineDetail',
                    'SalesItemLineDetail' => new Map<String, Object>{ 'ItemAccountRef' => ref('49', 'Plants and Soil'),
                        'ClassRef' => ref('1000000003', 'Development:Dinner') } },
                new Map<String, Object>{ 'Amount' => 275, 'DetailType' => 'SalesItemLineDetail',
                    'SalesItemLineDetail' => new Map<String, Object>{ 'ItemAccountRef' => ref('48', 'Fountains'),
                        'ClassRef' => ref('1000000001', 'Development') } },
                new Map<String, Object>{ 'Amount' => 425, 'DetailType' => 'SubTotalLineDetail' } } });
        m.put('customer/4', new Map<String, Object>{ 'Id' => '4', 'DisplayName' => 'Diego Rodriguez',
            'PrimaryEmailAddr' => new Map<String, Object>{ 'Address' => 'Diego@Rodriguez.com' } });
        m.put('customer/1', new Map<String, Object>{ 'Id' => '1', 'DisplayName' => 'Amy\'s Bird Sanctuary',
            'PrimaryEmailAddr' => new Map<String, Object>{ 'Address' => 'Birds@Intuit.com' } });
        m.put('paymentmethod/1000000001', new Map<String, Object>{ 'Id' => '1000000001', 'Name' => 'Wire-Transfer' });
        m.put('account/4', new Map<String, Object>{ 'Id' => '4', 'Name' => 'Undeposited Funds', 'AccountSubType' => 'UndepositedFunds' });
        m.put('account/35', new Map<String, Object>{ 'Id' => '35', 'Name' => 'Checking', 'AccountSubType' => 'Checking' });
        return m;
    }

    // ---- fixtures -------------------------------------------------------------------------------

    @TestSetup
    static void setup() {
        insert new QuickBooks_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Enabled__c = true,
            Verifier_Token__c = 'x', Realm_Id__c = REALM);
        insert new List<npsp__General_Accounting_Unit__c>{
            new npsp__General_Accounting_Unit__c(Name = 'QB Test Fund', npsp__Active__c = true),
            new npsp__General_Accounting_Unit__c(Name = 'QB Other Fund', npsp__Active__c = true) };
    }

    private static QuickBooks_Event__c event(String entity, String op, String entityId) {
        QuickBooks_Event__c e = new QuickBooks_Event__c(Event_Id__c = entity + '-' + op + '-' + entityId + '-' + Crypto.getRandomInteger(),
            Event_Type__c = 'qbo.' + entity + '.' + op + '.v1', Entity_Name__c = entity, Operation__c = op,
            Entity_Id__c = entityId, Entity_Key__c = entity + '-' + entityId, Realm_Id__c = REALM,
            Received_At__c = System.now(), Status__c = 'Received');
        insert e;
        return e;
    }

    private static QuickBooks_Event__c reload(Id eventId) {
        return [SELECT Status__c, Error_Message__c, Attempts__c, Imported_External_Ids__c, Processed_At__c
                FROM QuickBooks_Event__c WHERE Id = :eventId];
    }

    private static Pending_Transaction__c pendingByExternalId(String externalId) {
        List<Pending_Transaction__c> rows = [
            SELECT Id, Source__c, External_Id__c, External_Type__c, Amount__c, Transaction_Date__c, Deposit_Date__c,
                   Deposit_Reference__c, Payment_Method__c, Reference_Number__c, Payer_Name__c, Payer_Email__c, Memo__c,
                   QuickBooks_Customer_Id__c, Fund__c, Fund__r.Name, Import_Note__c, Raw_Data__c, Contact__c, Match_Status__c
            FROM Pending_Transaction__c WHERE External_Id__c = :externalId];
        return rows.isEmpty() ? null : rows[0];
    }

    /** A pending row as an earlier import would have left it, plus the earlier event that imported it. */
    private static Pending_Transaction__c priorImport(String entityKey, String externalId, Decimal amount, Boolean keepRow) {
        insert new QuickBooks_Event__c(Event_Id__c = 'prior-' + externalId, Entity_Name__c = entityKey.substringBefore('-'),
            Operation__c = 'created', Entity_Id__c = entityKey.substringAfter('-'), Entity_Key__c = entityKey,
            Realm_Id__c = REALM, Received_At__c = System.now().addMinutes(-10), Status__c = 'Processed',
            Imported_External_Ids__c = externalId);
        if (!keepRow) {
            return null;
        }
        Pending_Transaction__c row = new Pending_Transaction__c(Source__c = 'QuickBooks', External_Id__c = externalId,
            Amount__c = amount, Transaction_Date__c = Date.newInstance(2026, 9, 17), Payer_Name__c = 'Diego Rodriguez');
        insert row;
        return row;
    }

    // ---- deposits -------------------------------------------------------------------------------

    @IsTest
    static void directWireLineBecomesPendingTransaction() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c e = event('deposit', 'created', '145');

        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();

        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-145-l1');
        System.assertNotEquals(null, p, 'pending transaction created');
        System.assertEquals('QuickBooks', p.Source__c);
        System.assertEquals('Deposit', p.External_Type__c);
        System.assertEquals(180.00, p.Amount__c);
        System.assertEquals(Date.newInstance(2026, 9, 17), p.Transaction_Date__c);
        System.assertEquals(Date.newInstance(2026, 9, 17), p.Deposit_Date__c);
        System.assertEquals('QBO Deposit 145', p.Deposit_Reference__c);
        System.assertEquals('ACH/Wire', p.Payment_Method__c);
        System.assertEquals('123456', p.Reference_Number__c);
        System.assertEquals('Diego Rodriguez', p.Payer_Name__c);
        System.assertEquals('diego@rodriguez.com', p.Payer_Email__c, 'Salesforce stores email in lower case');
        System.assertEquals('TEST TRANSACTION', p.Memo__c);
        System.assertEquals('4', p.QuickBooks_Customer_Id__c);
        System.assertEquals('QB Test Fund', p.Fund__r.Name, 'fund from the mapped class');
        System.assertEquals(null, p.Import_Note__c);
        System.assert(p.Raw_Data__c.contains('"deposit"'));

        QuickBooks_Event__c after = reload(e.Id);
        System.assertEquals('Processed', after.Status__c);
        System.assertEquals('qbo-deposit-145-l1', after.Imported_External_Ids__c);
        System.assertEquals(1, after.Attempts__c);
    }


    @IsTest
    static void depositOfPaymentUsesThePaymentsCustomerAndInvoiceClasses() {
        // Invoice 67's two lines map to two different funds -> fund left for staff with a note.
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund', 'Development' => 'QB Other Fund' };
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c depositEvent = event('deposit', 'created', '147');

        Test.startTest();
        QuickBooksEventProcessor.process(depositEvent.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c], 'one pending transaction for the $239');
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-147-payment-146');
        System.assertEquals('Deposit (Payment)', p.External_Type__c);
        System.assertEquals(239.00, p.Amount__c);
        System.assertEquals('Amy\'s Bird Sanctuary', p.Payer_Name__c);
        System.assertEquals('birds@intuit.com', p.Payer_Email__c, 'Salesforce stores email in lower case');
        System.assertEquals('1', p.QuickBooks_Customer_Id__c);
        System.assertEquals('12345', p.Reference_Number__c);
        System.assertEquals('QBO Deposit 147', p.Deposit_Reference__c);
        System.assertEquals(null, p.Fund__c);
        System.assert(p.Import_Note__c.contains('several funds'), p.Import_Note__c);
    }

    @IsTest
    static void paymentInUndepositedFundsWaitsForItsDeposit() {
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c paymentEvent = event('payment', 'created', '146');
        Test.startTest();
        QuickBooksEventProcessor.process(paymentEvent.Id);
        Test.stopTest();
        QuickBooks_Event__c after = reload(paymentEvent.Id);
        System.assertEquals('Ignored', after.Status__c);
        System.assert(after.Error_Message__c.contains('Undeposited Funds'), after.Error_Message__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c], 'never counted twice');
    }

    @IsTest
    static void unmappedClassLeavesFundBlank() {
        // Only Development:Dinner is mapped; plain Development (Mark Cho's line in deposit 151) is left to staff.
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        Map<String, Object> dep = deposit145(50, 'Check');
        Map<String, Object> detail = (Map<String, Object>) ((Map<String, Object>) ((List<Object>) dep.get('Line'))[0]).get('DepositLineDetail');
        detail.put('ClassRef', ref('1000000001', 'Development'));
        mock.put('deposit/145', dep);
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-145-l1');
        System.assertEquals(null, p.Fund__c);
        System.assert(p.Import_Note__c.contains('QuickBooks class "Development" is not mapped to a fund'), p.Import_Note__c);
    }

    @IsTest
    static void classIsMatchedIgnoringCase() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ ' development:DINNER ' => 'QB Test Fund' };
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals('QB Test Fund', pendingByExternalId('qbo-deposit-145-l1').Fund__r.Name);
    }

    @IsTest
    static void lineWithNoClassLeavesFundBlank() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        Map<String, Object> dep = deposit145(50, 'Check');
        ((Map<String, Object>) ((Map<String, Object>) ((List<Object>) dep.get('Line'))[0]).get('DepositLineDetail')).remove('ClassRef');
        mock.put('deposit/145', dep);
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-145-l1');
        System.assertEquals(null, p.Fund__c);
        System.assert(p.Import_Note__c.contains('No QuickBooks class'), p.Import_Note__c);
    }

    @IsTest
    static void checkLineBecomesCheckPendingTransaction() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(50, 'Check'));
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-145-l1');
        System.assertNotEquals(null, p, 'a check is imported like ACH/wire');
        System.assertEquals('Check', p.Payment_Method__c);
        System.assertEquals('123456', p.Reference_Number__c, 'check number');
        System.assertEquals(50, p.Amount__c);
        System.assertEquals('QB Test Fund', p.Fund__r.Name);
        System.assertEquals('Processed', reload(e.Id).Status__c);
    }

    @IsTest
    static void depositOfCheckPaymentIsImportedAsCheck() {
        // The deposit line carries the payment method as an id only; QuickBooks names it "Check".
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        MockQuickBooks mock = realSandbox();
        mock.put('paymentmethod/1000000001', new Map<String, Object>{ 'Id' => '1000000001', 'Name' => 'Check' });
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '147');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-147-payment-146');
        System.assertNotEquals(null, p);
        System.assertEquals('Check', p.Payment_Method__c);
        System.assertEquals('12345', p.Reference_Number__c);
        System.assertEquals('Amy\'s Bird Sanctuary', p.Payer_Name__c);
    }

    @IsTest
    static void defaultCheckMethodsAllImportAsCheck() {
        // Amazon Smile, Benevity, Check and E-Check are all a Check in Salesforce; Cash is still skipped.
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        List<String> methods = new List<String>{ 'Amazon Smile', 'Benevity', 'Check', 'E-Check', 'Cash' };
        List<Object> lines = new List<Object>();
        for (Integer i = 0; i < methods.size(); i++) {
            lines.add(new Map<String, Object>{ 'Id' => String.valueOf(i + 1), 'Amount' => 10 + i,
                'DepositLineDetail' => new Map<String, Object>{
                    'Entity' => new Map<String, Object>{ 'value' => '4', 'name' => 'Diego Rodriguez', 'type' => 'CUSTOMER' },
                    'AccountRef' => ref('85', null), 'PaymentMethodRef' => ref('pm' + i, methods[i]) } });
        }
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', new Map<String, Object>{ 'Id' => '145', 'TxnDate' => '2026-10-23', 'Line' => lines });
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals(4, [SELECT COUNT() FROM Pending_Transaction__c WHERE Payment_Method__c = 'Check']);
        System.assertEquals(4, [SELECT COUNT() FROM Pending_Transaction__c], 'the cash line is not imported');
        System.assert(reload(e.Id).Error_Message__c.contains('1 deposit line(s) skipped'), reload(e.Id).Error_Message__c);
    }

    /** Deposit 900 depositing `count` earlier check Payments, each paying its own invoice for its own customer. */
    private static MockQuickBooks largeCheckDeposit(Integer count) {
        MockQuickBooks mock = realSandbox();
        mock.put('paymentmethod/2', new Map<String, Object>{ 'Id' => '2', 'Name' => 'Check' });
        List<Object> lines = new List<Object>();
        for (Integer i = 0; i < count; i++) {
            String paymentId = String.valueOf(1000 + i);
            String invoiceId = String.valueOf(5000 + i);
            String customerId = String.valueOf(2000 + i);
            lines.add(new Map<String, Object>{ 'Amount' => 100,
                'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => paymentId, 'TxnType' => 'Payment' } },
                'DepositLineDetail' => new Map<String, Object>{ 'PaymentMethodRef' => ref('2', null), 'CheckNum' => 'C' + i } });
            mock.put('payment/' + paymentId, new Map<String, Object>{ 'Id' => paymentId, 'TxnDate' => '2026-10-20',
                'TotalAmt' => 100, 'CustomerRef' => ref(customerId, 'Donor ' + i), 'PaymentMethodRef' => ref('2', null),
                'Line' => new List<Object>{ new Map<String, Object>{ 'Amount' => 100,
                    'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => invoiceId, 'TxnType' => 'Invoice' } } } } });
            mock.put('invoice/' + invoiceId, new Map<String, Object>{ 'Id' => invoiceId,
                'Line' => new List<Object>{ new Map<String, Object>{ 'Amount' => 100, 'DetailType' => 'SalesItemLineDetail',
                    'SalesItemLineDetail' => new Map<String, Object>{ 'ItemAccountRef' => ref('85', null),
                        'ClassRef' => ref('1000000003', 'Development:Dinner') } } } });
            mock.put('customer/' + customerId, new Map<String, Object>{ 'Id' => customerId, 'DisplayName' => 'Donor ' + i });
        }
        mock.put('deposit/900', new Map<String, Object>{ 'Id' => '900', 'TxnDate' => '2026-10-23', 'Line' => lines });
        return mock;
    }

    @IsTest
    static void largeCheckDepositIsReadInAFewQueries() {
        // 150 deposited check payments would take 450+ single reads; bulk queries keep it to a handful.
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = largeCheckDeposit(150);
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '900');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals('Processed', reload(e.Id).Status__c, 'Error: ' + reload(e.Id).Error_Message__c);
        System.assertEquals(150, [SELECT COUNT() FROM Pending_Transaction__c WHERE Payment_Method__c = 'Check']);
        System.assert(mock.calls <= 12, 'QuickBooks reads for 150 checks: ' + mock.calls);
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-900-payment-1149');
        System.assertEquals('Donor 149', p.Payer_Name__c);
        System.assertEquals('C149', p.Reference_Number__c);
        System.assertEquals('QB Test Fund', p.Fund__r.Name);
        System.assert(!p.Raw_Data__c.contains('C148'), 'Raw Data holds this line, not every line of the deposit');
    }

    @IsTest
    static void depositTooLargeForTheCalloutBudgetFailsWithAClearReason() {
        // Budget squeezed to 3 reads: the deposit can't be read, so the event fails once with a plain reason
        // instead of hitting Salesforce's uncatchable callout limit and retrying forever.
        QuickBooksApi.calloutBudgetOverride = 3;
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, largeCheckDeposit(5));
        QuickBooks_Event__c e = event('deposit', 'created', '900');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        QuickBooks_Event__c after = reload(e.Id);
        System.assertEquals('Failed', after.Status__c, 'not retried');
        System.assert(after.Error_Message__c.contains('Too large to import automatically'), after.Error_Message__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c], 'nothing half-imported');
    }

    @IsTest
    static void checkMethodNamesComeFromSettings() {
        // Finance's own name for checks, set in QuickBooks Settings; it replaces the default list.
        update new QuickBooks_Settings__c(Id = QuickBooks_Settings__c.getOrgDefaults().Id, Check_Payment_Methods__c = 'Paper Check, Mailed Check');
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(75, ' paper check '));
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals('Check', pendingByExternalId('qbo-deposit-145-l1').Payment_Method__c);
    }

    @IsTest
    static void cashLineIsSkipped() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(50, 'Cash'));
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
        QuickBooks_Event__c after = reload(e.Id);
        System.assertEquals('Processed', after.Status__c);
        System.assert(after.Error_Message__c.contains('not ACH/wire or check'), after.Error_Message__c);
    }


    @IsTest
    static void updatedDepositRefreshesButKeepsStaffChoices() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(200.00, 'Wire-Transfer')); // Finance corrected the amount
        Test.setMock(HttpCalloutMock.class, mock);
        Pending_Transaction__c row = priorImport('deposit-145', 'qbo-deposit-145-l1', 180.00, true);
        Id otherFund = [SELECT Id FROM npsp__General_Accounting_Unit__c WHERE Name = 'QB Other Fund'].Id;
        update new Pending_Transaction__c(Id = row.Id, Fund__c = otherFund, Notes__c = 'staff note');
        QuickBooks_Event__c e = event('deposit', 'updated', '145');

        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();

        Pending_Transaction__c refreshed = pendingByExternalId('qbo-deposit-145-l1');
        System.assertEquals(200.00, refreshed.Amount__c, 'amount refreshed from QuickBooks');
        System.assertEquals(otherFund, refreshed.Fund__c, 'the fund staff chose is kept');
        System.assertEquals('staff note', [SELECT Notes__c FROM Pending_Transaction__c WHERE Id = :row.Id].Notes__c);
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c]);
        System.assertEquals('Processed', reload(e.Id).Status__c);
    }

    @IsTest
    static void lineDeletedByStaffIsNeverRecreated() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, realSandbox());
        priorImport('deposit-145', 'qbo-deposit-145-l1', 180.00, false); // imported, then deleted by staff
        QuickBooks_Event__c e = event('deposit', 'updated', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c], 'deleted line not re-created');
        System.assert(reload(e.Id).Error_Message__c.contains('not re-created'), reload(e.Id).Error_Message__c);
    }


    @IsTest
    static void lineSwitchedToCashIsRemoved() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(180, 'Cash'));
        Test.setMock(HttpCalloutMock.class, mock);
        priorImport('deposit-145', 'qbo-deposit-145-l1', 180.00, true);
        QuickBooks_Event__c changed = event('deposit', 'updated', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(changed.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c], 'no longer a wire or check, so no longer pending');
        System.assert(reload(changed.Id).Error_Message__c.contains('Removed 1'), reload(changed.Id).Error_Message__c);
    }

    @IsTest
    static void lineSwitchedFromWireToCheckIsRelabelled() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        MockQuickBooks mock = realSandbox();
        mock.put('deposit/145', deposit145(180, 'Check'));
        Test.setMock(HttpCalloutMock.class, mock);
        Pending_Transaction__c row = priorImport('deposit-145', 'qbo-deposit-145-l1', 180.00, true);
        update new Pending_Transaction__c(Id = row.Id, Payment_Method__c = 'ACH/Wire');
        QuickBooks_Event__c changed = event('deposit', 'updated', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(changed.Id);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c], 'still pending - the same row');
        System.assertEquals('Check', [SELECT Payment_Method__c FROM Pending_Transaction__c WHERE Id = :row.Id].Payment_Method__c);
    }

    @IsTest
    static void deletedDepositRemovesItsPendingLines() {
        priorImport('deposit-147', 'qbo-deposit-147-payment-146', 239.00, true);
        QuickBooks_Event__c deleted = event('deposit', 'deleted', '147');
        Test.startTest();
        QuickBooksEventProcessor.process(deleted.Id); // no callouts needed for a delete
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
        System.assertEquals('Processed', reload(deleted.Id).Status__c);
    }

    @IsTest
    static void deletedAfterCommitIsFlagged() {
        priorImport('deposit-147', 'qbo-deposit-147-payment-146', 239.00, false); // committed or deleted already
        QuickBooks_Event__c voided = event('deposit', 'voided', '147');
        Test.startTest();
        QuickBooksEventProcessor.process(voided.Id);
        Test.stopTest();
        System.assert(reload(voided.Id).Error_Message__c.contains('check the gift'), reload(voided.Id).Error_Message__c);
    }

    @IsTest
    static void depositMissingInQuickBooksIsTreatedAsDeleted() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c e = event('deposit', 'created', '999');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
        System.assertEquals('Processed', reload(e.Id).Status__c);
    }

    // ---- payments and sales receipts deposited straight to the bank ------------------------------

    @IsTest
    static void paymentDepositedStraightToBankIsImported() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund', 'Development' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        mock.put('payment/900', new Map<String, Object>{
            'Id' => '900', 'TxnDate' => '2026-09-16', 'TotalAmt' => 500, 'PaymentRefNum' => 'WIRE-77',
            'CustomerRef' => ref('4', 'Diego Rodriguez'), 'DepositToAccountRef' => ref('35', null),
            'PaymentMethodRef' => ref('1000000001', null), 'PrivateNote' => 'annual gift',
            'Line' => new List<Object>{ new Map<String, Object>{ 'Amount' => 500,
                'LinkedTxn' => new List<Object>{ new Map<String, Object>{ 'TxnId' => '67', 'TxnType' => 'Invoice' } } } } });
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('payment', 'created', '900');

        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();

        Pending_Transaction__c p = pendingByExternalId('qbo-payment-900');
        System.assertEquals('Payment', p.External_Type__c);
        System.assertEquals(500, p.Amount__c);
        System.assertEquals('WIRE-77', p.Reference_Number__c);
        System.assertEquals('annual gift', p.Memo__c);
        System.assertEquals('diego@rodriguez.com', p.Payer_Email__c, 'Salesforce stores email in lower case');
        System.assertEquals(null, p.Deposit_Reference__c);
        System.assertEquals('QB Test Fund', p.Fund__r.Name, 'both invoice classes map to one fund');
    }

    /** Sales receipt 902 deposited straight to the bank; one class for the whole transaction, none on its lines. */
    private static Map<String, Object> salesReceipt902(List<Object> lines) {
        return new Map<String, Object>{
            'Id' => '902', 'TxnDate' => '2026-10-23', 'TotalAmt' => 250, 'CustomerRef' => ref('4', 'Diego Rodriguez'),
            'DepositToAccountRef' => ref('35', null), 'PaymentMethodRef' => ref('1000000001', null),
            'ClassRef' => ref('1000000003', 'Development:Dinner'), 'Line' => lines };
    }

    @IsTest
    static void salesReceiptLinesWithoutClassUseTheTransactionClass() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        mock.put('salesreceipt/902', salesReceipt902(new List<Object>{
            new Map<String, Object>{ 'Amount' => 250, 'SalesItemLineDetail' => new Map<String, Object>() },
            new Map<String, Object>{ 'Amount' => 250, 'DetailType' => 'SubTotalLineDetail' } }));
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('salesreceipt', 'created', '902');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-salesreceipt-902');
        System.assertEquals('QB Test Fund', p.Fund__r.Name, 'the subtotal line is passed over');
        System.assertEquals(null, p.Import_Note__c);
    }

    @IsTest
    static void unclassifiedItemLineLeavesFundBlank() {
        // One line is Dinner, the other has no class at all (and no transaction class): staff decide.
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>{ 'Development:Dinner' => 'QB Test Fund' };
        MockQuickBooks mock = realSandbox();
        Map<String, Object> receipt = salesReceipt902(new List<Object>{
            new Map<String, Object>{ 'Amount' => 200, 'SalesItemLineDetail' => new Map<String, Object>{
                'ClassRef' => ref('1000000003', 'Development:Dinner') } },
            new Map<String, Object>{ 'Amount' => 50, 'SalesItemLineDetail' => new Map<String, Object>() } });
        receipt.remove('ClassRef');
        mock.put('salesreceipt/902', receipt);
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('salesreceipt', 'created', '902');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-salesreceipt-902');
        System.assertEquals(null, p.Fund__c);
        System.assert(p.Import_Note__c.contains('Some QuickBooks lines have no class'), p.Import_Note__c);
    }

    @IsTest
    static void salesReceiptInUndepositedFundsIsIgnored() {
        MockQuickBooks mock = realSandbox();
        mock.put('salesreceipt/901', new Map<String, Object>{
            'Id' => '901', 'TxnDate' => '2026-09-16', 'TotalAmt' => 75, 'CustomerRef' => ref('4', 'Diego Rodriguez'),
            'DepositToAccountRef' => ref('4', null), 'PaymentMethodRef' => ref('1000000001', null) });
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c receipt = event('salesreceipt', 'created', '901');
        Test.startTest();
        QuickBooksEventProcessor.process(receipt.Id);
        Test.stopTest();
        System.assertEquals('Ignored', reload(receipt.Id).Status__c);
    }

    // ---- other events, settings and failures ----------------------------------------------------

    @IsTest
    static void otherEntitiesAndCompaniesAreIgnored() {
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c customer = event('customer', 'created', '4');
        QuickBooks_Event__c otherRealm = event('deposit', 'created', '145');
        update new QuickBooks_Event__c(Id = otherRealm.Id, Realm_Id__c = '1111');
        Test.startTest();
        QuickBooksEventProcessor.process(customer.Id);
        QuickBooksEventProcessor.process(otherRealm.Id);
        Test.stopTest();
        System.assertEquals('Ignored', reload(customer.Id).Status__c);
        System.assertEquals('Ignored', reload(otherRealm.Id).Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c]);
    }

    @IsTest
    static void switchedOffLeavesEventsWaiting() {
        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();
        cfg.Enabled__c = false;
        update cfg;
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        QuickBooksEventProcessor.process(e.Id);
        System.assertEquals('Received', reload(e.Id).Status__c);
        System.assertEquals(null, reload(e.Id).Attempts__c);
    }


    @IsTest
    static void temporaryQuickBooksFailureIsLeftForTheNextRun() {
        MockQuickBooks mock = realSandbox();
        mock.forcedStatus = 503;
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        QuickBooks_Event__c first = reload(e.Id);
        System.assertEquals('Received', first.Status__c, 'left for the next run');
        System.assertEquals(1, first.Attempts__c);
        System.assert(first.Error_Message__c.startsWith('Will retry'), first.Error_Message__c);
    }

    @IsTest
    static void temporaryFailureOnTheLastAttemptFails() {
        MockQuickBooks mock = realSandbox();
        mock.forcedStatus = 429;
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        update new QuickBooks_Event__c(Id = e.Id, Attempts__c = QuickBooksEventProcessor.MAX_ATTEMPTS - 1);
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        QuickBooks_Event__c last = reload(e.Id);
        System.assertEquals('Failed', last.Status__c);
        System.assertEquals(QuickBooksEventProcessor.MAX_ATTEMPTS, last.Attempts__c);
    }


    @IsTest
    static void permanentApiErrorFailsImmediately() {
        MockQuickBooks mock = realSandbox();
        mock.forcedStatus = 403;
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        System.assertEquals('Failed', reload(e.Id).Status__c);
        System.assert(reload(e.Id).Error_Message__c.contains('403'), reload(e.Id).Error_Message__c);
    }

    // ---- customer link --------------------------------------------------------------------------

    @IsTest
    static void donorLinkedToTheQuickBooksCustomerIsMatchedExactly() {
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.DuplicateRuleHeader.allowSave = true;
        Contact diego = new Contact(FirstName = 'Diego', LastName = 'Rodriguez-QBTest', QuickBooks_Customer_Id__c = '4');
        Database.insert(diego, opts);
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();
        Pending_Transaction__c p = pendingByExternalId('qbo-deposit-145-l1');
        System.assertEquals(diego.Id, p.Contact__c);
        System.assertEquals('Confirmed', p.Match_Status__c);
    }

    // ---- sweeper --------------------------------------------------------------------------------

    @IsTest
    static void sweeperStartsTheProcessorOnlyWhenThereIsWork() {
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, realSandbox());
        System.assertEquals(null, QuickBooksSweeper.run(), 'nothing waiting');
        QuickBooks_Event__c e = event('deposit', 'created', '145');
        Test.startTest();
        new QuickBooksSweeper().execute(null);
        Test.stopTest();
        System.assertEquals('Processed', reload(e.Id).Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Pending_Transaction__c]);
    }

    @IsTest
    static void apiHelpersReadQuickBooksShapes() {
        System.assertEquals('4', QuickBooksApi.refValue(new Map<String, Object>{ 'value' => '4', 'name' => 'Diego' }));
        System.assertEquals('Diego', QuickBooksApi.refName(new Map<String, Object>{ 'value' => '4', 'name' => 'Diego' }));
        System.assertEquals(null, QuickBooksApi.refValue(null));
        System.assertEquals(0, QuickBooksApi.items('not a list').size());
        System.assertEquals(null, QuickBooksApi.str('  '));
        delete [SELECT Id FROM QuickBooks_Settings__c];
        try {
            QuickBooksApi.realmId();
            System.assert(false, 'expected an error');
        } catch (QuickBooksApi.QuickBooksApiException e) {
            System.assert(e.getMessage().contains('Company ID'));
        }
    }

    // ---- already committed ------------------------------------------------------------------------

    @IsTest
    static void aLineAlreadyCommittedIsNeverRecreated() {
        // The gift carries the source id, so this holds even after old events have been purged.
        insert new Opportunity(Name = 'Committed wire', StageName = 'Posted', CloseDate = Date.today(), Amount = 180,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('NPSP_Default').getRecordTypeId(),
            Source_Transaction_Id__c = 'qbo-deposit-145-l1');
        QuickBooksEventProcessor.fundMapOverride = new Map<String, String>();
        Test.setMock(HttpCalloutMock.class, realSandbox());
        QuickBooks_Event__c e = event('deposit', 'created', '145');

        Test.startTest();
        QuickBooksEventProcessor.process(e.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Pending_Transaction__c], 'the money is already a gift');
        System.assert(reload(e.Id).Error_Message__c.contains('already committed'), reload(e.Id).Error_Message__c);
    }
}