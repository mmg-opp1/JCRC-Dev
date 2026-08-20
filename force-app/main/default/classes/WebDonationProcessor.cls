/**
 * @description Turns a stored website donation payload into real records: a Contact, an
 *              Opportunity, and one GAU Allocation per designation the donor ticked.
 *
 *              Runs ASYNCHRONOUSLY, off the back of the staging record rather than the HTTP
 *              request. The endpoint has already answered the website by the time this runs,
 *              so a slow donor match or a failure here can never make Gravity Forms think the
 *              submission failed - the payload is safely stored either way and can be replayed.
 *
 *              Failure policy: a failure marks the staging record Failed with the reason and
 *              stops. It never leaves a half-built gift behind, and never silently drops a
 *              designation - anything it cannot map is recorded on Unmapped_Designations__c so
 *              a new option on the website surfaces for review instead of vanishing.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (Website Donations phase 2).
 */
public with sharing class WebDonationProcessor implements Queueable {

    /**
     * Lets a test stage a record without the trigger also queuing the job. Needed because
     * Status__c DEFAULTS to 'Received', so simply omitting it on insert does not stop the
     * trigger - the default fills it in, the work runs twice, and the second run sees what
     * the first created.
     *
     * Public rather than @TestVisible because a trigger cannot see a @TestVisible member.
     */
    public static Boolean bypassTrigger = false;

    private final Id stagingId;

    public WebDonationProcessor(Id stagingId) {
        this.stagingId = stagingId;
    }

    public void execute(QueueableContext ctx) {
        process(stagingId);
    }

    /** Separated from execute() so it can be driven directly when replaying a payload. */
    public static void process(Id stagingId) {
        Web_Donation__c wd = [
            SELECT Id, Payload__c, Status__c, GF_Entry_Id__c
            FROM Web_Donation__c WHERE Id = :stagingId LIMIT 1
        ];

        Savepoint sp = Database.setSavepoint();
        try {
            WebDonationParser.Parsed p = WebDonationParser.parse(wd.Payload__c);

            if (String.isBlank(p.email)) {
                throw new ProcessingException('No email address in the payload - cannot identify the donor.');
            }
            if (p.amount == null || p.amount <= 0) {
                throw new ProcessingException('No usable gift amount in the payload.');
            }

            Boolean created = false;
            Contact c = findContact(p.email);
            if (c == null) {
                c = createContact(p);
                created = true;
            }

            Opportunity opp = buildOpportunity(p, c);
            insert opp;

            List<String> unmapped = new List<String>();
            List<npsp__Allocation__c> allocs = buildAllocations(p, opp, unmapped);
            if (!allocs.isEmpty()) {
                insert allocs;
            }

            update new Web_Donation__c(
                Id                       = wd.Id,
                Status__c                = 'Processed',
                Processed_At__c          = System.now(),
                Contact__c               = c.Id,
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

    // ---- donor ------------------------------------------------------------------------

    /**
     * Matches on email. Deliberately conservative: an exact email match is a strong signal,
     * and anything looser risks attaching a gift to the wrong donor, which is far more
     * damaging than creating a duplicate that staff can merge.
     * Oldest match wins, so repeat donors converge on their established record.
     */
    private static Contact findContact(String email) {
        List<Contact> found = [
            SELECT Id, FirstName, LastName, Email
            FROM Contact WHERE Email = :email
            ORDER BY CreatedDate ASC LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    private static Contact createContact(WebDonationParser.Parsed p) {
        Contact c = new Contact(
            FirstName          = p.firstName,
            LastName           = String.isBlank(p.lastName) ? 'Unknown' : p.lastName,
            Email              = p.email,
            Phone              = p.phone,
            MailingStreet      = joinStreet(p.street, p.street2),
            MailingCity        = p.city,
            MailingState       = p.state,
            MailingPostalCode  = p.postalCode
        );
        insert c;
        return c;
    }

    private static String joinStreet(String a, String b) {
        if (String.isBlank(a)) { return b; }
        if (String.isBlank(b)) { return a; }
        return a + '\n' + b;
    }

    // ---- gift -------------------------------------------------------------------------

    private static Opportunity buildOpportunity(WebDonationParser.Parsed p, Contact c) {
        String donorName = ((p.firstName == null ? '' : p.firstName) + ' '
                          + (p.lastName == null ? '' : p.lastName)).trim();
        if (String.isBlank(donorName)) {
            donorName = p.email;
        }

        Opportunity o = new Opportunity(
            Name                     = donorName + ' - Website Donation',
            Amount                   = p.amount,
            CloseDate                = p.submittedOn,
            StageName                = 'Posted',
            npsp__Primary_Contact__c = c.Id,
            Approach__c              = 'Online',
            npe01__Do_Not_Automatically_Create_Payment__c = false
        );

        Id rt = recordTypeId('NPSP_Default');
        if (rt != null) {
            o.RecordTypeId = rt;
        }

        // The donor typed their own programme name, so park the gift on the review campaign
        // and keep what they wrote - JSI-127's queue picks it up from there.
        if (String.isNotBlank(p.writeIn)) {
            o.Other_Campaign_Write_In__c = p.writeIn;
            Id reviewCampaign = campaignId('Website Donation - Other');
            if (reviewCampaign != null) {
                o.CampaignId = reviewCampaign;
            }
        }
        return o;
    }

    // ---- allocations -------------------------------------------------------------------

    /**
     * One allocation per ticked designation, split evenly across them. Even splitting is a
     * placeholder: the form does not ask the donor how to divide the gift, so any split is an
     * assumption - this one at least is obvious and reversible. Rounding remainder goes to the
     * first allocation so the parts always sum to the gift exactly.
     */
    private static List<npsp__Allocation__c> buildAllocations(
            WebDonationParser.Parsed p, Opportunity opp, List<String> unmapped) {

        List<npsp__Allocation__c> out = new List<npsp__Allocation__c>();
        if (p.designations.isEmpty()) {
            return out;
        }

        Map<String, Web_Donation_Designation__mdt> mapping = designationMap();
        Map<String, Id> gauByName = gauMap();

        List<Id> targets = new List<Id>();
        for (String d : p.designations) {
            Web_Donation_Designation__mdt row = mapping.get(normalise(d));
            Id gau = (row == null) ? null : gauByName.get(row.GAU_Name__c.toLowerCase());
            if (gau == null) {
                unmapped.add(d);
            } else {
                targets.add(gau);
            }
        }
        if (targets.isEmpty()) {
            return out;
        }

        Decimal each = (opp.Amount / targets.size()).setScale(2, System.RoundingMode.DOWN);
        Decimal running = 0;
        for (Integer i = 0; i < targets.size(); i++) {
            Decimal amt = (i == targets.size() - 1) ? (opp.Amount - running) : each;
            running += amt;
            out.add(new npsp__Allocation__c(
                npsp__Opportunity__c            = opp.Id,
                npsp__General_Accounting_Unit__c = targets[i],
                npsp__Amount__c                  = amt
            ));
        }
        return out;
    }

    /** Case-insensitive, and tolerant of the trailing colon the form sends ("Other:"). */
    private static String normalise(String s) {
        return String.isBlank(s) ? '' : s.trim().removeEnd(':').trim().toLowerCase();
    }

    private static Map<String, Web_Donation_Designation__mdt> designationMap() {
        Map<String, Web_Donation_Designation__mdt> m = new Map<String, Web_Donation_Designation__mdt>();
        for (Web_Donation_Designation__mdt r : [
                SELECT Form_Value__c, GAU_Name__c, Campaign_Name__c
                FROM Web_Donation_Designation__mdt WHERE Active__c = true]) {
            if (String.isNotBlank(r.Form_Value__c) && String.isNotBlank(r.GAU_Name__c)) {
                m.put(normalise(r.Form_Value__c), r);
            }
        }
        return m;
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

    private static Id campaignId(String name) {
        List<Campaign> c = [SELECT Id FROM Campaign WHERE Name = :name LIMIT 1];
        return c.isEmpty() ? null : c[0].Id;
    }

    public class ProcessingException extends Exception {}
}
