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
 * 2026-07-20 - Jason Ott - JSI-109: engagement applier (applyEmailActivity) — CC_Email__c + CC_Email_Activity__c + Contact 90-day counters.
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

    /** JSI-109: one Constant Contact email + its per-recipient engagement (built by the client). */
    public class EmailCampaignDTO {
        public String ccCampaignActivityId;               // CC campaign_activity_id — upsert key on CC_Email__c
        public String name;
        public String subject;
        public Datetime sentDate;
        public Set<String> ccListIds = new Set<String>(); // contact_list_ids the email was sent to
        public List<ContactActivityDTO> activities = new List<ContactActivityDTO>();
    }

    /** JSI-109: one recipient's summary engagement for a single email (not one row per event). */
    public class ContactActivityDTO {
        public Id salesforceId;         // pushed Salesforce Id (primary match)
        public String ccContactId;      // CC contact UUID (match + Activity_Key)
        public String email;            // fallback match
        public Boolean opened = false;
        public Boolean clicked = false;
        public Boolean bounced = false;
        public Integer openCount = 0;
        public Integer clickCount = 0;
        public Datetime firstOpen;
        public Datetime lastOpen;
        public Datetime firstClick;
        public Datetime lastClick;
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

    /**
     * JSI-109 engagement sync. Upserts one CC_Email__c per Constant Contact email and one
     * CC_Email_Activity__c summary per recipient (idempotent on Activity_Key__c), then refreshes each
     * affected Contact's rolling 90-day open/click counters and last open/click dates. Writes one
     * Integration_Log__c ('Engagement Sync'). System-mode DML (trusted backend); recipient matching
     * reuses the pushed Salesforce Id, then CC_Contact_Id__c, then a case-insensitive email fallback.
     * @param campaigns normalized CC emails + per-recipient activity (built by ConstantContactClient)
     */
    public SyncResult applyEmailActivity(List<EmailCampaignDTO> campaigns) {
        Datetime runStart = System.now();
        SyncResult res = new SyncResult();
        if (campaigns == null || campaigns.isEmpty()) {
            logRun('Engagement Sync', 'Success', runStart, res, 'No email campaigns to process.');
            return res;
        }

        // --- 1. Upsert CC_Email__c (one per CC email); resolve CC_List__c from the sent-to list ids ---
        Set<String> allListIds = new Set<String>();
        for (EmailCampaignDTO em : campaigns) {
            if (em.ccListIds != null) allListIds.addAll(em.ccListIds);
        }
        Map<String, Id> listToCampaign = new Map<String, Id>();
        if (!allListIds.isEmpty()) {
            for (Campaign camp : [
                SELECT Id, CC_List_Id__c FROM Campaign
                WHERE CC_List_Id__c IN :allListIds AND RecordType.DeveloperName = 'CC_List'
            ]) {
                if (String.isNotBlank(camp.CC_List_Id__c)) listToCampaign.put(camp.CC_List_Id__c, camp.Id);
            }
        }
        List<CC_Email__c> emails = new List<CC_Email__c>();
        for (EmailCampaignDTO em : campaigns) {
            if (String.isBlank(em.ccCampaignActivityId)) continue;
            // First matching sent-to list becomes the audience lookup; attribution Campaign__c is set manually.
            Id listCampId = null;
            for (String lid : em.ccListIds) {
                if (listToCampaign.containsKey(lid)) { listCampId = listToCampaign.get(lid); break; }
            }
            String nm = String.isNotBlank(em.name) ? em.name
                      : (String.isNotBlank(em.subject) ? em.subject : em.ccCampaignActivityId);
            emails.add(new CC_Email__c(
                Name = nm.abbreviate(80),
                CC_Campaign_Activity_Id__c = em.ccCampaignActivityId,
                Subject__c = em.subject,
                Sent_Date__c = em.sentDate,
                CC_List__c = listCampId
            ));
        }
        Map<String, Id> caIdToEmailId = new Map<String, Id>();
        if (!emails.isEmpty()) {
            List<Database.UpsertResult> emailUrs =
                Database.upsert(emails, CC_Email__c.CC_Campaign_Activity_Id__c, false);
            for (Integer i = 0; i < emailUrs.size(); i++) {
                if (emailUrs[i].isSuccess()) {
                    caIdToEmailId.put(emails[i].CC_Campaign_Activity_Id__c, emailUrs[i].getId());
                } else {
                    res.errors.add('CC_Email ' + emails[i].CC_Campaign_Activity_Id__c + ': '
                        + emailUrs[i].getErrors()[0].getMessage());
                }
            }
        }

        // --- 2. Match recipients and upsert one CC_Email_Activity__c per contact per email ---
        Set<Id> ids = new Set<Id>();
        Set<String> ccIds = new Set<String>();
        Set<String> recipEmails = new Set<String>();
        for (EmailCampaignDTO em : campaigns) {
            for (ContactActivityDTO a : em.activities) {
                res.processed++;
                if (a.salesforceId != null) ids.add(a.salesforceId);
                if (String.isNotBlank(a.ccContactId)) ccIds.add(a.ccContactId);
                if (String.isNotBlank(a.email)) recipEmails.add(a.email.toLowerCase());
            }
        }
        Map<Id, Contact> byId = new Map<Id, Contact>();
        Map<String, Contact> byCc = new Map<String, Contact>();
        Map<String, Contact> byEmail = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, Email, CC_Contact_Id__c FROM Contact
            WHERE Id IN :ids OR CC_Contact_Id__c IN :ccIds OR Email IN :recipEmails
        ]) {
            byId.put(c.Id, c);
            if (String.isNotBlank(c.CC_Contact_Id__c)) byCc.put(c.CC_Contact_Id__c, c);
            if (String.isNotBlank(c.Email)) {
                String k = c.Email.toLowerCase();
                if (!byEmail.containsKey(k)) byEmail.put(k, c);
            }
        }

        List<CC_Email_Activity__c> acts = new List<CC_Email_Activity__c>();
        Set<Id> affected = new Set<Id>();
        for (EmailCampaignDTO em : campaigns) {
            Id emailId = caIdToEmailId.get(em.ccCampaignActivityId);
            if (emailId == null) continue;
            for (ContactActivityDTO a : em.activities) {
                Contact c = null;
                if (a.salesforceId != null && byId.containsKey(a.salesforceId)) c = byId.get(a.salesforceId);
                else if (String.isNotBlank(a.ccContactId) && byCc.containsKey(a.ccContactId)) c = byCc.get(a.ccContactId);
                else if (String.isNotBlank(a.email) && byEmail.containsKey(a.email.toLowerCase())) c = byEmail.get(a.email.toLowerCase());
                if (c == null) {
                    res.failed++;
                    res.errors.add('No Contact match for '
                        + (a.salesforceId != null ? String.valueOf(a.salesforceId)
                           : (a.ccContactId != null ? a.ccContactId : a.email)));
                    continue;
                }
                String keyPart = String.isNotBlank(a.ccContactId) ? a.ccContactId : String.valueOf(c.Id);
                String status = a.clicked ? 'Clicked' : (a.opened ? 'Opened' : (a.bounced ? 'Bounced' : 'Sent'));
                acts.add(new CC_Email_Activity__c(
                    CC_Email__c = emailId,
                    Contact__c = c.Id,
                    Activity_Key__c = em.ccCampaignActivityId + '|' + keyPart,
                    Status__c = status,
                    Opened__c = a.opened, Clicked__c = a.clicked, Bounced__c = a.bounced,
                    Open_Count__c = a.openCount, Click_Count__c = a.clickCount,
                    First_Open_Date__c = a.firstOpen, Last_Open_Date__c = a.lastOpen,
                    First_Click_Date__c = a.firstClick, Last_Click_Date__c = a.lastClick
                ));
                affected.add(c.Id);
            }
        }
        if (!acts.isEmpty()) {
            List<Database.UpsertResult> urs =
                Database.upsert(acts, CC_Email_Activity__c.Activity_Key__c, false);
            for (Integer i = 0; i < urs.size(); i++) {
                if (urs[i].isSuccess()) res.updated++;
                else { res.failed++; res.errors.add(urs[i].getErrors()[0].getMessage()); }
            }
        }

        // --- 3. Refresh each affected Contact's rolling 90-day counters + last open/click dates ---
        if (!affected.isEmpty()) {
            Datetime cutoff = System.now().addDays(-90);
            Map<Id, Contact> upd = new Map<Id, Contact>();
            for (AggregateResult ar : [
                SELECT Contact__c cid, SUM(Open_Count__c) opens, SUM(Click_Count__c) clicks,
                       MAX(Last_Open_Date__c) lo, MAX(Last_Click_Date__c) lc
                FROM CC_Email_Activity__c
                WHERE Contact__c IN :affected AND CC_Email__r.Sent_Date__c >= :cutoff
                GROUP BY Contact__c
            ]) {
                Id cid = (Id) ar.get('cid');
                Contact e = new Contact(Id = cid);
                Object o = ar.get('opens');
                e.Email_Opens_Last_90_Days__c = (o == null) ? 0 : ((Decimal) o).intValue();
                Object cl = ar.get('clicks');
                e.Email_Clicks_Last_90_Days__c = (cl == null) ? 0 : ((Decimal) cl).intValue();
                Datetime lo = (Datetime) ar.get('lo');
                if (lo != null) e.Email_Last_Open__c = lo.date();
                Datetime lc = (Datetime) ar.get('lc');
                if (lc != null) e.Email_Last_Click__c = lc.date();
                upd.put(cid, e);
            }
            if (!upd.isEmpty()) Database.update(upd.values(), false);
        }

        String status = res.failed == 0 ? 'Success' : (res.updated > 0 ? 'Partial' : 'Failed');
        logRun('Engagement Sync', status, runStart, res, res.errors.isEmpty() ? 'OK' : String.join(res.errors, '\n'));
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
