/**
 * @description Server side of the Pending Transactions screen (LWC pendingTransactions, JSI-121 Phase 3).
 *
 *              A thin layer over PendingTransactionService: it shapes rows and options for the screen,
 *              takes the user's edits, and hands commits, previews and pledge lookups to the service.
 *
 *              Conventions (house gotchas from JSI-123):
 *                - Nothing is cacheable=true. Every call is imperative and must return fresh data after
 *                  a save; the Lightning client cache would otherwise serve stale rows.
 *                - Edits arrive as a JSON STRING and are parsed with JSON.deserializeUntyped. Typed inner-
 *                  class parameters from LWC can deserialize empty.
 *                - User edits are saved in USER_MODE, so field-level security applies to what a person
 *                  types. Status, Match Status and Error Message are stamped by the trigger, which does
 *                  not trip USER_MODE.
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 * 2026-09-16 - Jason Ott - Phase 4: createTransaction (manual Add) and deleteTransaction.
 * 2026-09-17 - Jason Ott - Phase 5b: rows carry the QuickBooks import note and customer id.
 * 2026-10-09 - Jason Ott - Source tabs: the workspace returns the user's last tab (savedQueue) and
 *                          saveQueue remembers it per user (Pending_Transaction_Preference__c).
 * 2026-10-09 - Jason Ott - Gala: rows carry isGala (Is_Gala__c) and their Event Registration, which the
 *                          editor may set on gala rows only; the workspace lists gala funds and campaigns
 *                          so the editor can tell when a fund/campaign choice makes a row gala.
 * 2026-11-06 - Jason Ott - getUnpaidRegistrations: the contact's unpaid gala Event Registrations, for the
 *                          editor's "is this money payment for one of these?" table.
 */
