/**
 * @description Turns a stored website donation payload into real records: a Contact, an
 *              Opportunity, and one GAU Allocation per designation the donor ticked.
 *
 *              Runs ASYNCHRONOUSLY, off the back of the staging record rather than the HTTP
 *              request. The endpoint has already answered the website by the time this runs,
 *              so a slow donor match or a failure here can never make Gravity Forms think the
 *              submission failed - the payload is safely stored either way and can be replayed.
 *
 *              CONFIGURATION-DRIVEN. Which payload key fills which field, how a donor is
 *              matched, what happens when nothing (or too much) matches, and where the gift is
 *              accounted all come from the Web Donation Mapping screen. Nothing about the shape
 *              of the form is hard-coded here any more.
 *
 *              Failure policy: a failure marks the staging record Failed with the reason and
 *              stops. It never leaves a half-built gift behind, and never silently drops a
 *              designation - anything it cannot map is recorded on Unmapped_Designations__c so
 *              a new option on the website surfaces for review instead of vanishing.
 *
 *              WITHOUT SHARING, deliberately. Async Apex runs as the user who enqueued it, and
 *              the only user who ever enqueues this one is the Site Guest User behind the
 *              webhook. Web_Donation__c is Private, guest-created records are reassigned away
 *              from the guest by the platform the moment they are saved, and the guest profile
 *              has neither View All nor Edit on the object - so under 'with sharing' this class
 *              could not read back the very record it was handed, and every automatic run
 *              failed. Record-level sharing is meaningless here anyway: the job is handed one
 *              specific staging id by its own trigger, it never queries on behalf of a person,
 *              and nothing a donor submits chooses which record it opens.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (Website Donations phase 2).
 * 2026-08-21 - Jason Ott - Now driven by the Web Donation Mapping configuration rather than
 *                          hard-coded field ids, match rules and account behavior.
 * 2026-09-10 - Jason Ott - Fixed: no website donation had ever processed automatically. Runs
 *                          without sharing so the guest-user context can read its own staging
 *                          record, and the read is now inside the try so a failure lands on the
 *                          record as Failed instead of disappearing.
 * 2026-10-23 - Jason Ott - American spelling throughout (no behavior change).
 */
