/**
 * @description Reads records from the QuickBooks Online Accounting API through the `Quickbooks` Named
 *              Credential (JSI-121 Phase 5b).
 *
 *              Read-only by design: Salesforce never writes to QuickBooks. Records are read one by id
 *              (GET /v3/company/{realm}/{entity}/{id}) or many at once by prefetch() (a query with
 *              "Id in (...)", verified against the sandbox company 2026-10-23), and results are cached for the
 *              transaction so a deposit with several lines doesn't fetch the same record twice.
 *
 *              READ BUDGET: Salesforce allows 100 callouts per transaction, and going over is a LimitException
 *              no code can catch - the event would stay Received and fail again every run. Every read therefore
 *              checks the budget first and, when it is spent, throws a normal (not retried) QuickBooksApiException
 *              saying the transaction is too large to import, so the event is marked Failed with that reason.
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
 * 2026-10-23 - Jason Ott - prefetch() reads many records in one query; read budget guard (large check deposits).
 */
public with sharing class QuickBooksApi {

    /** Named Credential developer name, as created in Setup. */
    @TestVisible private static final String NAMED_CREDENTIAL = 'Quickbooks';

    /** Minor version pins the response shape. */
    @TestVisible private static final String MINOR_VERSION = '75';

    private static final Map<String, Map<String, Object>> CACHE = new Map<String, Map<String, Object>>();

    /** Ids per prefetch query. QuickBooks ids are short numbers, so 100 keeps the request URL small. */
    @TestVisible private static final Integer IDS_PER_QUERY = 100;

    /** Tests lower the callout budget here; null = the Salesforce limit. */
    @TestVisible private static Integer calloutBudgetOverride;

    /** Reads made by this class in the transaction (counted here too, so a test's mock callouts count). */
    private static Integer readsMade = 0;

    public static final String TOO_LARGE_MESSAGE = 'Too large to import automatically: reading it from QuickBooks '
        + 'needs more callouts than Salesforce allows in one run. Enter it on the Pending Transactions screen by hand.';

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
        spendCallout();
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
        spendCallout();
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

    /**
     * Reads every listed record of one entity into the cache with as few queries as possible, so later get()
     * calls for them make no callout. Ids already cached are skipped. An id QuickBooks doesn't return (deleted)
     * is simply not cached - get() then reads it on its own and reports it as not found, as before.
     */
    public static void prefetch(String entity, Set<String> ids) {
        List<String> wanted = new List<String>();
        for (String id : ids) {
            // Only plain QuickBooks ids go into the query text; anything else is left to get().
            if (id != null && Pattern.matches('^[0-9A-Za-z-]+$', id) && !CACHE.containsKey(entity.toLowerCase() + '/' + id)) {
                wanted.add(id);
            }
        }
        // Loop: one query per IDS_PER_QUERY ids.
        for (Integer start = 0; start < wanted.size(); start += IDS_PER_QUERY) {
            List<String> chunk = new List<String>();
            for (Integer i = start; i < Math.min(start + IDS_PER_QUERY, wanted.size()); i++) {
                chunk.add('\'' + wanted[i] + '\'');
            }
            String q = 'select * from ' + entity + ' where Id in (' + String.join(chunk, ', ') + ') maxresults 1000';
            for (Object o : query(entity, q)) {
                Map<String, Object> record = obj(o);
                if (record != null && record.get('Id') != null) {
                    CACHE.put(entity.toLowerCase() + '/' + String.valueOf(record.get('Id')), record);
                }
            }
        }
    }

    /** The record if prefetch() or get() has already read it in this transaction, else null. No callout. */
    public static Map<String, Object> cached(String entity, String id) {
        return id == null ? null : CACHE.get(entity.toLowerCase() + '/' + id);
    }

    /** Runs one QuickBooks query and returns the records of the entity it selects. */
    private static List<Object> query(String entity, String q) {
        String realm = realmId();
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        spendCallout();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v3/company/' + EncodingUtil.urlEncode(realm, 'UTF-8')
            + '/query?query=' + EncodingUtil.urlEncode(q, 'UTF-8') + '&minorversion=' + MINOR_VERSION);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            QuickBooksApiException ex = new QuickBooksApiException('Could not reach QuickBooks: ' + e.getMessage());
            ex.isTransient = true;
            throw ex;
        }
        Integer status = res.getStatusCode();
        if (status != 200) {
            throw failure(status, 'QuickBooks query for ' + entity + ' returned HTTP ' + status + ': '
                + (res.getBody() == null ? '' : res.getBody().left(500)), status == 401 || status == 429 || status >= 500, false);
        }
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> qr = obj(root.get('QueryResponse'));
        return qr == null ? new List<Object>() : items(qr.get(entity));
    }

    /**
     * Called before every callout. When the transaction's callouts are used up, throws a not-retried error
     * instead of letting Salesforce stop the run with an uncatchable limit error.
     */
    private static void spendCallout() {
        Integer budget = calloutBudgetOverride != null ? calloutBudgetOverride : Limits.getLimitCallouts();
        if (Math.max(readsMade, Limits.getCallouts()) >= budget) {
            throw failure(null, TOO_LARGE_MESSAGE, false, false);
        }
        readsMade++;
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