public with sharing class PendingTransactionController {

    /** The screen's tabs. Must match QUEUES in the pendingTransactions LWC. */
    @TestVisible private static final Set<String> QUEUES = new Set<String>{ 'all', 'gala', 'quickbooks', 'manual' };

    /** Most rows the screen loads. The holding area is a short-lived queue, so this is a safety net. */
    @TestVisible private static final Integer MAX_ROWS = 500;

    /** Every field the screen may write, keyed by the name the screen uses. */
    private static final Map<String, Schema.SObjectField> EDITABLE = new Map<String, Schema.SObjectField>{
        'payerName' => Pending_Transaction__c.Payer_Name__c,
        'amount' => Pending_Transaction__c.Amount__c,
        'transactionDate' => Pending_Transaction__c.Transaction_Date__c,
        'paymentMethod' => Pending_Transaction__c.Payment_Method__c,
        'referenceNumber' => Pending_Transaction__c.Reference_Number__c,
        'depositDate' => Pending_Transaction__c.Deposit_Date__c,
        'depositReference' => Pending_Transaction__c.Deposit_Reference__c,
        'contactId' => Pending_Transaction__c.Contact__c,
        'accountId' => Pending_Transaction__c.Account__c,
        'applyAs' => Pending_Transaction__c.Apply_As__c,
        'pledgeId' => Pending_Transaction__c.Pledge__c,
        'giftRecordType' => Pending_Transaction__c.Gift_Record_Type__c,
        'campaignId' => Pending_Transaction__c.Campaign__c,
        'fundId' => Pending_Transaction__c.Fund__c,
        'approach' => Pending_Transaction__c.Approach__c,
        'giftName' => Pending_Transaction__c.Gift_Name__c,
        'notes' => Pending_Transaction__c.Notes__c,
        'eventRegistrationId' => Pending_Transaction__c.Event_Registration__c
    };

    /** What the editor saves. Payer Name is left out: on synced rows it is the record of what the bank said. */
    private static final Set<String> SAVE_KEYS = new Set<String>{ 'amount', 'transactionDate', 'paymentMethod',
        'referenceNumber', 'depositDate', 'depositReference', 'contactId', 'accountId', 'applyAs', 'pledgeId',
        'giftRecordType', 'campaignId', 'fundId', 'approach', 'giftName', 'notes', 'eventRegistrationId' };

    /** Shown when an Event Registration is saved on a row that is not gala money. */
    @TestVisible private static final String GALA_ONLY_MESSAGE = 'An Event Registration can only be linked to a '
        + 'gala transaction. Clear it, or choose a gala fund or campaign.';

    /** What the Add form may set on a new manual row; the rest is done in the editor afterwards. */
    private static final Set<String> CREATE_KEYS = new Set<String>{ 'amount', 'transactionDate', 'paymentMethod',
        'referenceNumber', 'depositDate', 'depositReference', 'contactId', 'accountId', 'payerName', 'notes' };

    /** An event is a gala when the word Gala is in its name (whole word, any capitalization). */
    private static final Pattern GALA_EVENT = Pattern.compile('(?i)\\bgala\\b');

    /** Most unpaid registrations offered for one contact - a safety net, real donors have one or two. */
    @TestVisible private static final Integer MAX_REGISTRATIONS = 50;

    /** The subset bulk edit may change. */
    private static final Set<String> BULK_EDITABLE = new Set<String>{ 'campaignId', 'fundId', 'approach', 'giftRecordType' };

    // =============================================================================================
    // Shapes returned to the screen
    // =============================================================================================

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Workspace {
        @AuraEnabled public List<RowInfo> rows = new List<RowInfo>();
        @AuraEnabled public List<Option> paymentMethods = new List<Option>();
        @AuraEnabled public List<Option> approaches = new List<Option>();
        @AuraEnabled public List<Option> giftRecordTypes = new List<Option>();
        @AuraEnabled public List<Option> funds = new List<Option>();
        @AuraEnabled public String defaultGiftRecordType;
        @AuraEnabled public Integer maxPerCommit = PendingTransactionService.MAX_ROWS_PER_COMMIT;
        @AuraEnabled public Boolean truncated = false;
        /** The tab this user last chose ('all' when they never chose one). */
        @AuraEnabled public String savedQueue = 'all';
        /** Funds and campaigns ticked Gala: choosing one makes a row gala in the editor before it is saved. */
        @AuraEnabled public List<Id> galaFundIds = new List<Id>();
        @AuraEnabled public List<Id> galaCampaignIds = new List<Id>();
    }

    public class RowInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public List<String> problems = new List<String>();
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String source;
        @AuraEnabled public String externalType;
        @AuraEnabled public String payerName;
        @AuraEnabled public String payerEmail;
        @AuraEnabled public String memo;
        @AuraEnabled public String importNote;
        @AuraEnabled public String quickBooksCustomerId;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date transactionDate;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public Date depositDate;
        @AuraEnabled public String depositReference;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public Id contactAccountId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String matchStatus;
        @AuraEnabled public String applyAs;
        @AuraEnabled public Id pledgeId;
        @AuraEnabled public String pledgeName;
        @AuraEnabled public String giftRecordType;
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String campaignName;
        @AuraEnabled public Id fundId;
        @AuraEnabled public String fundName;
        @AuraEnabled public String approach;
        @AuraEnabled public String giftName;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean isGala = false;
        @AuraEnabled public Id eventRegistrationId;
        @AuraEnabled public String eventRegistrationName;
    }

    public class InstallmentInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date scheduledDate;
    }

    public class PledgeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String recordType;
        @AuraEnabled public String stage;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String campaign;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal outstanding;
        @AuraEnabled public Integer unpaidCount;
        @AuraEnabled public List<InstallmentInfo> unpaid = new List<InstallmentInfo>();
    }

    public class PreviewInfo {
        @AuraEnabled public Boolean allowed;
        @AuraEnabled public String refusal;
        @AuraEnabled public List<String> steps;
    }

    public class ResultInfo {
        @AuraEnabled public Id rowId;
        @AuraEnabled public String rowName;
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String message;
    }

    /** One unpaid gala registration offered in the editor. pledge* is set when it already has a pledge. */
    public class RegistrationInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String summary;
        @AuraEnabled public String eventName;
        @AuraEnabled public String level;
        @AuraEnabled public Decimal tickets;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String paymentChoice;
        @AuraEnabled public Date submitted;
        @AuraEnabled public Id pledgeId;
        @AuraEnabled public String pledgeName;
        @AuraEnabled public Decimal pledgeOutstanding;
    }

    public class ContactResult {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public List<Option> possibleDuplicates = new List<Option>();
    }

    // =============================================================================================
    // Read
    // =============================================================================================

    /** Everything the screen needs on load: the rows (with their problems) and the option lists. */
    @AuraEnabled
    public static Workspace getWorkspace() {
        try {
            Workspace ws = new Workspace();
            List<Pending_Transaction__c> rows = queryRows(null);
            ws.truncated = rows.size() > MAX_ROWS;
            if (ws.truncated) {
                rows.remove(rows.size() - 1);
            }
            ws.rows = toInfos(rows);
            ws.paymentMethods = picklist(Pending_Transaction__c.Payment_Method__c);
            ws.approaches = picklist(Pending_Transaction__c.Approach__c);
            ws.defaultGiftRecordType = PendingTransactionService.DEFAULT_GIFT_RECORD_TYPE;
            // Loop: gift record types this user can create, minus the ones a cash gift can't be.
            for (Schema.RecordTypeInfo rt : Schema.SObjectType.Opportunity.getRecordTypeInfos()) {
                if (rt.isActive() && rt.isAvailable() && !rt.isMaster()
                        && !PendingTransactionService.NON_CASH_RECORD_TYPES.contains(rt.getDeveloperName())) {
                    ws.giftRecordTypes.add(new Option(rt.getName(), rt.getDeveloperName()));
                }
            }
            for (npsp__General_Accounting_Unit__c g : [SELECT Id, Name, Gala__c FROM npsp__General_Accounting_Unit__c
                                                        WHERE npsp__Active__c = true
                                                        WITH USER_MODE ORDER BY Name]) {
                ws.funds.add(new Option(g.Name, g.Id));
                if (g.Gala__c) {
                    ws.galaFundIds.add(g.Id);
                }
            }
            for (Campaign c : [SELECT Id FROM Campaign WHERE Gala__c = true WITH USER_MODE LIMIT 1000]) {
                ws.galaCampaignIds.add(c.Id);
            }
            // The user-level preference only (getValues, not getInstance), so an org-wide value can
            // never put everyone on one tab.
            Pending_Transaction_Preference__c pref = Pending_Transaction_Preference__c.getValues(UserInfo.getUserId());
            if (pref != null && QUEUES.contains(pref.Queue__c)) {
                ws.savedQueue = pref.Queue__c;
            }
            return ws;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * @description Remembers the tab the user just chose, so the screen opens there next time on any
     *              computer. Stored as this user's own Pending_Transaction_Preference__c record, so it
     *              can only ever be the running user's own. The org restricts custom settings to
     *              profiles granted them, so the setting is granted (customSettingAccesses) on Admin,
     *              JCRC - Fundraising and JCRC - Development - the profiles that use the screen.
     */
    @AuraEnabled
    public static void saveQueue(String queue) {
        try {
            if (!QUEUES.contains(queue)) {
                throw new IllegalArgumentException('Unknown tab: ' + queue);
            }
            Pending_Transaction_Preference__c pref = Pending_Transaction_Preference__c.getValues(UserInfo.getUserId());
            if (pref == null) {
                pref = new Pending_Transaction_Preference__c(SetupOwnerId = UserInfo.getUserId());
            }
            if (pref.Queue__c != queue) {
                pref.Queue__c = queue;
                // Explicit SYSTEM_MODE: a fundraiser has no field access to this setting, and the write
                // is limited to the user's own record above, so user-mode field checks add nothing.
                Database.upsert(pref, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** The donor's open Pledges and Grants, for the pledge cards. */
    @AuraEnabled
    public static List<PledgeInfo> getOpenPledges(Id contactId, Id accountId) {
        try {
            List<PledgeInfo> out = new List<PledgeInfo>();
            for (PendingTransactionService.OpenPledge p : PendingTransactionService.getOpenPledges(contactId, accountId)) {
                PledgeInfo info = new PledgeInfo();
                info.id = p.id;
                info.name = p.name;
                info.recordType = p.recordType;
                info.stage = p.stage;
                info.closeDate = p.closeDate;
                info.campaign = p.campaign;
                info.amount = p.amount;
                info.outstanding = p.outstanding;
                info.unpaidCount = p.unpaid.size();
                for (PendingTransactionService.Installment i : p.unpaid) {
                    InstallmentInfo ii = new InstallmentInfo();
                    ii.id = i.id;
                    ii.amount = i.amount;
                    ii.scheduledDate = i.scheduledDate;
                    info.unpaid.add(ii);
                }
                out.add(info);
            }
            return out;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * @description The contact's gala Event Registrations that are still unpaid, newest first, for the
     *              editor to offer as "is this money payment for one of these?". Left out:
     *                - events without the word Gala in their name;
     *                - registrations already claimed by a different pending transaction (either lookup),
     *                  so the same money is never matched twice;
     *                - registrations linked to a gift that is not an open pledge/grant with money owed -
     *                  new money can't be attached to those (commit would refuse it).
     *              A registration with an open pledge comes back with that pledge, so the editor can apply
     *              the money as a payment on it instead of a second gift.
     * @param rowId     the pending transaction being edited (its own claim does not hide a registration)
     * @param contactId the donor on that transaction
     */
    @AuraEnabled
    public static List<RegistrationInfo> getUnpaidRegistrations(Id rowId, Id contactId) {
        try {
            List<RegistrationInfo> out = new List<RegistrationInfo>();
            if (contactId == null) {
                return out;
            }
            // LIKE narrows to candidate events; the whole-word test below makes the final call.
            List<Event_Registration__c> regs = [
                SELECT Id, Name, Registration_Summary__c, Event__r.Name, Sponsorship_Level__c, Number_of_Tickets__c,
                       Sponsorship_Donation_Amount__c, toLabel(Payment_Method__c), CreatedDate,
                       Pending_Transaction__c, Opportunity__c, Opportunity__r.Name,
                       Opportunity__r.RecordType.DeveloperName, Opportunity__r.IsClosed, Opportunity__r.IsWon,
                       Opportunity__r.npe01__Amount_Outstanding__c
                FROM Event_Registration__c
                WHERE Contact__c = :contactId AND Paid__c = false AND Event__r.Name LIKE '%gala%'
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :MAX_REGISTRATIONS
            ];
            Set<Id> regIds = new Map<Id, Event_Registration__c>(regs).keySet();
            Set<Id> claimed = new Set<Id>();
            for (Pending_Transaction__c pt : [SELECT Event_Registration__c FROM Pending_Transaction__c
                                              WHERE Event_Registration__c IN :regIds AND Id != :rowId
                                              WITH USER_MODE]) {
                claimed.add(pt.Event_Registration__c);
            }

            // Loop: drop what can't take this money, shape the rest for the table.
            for (Event_Registration__c r : regs) {
                if (!GALA_EVENT.matcher(r.Event__r.Name).find() || claimed.contains(r.Id)
                        || (r.Pending_Transaction__c != null && r.Pending_Transaction__c != rowId)) {
                    continue;
                }
                RegistrationInfo info = new RegistrationInfo();
                // IF: already has a gift - only an open pledge/grant with money owed can take a payment.
                if (r.Opportunity__c != null) {
                    Opportunity p = r.Opportunity__r;
                    Boolean payable = PendingTransactionService.PAYABLE_RECORD_TYPES.contains(p.RecordType.DeveloperName)
                        && !(p.IsClosed && !p.IsWon)
                        && p.npe01__Amount_Outstanding__c != null && p.npe01__Amount_Outstanding__c > 0;
                    if (!payable) {
                        continue;
                    }
                    info.pledgeId = p.Id;
                    info.pledgeName = p.Name;
                    info.pledgeOutstanding = p.npe01__Amount_Outstanding__c;
                }
                info.id = r.Id;
                info.name = r.Name;
                info.summary = r.Registration_Summary__c;
                info.eventName = r.Event__r.Name;
                info.level = r.Sponsorship_Level__c;
                info.tickets = r.Number_of_Tickets__c;
                info.amount = r.Sponsorship_Donation_Amount__c;
                info.paymentChoice = r.Payment_Method__c;
                info.submitted = r.CreatedDate.date();
                out.add(info);
            }
            return out;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** What committing this amount against this pledge would do. Changes nothing. */
    @AuraEnabled
    public static PreviewInfo previewPledgePayment(Id pledgeId, Decimal amount) {
        try {
            PendingTransactionService.PaymentPlan plan = PendingTransactionService.previewPledgePayment(pledgeId, amount);
            PreviewInfo out = new PreviewInfo();
            out.allowed = plan.allowed;
            out.refusal = plan.refusal;
            out.steps = plan.steps;
            return out;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    // =============================================================================================
    // Write
    // =============================================================================================

    /** Saves the editor's changes to one row and returns it re-evaluated. */
    @AuraEnabled
    public static RowInfo saveTransaction(String rowJson) {
        try {
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(rowJson);
            Id rowId = (Id) values.get('id');
            Pending_Transaction__c rec = new Pending_Transaction__c(Id = rowId);
            applyValues(rec, values, SAVE_KEYS);
            // An Event Registration belongs only on gala money. Is_Gala__c is a formula over the saved
            // source, fund and campaign, so save, read it back, and undo if the result breaks the rule.
            Savepoint sp = Database.setSavepoint();
            Database.update(rec, AccessLevel.USER_MODE);
            Pending_Transaction__c saved = [SELECT Is_Gala__c, Event_Registration__c FROM Pending_Transaction__c
                                            WHERE Id = :rowId];
            if (saved.Event_Registration__c != null && !saved.Is_Gala__c) {
                Database.rollback(sp);
                throw new PendingTransactionService.PendingTransactionException(GALA_ONLY_MESSAGE);
            }
            return rowInfo(rowId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * Adds a transaction typed in by hand (money that will not come through the QuickBooks feed, or a test).
     * The trigger marks it Manual, suggests a donor from the payer name when none was chosen, and works
     * out its status. Returns the new row so the screen can open it in the editor.
     */
    @AuraEnabled
    public static RowInfo createTransaction(String rowJson) {
        try {
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(rowJson);
            Pending_Transaction__c rec = new Pending_Transaction__c();
            applyValues(rec, values, CREATE_KEYS);
            Database.insert(rec, AccessLevel.USER_MODE);
            return rowInfo(rec.Id);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** Deletes one pending transaction that should never become a gift. */
    @AuraEnabled
    public static void deleteTransaction(Id rowId) {
        try {
            PendingTransactionService.deleteTransactions(new Set<Id>{ rowId });
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** The user's "yes, that's the donor" on a suggested match. */
    @AuraEnabled
    public static RowInfo confirmDonor(Id rowId) {
        try {
            PendingTransactionService.confirmDonors(new Set<Id>{ rowId });
            return rowInfo(rowId);
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** Confirms every suggested donor among the selected rows; returns how many were confirmed. */
    @AuraEnabled
    public static Integer confirmDonors(List<Id> rowIds) {
        try {
            Set<Id> ids = new Set<Id>(rowIds);
            Integer suggested = [SELECT COUNT() FROM Pending_Transaction__c
                                 WHERE Id IN :ids AND Match_Status__c = :PendingTransactionService.MATCH_SUGGESTED];
            PendingTransactionService.confirmDonors(ids);
            return suggested;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * Sets Campaign / Fund / Approach / Gift Record Type on every selected row. Only the keys present in
     * fieldsJson are touched; a key sent with an empty value clears that field.
     */
    @AuraEnabled
    public static Integer bulkUpdate(List<Id> rowIds, String fieldsJson) {
        try {
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            List<Pending_Transaction__c> recs = new List<Pending_Transaction__c>();
            for (Id rowId : rowIds) {
                Pending_Transaction__c rec = new Pending_Transaction__c(Id = rowId);
                applyValues(rec, values, BULK_EDITABLE);
                recs.add(rec);
            }
            Database.update(recs, AccessLevel.USER_MODE);
            return recs.size();
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** Commits up to the service's per-call maximum; the screen sends larger selections in chunks. */
    @AuraEnabled
    public static List<ResultInfo> commitTransactions(List<Id> rowIds) {
        try {
            List<ResultInfo> out = new List<ResultInfo>();
            for (PendingTransactionService.CommitResult r : PendingTransactionService.commitTransactions(rowIds)) {
                ResultInfo info = new ResultInfo();
                info.rowId = r.rowId;
                info.rowName = r.rowName;
                info.success = r.success;
                info.recordId = r.recordId;
                info.recordName = r.recordName;
                info.message = r.message;
                out.add(info);
            }
            return out;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * Creates a donor Contact from the screen (NPSP gives them a household). Unless told to go ahead, the
     * org's Contact duplicate rules are checked first and any likely matches are returned instead, so the
     * user can pick the existing person rather than create a duplicate.
     */
    @AuraEnabled
    public static ContactResult createContact(String contactJson, Boolean ignoreDuplicates) {
        try {
            if (!Schema.SObjectType.Contact.isCreateable()) {
                throw new PendingTransactionService.PendingTransactionException('You do not have access to create contacts.');
            }
            Map<String, Object> v = (Map<String, Object>) JSON.deserializeUntyped(contactJson);
            Contact c = new Contact(
                FirstName = str(v.get('firstName')),
                LastName = str(v.get('lastName')),
                Email = str(v.get('email')),
                Phone = str(v.get('phone')),
                MailingStreet = str(v.get('street')),
                MailingCity = str(v.get('city')),
                MailingState = str(v.get('state')),
                MailingPostalCode = str(v.get('postalCode')));
            if (String.isBlank(c.LastName)) {
                throw new PendingTransactionService.PendingTransactionException('Enter a last name.');
            }

            ContactResult result = new ContactResult();
            if (ignoreDuplicates != true) {
                Set<Id> matchIds = new Set<Id>();
                for (Datacloud.FindDuplicatesResult fdr : Datacloud.FindDuplicates.findDuplicates(new List<Contact>{ c })) {
                    for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
                        for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                            for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                                matchIds.add(rec.getRecord().Id);
                            }
                        }
                    }
                }
                if (!matchIds.isEmpty()) {
                    for (Contact m : [SELECT Id, Name, Email, Account.Name FROM Contact WHERE Id IN :matchIds WITH USER_MODE]) {
                        String detail = String.isNotBlank(m.Email) ? m.Email : m.Account?.Name;
                        result.possibleDuplicates.add(new Option(m.Name + (String.isBlank(detail) ? '' : ' · ' + detail), m.Id));
                    }
                    return result;
                }
            }

            // Duplicates already checked (or the user chose to go ahead): let the save through the rules.
            Database.DMLOptions opts = new Database.DMLOptions();
            opts.DuplicateRuleHeader.allowSave = true;
            Database.SaveResult sr = Database.insert(c, opts);
            if (!sr.isSuccess()) {
                throw new PendingTransactionService.PendingTransactionException(sr.getErrors()[0].getMessage());
            }
            result.contactId = sr.getId();
            result.contactName = [SELECT Name FROM Contact WHERE Id = :sr.getId()].Name;
            return result;
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    // =============================================================================================
    // Helpers
    // =============================================================================================

    private static List<Pending_Transaction__c> queryRows(Id onlyId) {
        Integer lim = MAX_ROWS + 1;
        if (onlyId != null) {
            return [SELECT Id, Name, Status__c, Error_Message__c, Source__c, External_Type__c, External_Id__c,
                           Payer_Name__c, Payer_Email__c, Memo__c, Amount__c, Transaction_Date__c, Payment_Method__c,
                           Reference_Number__c, Deposit_Date__c, Deposit_Reference__c, Contact__c, Contact__r.Name,
                           Contact__r.Email, Contact__r.AccountId, Account__c, Account__r.Name, Match_Status__c,
                           Apply_As__c, Pledge__c, Pledge__r.Name, Gift_Record_Type__c, Campaign__c, Campaign__r.Name,
                           Fund__c, Fund__r.Name, Approach__c, Gift_Name__c, Notes__c, CreatedDate, Import_Note__c, QuickBooks_Customer_Id__c,
                           Is_Gala__c, Event_Registration__c, Event_Registration__r.Name
                    FROM Pending_Transaction__c WHERE Id = :onlyId WITH USER_MODE];
        }
        return [SELECT Id, Name, Status__c, Error_Message__c, Source__c, External_Type__c, External_Id__c,
                       Payer_Name__c, Payer_Email__c, Memo__c, Amount__c, Transaction_Date__c, Payment_Method__c,
                       Reference_Number__c, Deposit_Date__c, Deposit_Reference__c, Contact__c, Contact__r.Name,
                       Contact__r.Email, Contact__r.AccountId, Account__c, Account__r.Name, Match_Status__c,
                       Apply_As__c, Pledge__c, Pledge__r.Name, Gift_Record_Type__c, Campaign__c, Campaign__r.Name,
                       Fund__c, Fund__r.Name, Approach__c, Gift_Name__c, Notes__c, CreatedDate, Import_Note__c, QuickBooks_Customer_Id__c,
                       Is_Gala__c, Event_Registration__c, Event_Registration__r.Name
                FROM Pending_Transaction__c WITH USER_MODE
                ORDER BY Transaction_Date__c DESC NULLS FIRST, CreatedDate DESC
                LIMIT :lim];
    }

    private static RowInfo rowInfo(Id rowId) {
        List<RowInfo> infos = toInfos(queryRows(rowId));
        return infos.isEmpty() ? null : infos[0];
    }

    private static List<RowInfo> toInfos(List<Pending_Transaction__c> rows) {
        PendingTransactionService.Context ctx = new PendingTransactionService.Context(rows);
        List<RowInfo> out = new List<RowInfo>();
        for (Pending_Transaction__c r : rows) {
            RowInfo i = new RowInfo();
            i.id = r.Id;
            i.name = r.Name;
            i.status = r.Status__c;
            i.problems = PendingTransactionService.problems(r, ctx);
            i.errorMessage = r.Error_Message__c;
            i.source = r.Source__c;
            i.externalType = r.External_Type__c;
            i.payerName = r.Payer_Name__c;
            i.payerEmail = r.Payer_Email__c;
            i.memo = r.Memo__c;
            i.importNote = r.Import_Note__c;
            i.quickBooksCustomerId = r.QuickBooks_Customer_Id__c;
            i.amount = r.Amount__c;
            i.transactionDate = r.Transaction_Date__c;
            i.paymentMethod = r.Payment_Method__c;
            i.referenceNumber = r.Reference_Number__c;
            i.depositDate = r.Deposit_Date__c;
            i.depositReference = r.Deposit_Reference__c;
            i.contactId = r.Contact__c;
            i.contactName = r.Contact__r?.Name;
            i.contactEmail = r.Contact__r?.Email;
            i.contactAccountId = r.Contact__r?.AccountId;
            i.accountId = r.Account__c;
            i.accountName = r.Account__r?.Name;
            i.matchStatus = r.Match_Status__c;
            i.applyAs = r.Apply_As__c;
            i.pledgeId = r.Pledge__c;
            i.pledgeName = r.Pledge__r?.Name;
            i.giftRecordType = r.Gift_Record_Type__c;
            i.campaignId = r.Campaign__c;
            i.campaignName = r.Campaign__r?.Name;
            i.fundId = r.Fund__c;
            i.fundName = r.Fund__r?.Name;
            i.approach = r.Approach__c;
            i.giftName = r.Gift_Name__c;
            i.notes = r.Notes__c;
            i.createdDate = r.CreatedDate;
            i.isGala = r.Is_Gala__c;
            i.eventRegistrationId = r.Event_Registration__c;
            i.eventRegistrationName = r.Event_Registration__r?.Name;
            out.add(i);
        }
        return out;
    }

    /** Copies the allowed keys from the screen's JSON onto the record, converting to each field's type. */
    private static void applyValues(Pending_Transaction__c rec, Map<String, Object> values, Set<String> allowed) {
        for (String key : values.keySet()) {
            if (!allowed.contains(key)) {
                continue;
            }
            Schema.SObjectField field = EDITABLE.get(key);
            Object raw = values.get(key);
            String text = raw == null ? null : String.valueOf(raw).trim();
            if (String.isBlank(text)) {
                rec.put(field, null);
                continue;
            }
            Schema.DisplayType t = field.getDescribe().getType();
            if (t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.DOUBLE) {
                rec.put(field, Decimal.valueOf(text));
            } else if (t == Schema.DisplayType.DATE) {
                rec.put(field, Date.valueOf(text));
            } else if (t == Schema.DisplayType.REFERENCE) {
                rec.put(field, (Id) text);
            } else {
                rec.put(field, text);
            }
        }
    }

    private static List<Option> picklist(Schema.SObjectField field) {
        List<Option> out = new List<Option>();
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                out.add(new Option(e.getLabel(), e.getValue()));
            }
        }
        return out;
    }

    private static String str(Object o) {
        return o == null || String.isBlank(String.valueOf(o)) ? null : String.valueOf(o).trim();
    }

    /** An AuraHandledException whose message the screen can show as-is. */
    private static AuraHandledException auraError(Exception e) {
        String message = e.getMessage();
        if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) {
            message = ((DmlException) e).getDmlMessage(0);
        }
        AuraHandledException ae = new AuraHandledException(message);
        ae.setMessage(message);
        return ae;
    }
}