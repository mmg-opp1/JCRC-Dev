/**
 * @description Turns stored QuickBooks webhook events into Pending Transactions (JSI-121 Phase 5b).
 *
 *              The webhook only says "deposit 147 was created", so this job reads the record from QuickBooks
 *              and decides what, if anything, becomes a pending transaction. It runs as a Batchable, one
 *              event at a time (callouts, then DML), started every few minutes by QuickBooksSweeper as an
 *              administrator - never as the site guest user.
 *
 *              WHAT COUNTS AS MONEY IN (decisions 2026-09-17, Jason):
 *                - A BANK DEPOSIT is the trigger. Each deposit line paid by an ACH/wire or check payment method
 *                  (QuickBooks Settings > ACH/Wire Payment Methods, "Wire-Transfer" by default; Check Payment
 *                  Methods, "Amazon Smile, Benevity, Check, E-Check" by default) becomes one pending transaction,
 *                  its Payment Method set to ACH/Wire or Check by the list that matched. Two kinds of line:
 *                    * a direct line - customer, class, payment method and reference are on the line;
 *                    * a line depositing an earlier Payment or Sales Receipt (LinkedTxn) - the customer comes
 *                      from that payment, and the class from the invoice(s) it paid (or the sales receipt's
 *                      own lines).
 *                - A PAYMENT or SALES RECEIPT deposited straight to a bank account also counts. One sitting in
 *                  Undeposited Funds is ignored here - its bank deposit brings it in, so it is never counted twice.
 *              Everything else (customers, invoices, payment methods...) is logged as Ignored.
 *
 *              FUND: the QuickBooks CLASS maps to an NPSP fund through QuickBooks Fund Map custom metadata,
 *              matched on the class's full name ("Development:Dinner"), ignoring case (decision 2026-10-23,
 *              Jason: income accounts are no longer used). An item line without its own class uses the
 *              transaction's class. If a line has no class, a class isn't mapped, or the lines span several
 *              funds, Fund is left blank and the reason goes in Import Note for staff. Dinner maps to Gala Fund,
 *              so its rows are gala.
 *
 *              UPDATES AND DELETES:
 *                - created/updated: pending rows for the record are refreshed (amount, date, reference, payer,
 *                  memo, note - not the donor, routing or fund staff may have chosen); lines no longer present
 *                  or no longer ACH/wire or check are removed while still pending;
 *                - a line imported before but no longer pending was committed or deleted by staff, so it is
 *                  NOT created again (the event's Imported External IDs are the memory of this, and a line already
 *                  committed is recognized from the source id stamped on the gift or payment - which outlives any
 *                  purge of old events);
 *                - deleted/voided: still-pending rows are removed; committed ones are reported on the event.
 *
 *              FAILURES: a temporary QuickBooks problem leaves the event Received for the next run (up to 5
 *              attempts); anything else marks it Failed with the reason. No partial writes: callouts all happen
 *              first, then the DML runs inside one savepoint. A deposit's linked records are read in a few bulk
 *              queries first; one too large for the callouts Salesforce allows is marked Failed with a clear
 *              reason (QuickBooksApi read budget) rather than retried every run.
 * @author Jason Ott
 * @created 2026-09-17
 *
 * Change Log:
 * -----------
 * 2026-09-17 - Jason Ott - Initial version (JSI-121 Phase 5b).
 * 2026-09-23 - Jason Ott - Phase 5c: a line already committed as a gift or payment is never re-created, so
 *                          purging old events cannot resurrect committed money.
 * 2026-10-23 - Jason Ott - Checks are imported like ACH/wire (client decision): Check Payment Methods setting,
 *                          and each row's Payment Method comes from the list its QuickBooks method matched.
 *                          Default check methods Amazon Smile, Benevity, Check, E-Check. Large-deposit safeguard:
 *                          prefetchForDeposit() bulk reads; Raw Data holds the deposit header, not every line.
 * 2026-10-23 - Jason Ott - American spelling (normalized, recognized).
 * 2026-10-23 - Jason Ott - Fund comes from the QuickBooks class instead of the income account (Dinner -> Gala Fund).
 */
