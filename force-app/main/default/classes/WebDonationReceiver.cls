/**
 * @description Public webhook endpoint for website donations submitted through Gravity Forms.
 *
 *              Its ONLY job is to authenticate the caller, store the raw payload and return.
 *              It deliberately does not resolve donors, create Opportunities or allocate
 *              anything - all of that happens asynchronously against the stored payload.
 *              Two reasons:
 *                - a slow or failing donor match must never hang the donor's browser or make
 *                  Gravity Forms treat the submission as failed;
 *                - storing the payload before interpreting it means a mapping bug cannot
 *                  silently lose a gift; the submission can be replayed.
 *
 *              Endpoint (once a public Site is configured):
 *                POST https://<site-domain>/services/apexrest/webdonation
 *              Header:
 *                X-JCRC-Signature: <shared secret from the Webhook Config custom setting>
 *
 *              IDEMPOTENCY: Gravity Forms retries. Web_Donation__c.GF_Entry_Id__c is unique,
 *              and this class INSERTS and catches the duplicate error rather than querying
 *              first. A retry is answered 200 "duplicate ignored" so Gravity Forms stops.
 *
 *              NOTE on guest permissions: the intent was Create WITHOUT Read, but Salesforce
 *              refuses that - "Permission Create depends on permission(s): Read". So the guest
 *              profile carries object Read whether we want it or not. Data exposure is blocked
 *              at two other layers instead: the object's OWD is Private and records are owned
 *              by the site's default owner, so the guest can see no rows; and the guest has no
 *              route to query anyway, since the REST data API rejects the guest session. The
 *              insert-and-catch design still earns its keep - it means no query runs as guest.
 *
 *              SECURITY: runs as the Site guest user. It must never return anything that
 *              tells an anonymous caller what the org stores or why something failed.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (Website Donations phase 1).
 */
@RestResource(urlMapping='/webdonation/*')
global without sharing class WebDonationReceiver {

    private static final String SECRET_HEADER = 'X-JCRC-Signature';
    private static final Integer DEFAULT_MAX_BYTES = 200000;

    /** Minimal response. Deliberately says almost nothing. */
    global class Result {
        global String status;
        global Result(String s) { this.status = s; }
    }

    @HttpPost
    global static Result receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        // ---- 1. authenticate BEFORE doing anything else ---------------------------------
        if (!isAuthorised(req)) {
            res.statusCode = 401;
            return new Result('unauthorized');
        }

        // ---- 2. size ceiling, before parsing --------------------------------------------
        String body = (req.requestBody == null) ? null : req.requestBody.toString();
        if (String.isBlank(body)) {
            res.statusCode = 400;
            return new Result('empty');
        }
        if (body.length() > maxBytes()) {
            res.statusCode = 413;
            return new Result('too large');
        }

        // ---- 3. pull only the two keys needed to file it; everything else stays raw ------
        String entryId;
        String formId;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            entryId = firstNonBlank(parsed, new List<String>{'entry_id', 'entryId', 'id'});
            formId  = firstNonBlank(parsed, new List<String>{'form_id', 'formId'});
        } catch (Exception e) {
            // Malformed JSON is still worth keeping - it is evidence the form changed.
            entryId = null;
        }

        // ---- 4. store it -----------------------------------------------------------------
        Web_Donation__c rec = new Web_Donation__c(
            GF_Entry_Id__c = entryId,
            Form_Id__c     = formId,
            Payload__c     = body,
            Status__c      = 'Received',
            Received_At__c = System.now()
        );
        Database.SaveResult sr = Database.insert(rec, false);
        if (!sr.isSuccess()) {
            for (Database.Error err : sr.getErrors()) {
                if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                    // A retry of something already stored. Answer 200 so Gravity Forms stops.
                    res.statusCode = 200;
                    return new Result('duplicate ignored');
                }
            }
            // Something genuinely went wrong. Log internally; tell the caller nothing.
            System.debug(LoggingLevel.ERROR, 'WebDonationReceiver insert failed: ' + sr.getErrors());
            res.statusCode = 500;
            return new Result('error');
        }

        res.statusCode = 201;
        return new Result('received');
    }

    /**
     * Compares the presented secret with the configured one.
     * Length-independent comparison so the check does not leak the secret's length through
     * timing, and a blank configured secret always fails rather than accidentally allowing
     * everything through before the org has been set up.
     */
    private static Boolean isAuthorised(RestRequest req) {
        Webhook_Config__c cfg = Webhook_Config__c.getOrgDefaults();
        String expected = (cfg == null) ? null : cfg.Shared_Secret__c;
        if (String.isBlank(expected)) {
            return false;
        }
        String presented = header(req, SECRET_HEADER);
        if (String.isBlank(presented)) {
            return false;
        }
        return constantTimeEquals(expected, presented);
    }

    /** Header lookup that does not care about capitalisation. */
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

    /** Compares every character regardless of mismatch position. */
    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        Integer diff = a.length() ^ b.length();
        Integer n = Math.min(a.length(), b.length());
        for (Integer i = 0; i < n; i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
    }

    private static Integer maxBytes() {
        Webhook_Config__c cfg = Webhook_Config__c.getOrgDefaults();
        if (cfg != null && cfg.Max_Payload_Bytes__c != null && cfg.Max_Payload_Bytes__c > 0) {
            return Integer.valueOf(cfg.Max_Payload_Bytes__c);
        }
        return DEFAULT_MAX_BYTES;
    }

    /** First of the candidate keys that is present and non-blank. */
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
}