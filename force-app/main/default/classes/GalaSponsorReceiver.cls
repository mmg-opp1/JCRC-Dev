/**
 * @description Public endpoint for sponsorships submitted on the gala website (jcrcnygala.org).
 *
 *              Its ONLY job is to authenticate the caller, store the submission exactly as received and return.
 *              Nothing is interpreted here: Pay Now submissions become Pending Transactions and Pay Later
 *              submissions become Pledges, both done afterwards from the stored payload, by a job running as an
 *              administrator. The reasons are the ones the website donation endpoint proved:
 *                - a slow or failing match must never hang the sponsor's browser or make the form think the
 *                  submission failed;
 *                - the Site guest user this runs as cannot do the gift work anyway;
 *                - storing the raw submission first means a mapping bug can never lose a sponsorship.
 *
 *              Endpoint:  POST https://<hooks site domain>/services/apexrest/gala/sponsor
 *              Header:    X-JCRC-Signature: <Gala Shared Secret from the Webhook Config custom setting>
 *
 *              The secret is separate from the donation form's, so either can be rotated on its own.
 *
 *              IDEMPOTENCY: forms retry. Entry_Id__c is unique, and this inserts and catches the duplicate error
 *              rather than querying first, so no query runs as the guest user. A resend is answered 200.
 *
 *              PAYMENT BOUNDARY: Stripe takes the card. This must never receive a card number, CVV or full
 *              expiry - only the Stripe reference. Only known-safe values are read out of the payload later.
 *
 *              SECURITY: runs as the Site guest user and must never tell an anonymous caller what the org holds.
 * @author Jason Ott
 * @created 2026-09-24
 *
 * Change Log:
 * -----------
 * 2026-09-24 - Jason Ott - Created, so the gala form's webhook can be configured before the mapping exists.
 */
@RestResource(urlMapping='/gala/sponsor/*')
global without sharing class GalaSponsorReceiver {

    @TestVisible private static final String SECRET_HEADER = 'X-JCRC-Signature';
    @TestVisible private static final Integer DEFAULT_MAX_BYTES = 200000;

    global class Result {
        global String status;
        global Result(String s) { this.status = s; }
    }

    @HttpPost
    global static Result receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        Webhook_Config__c cfg = Webhook_Config__c.getOrgDefaults();
        String expected = cfg == null ? null : cfg.Gala_Shared_Secret__c;

        // ---- 1. authenticate before anything else ------------------------------------------------
        if (String.isBlank(expected) || !constantTimeEquals(expected, header(req, SECRET_HEADER))) {
            res.statusCode = 401;
            return new Result('unauthorized');
        }

        // ---- 2. size ceiling, before parsing -----------------------------------------------------
        String body = req.requestBody == null ? null : req.requestBody.toString();
        if (String.isBlank(body)) {
            res.statusCode = 400;
            return new Result('empty');
        }
        if (body.length() > maxBytes(cfg)) {
            res.statusCode = 413;
            return new Result('too large');
        }

        // ---- 3. read only what files it; everything else stays raw for the mapping work ----------
        String entryId;
        String formId;
        String payOption;
        String sponsorName;
        String sponsorEmail;
        String paymentReference;
        Decimal amount;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            entryId = firstNonBlank(parsed, new List<String>{ 'entry_id', 'entryId', 'id' });
            formId = firstNonBlank(parsed, new List<String>{ 'form_id', 'formId' });
            payOption = firstNonBlank(parsed, new List<String>{ 'pay_option', 'payOption', 'payment_option' });
            sponsorName = firstNonBlank(parsed, new List<String>{ 'name', 'sponsor_name', 'full_name' });
            sponsorEmail = firstNonBlank(parsed, new List<String>{ 'email', 'sponsor_email' });
            paymentReference = firstNonBlank(parsed, new List<String>{ 'transaction_id', 'stripe_payment_id',
                'payment_id', 'charge_id' });
            String amountText = firstNonBlank(parsed, new List<String>{ 'amount', 'payment_amount', 'total' });
            if (String.isNotBlank(amountText)) {
                amount = safeDecimal(amountText);
            }
        } catch (Exception e) {
            // Malformed JSON is still kept - it is evidence the form changed.
            entryId = null;
        }

        // ---- 4. store it --------------------------------------------------------------------------
        Gala_Submission__c rec = new Gala_Submission__c(
            Entry_Id__c = entryId,
            Form_Id__c = formId,
            Pay_Option__c = payOption == null ? null : payOption.left(40),
            Payer_Name__c = sponsorName == null ? null : sponsorName.left(255),
            Payer_Email__c = isEmail(sponsorEmail) ? sponsorEmail : null,
            Payment_Reference__c = paymentReference == null ? null : paymentReference.left(255),
            Amount__c = amount,
            Payload__c = body.left(131072),
            Status__c = 'Received',
            Received_At__c = System.now());
        Database.SaveResult sr = Database.insert(rec, false);
        if (!sr.isSuccess()) {
            for (Database.Error err : sr.getErrors()) {
                if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                    res.statusCode = 200;
                    return new Result('duplicate ignored');
                }
            }
            System.debug(LoggingLevel.ERROR, 'GalaSponsorReceiver insert failed: ' + sr.getErrors());
            res.statusCode = 500;
            return new Result('error');
        }
        res.statusCode = 200;
        return new Result('received');
    }

    /** Compares every character regardless of where they differ, and a blank configured secret always fails. */
    private static Boolean constantTimeEquals(String expected, String presented) {
        if (String.isBlank(presented)) {
            return false;
        }
        Integer diff = expected.length() ^ presented.length();
        Integer n = Math.min(expected.length(), presented.length());
        for (Integer i = 0; i < n; i++) {
            diff |= expected.charAt(i) ^ presented.charAt(i);
        }
        return diff == 0;
    }

    private static String header(RestRequest req, String name) {
        if (req == null || req.headers == null) {
            return null;
        }
        for (String k : req.headers.keySet()) {
            if (k != null && k.equalsIgnoreCase(name)) {
                return req.headers.get(k);
            }
        }
        return null;
    }

    private static Integer maxBytes(Webhook_Config__c cfg) {
        return (cfg != null && cfg.Max_Payload_Bytes__c != null && cfg.Max_Payload_Bytes__c > 0)
            ? Integer.valueOf(cfg.Max_Payload_Bytes__c) : DEFAULT_MAX_BYTES;
    }

    /** First of the candidate keys present and non-blank; forms name things differently. */
    private static String firstNonBlank(Map<String, Object> m, List<String> keys) {
        if (m == null) {
            return null;
        }
        for (String k : keys) {
            Object v = m.get(k);
            if (v != null && String.isNotBlank(String.valueOf(v))) {
                return String.valueOf(v);
            }
        }
        return null;
    }

    /** "$1,500.00" -> 1500.00; anything unreadable is left for the mapping work rather than failing the request. */
    @TestVisible
    private static Decimal safeDecimal(String s) {
        try {
            String cleaned = s.replaceAll('[^0-9.\\-]', '');
            return String.isBlank(cleaned) ? null : Decimal.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isEmail(String s) {
        return s != null && Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', s);
    }
}