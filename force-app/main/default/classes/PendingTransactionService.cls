/**
 * @description The engine behind the Pending Transactions holding area (JSI-121).
 *
 *              Money that reaches the bank outside Salesforce - ACH and wire from QuickBooks, Pay Now
 *              gala sponsorships - lands in Pending_Transaction__c first. Staff review each row, fix
 *              anything wrong, and COMMIT it. This class does everything around that:
 *
 *                - EVALUATE: works out whether a row can be committed and, if not, says why in plain
 *                  English. Runs from the trigger on every save, so Status__c is always current.
 *                - SUGGEST: on arrival, proposes a donor from the payer's email or name. A suggestion is
 *                  never committed silently - the user confirms it (confirmDonors) or picks another.
 *                - OPEN PLEDGES: the donor's Pledges and Grants that still have money outstanding.
 *                - PLAN: turns "apply $R to this pledge" into concrete installment changes, using the
 *                  rules Jason set (decisions D2 / D11). Pure - no DML - so the screen can preview it.
 *                - COMMIT: creates the gift or applies the payment, stamps the source id on whichever
 *                  record it created (D4), and deletes the holding row. Each row runs inside its own
 *                  savepoint, so one bad row fails alone and keeps its error for the user.
 *
 *              Installment rules (received amount R, pledge outstanding B, unpaid installments in date
 *              order, oldest O):
 *                1. R > B            -> refused.
 *                2. R = O            -> O marked paid.
 *                3. R < O            -> O set to R and paid; a new unpaid payment carries the remainder,
 *                                       scheduled on O's date.
 *                4. R > O            -> O set to R and paid; the extra comes off the LAST installment,
 *                                       working backwards (an installment the extra fully covers is
 *                                       deleted).
 *                No unpaid installments but B > 0 -> a new paid payment is added.
 *
 *              Sharing and modes: with sharing, so users only commit rows and pledges they can see.
 *              The writes themselves run in system mode on purpose - the service stamps fields users
 *              hold read-only (Status, Source Transaction ID), the documented house pattern for a
 *              trusted backend write (see WebDonationProcessor / GiftAllocationService). Entry points
 *              check the caller can edit Pending Transactions first.
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 2).
 */
