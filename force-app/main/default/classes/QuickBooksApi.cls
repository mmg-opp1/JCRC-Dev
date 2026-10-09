/**
 * @description Reads records from the QuickBooks Online Accounting API through the `Quickbooks` Named
 *              Credential (JSI-121 Phase 5b).
 *
 *              Read-only by design: Salesforce never writes to QuickBooks. Every read is for one entity by id
 *              (GET /v3/company/{realm}/{entity}/{id}), and results are cached for the transaction so a
 *              deposit with several lines doesn't fetch the same customer or payment method twice.
 *
 *              Failures are classified so the processor can decide whether to try again later:
 *                - transient (retry): QuickBooks rate limit (429), QuickBooks errors (5xx), an expired or
 *                  refreshing token (401), or the callout itself failing (timeout, connection);
 *                - not found (404 / "Object Not Found"): the record was deleted in QuickBooks;
 *                - anything else: a real problem, not retried.
 *
 *              The company (realm) id comes from the QuickBooks Settings custom setting.
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5b).
 * 2026-09-23 - Jason Ott - changesSince() for the nightly catch-up (JSI-121 Phase 5c).
 */
public with sharing class QuickBooksApi {

    /** Named Credential developer name, as created in Setup. */
    @TestVisible private static final String NAMED_CREDENTIAL = 'Quickbooks';

    /** Minor version pins the response shape. */
    @TestVisible private static final String MINOR_VERSION = '75';

    private static final Map<String, Map<String, Object>> CACHE = new Map<String, Map<String, Object>>();

    public class QuickBooksApiException extends Exception {
        public Integer statusCode;
        public Boolean isTransient = false;
        public Boolean isNotFound = false;
    }

    /**
     * One QuickBooks record, e.g. get('Deposit', '145') returns the "Deposit" object from the response.
     * Entity names are QuickBooks' own (Deposit, Payment, SalesReceipt, Invoice, Customer, Account,
     * PaymentMethod).
     */
    public static Map<String, Object> get(String entity, String id) {
        String key = entity.toLowerCase() + '/' + id;
        if (CACHE.containsKey(key)) {
            return CACHE.get(key);
        }
        String realm = realmId();
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(20000);
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v3/company/' + EncodingUtil.urlEncode(realm, 'UTF-8') + '/'
            + entity.toLowerCase() + '/' + EncodingUtil.urlEncode(id, 'UTF-8') + '?minorversion=' + MINOR_VERSION);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            QuickBooksApiException ex = new QuickBooksApiException('Could not reach QuickBooks: ' + e.getMessage());
            ex.isTransient = true;
            throw ex;
        }

        Integer status = res.getStatusCode();
        String body = res.getBody();
        if (status == 200) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
            Map<String, Object> record = (Map<String, Object>) root.get(entity);
            if (record == null) {
                throw failure(status, 'QuickBooks returned no ' + entity + ' for id ' + id + '.', false, true);
            }
            CACHE.put(key, record);
            return record;
        }
        Boolean notFound = status == 404 || (status == 400 && body != null && body.contains('Object Not Found'));
        Boolean isTransient = status == 401 || status == 429 || status >= 500;
        throw failure(status, 'QuickBooks ' + entity + ' ' + id + ' returned HTTP ' + status + ': '
            + (body == null ? '' : body.left(500)), isTransient, notFound);
    }

    /**
     * QuickBooks change tracking: every record of these entities changed since the given moment, as the list of
     * per-entity QueryResponse objects. An entity with no changes comes back as an empty object, and deleted
     * records come back with status "Deleted".
     *
     * The timestamp must be ISO-8601 with a Z or +hh:mm offset - QuickBooks rejects "-0000" with
     * "not valid for property MetaData.LastUpdatedTime" (verified 2026-09-23).
     */
    public static List<Object> changesSince(List<String> entities, Datetime since) {
        String realm = realmId();
        String stamp = since.formatGmt('yyyy-MM-dd') + 'T' + since.formatGmt('HH:mm:ss') + 'Z';
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v3/company/' + EncodingUtil.urlEncode(realm, 'UTF-8')
            + '/cdc?entities=' + EncodingUtil.urlEncode(String.join(entities, ','), 'UTF-8')
            + '&changedSince=' + EncodingUtil.urlEncode(stamp, 'UTF-8') + '&minorversion=' + MINOR_VERSION);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            QuickBooksApiException ex = new QuickBooksApiException('Could not reach QuickBooks: ' + e.getMessage());
            ex.isTransient = true;
            throw ex;
        }
        if (res.getStatusCode() != 200) {
            QuickBooksApiException ex = new QuickBooksApiException('QuickBooks change tracking returned HTTP '
                + res.getStatusCode() + ': ' + (res.getBody() == null ? '' : res.getBody().left(500)));
            ex.statusCode = res.getStatusCode();
            ex.isTransient = res.getStatusCode() == 401 || res.getStatusCode() == 429 || res.getStatusCode() >= 500;
            throw ex;
        }
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> out = new List<Object>();
        for (Object o : items(root.get('CDCResponse'))) {
            Map<String, Object> cdc = obj(o);
            if (cdc != null) {
                out.addAll(items(cdc.get('QueryResponse')));
            }
        }
        return out;
    }

    public static String realmId() {
        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Realm_Id__c)) {
            QuickBooksApiException ex = new QuickBooksApiException('QuickBooks Settings has no Company ID (Realm ID).');
            throw ex;
        }
        return cfg.Realm_Id__c.trim();
    }

    // ---- small readers for the untyped JSON QuickBooks returns --------------------------------

    public static Map<String, Object> obj(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
    }

    public static List<Object> items(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    /** The "value" of a QuickBooks reference such as {"value":"4","name":"Diego Rodriguez"}. */
    public static String refValue(Object ref) {
        Map<String, Object> m = obj(ref);
        return m == null || m.get('value') == null ? null : String.valueOf(m.get('value'));
    }

    public static String refName(Object ref) {
        Map<String, Object> m = obj(ref);
        return m == null || m.get('name') == null ? null : String.valueOf(m.get('name'));
    }

    public static String str(Object o) {
        return o == null || String.isBlank(String.valueOf(o)) ? null : String.valueOf(o);
    }

    private static QuickBooksApiException failure(Integer status, String message, Boolean isTransient, Boolean notFound) {
        QuickBooksApiException ex = new QuickBooksApiException(message);
        ex.statusCode = status;
        ex.isTransient = isTransient;
        ex.isNotFound = notFound;
        return ex;
    }
}