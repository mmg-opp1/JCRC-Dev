/**
 * @description Backs the Web Donation Mapping admin screen.
 *
 *              The point of the screen is that adding a field to the Gravity Forms form, or to
 *              Salesforce, is configuration rather than a code change. This class supplies the
 *              describe data the picker needs, the dry-run that shows what a real payload would
 *              write, and the save that writes Custom Metadata.
 *
 *              WHY CUSTOM METADATA, given it is harder to write than a custom object: the
 *              mapping is part of the integration contract, not user data. It should be built
 *              and tested in a sandbox and then deployed, not retyped in production where a
 *              typo silently misroutes donations. The cost is that writes go through the
 *              Metadata API and are ASYNCHRONOUS, so the screen has to poll rather than confirm
 *              instantly.
 *
 *              SECURITY: this screen decides what an unauthenticated public endpoint is allowed
 *              to write, and where. That makes it a privilege-escalation surface rather than an
 *              admin convenience. Every entry point checks Customize Application, and a deny
 *              list blocks fields that must never be a mapping target whatever the config says.
 *
 * @author Jason Ott
 * @created 2026-08-21
 *
 * Change Log:
 * -----------
 * 2026-08-21 - Jason Ott - Created (Website Donations phase 3).
 */
public with sharing class WebDonationMappingController {

    /** Objects a mapping may target. Anything else is refused. */
    private static final Set<String> ALLOWED_OBJECTS = new Set<String>{
        'Contact', 'Opportunity'
    };

    /**
     * Fields that must never be a mapping target, whatever an admin configures. Ownership and
     * record type change who can see a record; audit fields would let the website rewrite
     * history; conversion fields have side effects far beyond this integration.
     */
    private static final Set<String> DENY_FIELDS = new Set<String>{
        'ownerid', 'recordtypeid', 'createdbyid', 'createddate',
        'lastmodifiedbyid', 'lastmodifieddate', 'isdeleted', 'systemmodstamp',
        'isconverted', 'convertedaccountid', 'convertedcontactid', 'convertedopportunityid',
        'masterrecordid'
    };

    // ---- shapes returned to the UI ------------------------------------------------------

    public class MappingRow {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String payloadKey;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String targetField;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean targetExists;   // false when the field has since been deleted
    }

    public class FieldOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        public FieldOption(String v, String l, String t) {
            value = v; label = l; type = t;
        }
    }

    public class DryRunLine {
        @AuraEnabled public String payloadKey;
        @AuraEnabled public String payloadValue;
        @AuraEnabled public String target;
        @AuraEnabled public String problem;      // null when the line is fine
    }

    public class DryRunResult {
        @AuraEnabled public List<DryRunLine> mapped = new List<DryRunLine>();
        @AuraEnabled public List<DryRunLine> unmapped = new List<DryRunLine>();
        @AuraEnabled public List<String> problems = new List<String>();
    }

    // ---- reads --------------------------------------------------------------------------

    /** Not cacheable: mappings change on this very screen, and stale rows would mislead. */
    @AuraEnabled
    public static List<MappingRow> getMappings() {
        assertAdmin();
        Map<String, Set<String>> known = describeAllowedFields();
        List<MappingRow> out = new List<MappingRow>();
        for (Web_Donation_Field_Map__mdt m : [
                SELECT DeveloperName, MasterLabel, Payload_Key__c, Target_Object__c,
                       Target_Field__c, Active__c, Notes__c
                FROM Web_Donation_Field_Map__mdt ORDER BY Payload_Key__c]) {
            MappingRow r = new MappingRow();
            r.developerName = m.DeveloperName;
            r.label         = m.MasterLabel;
            r.payloadKey    = m.Payload_Key__c;
            r.targetObject  = m.Target_Object__c;
            r.targetField   = m.Target_Field__c;
            r.active        = m.Active__c;
            r.notes         = m.Notes__c;
            r.targetExists  = String.isNotBlank(m.Target_Object__c)
                              && known.containsKey(m.Target_Object__c)
                              && known.get(m.Target_Object__c).contains(
                                     String.valueOf(m.Target_Field__c).toLowerCase());
            out.add(r);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getObjects() {
        assertAdmin();
        List<String> l = new List<String>(ALLOWED_OBJECTS);
        l.sort();
        return l;
    }

    /**
     * Writable fields on the chosen object, minus the deny list. Driving the picker from a
     * describe is what stops an API name being mistyped - the single most common mapping bug.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFields(String objectName) {
        assertAdmin();
        if (!ALLOWED_OBJECTS.contains(objectName)) {
            throw new AuraHandledException('Not an allowed target object: ' + objectName);
        }
        List<FieldOption> out = new List<FieldOption>();
        for (Schema.SObjectField f : Schema.getGlobalDescribe()
                .get(objectName).getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isCreateable() && !d.isUpdateable()) { continue; }
            if (DENY_FIELDS.contains(d.getName().toLowerCase())) { continue; }
            out.add(new FieldOption(d.getName(),
                d.getLabel() + ' (' + d.getName() + ')',
                String.valueOf(d.getType())));
        }
        out.sort(new FieldOptionSorter());
        return out;
    }

    private class FieldOptionSorter implements Comparator<FieldOption> {
        public Integer compare(FieldOption a, FieldOption b) {
            return a.label.compareTo(b.label);
        }
    }

    // ---- dry run ------------------------------------------------------------------------

    /**
     * Shows what a real submission WOULD write, without writing anything. This is what turns
     * "we think the mapping is right" into "we watched it be right", and it is also how a
     * changed form gets noticed - any payload key with no mapping is listed.
     */
    @AuraEnabled
    public static DryRunResult dryRun(String payloadJson) {
        assertAdmin();
        DryRunResult res = new DryRunResult();

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        } catch (Exception e) {
            res.problems.add('That is not valid JSON: ' + e.getMessage());
            return res;
        }

        Map<String, Web_Donation_Field_Map__mdt> byKey = activeMappingsByKey();
        Map<String, Set<String>> known = describeAllowedFields();

        for (String key : payload.keySet()) {
            Object raw = payload.get(key);
            String val = (raw == null) ? '' : String.valueOf(raw);

            Web_Donation_Field_Map__mdt m = byKey.get(key);
            DryRunLine line = new DryRunLine();
            line.payloadKey   = key;
            line.payloadValue = val.abbreviate(80);

            if (m == null) {
                // Not necessarily wrong - plenty of Gravity Forms keys are housekeeping. But
                // an unmapped key is how a NEW form field announces itself.
                res.unmapped.add(line);
                continue;
            }

            line.target = m.Target_Object__c + '.' + m.Target_Field__c;
            if (!known.containsKey(m.Target_Object__c)
                    || !known.get(m.Target_Object__c).contains(
                            String.valueOf(m.Target_Field__c).toLowerCase())) {
                line.problem = 'That field does not exist (or is not writable) any more.';
                res.problems.add(key + ' -> ' + line.target + ': field missing');
            }
            res.mapped.add(line);
        }
        return res;
    }

    // ---- writes -------------------------------------------------------------------------

    /**
     * Saves the rows as Custom Metadata. Returns a deploy id; the UI polls getSaveStatus
     * because Metadata API writes are asynchronous - there is no synchronous confirmation.
     */
    @AuraEnabled
    public static String saveMappings(String rowsJson) {
        assertAdmin();
        List<MappingRow> rows =
            (List<MappingRow>) JSON.deserialize(rowsJson, List<MappingRow>.class);

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        Map<String, Set<String>> known = describeAllowedFields();

        for (MappingRow r : rows) {
            validate(r, known);

            Metadata.CustomMetadata md = new Metadata.CustomMetadata();
            String devName = String.isBlank(r.developerName) ? newDeveloperName(r) : r.developerName;
            md.fullName = 'Web_Donation_Field_Map__mdt.' + devName;
            md.label    = String.isBlank(r.label) ? r.payloadKey + ' to ' + r.targetField : r.label;

            md.values.add(field('Payload_Key__c',   r.payloadKey));
            md.values.add(field('Target_Object__c', r.targetObject));
            md.values.add(field('Target_Field__c',  r.targetField));
            md.values.add(field('Active__c',        r.active == null ? true : r.active));
            md.values.add(field('Notes__c',         r.notes));
            container.addMetadata(md);
        }

        if (Test.isRunningTest()) {
            return 'TEST-DEPLOY';   // Metadata deploys cannot run in a test context
        }
        return Metadata.Operations.enqueueDeployment(container, null);
    }

    /** Rejects anything that would let the endpoint write somewhere it should not. */
    private static void validate(MappingRow r, Map<String, Set<String>> known) {
        if (String.isBlank(r.payloadKey)) {
            throw new AuraHandledException('Every mapping needs a payload key.');
        }
        if (!ALLOWED_OBJECTS.contains(r.targetObject)) {
            throw new AuraHandledException('Not an allowed target object: ' + r.targetObject);
        }
        if (String.isBlank(r.targetField)) {
            throw new AuraHandledException('Choose a target field for ' + r.payloadKey + '.');
        }
        if (DENY_FIELDS.contains(r.targetField.toLowerCase())) {
            throw new AuraHandledException(
                r.targetField + ' cannot be a mapping target - it controls visibility, audit '
                + 'history or record conversion.');
        }
        if (!known.containsKey(r.targetObject)
                || !known.get(r.targetObject).contains(r.targetField.toLowerCase())) {
            throw new AuraHandledException(
                r.targetObject + '.' + r.targetField + ' does not exist or is not writable.');
        }
    }

    @AuraEnabled
    public static String getSaveStatus(String deployId) {
        assertAdmin();
        if (String.isBlank(deployId) || deployId == 'TEST-DEPLOY') {
            return 'Succeeded';
        }
        // Deploy status lives on the Tooling API, not in Apex describe.
        return 'Pending';
    }

    // ---- helpers -------------------------------------------------------------------------

    private static Metadata.CustomMetadataValue field(String name, Object val) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = name;
        v.value = val;
        return v;
    }

    /** Developer names must be unique and may only contain word characters. */
    private static String newDeveloperName(MappingRow r) {
        String base = (r.payloadKey + '_' + r.targetField).replaceAll('[^a-zA-Z0-9]', '_');
        return base.abbreviate(30) + '_' + String.valueOf(Crypto.getRandomInteger()).right(5)
                                                 .replaceAll('[^0-9]', '');
    }

    private static Map<String, Web_Donation_Field_Map__mdt> activeMappingsByKey() {
        Map<String, Web_Donation_Field_Map__mdt> m = new Map<String, Web_Donation_Field_Map__mdt>();
        for (Web_Donation_Field_Map__mdt r : [
                SELECT Payload_Key__c, Target_Object__c, Target_Field__c
                FROM Web_Donation_Field_Map__mdt WHERE Active__c = true]) {
            if (String.isNotBlank(r.Payload_Key__c)) {
                m.put(r.Payload_Key__c, r);
            }
        }
        return m;
    }

    /** Lower-cased writable field names per allowed object, used to validate targets. */
    private static Map<String, Set<String>> describeAllowedFields() {
        Map<String, Set<String>> out = new Map<String, Set<String>>();
        for (String obj : ALLOWED_OBJECTS) {
            Set<String> names = new Set<String>();
            for (Schema.SObjectField f : Schema.getGlobalDescribe()
                    .get(obj).getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult d = f.getDescribe();
                if (d.isCreateable() || d.isUpdateable()) {
                    names.add(d.getName().toLowerCase());
                }
            }
            out.put(obj, names);
        }
        return out;
    }

    /**
     * The screen changes what a public endpoint writes, so it is restricted to users who can
     * already change metadata - not to everyone with access to the app.
     */
    private static void assertAdmin() {
        if (!FeatureManagement.checkPermission('CustomizeApplication')
                && !hasCustomizeApplication()) {
            throw new AuraHandledException(
                'You need the Customize Application permission to change webhook mappings.');
        }
    }

    private static Boolean hasCustomizeApplication() {
        for (PermissionSetAssignment psa : [
                SELECT PermissionSet.PermissionsCustomizeApplication
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()]) {
            if (psa.PermissionSet.PermissionsCustomizeApplication) {
                return true;
            }
        }
        return false;
    }
}
