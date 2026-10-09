/**
 * @description Public endpoint that receives QuickBooks Online webhooks (JSI-121 Phase 5a).
 *
 *              Its ONLY job is to prove the request came from Intuit, store each event exactly as
 *              received, and answer 200. It does not read QuickBooks or create anything - a scheduled
 *              job running as an administrator does that from the stored events. Reasons:
 *                - Intuit requires an HTTP 200 within 3 seconds and holds back later events until it
 *                  gets one;
 *                - the Site guest user this runs as cannot make authenticated callouts or run the gift
 *                  logic (the website donations lesson, 2026-09-10);
 *                - storing before interpreting means a mapping bug can never lose a transaction.
 *
 *              Endpoint:  POST https://<hooks site domain>/services/apexrest/qbo/webhook
 *
 *              AUTHENTICATION: Intuit signs every request. The intuit-signature header is the base64
 *              HMAC-SHA256 of the raw request body, keyed with the app's webhook verifier token (kept in
 *              the protected QuickBooks Settings custom setting, never in code). Checked before any
 *              parsing, query or DML.
 *
 *              FORMAT: CloudEvents 1.0 - a JSON array of events, each with id, type
 *              (qbo.<entity>.<operation>.v1), intuitentityid, intuitaccountid (the company), time and an
 *              optional data object. One QuickBooks_Event__c row per event. A body that isn't a
 *              CloudEvents array is still stored (Failed) so nothing Intuit sends is lost.
 *
 *              IDEMPOTENCY: Intuit retries until it gets a 200. Event_Id__c is unique; the receiver
 *              inserts and ignores duplicate errors rather than querying first, so no query runs as guest.
 *
 *              RESPONSES: 200 stored (or already stored) · 401 bad or missing signature · 400 empty body ·
 *              413 too large · 503 not configured or switched off (Intuit keeps retrying, nothing is lost)
 *              · 500 storage failed (Intuit retries). Bodies say almost nothing - this is public.
 *
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5a).
 * 2026-09-23 - Jason Ott - Stamps Discovered By = Webhook (the nightly catch-up stamps Catch-up).
 */