public with sharing class PendingTransactionService {

    public static final String STATUS_NEEDS_REVIEW = 'Needs Review';
    public static final String STATUS_READY = 'Ready';
    public static final String STATUS_ERROR = 'Error';

    public static final String APPLY_NEW_GIFT = 'New Gift';
    public static final String APPLY_PLEDGE_PAYMENT = 'Pledge Payment';

    public static final String MATCH_SUGGESTED = 'Suggested';
    public static final String MATCH_CONFIRMED = 'Confirmed';
    public static final String MATCH_NONE = 'No Match';
    public static final String MATCH_MULTIPLE = 'Multiple Matches';

    /** Rows per commit call. Each new gift fans out through NPSP and our own automation; the screen
     *  sends larger selections in chunks of this size. Low volume by design (decision D10). */
    public static final Integer MAX_ROWS_PER_COMMIT = 20;

    /** Stage a committed new gift is created in - closed/won, money received. */
    @TestVisible private static final String NEW_GIFT_STAGE = 'Posted';

    /** Record types a pledge payment can be applied to (decision D3). */
    public static final Set<String> PAYABLE_RECORD_TYPES = new Set<String>{ 'Pledge', 'Grant' };

    /** Record types a new gift can NOT be created as: in-kind gifts carry no cash. */
    public static final Set<String> NON_CASH_RECORD_TYPES = new Set<String>{ 'In_Kind_Gift' };

    /** Default record type for a new gift when the row does not name one. */
    public static final String DEFAULT_GIFT_RECORD_TYPE = 'NPSP_Default';

    /** Set while this class writes rows itself, so the trigger does not re-evaluate over the top. */
    @TestVisible private static Boolean suppressTrigger = false;

    public class PendingTransactionException extends Exception {}

    // =============================================================================================
    // Trigger entry points
    // =============================================================================================

    /**
     * BEFORE INSERT / BEFORE UPDATE.
     *
     * Fills the donor Account from the Contact, records how the donor was decided (a person changing
     * it is a confirmation), suggests a donor for new rows that arrive without one, and recomputes
     * Status__c. A user edit also clears a previous commit error - the next commit will tell them if
     * it is still a problem.
     */
    public static void beforeSave(List<Pending_Transaction__c> rows, Map<Id, Pending_Transaction__c> oldMap) {
        if (suppressTrigger) {
            return;
        }
        Boolean isInsert = (oldMap == null);

        // Loop: work out Match Status for rows whose donor was set or changed by a person.
        for (Pending_Transaction__c row : rows) {
            Pending_Transaction__c old = isInsert ? null : oldMap.get(row.Id);
            Boolean hasDonor = row.Contact__c != null || row.Account__c != null;
            if (isInsert) {
                if (hasDonor && String.isBlank(row.Match_Status__c)) {
                    row.Match_Status__c = MATCH_CONFIRMED;
                }
            } else if (row.Contact__c != old.Contact__c || row.Account__c != old.Account__c) {
                row.Match_Status__c = hasDonor ? MATCH_CONFIRMED : MATCH_NONE;
            }
        }

        if (isInsert) {
            suggestDonors(rows);
        }
        fillAccountsFromContacts(rows);

        Context ctx = new Context(rows);
        // Loop: recompute status. An edit supersedes a previous commit error.
        for (Pending_Transaction__c row : rows) {
            row.Error_Message__c = null;
            row.Status__c = problems(row, ctx).isEmpty() ? STATUS_READY : STATUS_NEEDS_REVIEW;
        }
    }

    /**
     * Copies the Contact's Account onto rows that name a Contact but no Account. Only ever fills a blank:
     * a gift from an organization can legitimately pair the organization with one of its people.
     */
    private static void fillAccountsFromContacts(List<Pending_Transaction__c> rows) {
        List<Pending_Transaction__c> needing = new List<Pending_Transaction__c>();
        Set<Id> contactIds = new Set<Id>();
        for (Pending_Transaction__c row : rows) {
            if (row.Contact__c != null && row.Account__c == null) {
                needing.add(row);
                contactIds.add(row.Contact__c);
            }
        }
        if (needing.isEmpty()) {
            return;
        }
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]);
        for (Pending_Transaction__c row : needing) {
            Contact c = contacts.get(row.Contact__c);
            if (c != null) {
                row.Account__c = c.AccountId;
            }
        }
    }

    // =============================================================================================
    // Evaluation
    // =============================================================================================

    /**
     * Everything the evaluation needs about related records, loaded in bulk once for a set of rows:
     * the pledges named, record types, and which source ids are already stamped on gifts/payments.
     */
    public class Context {
        public Map<Id, Opportunity> pledges = new Map<Id, Opportunity>();
        public Map<String, String> committedAs = new Map<String, String>();

        public Context(List<Pending_Transaction__c> rows) {
            Set<Id> pledgeIds = new Set<Id>();
            Set<String> externalIds = new Set<String>();
            for (Pending_Transaction__c row : rows) {
                if (row.Pledge__c != null) {
                    pledgeIds.add(row.Pledge__c);
                }
                if (String.isNotBlank(row.External_Id__c)) {
                    externalIds.add(row.External_Id__c);
                }
            }
            if (!pledgeIds.isEmpty()) {
                pledges = new Map<Id, Opportunity>([
                    SELECT Id, Name, Amount, IsClosed, IsWon, RecordType.DeveloperName,
                           npe01__Amount_Outstanding__c
                    FROM Opportunity WHERE Id IN :pledgeIds
                ]);
            }
            if (!externalIds.isEmpty()) {
                for (Opportunity o : [SELECT Name, Source_Transaction_Id__c FROM Opportunity
                                      WHERE Source_Transaction_Id__c IN :externalIds]) {
                    committedAs.put(o.Source_Transaction_Id__c.toLowerCase(), 'gift ' + o.Name);
                }
                for (npe01__OppPayment__c p : [SELECT Name, npe01__Opportunity__r.Name, Source_Transaction_Id__c
                                               FROM npe01__OppPayment__c
                                               WHERE Source_Transaction_Id__c IN :externalIds]) {
                    committedAs.put(p.Source_Transaction_Id__c.toLowerCase(),
                        'payment ' + p.Name + ' on ' + p.npe01__Opportunity__r.Name);
                }
            }
        }
    }

    /**
     * Why this row cannot be committed yet, as sentences a user can act on. Empty = Ready.
     */
    public static List<String> problems(Pending_Transaction__c row, Context ctx) {
        List<String> out = new List<String>();

        if (String.isNotBlank(row.External_Id__c)
                && ctx.committedAs.containsKey(row.External_Id__c.toLowerCase())) {
            out.add('This transaction was already committed as '
                + ctx.committedAs.get(row.External_Id__c.toLowerCase()) + '.');
        }
        if (row.Amount__c == null || row.Amount__c <= 0) {
            out.add('Enter an amount greater than zero.');
        }
        if (row.Transaction_Date__c == null) {
            out.add('Enter the date the money was received.');
        }
        if (row.Contact__c == null && row.Account__c == null) {
            out.add(row.Match_Status__c == MATCH_MULTIPLE
                ? 'Several donors match this payer - choose the right one.'
                : 'Choose the donor.');
        } else if (row.Match_Status__c == MATCH_SUGGESTED) {
            out.add('Confirm the suggested donor.');
        }

        if (row.Apply_As__c == APPLY_PLEDGE_PAYMENT) {
            out.addAll(pledgeProblems(row, ctx));
        } else {
            String rtProblem = recordTypeProblem(row.Gift_Record_Type__c);
            if (rtProblem != null) {
                out.add(rtProblem);
            }
        }
        return out;
    }

    private static List<String> pledgeProblems(Pending_Transaction__c row, Context ctx) {
        List<String> out = new List<String>();
        if (row.Pledge__c == null) {
            out.add('Choose the pledge this payment applies to.');
            return out;
        }
        Opportunity p = ctx.pledges.get(row.Pledge__c);
        if (p == null) {
            out.add('The chosen pledge could not be found.');
            return out;
        }
        if (!PAYABLE_RECORD_TYPES.contains(p.RecordType.DeveloperName)) {
            out.add(p.Name + ' is not a pledge or grant.');
        } else if (p.IsClosed && !p.IsWon) {
            out.add(p.Name + ' is closed and cannot take payments.');
        } else if (p.npe01__Amount_Outstanding__c == null || p.npe01__Amount_Outstanding__c <= 0) {
            out.add(p.Name + ' has nothing outstanding.');
        } else if (row.Amount__c != null && row.Amount__c > p.npe01__Amount_Outstanding__c) {
            out.add(p.Name + ' has ' + money(p.npe01__Amount_Outstanding__c)
                + ' outstanding; this transaction is ' + money(row.Amount__c) + '.');
        }
        return out;
    }

    /** Null when the developer name is blank (= default) or an active, cash-bearing gift record type. */
    private static String recordTypeProblem(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        Schema.RecordTypeInfo info =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName);
        if (info == null || !info.isActive()) {
            return '"' + developerName + '" is not an active gift record type.';
        }
        if (NON_CASH_RECORD_TYPES.contains(developerName)) {
            return info.getName() + ' gifts carry no cash - choose another record type.';
        }
        return null;
    }

    // =============================================================================================
    // Donor suggestion
    // =============================================================================================

    /**
     * Proposes a donor for new rows that arrive without one. In order:
     *   1. payer email = any Contact email field  -> that contact
     *   2. payer name  = an Account name exactly  -> that account (organizations, foundations)
     *   3. payer name through the org's Contact duplicate rules (fuzzy first + last name)
     * One candidate = Suggested; several = Multiple Matches (left blank for the user); none = No Match.
     * Matching is advisory, so a failure here never blocks the row from saving.
     */
    @TestVisible
    private static void suggestDonors(List<Pending_Transaction__c> rows) {
        List<Pending_Transaction__c> open = new List<Pending_Transaction__c>();
        Set<String> emails = new Set<String>();
        Set<String> names = new Set<String>();
        for (Pending_Transaction__c row : rows) {
            if (row.Contact__c != null || row.Account__c != null) {
                continue;
            }
            if (String.isBlank(row.Payer_Email__c) && String.isBlank(row.Payer_Name__c)) {
                continue;
            }
            open.add(row);
            if (String.isNotBlank(row.Payer_Email__c)) {
                emails.add(row.Payer_Email__c.trim());
            }
            if (String.isNotBlank(row.Payer_Name__c)) {
                names.add(row.Payer_Name__c.trim());
            }
        }
        if (open.isEmpty()) {
            return;
        }
        try {
            // 1. Email - every NPSP email field, since the bank may carry any of them.
            Map<String, Set<Id>> contactsByEmail = new Map<String, Set<Id>>();
            Map<Id, Id> accountByContact = new Map<Id, Id>();
            if (!emails.isEmpty()) {
                for (Contact c : [SELECT Id, AccountId, Email, npe01__HomeEmail__c, npe01__WorkEmail__c,
                                         npe01__AlternateEmail__c
                                  FROM Contact
                                  WHERE Email IN :emails OR npe01__HomeEmail__c IN :emails
                                     OR npe01__WorkEmail__c IN :emails OR npe01__AlternateEmail__c IN :emails]) {
                    accountByContact.put(c.Id, c.AccountId);
                    for (String e : new List<String>{ c.Email, c.npe01__HomeEmail__c, c.npe01__WorkEmail__c,
                                                      c.npe01__AlternateEmail__c }) {
                        if (String.isNotBlank(e)) {
                            String key = e.toLowerCase();
                            if (!contactsByEmail.containsKey(key)) {
                                contactsByEmail.put(key, new Set<Id>());
                            }
                            contactsByEmail.get(key).add(c.Id);
                        }
                    }
                }
            }

            // 2. Exact account name.
            Map<String, Set<Id>> accountsByName = new Map<String, Set<Id>>();
            if (!names.isEmpty()) {
                for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :names]) {
                    String key = a.Name.toLowerCase();
                    if (!accountsByName.containsKey(key)) {
                        accountsByName.put(key, new Set<Id>());
                    }
                    accountsByName.get(key).add(a.Id);
                }
            }

            // Loop: settle each row on email, then account name; collect the rest for fuzzy matching.
            List<Pending_Transaction__c> fuzzyRows = new List<Pending_Transaction__c>();
            List<Contact> probes = new List<Contact>();
            for (Pending_Transaction__c row : open) {
                Set<Id> byEmail = String.isBlank(row.Payer_Email__c) ? null
                    : contactsByEmail.get(row.Payer_Email__c.trim().toLowerCase());
                if (byEmail != null && !byEmail.isEmpty()) {
                    applySuggestion(row, byEmail, accountByContact, true);
                    continue;
                }
                Set<Id> byName = String.isBlank(row.Payer_Name__c) ? null
                    : accountsByName.get(row.Payer_Name__c.trim().toLowerCase());
                if (byName != null && !byName.isEmpty()) {
                    applySuggestion(row, byName, null, false);
                    continue;
                }
                Contact probe = probeFor(row.Payer_Name__c);
                if (probe != null) {
                    fuzzyRows.add(row);
                    probes.add(probe);
                } else {
                    row.Match_Status__c = MATCH_NONE;
                }
            }

            // 3. Fuzzy name through the Contact duplicate rules, in chunks of 50 (the API's limit).
            if (!probes.isEmpty()) {
                List<Set<Id>> matches = findDuplicateContacts(probes);
                Set<Id> matchedIds = new Set<Id>();
                for (Set<Id> s : matches) {
                    matchedIds.addAll(s);
                }
                for (Contact c : [SELECT Id, AccountId FROM Contact WHERE Id IN :matchedIds]) {
                    accountByContact.put(c.Id, c.AccountId);
                }
                for (Integer i = 0; i < fuzzyRows.size(); i++) {
                    applySuggestion(fuzzyRows[i], matches[i], accountByContact, true);
                }
            }
        } catch (Exception e) {
            // Advisory only: leave the donor for the user rather than fail the sync.
            for (Pending_Transaction__c row : open) {
                if (row.Contact__c == null && row.Account__c == null) {
                    row.Match_Status__c = MATCH_NONE;
                }
            }
        }
    }

    private static void applySuggestion(Pending_Transaction__c row, Set<Id> candidates,
                                        Map<Id, Id> accountByContact, Boolean areContacts) {
        if (candidates == null || candidates.isEmpty()) {
            row.Match_Status__c = MATCH_NONE;
        } else if (candidates.size() > 1) {
            row.Match_Status__c = MATCH_MULTIPLE;
        } else {
            Id only = new List<Id>(candidates)[0];
            if (areContacts) {
                row.Contact__c = only;
                row.Account__c = accountByContact.get(only);
            } else {
                row.Account__c = only;
            }
            row.Match_Status__c = MATCH_SUGGESTED;
        }
    }

    /** "Rachel Cohen" -> FirstName Rachel, LastName Cohen. Null when there is no first + last to try. */
    private static Contact probeFor(String payerName) {
        if (String.isBlank(payerName)) {
            return null;
        }
        List<String> parts = payerName.normalizeSpace().split(' ');
        if (parts.size() < 2) {
            return null;
        }
        String last = parts.remove(parts.size() - 1);
        return new Contact(FirstName = String.join(parts, ' '), LastName = last);
    }

    /** Runs the org's active Contact duplicate rules; one match-Id set per probe, in order. */
    private static List<Set<Id>> findDuplicateContacts(List<Contact> probes) {
        List<Set<Id>> out = new List<Set<Id>>();
        for (Integer start = 0; start < probes.size(); start += 50) {
            List<Contact> chunk = new List<Contact>();
            for (Integer i = start; i < Math.min(start + 50, probes.size()); i++) {
                chunk.add(probes[i]);
            }
            for (Datacloud.FindDuplicatesResult result : Datacloud.FindDuplicates.findDuplicates(chunk)) {
                Set<Id> ids = new Set<Id>();
                for (Datacloud.DuplicateResult dr : result.getDuplicateResults()) {
                    for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                        for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                            if (rec.getRecord() != null && rec.getRecord().Id != null) {
                                ids.add(rec.getRecord().Id);
                            }
                        }
                    }
                }
                out.add(ids);
            }
        }
        return out;
    }

    /**
     * Marks suggested donors as confirmed - the user's "yes, that's them". Match Status is read-only to
     * staff, so this is the way it changes without picking a different donor.
     */
    public static void confirmDonors(Set<Id> rowIds) {
        requireEditAccess();
        List<Pending_Transaction__c> rows = [
            SELECT Id, Match_Status__c, Contact__c, Account__c FROM Pending_Transaction__c
            WHERE Id IN :rowIds AND Match_Status__c = :MATCH_SUGGESTED
        ];
        for (Pending_Transaction__c row : rows) {
            row.Match_Status__c = MATCH_CONFIRMED;
        }
        // Normal save path: the trigger re-evaluates status now the donor is confirmed.
        update rows;
    }

    // =============================================================================================
    // Open pledges
    // =============================================================================================

    public class OpenPledge {
        public Id id;
        public String name;
        public String recordType;
        public String stage;
        public Date closeDate;
        public String campaign;
        public Decimal amount;
        public Decimal outstanding;
        public List<Installment> unpaid = new List<Installment>();
    }

    public class Installment {
        public Id id;
        public String name;
        public Decimal amount;
        public Date scheduledDate;
    }

    /**
     * The donor's Pledges and Grants with money still outstanding, oldest first, each with its unpaid
     * installments in the order they would be paid. Matches on the donor's Account OR on the Contact
     * as primary contact, so a pledge sitting on the household is found from either.
     */
    public static List<OpenPledge> getOpenPledges(Id contactId, Id accountId) {
        List<OpenPledge> out = new List<OpenPledge>();
        if (contactId == null && accountId == null) {
            return out;
        }
        // Sets rather than single binds: "AccountId = :accountId" with a null id would match every
        // gift that has no account. An empty set matches nothing.
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        if (accountId != null) {
            accountIds.add(accountId);
        }
        if (contactId != null) {
            contactIds.add(contactId);
        }
        for (Opportunity o : [
                SELECT Id, Name, StageName, CloseDate, Amount, npe01__Amount_Outstanding__c,
                       RecordType.Name, Campaign.Name,
                       (SELECT Id, Name, npe01__Payment_Amount__c, npe01__Scheduled_Date__c, CreatedDate
                        FROM npe01__OppPayment__r
                        WHERE npe01__Paid__c = false AND npe01__Written_Off__c = false
                        ORDER BY npe01__Scheduled_Date__c ASC NULLS LAST, CreatedDate ASC, Name ASC)
                FROM Opportunity
                WHERE RecordType.DeveloperName IN :PAYABLE_RECORD_TYPES
                  AND npe01__Amount_Outstanding__c > 0
                  AND (IsClosed = false OR IsWon = true)
                  AND (AccountId IN :accountIds OR npsp__Primary_Contact__c IN :contactIds)
                ORDER BY CloseDate ASC]) {
            OpenPledge p = new OpenPledge();
            p.id = o.Id;
            p.name = o.Name;
            p.recordType = o.RecordType.Name;
            p.stage = o.StageName;
            p.closeDate = o.CloseDate;
            p.campaign = o.Campaign?.Name;
            p.amount = o.Amount;
            p.outstanding = o.npe01__Amount_Outstanding__c;
            for (npe01__OppPayment__c pay : o.npe01__OppPayment__r) {
                Installment i = new Installment();
                i.id = pay.Id;
                i.name = pay.Name;
                i.amount = pay.npe01__Payment_Amount__c;
                i.scheduledDate = pay.npe01__Scheduled_Date__c;
                p.unpaid.add(i);
            }
            out.add(p);
        }
        return out;
    }

    // =============================================================================================
    // Pledge payment plan (pure)
    // =============================================================================================

    /** What applying an amount to a pledge will do. Nothing is saved by building one. */
    public class PaymentPlan {
        public Boolean allowed = true;
        public String refusal;
        /** The installment that becomes paid (existing), or null when a new paid payment is added. */
        public npe01__OppPayment__c paid;
        public npe01__OppPayment__c newPaid;
        public npe01__OppPayment__c remainder;
        public List<npe01__OppPayment__c> reduced = new List<npe01__OppPayment__c>();
        public List<npe01__OppPayment__c> removed = new List<npe01__OppPayment__c>();
        public List<String> steps = new List<String>();
    }

    /**
     * Applies the installment rules to in-memory payments. `unpaid` must be the pledge's unpaid,
     * not-written-off installments in payment order (as getOpenPledges / the commit query return
     * them). The records passed in are modified in place, so the commit can save them directly.
     */
    public static PaymentPlan planPledgePayment(Decimal received, Decimal outstanding,
                                                List<npe01__OppPayment__c> unpaid) {
        PaymentPlan plan = new PaymentPlan();
        received = received == null ? 0 : received.setScale(2);
        outstanding = outstanding == null ? 0 : outstanding.setScale(2);

        // Rule 1: never pay more than the pledge still owes.
        if (received <= 0) {
            plan.allowed = false;
            plan.refusal = 'Enter an amount greater than zero.';
            return plan;
        }
        if (received > outstanding) {
            plan.allowed = false;
            plan.refusal = 'This pledge has ' + money(outstanding) + ' outstanding; this transaction is '
                + money(received) + '.';
            return plan;
        }

        // No schedule left to fill, but money still owed: add a paid payment.
        if (unpaid == null || unpaid.isEmpty()) {
            plan.newPaid = new npe01__OppPayment__c(npe01__Payment_Amount__c = received, npe01__Paid__c = true);
            plan.steps.add('Adds a new ' + money(received) + ' payment (the pledge has no scheduled installments left).');
            return plan;
        }

        npe01__OppPayment__c oldest = unpaid[0];
        Decimal due = oldest.npe01__Payment_Amount__c == null ? 0 : oldest.npe01__Payment_Amount__c.setScale(2);
        String dueText = oldest.npe01__Scheduled_Date__c == null ? ''
            : ' due ' + oldest.npe01__Scheduled_Date__c.format();

        oldest.npe01__Payment_Amount__c = received;
        oldest.npe01__Paid__c = true;
        plan.paid = oldest;

        if (received == due) {
            // Rule 2: exact.
            plan.steps.add('Marks the ' + money(due) + ' installment' + dueText + ' as paid.');

        } else if (received < due) {
            // Rule 3: short - the rest stays scheduled on the same date.
            Decimal rest = due - received;
            plan.remainder = new npe01__OppPayment__c(
                npe01__Opportunity__c = oldest.npe01__Opportunity__c,
                npe01__Payment_Amount__c = rest,
                npe01__Scheduled_Date__c = oldest.npe01__Scheduled_Date__c,
                npe01__Paid__c = false);
            plan.steps.add('Pays ' + money(received) + ' of the ' + money(due) + ' installment' + dueText + '.');
            plan.steps.add('Schedules the remaining ' + money(rest) + ' as a new installment'
                + (oldest.npe01__Scheduled_Date__c == null ? '' : ' on ' + oldest.npe01__Scheduled_Date__c.format()) + '.');

        } else {
            // Rule 4: over - take the extra off the last installments, working backwards (D11).
            Decimal extra = received - due;
            plan.steps.add('Pays the ' + money(due) + ' installment' + dueText + ' with ' + money(received)
                + ' (' + money(extra) + ' extra).');
            // Loop: from the last installment back towards the oldest, absorbing the extra.
            for (Integer i = unpaid.size() - 1; i >= 1 && extra > 0; i--) {
                npe01__OppPayment__c inst = unpaid[i];
                Decimal amt = inst.npe01__Payment_Amount__c == null ? 0 : inst.npe01__Payment_Amount__c.setScale(2);
                String instWhen = inst.npe01__Scheduled_Date__c == null ? ''
                    : ' due ' + inst.npe01__Scheduled_Date__c.format();
                if (amt <= extra) {
                    plan.removed.add(inst);
                    extra -= amt;
                    plan.steps.add('Removes the ' + money(amt) + ' installment' + instWhen + '.');
                } else {
                    inst.npe01__Payment_Amount__c = amt - extra;
                    plan.reduced.add(inst);
                    plan.steps.add('Reduces the installment' + instWhen + ' from ' + money(amt) + ' to '
                        + money(amt - extra) + '.');
                    extra = 0;
                }
            }
        }
        return plan;
    }

    /**
     * Preview for the screen: what committing this amount against this pledge would do, without
     * changing anything.
     */
    public static PaymentPlan previewPledgePayment(Id pledgeId, Decimal received) {
        Opportunity pledge = [SELECT Id, npe01__Amount_Outstanding__c FROM Opportunity WHERE Id = :pledgeId];
        return planPledgePayment(received, pledge.npe01__Amount_Outstanding__c, unpaidInstallments(pledgeId, false));
    }

    private static List<npe01__OppPayment__c> unpaidInstallments(Id pledgeId, Boolean lock) {
        if (lock) {
            // Lock first - Salesforce will not combine FOR UPDATE with ORDER BY - then read them in
            // payment order below; the locks hold for the rest of the transaction.
            List<npe01__OppPayment__c> locked = [
                SELECT Id FROM npe01__OppPayment__c
                WHERE npe01__Opportunity__c = :pledgeId AND npe01__Paid__c = false
                  AND npe01__Written_Off__c = false
                FOR UPDATE];
        }
        return [SELECT Id, Name, npe01__Opportunity__c, npe01__Payment_Amount__c, npe01__Scheduled_Date__c
                FROM npe01__OppPayment__c
                WHERE npe01__Opportunity__c = :pledgeId AND npe01__Paid__c = false
                  AND npe01__Written_Off__c = false
                ORDER BY npe01__Scheduled_Date__c ASC NULLS LAST, CreatedDate ASC, Name ASC];
    }

    // =============================================================================================
    // Commit
    // =============================================================================================

    public class CommitResult {
        public Id rowId;
        public String rowName;
        public Boolean success = false;
        /** The gift created (new gift) or the pledge paid (pledge payment). */
        public Id recordId;
        public String recordName;
        public String message;
    }

    /**
     * Commits rows one at a time, each inside its own savepoint: validate, create the gift or apply the
     * payment, stamp the source id, delete the holding row. A failed row is rolled back on its own,
     * marked Error with the reason, and left for the user. Successful holding rows are then emptied from
     * the Recycle Bin too, so they stop counting against storage. (Salesforce purges emptied records in the
     * background - an ALL ROWS query still returns them, IsDeleted = true, for a while afterwards.)
     *
     * Deleting the holding row needs Delete on Pending Transactions, which Apex enforces here - the JCRC
     * profiles that commit carry it.
     */
    public static List<CommitResult> commitTransactions(List<Id> rowIds) {
        requireEditAccess();
        if (rowIds == null || rowIds.isEmpty()) {
            return new List<CommitResult>();
        }
        if (rowIds.size() > MAX_ROWS_PER_COMMIT) {
            throw new PendingTransactionException('Commit at most ' + MAX_ROWS_PER_COMMIT
                + ' transactions at a time.');
        }

        List<Pending_Transaction__c> rows = [
            SELECT Id, Name, Source__c, External_Id__c, Amount__c, Transaction_Date__c, Payment_Method__c,
                   Reference_Number__c, Deposit_Reference__c, Contact__c, Account__c, Match_Status__c,
                   Apply_As__c, Pledge__c, Gift_Record_Type__c, Campaign__c, Fund__c, Approach__c,
                   Gift_Name__c, Notes__c, Status__c
            FROM Pending_Transaction__c WHERE Id IN :rowIds
        ];
        Context ctx = new Context(rows);
        Map<Id, Contact> contacts = contactsFor(rows);

        List<CommitResult> results = new List<CommitResult>();
        List<Pending_Transaction__c> failed = new List<Pending_Transaction__c>();
        List<Id> deleted = new List<Id>();

        // Loop: one savepoint per row, so rows succeed or fail independently (by design - isolation
        // is the requirement, which is why DML sits inside this loop).
        for (Pending_Transaction__c row : rows) {
            CommitResult result = new CommitResult();
            result.rowId = row.Id;
            result.rowName = row.Name;
            Savepoint sp = Database.setSavepoint();
            try {
                List<String> issues = problems(row, ctx);
                if (!issues.isEmpty()) {
                    throw new PendingTransactionException(String.join(issues, ' '));
                }
                Writer writer = new Writer();
                if (row.Apply_As__c == APPLY_PLEDGE_PAYMENT) {
                    writer.applyPledgePayment(row, result);
                } else {
                    writer.createGift(row, contacts.get(row.Contact__c), result);
                }
                writer.deleteRow(row);
                deleted.add(row.Id);
                result.success = true;
            } catch (Exception e) {
                Database.rollback(sp);
                System.debug(LoggingLevel.ERROR, 'Pending transaction ' + row.Name + ' failed to commit: '
                    + e.getTypeName() + ': ' + e.getMessage() + ' | ' + e.getStackTraceString());
                result.success = false;
                result.message = friendly(e);
                failed.add(new Pending_Transaction__c(Id = row.Id, Status__c = STATUS_ERROR,
                    Error_Message__c = result.message.left(4000)));
            }
            results.add(result);
        }

        if (!failed.isEmpty()) {
            suppressTrigger = true;
            try {
                update failed;
            } finally {
                suppressTrigger = false;
            }
        }
        if (!deleted.isEmpty()) {
            try {
                Database.emptyRecycleBin(deleted);
            } catch (Exception e) {
                // Storage housekeeping only - the commit itself already succeeded.
                System.debug(LoggingLevel.WARN, 'Pending transactions not purged from Recycle Bin: ' + e.getMessage());
            }
        }
        return results;
    }

    /**
     * The writes a commit makes, deliberately WITHOUT SHARING.
     *
     * By the time a row gets here the caller has passed the object-permission check and the row has passed
     * evaluation, both under the caller's sharing. What remains must work whoever owns the records involved:
     * Opportunity sharing is Read org-wide, so updating installments on a pledge someone else owns would
     * otherwise fail, and deleting a holding row created by the QuickBooks sync user needs more than the
     * Read/Write sharing on Pending Transactions gives. Same trusted-backend pattern as the website
     * donation processor. Instance methods because Apex does not allow static methods on inner classes.
     */
    private without sharing class Writer {

        public void deleteRow(Pending_Transaction__c row) {
            delete new Pending_Transaction__c(Id = row.Id);
        }

        /** New gift: Opportunity (Posted), then details on NPSP's auto-created payment, then the fund. */
        public void createGift(Pending_Transaction__c row, Contact donor, CommitResult result) {
            String rtName = String.isBlank(row.Gift_Record_Type__c) ? DEFAULT_GIFT_RECORD_TYPE : row.Gift_Record_Type__c;
            Id rtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(rtName).getRecordTypeId();
            Id accountId = row.Account__c != null ? row.Account__c : donor?.AccountId;

            Opportunity gift = new Opportunity(
                // NPSP opportunity naming renames this on insert; a name the user typed is restored below.
                Name = String.isNotBlank(row.Gift_Name__c) ? row.Gift_Name__c : row.Name,
                RecordTypeId = rtId,
                StageName = NEW_GIFT_STAGE,
                CloseDate = row.Transaction_Date__c,
                Amount = row.Amount__c,
                AccountId = accountId,
                npsp__Primary_Contact__c = row.Contact__c,
                CampaignId = row.Campaign__c,
                Approach__c = row.Approach__c,
                Payment_Method__c = row.Payment_Method__c,
                Description = row.Notes__c,
                Source_Transaction_Id__c = String.isBlank(row.External_Id__c) ? null : row.External_Id__c
            );
            insert gift;

            if (String.isNotBlank(row.Gift_Name__c)) {
                Opportunity named = [SELECT Name FROM Opportunity WHERE Id = :gift.Id];
                if (named.Name != row.Gift_Name__c) {
                    update new Opportunity(Id = gift.Id, Name = row.Gift_Name__c);
                }
            }

            // NPSP created the payment during the insert; add the bank details to it.
            List<npe01__OppPayment__c> payments = [
                SELECT Id FROM npe01__OppPayment__c WHERE npe01__Opportunity__c = :gift.Id
            ];
            if (String.isNotBlank(row.Reference_Number__c) || String.isNotBlank(row.Deposit_Reference__c)) {
                for (npe01__OppPayment__c p : payments) {
                    p.npe01__Check_Reference_Number__c = row.Reference_Number__c;
                    p.npsp__Batch_Number__c = row.Deposit_Reference__c;
                }
                update payments;
            }

            if (row.Fund__c != null) {
                // A 100% allocation replaces NPSP's default-fund allocation (verified in JCRC-Dev).
                insert new npsp__Allocation__c(npsp__Opportunity__c = gift.Id,
                    npsp__General_Accounting_Unit__c = row.Fund__c, npsp__Percent__c = 100);
            }

            Opportunity saved = [SELECT Id, Name FROM Opportunity WHERE Id = :gift.Id];
            result.recordId = saved.Id;
            result.recordName = saved.Name;
            result.message = 'Created gift ' + saved.Name + '.';
        }

        /** Pledge payment: lock the installments, apply the rules, stamp the paid installment. */
        public void applyPledgePayment(Pending_Transaction__c row, CommitResult result) {
            Opportunity pledge = [SELECT Id, Name, npe01__Amount_Outstanding__c FROM Opportunity
                                  WHERE Id = :row.Pledge__c FOR UPDATE];
            PaymentPlan plan = planPledgePayment(row.Amount__c, pledge.npe01__Amount_Outstanding__c,
                                                 unpaidInstallments(pledge.Id, true));
            if (!plan.allowed) {
                throw new PendingTransactionException(plan.refusal);
            }

            // Write through fresh records carrying only the fields that change. The queried installments
            // hold the master-detail parent, which cannot be updated and makes the DML fail.
            npe01__OppPayment__c paid = new npe01__OppPayment__c(
                npe01__Payment_Amount__c = row.Amount__c,
                npe01__Paid__c = true,
                npe01__Payment_Date__c = row.Transaction_Date__c,
                npe01__Payment_Method__c = PaymentMethodService.toPaymentValue(row.Payment_Method__c),
                npe01__Check_Reference_Number__c = row.Reference_Number__c,
                npsp__Batch_Number__c = row.Deposit_Reference__c,
                Source_Transaction_Id__c = String.isBlank(row.External_Id__c) ? null : row.External_Id__c);
            if (plan.paid != null) {
                paid.Id = plan.paid.Id;
            } else {
                paid.npe01__Opportunity__c = pledge.Id;
            }

            // Reduce/remove later installments before raising the paid one, so the schedule never
            // momentarily totals more than the pledge.
            if (!plan.removed.isEmpty()) {
                List<npe01__OppPayment__c> toDelete = new List<npe01__OppPayment__c>();
                for (npe01__OppPayment__c x : plan.removed) {
                    toDelete.add(new npe01__OppPayment__c(Id = x.Id));
                }
                delete toDelete;
            }
            if (!plan.reduced.isEmpty()) {
                List<npe01__OppPayment__c> toReduce = new List<npe01__OppPayment__c>();
                for (npe01__OppPayment__c x : plan.reduced) {
                    toReduce.add(new npe01__OppPayment__c(Id = x.Id, npe01__Payment_Amount__c = x.npe01__Payment_Amount__c));
                }
                update toReduce;
            }
            if (paid.Id != null) {
                update paid;
            } else {
                insert paid;
            }
            if (plan.remainder != null) {
                plan.remainder.npe01__Opportunity__c = pledge.Id;
                insert plan.remainder;
            }

            result.recordId = pledge.Id;
            result.recordName = pledge.Name;
            result.message = String.join(plan.steps, ' ');
        }
    }

    // =============================================================================================
    // Helpers
    // =============================================================================================

    private static Map<Id, Contact> contactsFor(List<Pending_Transaction__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (Pending_Transaction__c row : rows) {
            if (row.Contact__c != null) {
                ids.add(row.Contact__c);
            }
        }
        return new Map<Id, Contact>([SELECT Id, AccountId FROM Contact WHERE Id IN :ids]);
    }

    private static void requireEditAccess() {
        if (!Schema.SObjectType.Pending_Transaction__c.isUpdateable()) {
            throw new PendingTransactionException('You do not have access to commit pending transactions.');
        }
    }

    /** The first DML error message rather than Apex's wrapper text. */
    private static String friendly(Exception e) {
        if (e instanceof DmlException) {
            DmlException d = (DmlException) e;
            return d.getNumDml() > 0 ? d.getDmlMessage(0) : d.getMessage();
        }
        return e.getMessage();
    }

    /** $1,250.00 - always two decimals, which Decimal.format() alone does not guarantee. */
    @TestVisible
    private static String money(Decimal amount) {
        String s = (amount == null ? 0 : amount.setScale(2)).format();
        if (!s.contains('.')) {
            s += '.00';
        } else if (s.substringAfter('.').length() == 1) {
            s += '0';
        }
        return '$' + s;
    }
}