public without sharing class QuickBooksEventProcessor implements Database.Batchable<SObject>, Database.AllowsCallouts {

    public static final Integer MAX_ATTEMPTS = 5;
    @TestVisible private static final String DEFAULT_ACH_WIRE_METHODS = 'Wire-Transfer';
    @TestVisible private static final String DEFAULT_CHECK_METHODS = 'Amazon Smile, Benevity, Check, E-Check';
    private static final String ACH_WIRE_VALUE = 'ACH/Wire';
    private static final String CHECK_VALUE = 'Check';

    /** Tests supply the fund mapping (class name -> fund name) here; custom metadata can't be inserted in a test. */
    @TestVisible private static Map<String, String> fundMapOverride;

    // =============================================================================================
    // Batch
    // =============================================================================================

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id FROM QuickBooks_Event__c
            WHERE Status__c = 'Received' AND (Attempts__c = null OR Attempts__c < :MAX_ATTEMPTS)
            ORDER BY Event_Time__c ASC NULLS LAST, Received_At__c ASC
        ]);
    }

    /** Scope 1: each event's callouts, DML and outcome are its own. */
    public void execute(Database.BatchableContext ctx, List<QuickBooks_Event__c> scope) {
        for (QuickBooks_Event__c e : scope) {
            process(e.Id);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Each event records its own outcome.
    }

    // =============================================================================================
    // One event
    // =============================================================================================

    /** What handling an event amounts to, applied in one go after every callout is done. */
    private class Outcome {
        String status = 'Processed';
        List<String> notes = new List<String>();
        List<Pending_Transaction__c> inserts = new List<Pending_Transaction__c>();
        List<Pending_Transaction__c> updates = new List<Pending_Transaction__c>();
        List<Pending_Transaction__c> deletes = new List<Pending_Transaction__c>();
    }

    /** A pending transaction as QuickBooks describes it, before it is matched against what exists. */
    private class Candidate {
        String externalId;
        String externalType;
        Decimal amount;
        Date txnDate;
        String reference;
        String depositReference;
        String customerId;
        String payerName;
        String payerEmail;
        String memo;
        String paymentMethod;
        Set<String> classNames = new Set<String>();
        Boolean unclassifiedLine = false;
        String raw;
    }

    public static void process(Id eventId) {
        QuickBooks_Event__c ev = [
            SELECT Id, Name, Status__c, Entity_Name__c, Operation__c, Entity_Id__c, Entity_Key__c, Realm_Id__c,
                   Attempts__c, Imported_External_Ids__c
            FROM QuickBooks_Event__c WHERE Id = :eventId
        ];
        // No FOR UPDATE: callouts follow, and QuickBooksSweeper never runs two processors at once.
        if (ev.Status__c != 'Received') {
            return;
        }
        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();
        if (cfg == null || cfg.Enabled__c != true) {
            return; // switched off: leave it for later
        }

        Outcome outcome;
        try {
            outcome = decide(ev, cfg);
        } catch (QuickBooksApi.QuickBooksApiException e) {
            recordFailure(ev, e.getMessage(), e.isTransient == true);
            return;
        } catch (Exception e) {
            recordFailure(ev, e.getTypeName() + ': ' + e.getMessage(), false);
            return;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            if (!outcome.deletes.isEmpty()) {
                delete outcome.deletes;
            }
            if (!outcome.updates.isEmpty()) {
                update outcome.updates;
            }
            if (!outcome.inserts.isEmpty()) {
                insert outcome.inserts;
            }
            List<String> imported = String.isBlank(ev.Imported_External_Ids__c)
                ? new List<String>() : ev.Imported_External_Ids__c.split('\n');
            for (Pending_Transaction__c p : outcome.inserts) {
                imported.add(p.External_Id__c);
            }
            ev.Imported_External_Ids__c = String.join(imported, '\n').left(32768);
            ev.Status__c = outcome.status;
            ev.Error_Message__c = outcome.notes.isEmpty() ? null : String.join(outcome.notes, ' ').left(4000);
            ev.Processed_At__c = System.now();
            ev.Attempts__c = (ev.Attempts__c == null ? 0 : ev.Attempts__c) + 1;
            update ev;
        } catch (Exception e) {
            Database.rollback(sp);
            recordFailure(ev, e.getTypeName() + ': ' + e.getMessage(), false);
        }
    }

    private static void recordFailure(QuickBooks_Event__c ev, String message, Boolean isTransient) {
        Decimal attempts = (ev.Attempts__c == null ? 0 : ev.Attempts__c) + 1;
        update new QuickBooks_Event__c(
            Id = ev.Id,
            Attempts__c = attempts,
            Status__c = isTransient && attempts < MAX_ATTEMPTS ? 'Received' : 'Failed',
            Error_Message__c = ((isTransient && attempts < MAX_ATTEMPTS ? 'Will retry: ' : '') + message).left(4000),
            Processed_At__c = System.now());
    }

    /** Callouts only - works out what should change. No DML happens in here. */
    private static Outcome decide(QuickBooks_Event__c ev, QuickBooks_Settings__c cfg) {
        Outcome out = new Outcome();
        String entity = ev.Entity_Name__c;
        String op = ev.Operation__c;
        String realm = cfg.Realm_Id__c == null ? null : cfg.Realm_Id__c.trim();

        if (String.isNotBlank(realm) && ev.Realm_Id__c != realm) {
            out.status = 'Ignored';
            out.notes.add('Event is for another QuickBooks company.');
            return out;
        }
        Boolean removal = op == 'deleted' || op == 'voided';
        Boolean change = op == 'created' || op == 'updated';

        if (entity == 'deposit' && (change || removal)) {
            String prefix = 'qbo-deposit-' + ev.Entity_Id__c + '-';
            List<Candidate> candidates = new List<Candidate>();
            if (change) {
                Map<String, Object> dep = fetchOrNull('Deposit', ev.Entity_Id__c);
                if (dep == null) {
                    removal = true; // deleted in QuickBooks since the event
                } else {
                    candidates = depositCandidates(dep, importedMethods(cfg), out);
                }
            }
            reconcile(out, ev, prefix, candidates, removal);
            return out;
        }

        if ((entity == 'payment' || entity == 'salesreceipt') && (change || removal)) {
            String qbEntity = entity == 'payment' ? 'Payment' : 'SalesReceipt';
            String externalId = 'qbo-' + entity + '-' + ev.Entity_Id__c;
            List<Candidate> candidates = new List<Candidate>();
            if (change) {
                Map<String, Object> rec = fetchOrNull(qbEntity, ev.Entity_Id__c);
                if (rec == null) {
                    removal = true;
                } else {
                    String depositTo = QuickBooksApi.refValue(rec.get('DepositToAccountRef'));
                    if (depositTo == null || isUndepositedFunds(depositTo)) {
                        out.status = 'Ignored';
                        out.notes.add('In Undeposited Funds - it will come in with its bank deposit.');
                        return out;
                    }
                    Candidate c = linkedCandidate(qbEntity, rec, importedMethods(cfg), null, out);
                    if (c != null) {
                        c.externalId = externalId;
                        c.externalType = entity == 'payment' ? 'Payment' : 'Sales Receipt';
                        enrichCustomer(c);
                        candidates.add(c);
                    }
                }
            }
            reconcile(out, ev, externalId, candidates, removal);
            return out;
        }

        out.status = 'Ignored';
        out.notes.add('Not a money-in transaction (' + entity + ' ' + op + ').');
        return out;
    }

    // =============================================================================================
    // Reading QuickBooks records into candidates
    // =============================================================================================

    private static List<Candidate> depositCandidates(Map<String, Object> dep, Map<String, String> methods, Outcome out) {
        List<Candidate> result = new List<Candidate>();
        String depositId = QuickBooksApi.str(dep.get('Id'));
        Date txnDate = parseDate(dep.get('TxnDate'));
        Integer index = 0;
        Integer skipped = 0;
        prefetchForDeposit(dep);

        // The deposit without its lines, stored on each row with that row's own line. Repeating the whole
        // deposit on every row would grow with the square of the line count and exhaust heap on a big deposit.
        Map<String, Object> depositHeader = dep.clone();
        depositHeader.remove('Line');
        String depositJson = JSON.serialize(depositHeader);

        // Loop: one candidate per ACH/wire or check line.
        for (Object o : QuickBooksApi.items(dep.get('Line'))) {
            index++;
            Map<String, Object> line = QuickBooksApi.obj(o);
            if (line == null) {
                continue;
            }
            Map<String, Object> detail = QuickBooksApi.obj(line.get('DepositLineDetail'));
            Map<String, Object> linked = firstLinked(line, new Set<String>{ 'Payment', 'SalesReceipt' });
            Candidate c;

            if (linked != null) {
                String type = String.valueOf(linked.get('TxnType'));
                String txnId = String.valueOf(linked.get('TxnId'));
                Map<String, Object> source = QuickBooksApi.get(type, txnId);
                c = linkedCandidate(type, source, methods, detail, out);
                if (c != null) {
                    c.externalId = 'qbo-deposit-' + depositId + '-' + type.toLowerCase() + '-' + txnId;
                    c.externalType = 'Deposit (' + (type == 'Payment' ? 'Payment' : 'Sales Receipt') + ')';
                }
            } else if (QuickBooksApi.items(line.get('LinkedTxn')).size() > 0) {
                out.notes.add('Deposit line ' + index + ' deposits a ' + String.valueOf(QuickBooksApi.obj(
                    QuickBooksApi.items(line.get('LinkedTxn'))[0]).get('TxnType')) + ', which is not imported.');
                continue;
            } else if (detail != null) {
                String methodName = normalize(paymentMethodName(detail.get('PaymentMethodRef')));
                if (!methods.containsKey(methodName)) {
                    skipped++;
                    continue;
                }
                c = new Candidate();
                c.paymentMethod = methods.get(methodName);
                String lineId = QuickBooksApi.str(line.get('Id'));
                c.externalId = 'qbo-deposit-' + depositId + '-' + (lineId != null ? 'l' + lineId : 'n' + index);
                c.externalType = 'Deposit';
                c.reference = QuickBooksApi.str(detail.get('CheckNum'));
                Map<String, Object> entityRef = QuickBooksApi.obj(detail.get('Entity'));
                if (entityRef != null && String.valueOf(entityRef.get('type')) == 'CUSTOMER') {
                    c.customerId = QuickBooksApi.refValue(entityRef);
                    c.payerName = QuickBooksApi.refName(entityRef);
                }
                addClass(c, QuickBooksApi.refName(detail.get('ClassRef')));
                c.memo = QuickBooksApi.str(line.get('Description'));
                c.raw = JSON.serialize(line);
            } else {
                continue;
            }

            if (c == null) {
                skipped++;
                continue;
            }
            c.amount = line.get('Amount') == null ? null : Decimal.valueOf(String.valueOf(line.get('Amount')));
            c.txnDate = txnDate;
            c.depositReference = ('QBO Deposit ' + depositId).left(30);
            if (c.memo == null) {
                c.memo = QuickBooksApi.str(line.get('Description'));
            }
            c.raw = '{"deposit":' + depositJson + ',"line":' + JSON.serialize(line)
                + (c.raw != null && linked != null ? ',"source":' + c.raw : '') + '}';
            enrichCustomer(c);
            result.add(c);
        }
        if (skipped > 0) {
            out.notes.add(skipped + ' deposit line(s) skipped - payment method is not ACH/wire or check.');
        }
        return result;
    }

    /**
     * Reads everything a deposit's lines will need in a handful of queries, before the line loop: the linked
     * Payments and Sales Receipts, then the invoices those payments paid, the customers and any payment methods
     * given by id only. The loop then finds them in QuickBooksApi's cache, so a deposit of hundreds of checks
     * costs about six callouts instead of three or four per line. Anything not found here (deleted in
     * QuickBooks) is read on its own later, exactly as before.
     */
    private static void prefetchForDeposit(Map<String, Object> dep) {
        Set<String> paymentIds = new Set<String>();
        Set<String> receiptIds = new Set<String>();
        Set<String> customerIds = new Set<String>();
        Set<String> methodIds = new Set<String>();

        // Loop: what each deposit line points at.
        for (Object o : QuickBooksApi.items(dep.get('Line'))) {
            Map<String, Object> line = QuickBooksApi.obj(o);
            if (line == null) {
                continue;
            }
            Map<String, Object> linked = firstLinked(line, new Set<String>{ 'Payment', 'SalesReceipt' });
            if (linked != null) {
                (String.valueOf(linked.get('TxnType')) == 'Payment' ? paymentIds : receiptIds)
                    .add(String.valueOf(linked.get('TxnId')));
            }
            Map<String, Object> detail = QuickBooksApi.obj(line.get('DepositLineDetail'));
            if (detail != null) {
                addMethodId(methodIds, detail.get('PaymentMethodRef'));
                Map<String, Object> entityRef = QuickBooksApi.obj(detail.get('Entity'));
                if (entityRef != null && String.valueOf(entityRef.get('type')) == 'CUSTOMER') {
                    addIfPresent(customerIds, QuickBooksApi.refValue(entityRef));
                }
            }
        }
        QuickBooksApi.prefetch('Payment', paymentIds);
        QuickBooksApi.prefetch('SalesReceipt', receiptIds);

        // Loop: from the payments and receipts just read, their customers, methods and paid invoices.
        Set<String> invoiceIds = new Set<String>();
        List<Map<String, Object>> sources = new List<Map<String, Object>>();
        for (String id : paymentIds) {
            sources.add(QuickBooksApi.cached('Payment', id));
        }
        for (String id : receiptIds) {
            sources.add(QuickBooksApi.cached('SalesReceipt', id));
        }
        for (Map<String, Object> rec : sources) {
            if (rec == null) {
                continue;
            }
            addIfPresent(customerIds, QuickBooksApi.refValue(rec.get('CustomerRef')));
            addMethodId(methodIds, rec.get('PaymentMethodRef'));
            for (Object lo : QuickBooksApi.items(rec.get('Line'))) {
                Map<String, Object> pl = QuickBooksApi.obj(lo);
                for (Object to : QuickBooksApi.items(pl == null ? null : pl.get('LinkedTxn'))) {
                    Map<String, Object> t = QuickBooksApi.obj(to);
                    if (t != null && String.valueOf(t.get('TxnType')) == 'Invoice') {
                        addIfPresent(invoiceIds, String.valueOf(t.get('TxnId')));
                    }
                }
            }
        }
        QuickBooksApi.prefetch('Invoice', invoiceIds);
        QuickBooksApi.prefetch('Customer', customerIds);
        QuickBooksApi.prefetch('PaymentMethod', methodIds);
    }

    /** A payment method given by id only is looked up by name later, so it is worth prefetching. */
    private static void addMethodId(Set<String> ids, Object ref) {
        if (QuickBooksApi.refName(ref) == null) {
            addIfPresent(ids, QuickBooksApi.refValue(ref));
        }
    }

    private static void addIfPresent(Set<String> ids, String id) {
        if (String.isNotBlank(id)) {
            ids.add(id);
        }
    }

    /**
     * A Payment or Sales Receipt, either deposited by a bank deposit line or deposited straight to a bank.
     * Returns null when its payment method isn't ACH/wire or check.
     */
    private static Candidate linkedCandidate(String type, Map<String, Object> rec, Map<String, String> methods,
                                             Map<String, Object> depositLineDetail, Outcome out) {
        Object methodRef = depositLineDetail != null && depositLineDetail.get('PaymentMethodRef') != null
            ? depositLineDetail.get('PaymentMethodRef') : rec.get('PaymentMethodRef');
        String methodName = normalize(paymentMethodName(methodRef));
        if (!methods.containsKey(methodName)) {
            return null;
        }
        Candidate c = new Candidate();
        c.paymentMethod = methods.get(methodName);
        c.customerId = QuickBooksApi.refValue(rec.get('CustomerRef'));
        c.payerName = QuickBooksApi.refName(rec.get('CustomerRef'));
        c.amount = rec.get('TotalAmt') == null ? null : Decimal.valueOf(String.valueOf(rec.get('TotalAmt')));
        c.txnDate = parseDate(rec.get('TxnDate'));
        String ref = depositLineDetail == null ? null : QuickBooksApi.str(depositLineDetail.get('CheckNum'));
        c.reference = ref != null ? ref : QuickBooksApi.str(rec.get('PaymentRefNum'));
        c.memo = QuickBooksApi.str(rec.get('PrivateNote'));
        c.raw = JSON.serialize(rec);

        if (type == 'Payment') {
            // Classes live on the invoice(s) the payment paid.
            for (Object lo : QuickBooksApi.items(rec.get('Line'))) {
                for (Object to : QuickBooksApi.items(QuickBooksApi.obj(lo) == null ? null : QuickBooksApi.obj(lo).get('LinkedTxn'))) {
                    Map<String, Object> t = QuickBooksApi.obj(to);
                    if (t != null && String.valueOf(t.get('TxnType')) == 'Invoice') {
                        addSalesLineClasses(QuickBooksApi.get('Invoice', String.valueOf(t.get('TxnId'))), c);
                    }
                }
            }
        } else {
            addSalesLineClasses(rec, c);
        }
        return c;
    }

    /**
     * The class of each item line on an invoice or sales receipt. Subtotal, discount and tax lines carry no
     * class and are passed over. An item line without its own class takes the transaction's class (Finance may
     * track one class per transaction); with neither, the line is unclassified and the fund is left to staff.
     */
    private static void addSalesLineClasses(Map<String, Object> rec, Candidate c) {
        String headerClass = QuickBooksApi.refName(rec.get('ClassRef'));
        // Loop: item lines only.
        for (Object lo : QuickBooksApi.items(rec.get('Line'))) {
            Map<String, Object> line = QuickBooksApi.obj(lo);
            Map<String, Object> sales = line == null ? null : QuickBooksApi.obj(line.get('SalesItemLineDetail'));
            if (sales == null) {
                continue;
            }
            String className = QuickBooksApi.refName(sales.get('ClassRef'));
            addClass(c, className != null ? className : headerClass);
        }
    }

    /** Records one line's class by its full name ("Development:Dinner"), or that the line had none. */
    private static void addClass(Candidate c, String className) {
        if (String.isBlank(className)) {
            c.unclassifiedLine = true;
        } else {
            c.classNames.add(className.trim());
        }
    }

    private static void enrichCustomer(Candidate c) {
        if (c.customerId == null) {
            return;
        }
        Map<String, Object> cust = fetchOrNull('Customer', c.customerId);
        if (cust == null) {
            return;
        }
        String display = QuickBooksApi.str(cust.get('DisplayName'));
        if (display != null) {
            c.payerName = display;
        }
        c.payerEmail = QuickBooksApi.str(QuickBooksApi.obj(cust.get('PrimaryEmailAddr')) == null
            ? null : QuickBooksApi.obj(cust.get('PrimaryEmailAddr')).get('Address'));
    }

    // =============================================================================================
    // Matching candidates against what already exists
    // =============================================================================================

    /**
     * Decides inserts, refreshes and removals for one QuickBooks record. `key` is the External ID prefix
     * (deposits, whose lines share it) or the exact External ID (a payment or sales receipt).
     */
    private static void reconcile(Outcome out, QuickBooks_Event__c ev, String key, List<Candidate> candidates, Boolean removal) {
        String likeKey = key.endsWith('-') ? key + '%' : key;
        Map<String, Pending_Transaction__c> pending = new Map<String, Pending_Transaction__c>();
        for (Pending_Transaction__c p : [SELECT Id, External_Id__c, Fund__c FROM Pending_Transaction__c
                                         WHERE External_Id__c LIKE :likeKey]) {
            pending.put(p.External_Id__c.toLowerCase(), p);
        }

        // Every External ID imported before for this QuickBooks record (by any earlier event).
        Set<String> importedBefore = new Set<String>();
        // Long text can't be filtered in SOQL, so blank ones are skipped here.
        for (QuickBooks_Event__c prior : [SELECT Imported_External_Ids__c FROM QuickBooks_Event__c
                                          WHERE Entity_Key__c = :ev.Entity_Key__c]) {
            if (String.isBlank(prior.Imported_External_Ids__c)) {
                continue;
            }
            for (String s : prior.Imported_External_Ids__c.split('\n')) {
                importedBefore.add(s.trim().toLowerCase());
            }
        }

        // Already committed? The source id stamped on the gift or payment says so, whatever the event log holds.
        Set<String> committed = new Set<String>();
        if (!candidates.isEmpty()) {
            Set<String> candidateIds = new Set<String>();
            for (Candidate c : candidates) {
                candidateIds.add(c.externalId);
            }
            for (Opportunity o : [SELECT Source_Transaction_Id__c FROM Opportunity
                                  WHERE Source_Transaction_Id__c IN :candidateIds]) {
                committed.add(o.Source_Transaction_Id__c.toLowerCase());
            }
            for (npe01__OppPayment__c p : [SELECT Source_Transaction_Id__c FROM npe01__OppPayment__c
                                           WHERE Source_Transaction_Id__c IN :candidateIds]) {
                committed.add(p.Source_Transaction_Id__c.toLowerCase());
            }
        }

        Set<String> keep = new Set<String>();
        if (!removal) {
            Map<String, String> funds = fundMap();
            Map<String, Id> gauIds = gauIdsByName(funds.values());
            for (Candidate c : candidates) {
                String extId = c.externalId.toLowerCase();
                keep.add(extId);
                Pending_Transaction__c existing = pending.get(extId);
                if (existing != null) {
                    Pending_Transaction__c upd = toRecord(c, funds, gauIds, false);
                    upd.Id = existing.Id;
                    // A fund already on the row (chosen by staff, or mapped earlier) is kept.
                    if (existing.Fund__c != null) {
                        upd.Fund__c = existing.Fund__c;
                    }
                    out.updates.add(upd);
                } else if (committed.contains(extId)) {
                    out.notes.add(c.externalId + ' is already committed in Salesforce - not re-created.');
                } else if (importedBefore.contains(extId)) {
                    out.notes.add(c.externalId + ' was imported before and has since been committed or deleted - not re-created.');
                } else {
                    out.inserts.add(toRecord(c, funds, gauIds, true));
                }
            }
        }

        // Still-pending rows that QuickBooks no longer describes (removed line, changed method, deleted record).
        Integer removed = 0;
        for (String extId : pending.keySet()) {
            if (!keep.contains(extId)) {
                out.deletes.add(new Pending_Transaction__c(Id = pending.get(extId).Id));
                removed++;
            }
        }
        if (removed > 0) {
            out.notes.add('Removed ' + removed + ' pending transaction(s) no longer in QuickBooks as ACH/wire or check.');
        }
        if (removal && removed == 0 && !importedBefore.isEmpty()) {
            out.notes.add('Deleted or voided in QuickBooks after it was committed or deleted in Salesforce - check the gift.');
        }
        if (out.inserts.isEmpty() && out.updates.isEmpty() && removed == 0 && candidates.isEmpty() && !removal
                && out.notes.isEmpty()) {
            out.status = 'Ignored';
            out.notes.add('No ACH/wire or check money in this transaction.');
        }
    }

    private static Pending_Transaction__c toRecord(Candidate c, Map<String, String> funds, Map<String, Id> gauIds, Boolean isNew) {
        Pending_Transaction__c p = new Pending_Transaction__c(
            External_Id__c = c.externalId,
            External_Type__c = c.externalType == null ? null : c.externalType.left(40),
            Amount__c = c.amount,
            Transaction_Date__c = c.txnDate,
            Deposit_Date__c = c.depositReference == null ? null : c.txnDate,
            Deposit_Reference__c = c.depositReference,
            Payment_Method__c = c.paymentMethod,
            Reference_Number__c = c.reference == null ? null : c.reference.left(255),
            Payer_Name__c = c.payerName == null ? null : c.payerName.left(255),
            Payer_Email__c = isEmail(c.payerEmail) ? c.payerEmail : null,
            Memo__c = c.memo == null ? null : c.memo.left(4000),
            QuickBooks_Customer_Id__c = c.customerId,
            Raw_Data__c = c.raw == null ? null : c.raw.left(131072));
        if (isNew) {
            p.Source__c = 'QuickBooks';
        }

        // Fund from the QuickBooks class(es) of the lines.
        List<String> notes = new List<String>();
        Set<String> gauNames = new Set<String>();
        for (String className : c.classNames) {
            String gau = funds.get(normalize(className));
            if (gau == null) {
                notes.add('QuickBooks class "' + className + '" is not mapped to a fund - choose the fund.');
            } else {
                gauNames.add(gau);
            }
        }
        if (c.classNames.isEmpty()) {
            notes.add('No QuickBooks class on this transaction - choose the fund.');
        } else if (c.unclassifiedLine) {
            notes.add('Some QuickBooks lines have no class - choose the fund.');
        } else if (gauNames.size() > 1) {
            notes.add('The QuickBooks lines span several funds (' + String.join(new List<String>(gauNames), ', ') + ') - choose the fund.');
        } else if (gauNames.size() == 1 && notes.isEmpty()) {
            String name = new List<String>(gauNames)[0];
            if (gauIds.containsKey(name.toLowerCase())) {
                p.Fund__c = gauIds.get(name.toLowerCase());
            } else {
                notes.add('Fund "' + name + '" from the QuickBooks Fund Map was not found or is inactive.');
            }
        }
        if (c.customerId == null) {
            notes.add('No QuickBooks customer on this line - choose the donor.');
        }
        p.Import_Note__c = notes.isEmpty() ? null : String.join(notes, ' ').left(4000);
        return p;
    }

    // =============================================================================================
    // Lookups
    // =============================================================================================

    /** QuickBooks class full name (normalized) -> fund (GAU) name, from active QuickBooks Fund Map records. */
    private static Map<String, String> fundMap() {
        Map<String, String> out = new Map<String, String>();
        if (fundMapOverride != null) {
            for (String className : fundMapOverride.keySet()) {
                out.put(normalize(className), fundMapOverride.get(className));
            }
            return out;
        }
        for (QuickBooks_Fund_Map__mdt m : QuickBooks_Fund_Map__mdt.getAll().values()) {
            if (m.Active__c && String.isNotBlank(m.QBO_Class_Name__c) && String.isNotBlank(m.GAU_Name__c)) {
                out.put(normalize(m.QBO_Class_Name__c), m.GAU_Name__c.trim());
            }
        }
        return out;
    }

    private static Map<String, Id> gauIdsByName(List<String> names) {
        Map<String, Id> out = new Map<String, Id>();
        Set<String> wanted = new Set<String>(names);
        if (wanted.isEmpty()) {
            return out;
        }
        for (npsp__General_Accounting_Unit__c g : [SELECT Id, Name FROM npsp__General_Accounting_Unit__c
                                                   WHERE Name IN :wanted AND npsp__Active__c = true]) {
            out.put(g.Name.toLowerCase(), g.Id);
        }
        return out;
    }

    /**
     * QuickBooks payment method name (normalized) -> the Pending Transaction Payment Method it imports as.
     * Only lines whose method is in here are imported. A name in both lists counts as ACH/Wire.
     */
    private static Map<String, String> importedMethods(QuickBooks_Settings__c cfg) {
        Map<String, String> out = new Map<String, String>();
        addMethods(out, String.isBlank(cfg.Check_Payment_Methods__c) ? DEFAULT_CHECK_METHODS : cfg.Check_Payment_Methods__c, CHECK_VALUE);
        addMethods(out, String.isBlank(cfg.ACH_Wire_Payment_Methods__c) ? DEFAULT_ACH_WIRE_METHODS : cfg.ACH_Wire_Payment_Methods__c, ACH_WIRE_VALUE);
        return out;
    }

    /** Adds each name in a comma-separated setting, mapped to one Payment Method value. */
    private static void addMethods(Map<String, String> out, String commaSeparated, String value) {
        for (String s : commaSeparated.split(',')) {
            if (String.isNotBlank(s)) {
                out.put(normalize(s), value);
            }
        }
    }

    /** The payment method's name; the reference on a deposit line often carries only the id. */
    private static String paymentMethodName(Object ref) {
        String name = QuickBooksApi.refName(ref);
        String id = QuickBooksApi.refValue(ref);
        if (name == null && id != null) {
            name = QuickBooksApi.str(QuickBooksApi.get('PaymentMethod', id).get('Name'));
        }
        return name;
    }

    private static Boolean isUndepositedFunds(String accountId) {
        Map<String, Object> acct = QuickBooksApi.get('Account', accountId);
        return String.valueOf(acct.get('AccountSubType')) == 'UndepositedFunds';
    }

    private static Map<String, Object> fetchOrNull(String entity, String id) {
        try {
            return QuickBooksApi.get(entity, id);
        } catch (QuickBooksApi.QuickBooksApiException e) {
            if (e.isNotFound == true) {
                return null;
            }
            throw e;
        }
    }

    private static Map<String, Object> firstLinked(Map<String, Object> line, Set<String> types) {
        for (Object o : QuickBooksApi.items(line.get('LinkedTxn'))) {
            Map<String, Object> t = QuickBooksApi.obj(o);
            if (t != null && types.contains(String.valueOf(t.get('TxnType')))) {
                return t;
            }
        }
        return null;
    }

    private static String normalize(String s) {
        return s == null ? '' : s.trim().toLowerCase();
    }

    private static Date parseDate(Object o) {
        String s = QuickBooksApi.str(o);
        try {
            return s == null ? null : Date.valueOf(s.left(10));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isEmail(String s) {
        return s != null && Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', s);
    }
}