@RestResource(urlMapping='/qbo/webhook')
global without sharing class QuickBooksWebhookReceiver {

    @TestVisible private static final String SIGNATURE_HEADER = 'intuit-signature';
    @TestVisible private static final Integer DEFAULT_MAX_BYTES = 1000000;

    global class Result {
        global String status;
        global Result(String s) { this.status = s; }
    }

    @HttpPost
    global static Result receive() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();

        // ---- 1. switched on and configured? Otherwise let Intuit retry later. -----------------
        if (cfg == null || cfg.Enabled__c != true || String.isBlank(cfg.Verifier_Token__c)) {
            res.statusCode = 503;
            return new Result('unavailable');
        }

        // ---- 2. size, then signature - before anything is parsed or stored ---------------------
        Blob body = req.requestBody;
        if (body == null || body.size() == 0) {
            res.statusCode = 400;
            return new Result('empty');
        }
        if (body.size() > maxBytes(cfg)) {
            res.statusCode = 413;
            return new Result('too large');
        }
        if (!signatureValid(body, header(req, SIGNATURE_HEADER), cfg.Verifier_Token__c)) {
            res.statusCode = 401;
            return new Result('unauthorized');
        }

        // ---- 3. one row per event --------------------------------------------------------------
        String raw = body.toString();
        List<QuickBooks_Event__c> rows = toEvents(raw, cfg.Realm_Id__c);

        // ---- 4. store; a retry's duplicates are expected and fine ------------------------------
        Boolean failed = false;
        List<Database.SaveResult> results = Database.insert(rows, false);
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                continue;
            }
            for (Database.Error err : sr.getErrors()) {
                if (err.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                    failed = true;
                    System.debug(LoggingLevel.ERROR, 'QuickBooksWebhookReceiver insert failed: ' + err.getMessage());
                }
            }
        }
        if (failed) {
            // Intuit retries the whole delivery; the rows that did save are skipped as duplicates.
            res.statusCode = 500;
            return new Result('error');
        }
        res.statusCode = 200;
        return new Result('received');
    }

    /**
     * Turns the body into event rows. Each CloudEvent keeps its own JSON as the payload. Anything that
     * isn't a CloudEvents array becomes a single Failed row holding the whole body, keyed by a hash of the
     * body so a retry of the same unreadable delivery still dedupes.
     */
    @TestVisible
    private static List<QuickBooks_Event__c> toEvents(String raw, String expectedRealm) {
        List<QuickBooks_Event__c> rows = new List<QuickBooks_Event__c>();
        Datetime now = System.now();
        List<Object> events;
        try {
            events = (List<Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            events = null;
        }
        if (events == null || events.isEmpty()) {
            rows.add(unreadable(raw, now, 'Not a CloudEvents array - check the webhook payload format is set to CloudEvents in the Intuit portal.'));
            return rows;
        }

        // Loop: one row per event; malformed individual events are kept as Failed rather than dropped.
        for (Object o : events) {
            if (!(o instanceof Map<String, Object>)) {
                rows.add(unreadable(JSON.serialize(o), now, 'Event is not a JSON object.'));
                continue;
            }
            Map<String, Object> ev = (Map<String, Object>) o;
            String id = text(ev.get('id'));
            String type = text(ev.get('type'));
            String entityId = text(ev.get('intuitentityid'));
            String realm = text(ev.get('intuitaccountid'));
            String json = JSON.serialize(ev);

            if (String.isBlank(id)) {
                rows.add(unreadable(json, now, 'Event has no id.'));
                continue;
            }

            // qbo.deposit.created.v1 -> entity "deposit", operation "created"
            String entity;
            String operation;
            List<String> parts = String.isBlank(type) ? new List<String>() : type.split('\\.');
            if (parts.size() >= 3) {
                entity = parts[1].toLowerCase();
                operation = parts[2].toLowerCase();
            }

            QuickBooks_Event__c row = new QuickBooks_Event__c(
                Event_Id__c = id.left(255),
                Event_Type__c = type == null ? null : type.left(120),
                Entity_Name__c = entity == null ? null : entity.left(60),
                Operation__c = operation == null ? null : operation.left(40),
                Entity_Id__c = entityId == null ? null : entityId.left(40),
                Entity_Key__c = (entity == null || entityId == null) ? null : (entity + '-' + entityId).toLowerCase().left(120),
                Realm_Id__c = realm == null ? null : realm.left(40),
                Event_Time__c = parseTime(text(ev.get('time'))),
                Received_At__c = now,
                Discovered_By__c = 'Webhook',
                Payload__c = json.left(131072),
                Status__c = 'Received');

            if (String.isNotBlank(expectedRealm) && realm != expectedRealm) {
                row.Status__c = 'Ignored';
                row.Error_Message__c = 'Event is for QuickBooks company ' + realm + ', not the configured company.';
            } else if (entity == null || String.isBlank(entityId)) {
                row.Status__c = 'Failed';
                row.Error_Message__c = 'Event type or entity id missing or not in the qbo.<entity>.<operation>.v1 form.';
            }
            rows.add(row);
        }
        return rows;
    }

    private static QuickBooks_Event__c unreadable(String raw, Datetime now, String reason) {
        String digest = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(raw)));
        return new QuickBooks_Event__c(
            Event_Id__c = 'unreadable-' + digest,
            Received_At__c = now,
            Discovered_By__c = 'Webhook',
            Payload__c = raw.left(131072),
            Status__c = 'Failed',
            Error_Message__c = reason);
    }

    /** base64(HMAC-SHA256(body, verifier token)) compared without an early exit. */
    @TestVisible
    private static Boolean signatureValid(Blob body, String presented, String verifierToken) {
        if (String.isBlank(presented) || String.isBlank(verifierToken)) {
            return false;
        }
        String expected = EncodingUtil.base64Encode(Crypto.generateMac('hmacSHA256', body, Blob.valueOf(verifierToken)));
        return constantTimeEquals(expected, presented.trim());
    }

    private static Boolean constantTimeEquals(String a, String b) {
        Integer diff = a.length() ^ b.length();
        Integer n = Math.min(a.length(), b.length());
        for (Integer i = 0; i < n; i++) {
            diff |= a.charAt(i) ^ b.charAt(i);
        }
        return diff == 0;
    }

    /** Header lookup that ignores capitalisation. */
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

    private static Integer maxBytes(QuickBooks_Settings__c cfg) {
        return (cfg.Max_Payload_Bytes__c != null && cfg.Max_Payload_Bytes__c > 0)
            ? Integer.valueOf(cfg.Max_Payload_Bytes__c) : DEFAULT_MAX_BYTES;
    }

    private static String text(Object o) {
        return (o == null || String.isBlank(String.valueOf(o))) ? null : String.valueOf(o);
    }

    /** ISO-8601 (2025-09-10T21:31:25.179Z) to Datetime; null if it isn't one. */
    @TestVisible
    private static Datetime parseTime(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}