/**
 * @description Tests for WebDonationParser.
 *
 *              The primary payload here is a REDACTED COPY OF A REAL GRAVITY FORMS SUBMISSION
 *              (entry 882, form 15), not an invented shape. That matters: the whole contract
 *              with the form is a set of numeric field ids, and a payload someone made up
 *              would happily pass while the real one failed.
 *
 * @author Jason Ott
 * @created 2026-08-20
 *
 * Change Log:
 * -----------
 * 2026-08-20 - Jason Ott - Created (Website Donations phase 2 coverage).
 */
@IsTest
private class WebDonationParserTest {

    /** Shape and field ids exactly as Gravity Forms sends them; values are test data. */
    public static String realWorldPayload() {
        return '{'
            + '"1.3":"Testfirst","1.6":"Testlast","2":"parser.test@example.com",'
            + '"3":"$18|18","5":"18.82","9":"Test Company","11":"5555550100","13":"Cell",'
            + '"10.1":"1 Test Street","10.2":"Apt 2","10.3":"St. Louis","10.4":"MO","10.5":"63119",'
            + '"20.1":"XXXXXXXXXXXX","21.1":"Yes, I want to pay the processing fee",'
            + '"22.1":"Processing fee","22.2":"$0.82","22.3":"1",'
            + '"23":"Some Programme","24.1":"In honor of","24.2":"Someone",'
            + '"25":"notify@example.com","28.13":"Other:","28.1":"","28.2":"",'
            + '"id":"882","form_id":"15","source_url":"https://example.org/test",'
            + '"date_created":"2026-08-19 20:37:25","currency":"USD",'
            + '"transaction_id":null,"payment_status":null,"payment_amount":null'
            + '}';
    }

    @IsTest
    static void parsesRealGravityFormsPayload() {
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());

        System.assertEquals('Testfirst', p.firstName, 'first name comes from field 1.3');
        System.assertEquals('Testlast', p.lastName, 'last name comes from field 1.6');
        System.assertEquals('parser.test@example.com', p.email, 'email comes from field 2');
        System.assertEquals('5555550100', p.phone, 'phone comes from field 11');
        System.assertEquals('Test Company', p.company, 'company comes from field 9');
        System.assertEquals('1 Test Street', p.street);
        System.assertEquals('St. Louis', p.city);
        System.assertEquals('MO', p.state);
        System.assertEquals('63119', p.postalCode);
        System.assertEquals('882', p.entryId);
        System.assertEquals('15', p.formId);
        System.assertEquals(Date.newInstance(2026, 8, 19), p.submittedOn, 'date from date_created');
    }

    @IsTest
    static void amountIsTheTotalCharged() {
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());
        // Field 3 is the tier the donor picked ($18); field 5 is what was actually charged
        // once they elected to cover the fee. Jason confirmed the whole 18.82 is the gift.
        System.assertEquals(18.82, p.amount, 'gift is field 5, the total charged - not the tier');
        System.assertEquals(0.82, p.feeAmount, 'fee parsed with its currency symbol stripped');
        System.assertEquals(true, p.paidFee, 'donor opted to cover the fee');
    }

    @IsTest
    static void collectsOnlyTickedDesignations() {
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());
        // The checkbox group sends every option as its own 28.x key; unticked ones are blank.
        System.assertEquals(1, p.designations.size(), 'only the ticked option is collected');
        System.assertEquals('Other:', p.designations[0], 'value kept verbatim, colon and all');
    }

    @IsTest
    static void capturesTributeAndWriteIn() {
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());
        System.assertEquals('Some Programme', p.writeIn);
        System.assertEquals('In honor of', p.tributeType);
        System.assertEquals('Someone', p.tributeName);
        System.assertEquals('notify@example.com', p.notifyEmail);
    }

    @IsTest
    static void missingPaymentDataMeansNotSettledYet() {
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());
        // Stripe fills these in via its own webhook AFTER this one fires, so null here means
        // "not settled yet" rather than "intent only".
        System.assertEquals(false, p.hasPayment, 'no transaction id on the form webhook');
        System.assertEquals(null, p.transactionId);
    }

    @IsTest
    static void handlesEmptyAndMissingValues() {
        WebDonationParser.Parsed p = WebDonationParser.parse('{"id":"1","form_id":"15"}');
        System.assertEquals(null, p.firstName, 'absent keys give null, not an exception');
        System.assertEquals(null, p.amount, 'no amount at all');
        System.assertEquals(0, p.designations.size());
        System.assertEquals(Date.today(), p.submittedOn, 'missing date falls back to today');
    }

    @IsTest
    static void unparseableAmountDoesNotThrow() {
        WebDonationParser.Parsed p = WebDonationParser.parse('{"id":"2","5":"not a number"}');
        System.assertEquals(null, p.amount, 'garbage amount yields null rather than an exception');
    }

    @IsTest
    static void doesNotReadTheCardField() {
        // 20.1 arrives masked. The parser must never surface it anywhere - card data stays out
        // of Salesforce by construction, not by trust.
        WebDonationParser.Parsed p = WebDonationParser.parse(realWorldPayload());
        String dump = JSON.serialize(p);
        System.assertEquals(false, dump.contains('XXXXXXXXXXXX'),
            'the masked card value must not appear in the parsed output');
    }
}