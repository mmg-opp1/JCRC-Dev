/**
 * @description JSI-107 reverse-sync applier. Takes normalized ContactUpdate records
 *   (built by a Constant Contact API client from CC responses) and applies opt-outs,
 *   hard bounces, and engagement onto NPSP Contact records, then logs the run to
 *   Integration_Log__c. This is the CC-API-agnostic core of the inbound poller:
 *   matching uses the Salesforce Id we push into CC (indexed on Contact.Id), with a
 *   case-insensitive email fallback for records that predate the Id push.
 *
 *   Runs as a trusted backend sync (with sharing; system-mode DML) so it can update any
 *   Contact the integration user is entitled to see; the integration user still holds FLS
 *   on the target fields (granted in JSI-107 Phase 2).
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: reverse-sync applier + run logging (CC client wired separately).
 */
public with sharing class ConstantContactSyncService {

    /**
     * One normalized update for a single contact, produced from a Constant Contact response.
     * Any attribute left null means "no change" for that attribute.
     */
    public class ContactUpdate {
        public Id salesforceId;     // from the "Salesforce ID" custom field we push into CC (primary match)
        public String ccContactId;  // CC contact UUID — backfilled onto Contact.CC_Contact_Id__c
        public String email;        // fallback match key
        public Boolean optedOut;    // true = unsubscribed in CC (sets HasOptedOutOfEmail)
        public Date optOutDate;
        public Boolean hardBounce;
        public Date bounceDate;
        public Date lastOpen;
        public Date lastClick;
        public Integer opens90;
    }

    /** Outcome counts for a run (also mirrored into Integration_Log__c). */
    public class SyncResult {
        public Integer processed = 0;
        public Integer updated = 0;
        public Integer failed = 0;
        public List<String> errors = new List<String>();
    }

    /** One contact's current set of subscribed CC list ids (JSI-108 topic preference sync). */
    public class TopicMembership {
        public Id salesforceId;   // from the pushed "Salesforce ID" custom field (primary match)
        public String ccContactId;
        public String email;      // fallback match
        public Set<String> subscribedListIds = new Set<String>();
    }

    /**
     * Match each update to a Contact (by pushed Salesforce Id, else email), apply the
     * changed fields, bulk-update with partial success, and write one Integration_Log__c row.
     * @param updates normalized CC updates
     * @param operation one of the Integration_Log__c Operation picklist values (e.g. 'Opt-Out Sync')
     */
    public SyncResult apply(List<ContactUpdate> updates, String operation) {
        Datetime runStart = System.now();
        SyncResult res = new SyncResult();

        // Nothing to do — still log the run so the admin sees the poller executed.
        if (updates == null || updates.isEmpty()) {
            logRun(operation, 'Success', runStart, res, 'No updates to process.');
            return res;
        }
        res.processed = updates.size();

        // Collect match keys: prefer the Salesforce Id CC hands back; fall back to email.
        Set<Id> ids = new Set<Id>();
        Set<String> emails = new Set<String>();
        for (ContactUpdate u : updates) {
            if (u.salesforceId != null) ids.add(u.salesforceId);
            else if (String.isNotBlank(u.email)) emails.add(u.email.toLowerCase());
        }

        // Load candidate Contacts (Id is indexed; email covers un-pushed records).
        Map<Id, Contact> byId = new Map<Id, Contact>();
        Map<String, Contact> byEmail = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, Email, CC_Contact_Id__c, HasOptedOutOfEmail, CC_Subscription_Status__c,
                   Email_Hard_Bounce__c, Email_Last_Bounce_Date__c, Email_Last_Open__c,
                   Email_Last_Click__c, Email_Opens_Last_90_Days__c
            FROM Contact
            WHERE Id IN :ids OR Email IN :emails
        ]) {
            byId.put(c.Id, c);
            if (String.isNotBlank(c.Email)) {
                String k = c.Email.toLowerCase();
                if (!byEmail.containsKey(k)) byEmail.put(k, c); // first record wins on duplicate emails
            }
        }

        // Resolve + apply changed fields onto a minimal update record per Contact.
        Map<Id, Contact> toUpdate = new Map<Id, Contact>();
        for (ContactUpdate u : updates) {
            Contact c = null;
            if (u.salesforceId != null && byId.containsKey(u.salesforceId)) {
                c = byId.get(u.salesforceId);
            } else if (String.isNotBlank(u.email) && byEmail.containsKey(u.email.toLowerCase())) {
                c = byEmail.get(u.email.toLowerCase());
            }
            if (c == null) {
                res.failed++;
                res.errors.add('No Contact match for ' + (u.salesforceId != null ? String.valueOf(u.salesforceId) : u.email));
                continue;
            }

            Contact edit = toUpdate.containsKey(c.Id) ? toUpdate.get(c.Id) : new Contact(Id = c.Id);
            if (u.optedOut != null) {
                edit.HasOptedOutOfEmail = u.optedOut;
                edit.CC_Subscription_Status__c = u.optedOut ? 'Unsubscribed' : 'Subscribed';
            }
            if (u.hardBounce != null)  edit.Email_Hard_Bounce__c = u.hardBounce;
            if (u.bounceDate != null)  edit.Email_Last_Bounce_Date__c = u.bounceDate;
            if (u.lastOpen != null)    edit.Email_Last_Open__c = u.lastOpen;
            if (u.lastClick != null)   edit.Email_Last_Click__c = u.lastClick;
            if (u.opens90 != null)     edit.Email_Opens_Last_90_Days__c = u.opens90;
            if (String.isNotBlank(u.ccContactId) && String.isBlank(c.CC_Contact_Id__c)) {
                edit.CC_Contact_Id__c = u.ccContactId;
            }
            toUpdate.put(c.Id, edit);
        }

        // Partial-success DML so one bad record doesn't sink the batch.
        if (!toUpdate.isEmpty()) {
            List<Contact> updList = toUpdate.values();
            List<Database.SaveResult> srs = Database.update(updList, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (srs[i].isSuccess()) {
                    res.updated++;
                } else {
                    res.failed++;
                    res.errors.add(updList[i].Id + ': ' + srs[i].getErrors()[0].getMessage());
                }
            }
        }

        String status = res.failed == 0 ? 'Success' : (res.updated > 0 ? 'Partial' : 'Failed');
        logRun(operation, status, runStart, res, res.errors.isEmpty() ? 'OK' : String.join(res.errors, '\n'));
        return res;
    }

    /**
     * JSI-108 topic preference sync. Given each contact's current CC list memberships, reconcile
     * their CampaignMembers on the mapped CC List campaigns (topic = Campaign = CC list, mapped via
     * Campaign.CC_List_Id__c): subscribed → CampaignMember Status 'Subscribed'; a previously-subscribed
     * topic no longer present → 'Unsubscribed'. Writes one Integration_Log__c ('Preference Sync').
     * NOTE: each CC List campaign must have 'Subscribed'/'Unsubscribed' CampaignMemberStatus values.
     */
    public SyncResult applyTopicMemberships(List<TopicMembership> memberships) {
        Datetime runStart = System.now();
        SyncResult res = new SyncResult();
        if (memberships == null || memberships.isEmpty()) {
            logRun('Preference Sync', 'Success', runStart, res, 'No memberships to process.');
            return res;
        }
        res.processed = memberships.size();

        // Collect all list ids + match keys.
        Set<String> allListIds = new Set<String>();
        Set<Id> ids = new Set<Id>();
        Set<String> emails = new Set<String>();
        for (TopicMembership m : memberships) {
            if (m.subscribedListIds != null) allListIds.addAll(m.subscribedListIds);
            if (m.salesforceId != null) ids.add(m.salesforceId);
            else if (String.isNotBlank(m.email)) emails.add(m.email.toLowerCase());
        }

        // CC list id -> CC List Campaign.
        Map<String, Id> listToCampaign = new Map<String, Id>();
        for (Campaign c : [
            SELECT Id, CC_List_Id__c FROM Campaign
            WHERE CC_List_Id__c IN :allListIds AND RecordType.DeveloperName = 'CC_List'
        ]) {
            if (String.isNotBlank(c.CC_List_Id__c)) listToCampaign.put(c.CC_List_Id__c, c.Id);
        }

        // Match contacts (Salesforce Id primary, email fallback).
        Map<Id, Contact> byId = new Map<Id, Contact>();
        Map<String, Contact> byEmail = new Map<String, Contact>();
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Id IN :ids OR Email IN :emails]) {
            byId.put(c.Id, c);
            if (String.isNotBlank(c.Email)) {
                String k = c.Email.toLowerCase();
                if (!byEmail.containsKey(k)) byEmail.put(k, c);
            }
        }

        // Desired subscribed campaigns per matched contact.
        Map<Id, Set<Id>> desiredByContact = new Map<Id, Set<Id>>();
        for (TopicMembership m : memberships) {
            Contact c = null;
            if (m.salesforceId != null && byId.containsKey(m.salesforceId)) c = byId.get(m.salesforceId);
            else if (String.isNotBlank(m.email) && byEmail.containsKey(m.email.toLowerCase())) c = byEmail.get(m.email.toLowerCase());
            if (c == null) { res.failed++; res.errors.add('No Contact match for ' + (m.salesforceId != null ? String.valueOf(m.salesforceId) : m.email)); continue; }
            Set<Id> camps = new Set<Id>();
            for (String lid : m.subscribedListIds) {
                if (listToCampaign.containsKey(lid)) camps.add(listToCampaign.get(lid));
            }
            desiredByContact.put(c.Id, camps);
        }

        // Existing CampaignMembers for these contacts across ALL CC List campaigns — so topics the
        // contact has LEFT are reconciled to Unsubscribed, not just the ones they're still in.
        Map<String, CampaignMember> existing = new Map<String, CampaignMember>(); // key = contactId|campaignId
        for (CampaignMember cm : [
            SELECT Id, ContactId, CampaignId, Status FROM CampaignMember
            WHERE ContactId IN :desiredByContact.keySet()
              AND Campaign.RecordType.DeveloperName = 'CC_List'
        ]) {
            existing.put(cm.ContactId + '|' + cm.CampaignId, cm);
        }

        // Reconcile: desired -> Subscribed; existing-but-not-desired -> Unsubscribed.
        List<CampaignMember> toUpsert = new List<CampaignMember>();
        for (Id cid : desiredByContact.keySet()) {
            Set<Id> desired = desiredByContact.get(cid);
            for (Id campId : desired) {
                String key = cid + '|' + campId;
                if (existing.containsKey(key)) {
                    CampaignMember cm = existing.get(key);
                    if (cm.Status != 'Subscribed') { cm.Status = 'Subscribed'; toUpsert.add(cm); }
                } else {
                    toUpsert.add(new CampaignMember(ContactId = cid, CampaignId = campId, Status = 'Subscribed'));
                }
            }
            for (String key : existing.keySet()) {
                if (!key.startsWith(cid + '|')) continue;
                CampaignMember cm = existing.get(key);
                if (!desired.contains(cm.CampaignId) && cm.Status != 'Unsubscribed') {
                    cm.Status = 'Unsubscribed';
                    toUpsert.add(cm);
                }
            }
        }

        if (!toUpsert.isEmpty()) {
            List<Database.UpsertResult> urs = Database.upsert(toUpsert, false);
            for (Integer i = 0; i < urs.size(); i++) {
                if (urs[i].isSuccess()) res.updated++;
                else { res.failed++; res.errors.add(urs[i].getErrors()[0].getMessage()); }
            }
        }

        String status = res.failed == 0 ? 'Success' : (res.updated > 0 ? 'Partial' : 'Failed');
        logRun('Preference Sync', status, runStart, res, res.errors.isEmpty() ? 'OK' : String.join(res.errors, '\n'));
        return res;
    }

    /** Write one Integration_Log__c row for the run (best-effort; never throws to the caller). */
    private void logRun(String operation, String status, Datetime runStart, SyncResult res, String message) {
        Integration_Log__c log = new Integration_Log__c(
            Integration__c = 'Constant Contact',
            Operation__c = operation,
            Run_Status__c = status,
            Run_Start__c = runStart,
            Run_End__c = System.now(),
            Records_Processed__c = res.processed,
            Records_Updated__c = res.updated,
            Records_Failed__c = res.failed,
            Message__c = (message != null && message.length() > 32000) ? message.substring(0, 32000) : message
        );
        try {
            insert log;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Integration_Log insert failed: ' + e.getMessage());
        }
    }
}
