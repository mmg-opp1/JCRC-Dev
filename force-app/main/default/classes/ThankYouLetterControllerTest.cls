/**
 * @description Tests for ThankYouLetterController (JSI-87 thank-you letter merge data).
 *              Covers a gift with a primary contact (contact name and mailing address), a gift
 *              from an organization with no contact (account name and billing address, "Friend"),
 *              the template variant flags (Tax / NoTax, Parade, Board, blank = Standard_Tax), and
 *              the amount format (always two decimals). Expected values for the variant flags are
 *              read back from the saved gift, because the acknowledgment router may stamp the
 *              template on save.
 * @author Jason Ott
 * @created 2026-11-20
 *
 * Change Log:
 * -----------
 * 2026-11-20 - Jason Ott - Created; the class had no test, which blocks a production deploy.
 */
@isTest
private class ThankYouLetterControllerTest {

    /** Builds the controller the way the Visualforce page does: a standard controller on the gift. */
    private static ThankYouLetterController controllerFor(Id oppId) {
        return new ThankYouLetterController(new ApexPages.StandardController(new Opportunity(Id = oppId)));
    }

    /** Gift with a primary contact: the letter is addressed to the contact at their mailing address. */
    @isTest
    static void contactGift_usesContactNameAndMailingAddress() {
        Contact c = new Contact(Salutation = 'Dr.', FirstName = 'Ada', LastName = 'Lettertest',
                                MailingStreet = '1 Main St\nApt 4', MailingCity = 'New York',
                                MailingState = 'NY', MailingPostalCode = '10001');
        insert c;
        c = [SELECT Id, AccountId FROM Contact WHERE Id = :c.Id];
        Opportunity o = new Opportunity(Name = 'Letter Test Gift', AccountId = c.AccountId,
                                        npsp__Primary_Contact__c = c.Id, StageName = 'Prospecting',
                                        CloseDate = Date.newInstance(2026, 3, 5), Amount = 12500);
        insert o;

        Test.startTest();
        ThankYouLetterController ctl = controllerFor(o.Id);
        Test.stopTest();

        Opportunity saved = [SELECT Last_Payment_Date__c, CloseDate FROM Opportunity WHERE Id = :o.Id];
        Date expectedDate = saved.Last_Payment_Date__c != null ? saved.Last_Payment_Date__c : saved.CloseDate;

        Assert.areEqual('Ada', ctl.firstName, 'First name comes from the primary contact');
        Assert.areEqual('Dr. Ada Lettertest', ctl.recipientName, 'Salutation, first and last name');
        // NPSP's address sync saves the street with \r\n line breaks, so compare trimmed lines
        List<String> lines = new List<String>();
        for (String line : ctl.addressLines) {
            lines.add(line.trim());
        }
        Assert.areEqual(new List<String>{ '1 Main St', 'Apt 4', 'New York, NY 10001' }, lines,
                        'Each street line, then "City, ST Zip"');
        Assert.areEqual('12,500.00', ctl.giftAmount, 'Thousands separator and two decimals');
        Assert.areEqual(Datetime.newInstance(expectedDate, Time.newInstance(0, 0, 0, 0)).format('MMMM d, yyyy'),
                        ctl.paymentDate, 'Payment date, else close date');
        Assert.isTrue(String.isNotBlank(ctl.letterDate), 'Letter is dated today');
        Assert.areEqual('', ctl.campaignName, 'No campaign gives a blank campaign name');
    }

    /** Organization gift with no contact: "Friend", the account name and its billing address. */
    @isTest
    static void organizationGift_usesAccountNameAndBillingAddress() {
        Account a = new Account(Name = 'Lettertest Foundation', BillingStreet = '500 Fifth Ave',
                                BillingCity = 'New York', BillingState = 'NY', BillingPostalCode = '10110',
                                RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                                               .get('Organization').getRecordTypeId());
        insert a;
        Opportunity o = new Opportunity(Name = 'Letter Test Org Gift', AccountId = a.Id, StageName = 'Prospecting',
                                        CloseDate = Date.today(), Amount = 100.5);
        insert o;

        ThankYouLetterController ctl = controllerFor(o.Id);

        Assert.areEqual('Friend', ctl.firstName, 'No contact: the greeting falls back to "Friend"');
        Assert.areEqual('Lettertest Foundation', ctl.recipientName, 'No contact: the organization name');
        Assert.areEqual(new List<String>{ '500 Fifth Ave', 'New York, NY 10110' }, ctl.addressLines,
                        'No contact: the billing address');
        Assert.areEqual('100.50', ctl.giftAmount, 'One decimal place is padded to two');
    }

    /** Variant flags follow the template key; a blank key falls back to Standard with tax. */
    @isTest
    static void templateFlags_followTheTemplateKey() {
        Account a = new Account(Name = 'Lettertest Variants', RecordTypeId = Schema.SObjectType.Account
                                .getRecordTypeInfosByDeveloperName().get('Organization').getRecordTypeId());
        insert a;
        List<Opportunity> gifts = new List<Opportunity>();
        // loop: one gift per template key, plus one with no key and one with no amount
        for (String key : new List<String>{ 'Ack_Letter_Parade_NoTax', 'Ack_Letter_Board_Tax', null }) {
            gifts.add(new Opportunity(Name = 'Letter Variant ' + key, AccountId = a.Id, StageName = 'Prospecting',
                                      CloseDate = Date.today(), Amount = 50, Acknowledgment_Template__c = key));
        }
        gifts.add(new Opportunity(Name = 'Letter No Amount', AccountId = a.Id, StageName = 'Prospecting',
                                  CloseDate = Date.today()));
        insert gifts;

        // loop: expectations come from the key actually saved (the router may stamp one)
        for (Opportunity saved : [SELECT Id, Amount, Acknowledgment_Template__c FROM Opportunity WHERE Id IN :gifts]) {
            ThankYouLetterController ctl = controllerFor(saved.Id);
            String key = String.isBlank(saved.Acknowledgment_Template__c)
                         ? 'Ack_Letter_Standard_Tax' : saved.Acknowledgment_Template__c;
            Assert.areEqual(key, ctl.templateKey, 'Saved key, or Standard_Tax when blank');
            Assert.areEqual(!key.endsWith('_NoTax'), ctl.showTaxBlock, 'Tax block hidden only for NoTax');
            Assert.areEqual(key.contains('_Parade_'), ctl.isParade, 'Parade variant flag');
            Assert.areEqual(key.contains('_Board_'), ctl.isBoard, 'Board variant flag');
            if (saved.Amount == null) {
                Assert.areEqual('', ctl.giftAmount, 'No amount prints nothing');
            }
        }
    }
}