public without sharing class WebDonationProcessor implements Queueable {

    private final Id stagingId;

    public WebDonationProcessor(Id stagingId) {
        this.stagingId = stagingId;
    }

    public void execute(QueueableContext ctx) {
        process(stagingId);
    }

    /** Separated from execute() so it can be driven directly when replaying a payload. */
    public static void process(Id stagingId) {
        Savepoint sp = Database.setSavepoint();
        try {
            // Queried INSIDE the try, and as a List rather than straight into an SObject. A
            // single-row assignment that matches nothing throws before the catch below is in
            // scope, so the staging record was left sitting at 'Received' with an empty
            // Error_Message__c - which is exactly how the guest-context failure above stayed
            // invisible for three weeks. A List cannot throw, so a miss is now reportable.
            List<Web_Donation__c> staged = [
                SELECT Id, Payload__c, Status__c, GF_Entry_Id__c
                FROM Web_Donation__c WHERE Id = :stagingId LIMIT 1
            ];
            if (staged.isEmpty()) {
                throw new ProcessingException(
                    'Staging record ' + stagingId + ' could not be read back for processing.');
            }
            Web_Donation__c wd = staged[0];

            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(wd.Payload__c);
            WebDonationConfig.Settings cfg = WebDonationConfig.settings();

            // ---- donor -------------------------------------------------------------------
            Contact incoming = buildContact(payload);
            if (String.isBlank(incoming.LastName)) {
                incoming.LastName = 'Unknown';
            }

            Boolean created = false;
            Contact donor = findContact(incoming, cfg);
            if (donor == null) {
                if (cfg.onNoMatch == 'Fail') {
                    throw new ProcessingException(
                        'No existing contact matched, and the configuration says to hold '
                        + 'unmatched submissions for review.');
                }
                insert incoming;
                donor = incoming;
                created = true;
            }

            // ---- gift ---------------------------------------------------------------------
            Opportunity opp = buildOpportunity(payload, donor, cfg);
            insert opp;

            if (String.isNotBlank(cfg.contactRole)) {
                setPrimaryRole(opp.Id, donor.Id, cfg.contactRole);
            }

            // ---- allocations ---------------------------------------------------------------
            List<String> unmapped = new List<String>();
            List<npsp__Allocation__c> allocs = buildAllocations(payload, opp, unmapped);
            if (!allocs.isEmpty()) {
                insert allocs;
            }

            update new Web_Donation__c(
                Id                       = wd.Id,
                Status__c                = 'Processed',
                Processed_At__c          = System.now(),
                Contact__c               = donor.Id,
                Contact_Was_Created__c   = created,
                Opportunity__c           = opp.Id,
                Unmapped_Designations__c = unmapped.isEmpty() ? null : String.join(unmapped, '\n'),
                Error_Message__c         = null
            );

        } catch (Exception e) {
            // Roll back any partial records - a half-built gift is worse than none.
            Database.rollback(sp);
            update new Web_Donation__c(
                Id               = stagingId,
                Status__c        = 'Failed',
                Processed_At__c  = System.now(),
                Error_Message__c = e.getTypeName() + ': ' + e.getMessage()
                                   + ' (line ' + e.getLineNumber() + ')'
            );
        }
    }

    // ---- donor -------------------------------------------------------------------------

    /** Builds a Contact from whatever the configuration maps onto Contact. */
    private static Contact buildContact(Map<String, Object> payload) {
        Contact c = new Contact();
        for (WebDonationConfig.Mapping m : WebDonationConfig.mappingsFor('Contact')) {
            WebDonationConfig.applyValue(c, m.targetField, valueFor(m, payload));
        }
        return c;
    }

    /**
     * Applies the configured match rule.
     *
     * Email-only is the loosest of the matching rules and the historical default; the stricter
     * ones exist because a shared household email would otherwise merge two people. Whatever
     * the rule, attaching a gift to the WRONG donor is far more damaging than a duplicate staff
     * can merge - so a rule that finds several candidates can be configured to stop rather than
     * guess.
     */
    private static Contact findContact(Contact incoming, WebDonationConfig.Settings cfg) {
        if (cfg.contactMatchRule == 'None') {
            return null;
        }
        String email = incoming.Email;
        String first = incoming.FirstName;
        String last  = incoming.LastName;

        List<Contact> found = new List<Contact>();

        if (cfg.contactMatchRule == 'Email') {
            if (String.isBlank(email)) {
                throw new ProcessingException(
                    'The match rule is email only, but this submission has no email address.');
            }
            found = [SELECT Id, FirstName, LastName, Email FROM Contact
                     WHERE Email = :email ORDER BY CreatedDate ASC];

        } else if (cfg.contactMatchRule == 'FirstLastEmail') {
            // All three must agree - distinguishes family members sharing one address.
            if (String.isBlank(email) || String.isBlank(first) || String.isBlank(last)) {
                throw new ProcessingException(
                    'The match rule needs first name, last name and email, and this submission '
                    + 'is missing at least one of them.');
            }
            found = [SELECT Id, FirstName, LastName, Email FROM Contact
                     WHERE Email = :email AND FirstName = :first AND LastName = :last
                     ORDER BY CreatedDate ASC];

        } else if (cfg.contactMatchRule == 'EmailOrFirstLast') {
            if (String.isNotBlank(email)) {
                found = [SELECT Id, FirstName, LastName, Email FROM Contact
                         WHERE Email = :email ORDER BY CreatedDate ASC];
            }
            if (found.isEmpty() && String.isNotBlank(first) && String.isNotBlank(last)) {
                found = [SELECT Id, FirstName, LastName, Email FROM Contact
                         WHERE FirstName = :first AND LastName = :last
                         ORDER BY CreatedDate ASC];
            }
        }

        if (found.isEmpty()) {
            return null;
        }
        if (found.size() > 1 && cfg.multipleMatchRule == 'Fail') {
            throw new ProcessingException(
                found.size() + ' contacts match this donor, and the configuration says to hold '
                + 'ambiguous submissions for review rather than guess.');
        }
        return (cfg.multipleMatchRule == 'Newest') ? found[found.size() - 1] : found[0];
    }

    // ---- gift --------------------------------------------------------------------------

    private static Opportunity buildOpportunity(Map<String, Object> payload, Contact donor,
                                                WebDonationConfig.Settings cfg) {
        Opportunity o = new Opportunity();

        for (WebDonationConfig.Mapping m : WebDonationConfig.mappingsFor('Opportunity')) {
            String raw = valueFor(m, payload);
            if (m.mappingType == 'Lookup') {
                Web_Donation_Value_Map__mdt t = WebDonationConfig.translate(m.payloadKey, raw);
                if (t != null) {
                    Id recId = WebDonationConfig.resolveRecord(
                        t.Target_Object__c, t.Target_Record_Name__c);
                    if (recId != null) {
                        o.put(m.targetField, recId);
                        continue;
                    }
                }
            }
            WebDonationConfig.applyValue(o, m.targetField, raw);
        }

        // Any translation that resolves to a Campaign sets the gift's campaign, wherever in the
        // payload it came from - this is how "Other:" lands on the review campaign.
        if (o.CampaignId == null) {
            Id camp = campaignFromTranslations(payload);
            if (camp != null) {
                o.CampaignId = camp;
            }
        }

        // The donor is always the primary contact; NPSP derives the household account from it
        // unless the configuration says to use an organization instead.
        o.npsp__Primary_Contact__c = donor.Id;

        if (String.isBlank(o.Name)) {
            String donorName = ((donor.FirstName == null ? '' : donor.FirstName) + ' '
                              + (donor.LastName == null ? '' : donor.LastName)).trim();
            o.Name = (String.isBlank(donorName) ? donor.Email : donorName) + ' - Website Donation';
        }
        if (o.CloseDate == null) {
            o.CloseDate = submittedDate(payload);
        }
        if (String.isBlank(o.StageName)) {
            throw new ProcessingException(
                'No stage. Add a Static mapping for Opportunity.StageName on the mapping screen.');
        }
        if (o.Amount == null || o.Amount <= 0) {
            throw new ProcessingException(
                'No usable gift amount. Check the mapping for Opportunity.Amount.');
        }
        if (o.RecordTypeId == null) {
            Id rt = recordTypeId('NPSP_Default');
            if (rt != null) { o.RecordTypeId = rt; }
        }

        applyAccountHandling(o, payload, cfg);
        return o;
    }

    /** First payload value that translates to a Campaign. */
    private static Id campaignFromTranslations(Map<String, Object> payload) {
        for (String key : payload.keySet()) {
            String val = str(payload, key);
            if (String.isBlank(val)) {
                continue;
            }
            Web_Donation_Value_Map__mdt t = WebDonationConfig.translate(key, val);
            if (t != null && t.Target_Object__c == 'Campaign') {
                Id c = WebDonationConfig.resolveRecord(t.Target_Object__c, t.Target_Record_Name__c);
                if (c != null) {
                    return c;
                }
            }
        }
        return null;
    }

    /**
     * Decides where the gift is credited. NPSP default leaves AccountId unset and lets NPSP put
     * an individual gift on their household account. The organization options matter because a
     * corporate gift landing on someone's household account is credited to the wrong donor.
     */
    private static void applyAccountHandling(Opportunity o, Map<String, Object> payload,
                                             WebDonationConfig.Settings cfg) {
        if (cfg.accountHandling == 'NPSPDefault') {
            return;
        }
        String company = String.isBlank(cfg.organizationPayloadKey)
            ? null : str(payload, cfg.organizationPayloadKey);

        if (String.isBlank(company)) {
            if (cfg.accountHandling == 'AlwaysOrganization') {
                throw new ProcessingException(
                    'Account handling is set to always use an organization, but this submission '
                    + 'has no company name.');
            }
            return;   // MatchOrganization with no company supplied: fall through to NPSP
        }

        List<Account> found = [SELECT Id FROM Account WHERE Name = :company LIMIT 2];
        if (!found.isEmpty()) {
            o.AccountId = found[0].Id;
            return;
        }
        if (cfg.onOrganizationNoMatch == 'CreateAccount') {
            Account a = new Account(Name = company);
            insert a;
            o.AccountId = a.Id;
        } else if (cfg.onOrganizationNoMatch == 'Fail') {
            throw new ProcessingException(
                'No Account named "' + company + '", and the configuration says to hold rather '
                + 'than create one.');
        }
        // UseHousehold: leave AccountId unset and let NPSP handle it
    }

    private static void setPrimaryRole(Id oppId, Id contactId, String role) {
        List<OpportunityContactRole> existing = [
            SELECT Id FROM OpportunityContactRole
            WHERE OpportunityId = :oppId AND ContactId = :contactId LIMIT 1];
        if (existing.isEmpty()) {
            insert new OpportunityContactRole(
                OpportunityId = oppId, ContactId = contactId, Role = role, IsPrimary = true);
        } else {
            update new OpportunityContactRole(Id = existing[0].Id, Role = role);
        }
    }

    // ---- allocations --------------------------------------------------------------------

    /**
     * One allocation per designation that translates to a GAU, split evenly. Even splitting is
     * a placeholder: the form never asks the donor how to divide a gift, so any split is an
     * assumption - this one is at least obvious and reversible. The rounding remainder goes to
     * the last allocation so the parts always sum to the gift exactly.
     */
    private static List<npsp__Allocation__c> buildAllocations(
            Map<String, Object> payload, Opportunity opp, List<String> unmapped) {

        List<npsp__Allocation__c> out = new List<npsp__Allocation__c>();
        Map<String, Id> gauByName = gauMap();
        Set<String> desigGroups = designationGroups();
        List<Id> targets = new List<Id>();

        for (String key : payload.keySet()) {
            String val = str(payload, key);
            if (String.isBlank(val) || !isDesignationKey(key, desigGroups)) {
                continue;
            }
            Web_Donation_Value_Map__mdt t = WebDonationConfig.translate(key, val);
            if (t == null) {
                // A designation nothing knows about - record it rather than lose it silently.
                if (!unmapped.contains(val)) {
                    unmapped.add(val);
                }
                continue;
            }
            if (t.Target_Object__c != 'General Accounting Unit') {
                continue;   // e.g. a Campaign translation, already handled on the gift
            }
            Id gau = gauByName.get(String.valueOf(t.Target_Record_Name__c).toLowerCase());
            if (gau == null) {
                if (!unmapped.contains(val)) {
                    unmapped.add(val);
                }
            } else {
                targets.add(gau);
            }
        }

        if (targets.isEmpty() || opp.Amount == null) {
            return out;
        }
        Decimal each = (opp.Amount / targets.size()).setScale(2, System.RoundingMode.DOWN);
        Decimal running = 0;
        for (Integer i = 0; i < targets.size(); i++) {
            Decimal amt = (i == targets.size() - 1) ? (opp.Amount - running) : each;
            running += amt;
            out.add(new npsp__Allocation__c(
                npsp__Opportunity__c             = opp.Id,
                npsp__General_Accounting_Unit__c = targets[i],
                npsp__Amount__c                  = amt));
        }
        return out;
    }

    /**
     * Which payload keys are designations.
     *
     * Derived from the configuration rather than guessed: a key is a designation if the value
     * translation table has a row scoped to that key, or to its checkbox group. An earlier
     * version assumed "any dotted key numbered 20 or above", which swept in the processing-fee
     * and tribute groups and reported "Yes, I want to pay the processing fee" as an unmapped
     * designation.
     *
     * The consequence of deriving it: a designation the table has never seen is only recognized
     * once at least one sibling in its group has been mapped. That is the right trade - it means
     * the unmapped list holds real designations rather than every stray checkbox on the form.
     */
    private static Set<String> designationGroups() {
        Set<String> groups = new Set<String>();
        for (Web_Donation_Value_Map__mdt v : [
                SELECT Payload_Key__c FROM Web_Donation_Value_Map__mdt
                WHERE Active__c = true AND Payload_Key__c != null]) {
            String k = v.Payload_Key__c;
            groups.add(k.contains('.') ? k.substringBefore('.') : k);
        }
        return groups;
    }

    private static Boolean isDesignationKey(String key, Set<String> groups) {
        if (String.isBlank(key)) {
            return false;
        }
        String g = key.contains('.') ? key.substringBefore('.') : key;
        return groups.contains(g);
    }

    // ---- helpers ---------------------------------------------------------------------------

    /** The value a mapping contributes: a static, or whatever the payload holds. */
    private static String valueFor(WebDonationConfig.Mapping m, Map<String, Object> payload) {
        if (m.mappingType == 'Static') {
            return m.staticValue;
        }
        return str(payload, m.payloadKey);
    }

    private static String str(Map<String, Object> m, String key) {
        if (m == null || String.isBlank(key)) {
            return null;
        }
        Object v = m.get(key);
        return (v == null) ? null : String.valueOf(v).trim();
    }

    private static Date submittedDate(Map<String, Object> payload) {
        String s = str(payload, 'date_created');
        if (String.isBlank(s)) {
            return Date.today();
        }
        try {
            return Date.valueOf(s.substring(0, 10));
        } catch (Exception e) {
            return Date.today();
        }
    }

    private static Map<String, Id> gauMap() {
        Map<String, Id> m = new Map<String, Id>();
        for (npsp__General_Accounting_Unit__c g : [
                SELECT Id, Name FROM npsp__General_Accounting_Unit__c WHERE npsp__Active__c = true]) {
            m.put(g.Name.toLowerCase(), g.Id);
        }
        return m;
    }

    private static Id recordTypeId(String devName) {
        List<RecordType> rt = [SELECT Id FROM RecordType
                               WHERE SobjectType = 'Opportunity' AND DeveloperName = :devName LIMIT 1];
        return rt.isEmpty() ? null : rt[0].Id;
    }

    public class ProcessingException extends Exception {}
}