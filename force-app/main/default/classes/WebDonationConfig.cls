/**
 * @description Reads the Web Donation mapping configuration and applies it to a payload.
 *
 *              This is what makes the integration configurable rather than hard-coded: the
 *              field mappings, value translations and donor/account settings all come from
 *              Custom Metadata edited on the Web Donation Mapping screen, so adding a form
 *              field is configuration rather than a deployment.
 *
 *              Everything is loaded once per transaction and cached, because a submission can
 *              touch every mapping several times over.
 *
 *              READS CONFIG VIA getAll(), NOT SOQL, and runs WITHOUT SHARING. Both exist for
 *              the same reason: the website's Site Guest User is what ultimately drives this.
 *              SOQL against a custom metadata type is refused outright in a guest context
 *              ("sObject type is not supported"), and guest object permissions cannot be
 *              granted to cover it - getAll() reads the metadata cache instead, so it works in
 *              any context and costs no query. Sharing is off so resolveRecord() can still find
 *              the Campaign or GAU a translation points at; a guest sees no rows otherwise.
 *              Nothing here is donor-supplied - it reads administrator-authored configuration.
 *
 * @author Jason Ott
 * @created 2026-08-21
 *
 * Change Log:
 * -----------
 * 2026-08-21 - Jason Ott - Created (Website Donations - configuration-driven processing).
 * 2026-09-10 - Jason Ott - getAll() instead of SOQL for the three metadata types, and
 *                          without sharing, so website donations process in the guest
 *                          context instead of failing on every submission. applyValue no
 *                          longer gates on FLS, which was silently emptying every mapped
 *                          Contact and Opportunity field for the guest user.
 */
public without sharing class WebDonationConfig {

    // ---- settings ------------------------------------------------------------------------

    public class Settings {
        public String contactMatchRule       = 'Email';
        public String onNoMatch              = 'Create';
        public String multipleMatchRule      = 'Oldest';
        public String accountHandling        = 'NPSPDefault';
        public String organizationPayloadKey;
        public String onOrganizationNoMatch  = 'UseHousehold';
        public String contactRole;
    }

    private static Settings cachedSettings;

    /**
     * The active settings record, or the defaults. Defaults deliberately match what the
     * processor did before this existed, so an org with no setting record behaves as it always
     * has rather than changing silently.
     */
    public static Settings settings() {
        if (cachedSettings != null) {
            return cachedSettings;
        }
        Settings s = new Settings();
        // getAll() rather than SOQL - see the class header. Only one row is ever active, so
        // the first match wins, exactly as the old LIMIT 1 did.
        for (Web_Donation_Setting__mdt m : Web_Donation_Setting__mdt.getAll().values()) {
            if (m.Active__c != true) {
                continue;
            }
            if (String.isNotBlank(m.Contact_Match_Rule__c))      s.contactMatchRule      = m.Contact_Match_Rule__c;
            if (String.isNotBlank(m.On_No_Match__c))             s.onNoMatch             = m.On_No_Match__c;
            if (String.isNotBlank(m.Multiple_Match_Rule__c))     s.multipleMatchRule     = m.Multiple_Match_Rule__c;
            if (String.isNotBlank(m.Account_Handling__c))        s.accountHandling       = m.Account_Handling__c;
            if (String.isNotBlank(m.On_Organization_No_Match__c)) s.onOrganizationNoMatch = m.On_Organization_No_Match__c;
            s.organizationPayloadKey = m.Organization_Payload_Key__c;
            s.contactRole            = m.Contact_Role__c;
            break;
        }
        cachedSettings = s;
        return s;
    }

    // ---- field mappings -------------------------------------------------------------------

    public class Mapping {
        public String payloadKey;
        public String mappingType;   // Payload | Static | Lookup
        public String staticValue;
        public String targetObject;
        public String targetField;
    }

    private static List<Mapping> cachedMappings;

    public static List<Mapping> mappings() {
        if (cachedMappings != null) {
            return cachedMappings;
        }
        cachedMappings = new List<Mapping>();
        for (Web_Donation_Field_Map__mdt m : Web_Donation_Field_Map__mdt.getAll().values()) {
            if (m.Active__c != true) {
                continue;
            }
            if (String.isBlank(m.Target_Object__c) || String.isBlank(m.Target_Field__c)) {
                continue;
            }
            Mapping x = new Mapping();
            x.payloadKey   = m.Payload_Key__c;
            x.mappingType  = String.isBlank(m.Mapping_Type__c) ? 'Payload' : m.Mapping_Type__c;
            x.staticValue  = m.Static_Value__c;
            x.targetObject = m.Target_Object__c;
            x.targetField  = m.Target_Field__c;
            cachedMappings.add(x);
        }
        return cachedMappings;
    }

    /** Mappings for one object, e.g. every Contact mapping. */
    public static List<Mapping> mappingsFor(String objectName) {
        List<Mapping> out = new List<Mapping>();
        for (Mapping m : mappings()) {
            if (m.targetObject == objectName) {
                out.add(m);
            }
        }
        return out;
    }

    // ---- value translations ----------------------------------------------------------------

    private static List<Web_Donation_Value_Map__mdt> cachedValueMaps;

    private static List<Web_Donation_Value_Map__mdt> valueMaps() {
        if (cachedValueMaps == null) {
            cachedValueMaps = new List<Web_Donation_Value_Map__mdt>();
            for (Web_Donation_Value_Map__mdt v : Web_Donation_Value_Map__mdt.getAll().values()) {
                if (v.Active__c == true) {
                    cachedValueMaps.add(v);
                }
            }
        }
        return cachedValueMaps;
    }

    /**
     * Finds a translation for a value arriving under a given key. A row with a payload key set
     * only applies to that key; a row with none applies to any key, which suits the designation
     * checkbox group where every ticked option arrives under its own key.
     *
     * Matching ignores capitalisation and a trailing colon, because Gravity Forms sends values
     * like "Other:".
     */
    public static Web_Donation_Value_Map__mdt translate(String payloadKey, String incomingValue) {
        if (String.isBlank(incomingValue)) {
            return null;
        }
        String needle = normalise(incomingValue);
        Web_Donation_Value_Map__mdt generic;
        for (Web_Donation_Value_Map__mdt v : valueMaps()) {
            if (normalise(v.Incoming_Value__c) != needle) {
                continue;
            }
            if (String.isBlank(v.Payload_Key__c)) {
                generic = v;                       // keep looking for a key-specific match
            } else if (v.Payload_Key__c == payloadKey) {
                return v;                          // key-specific wins
            }
        }
        return generic;
    }

    public static String normalise(String s) {
        return String.isBlank(s) ? '' : s.trim().removeEnd(':').trim().toLowerCase();
    }

    /** Resolves a translation target to a record Id. Literal translations have none. */
    public static Id resolveRecord(String objectName, String recordName) {
        if (String.isBlank(objectName) || String.isBlank(recordName)) {
            return null;
        }
        if (objectName == 'Campaign') {
            List<Campaign> c = [SELECT Id FROM Campaign WHERE Name = :recordName LIMIT 1];
            return c.isEmpty() ? null : c[0].Id;
        }
        if (objectName == 'General Accounting Unit') {
            List<npsp__General_Accounting_Unit__c> g = [
                SELECT Id FROM npsp__General_Accounting_Unit__c WHERE Name = :recordName LIMIT 1];
            return g.isEmpty() ? null : g[0].Id;
        }
        return null;
    }

    // ---- applying a mapping to a record -----------------------------------------------------

    /**
     * Writes one mapped value onto a record, converting the text from the payload into whatever
     * the target field actually expects. A mapping pointing at a field that no longer exists is
     * skipped rather than throwing, so one stale row cannot stop a donation being recorded - the
     * mapping screen is where that gets noticed.
     *
     * @return true when a value was written
     */
    public static Boolean applyValue(SObject rec, String fieldName, String rawValue) {
        if (String.isBlank(fieldName) || rawValue == null) {
            return false;
        }
        Schema.SObjectField token = rec.getSObjectType().getDescribe()
                                       .fields.getMap().get(fieldName);
        if (token == null) {
            return false;
        }
        Schema.DescribeFieldResult d = token.getDescribe();
        // Deliberately NOT gated on isCreateable()/isUpdateable(). Those are FLS-aware, and the
        // Site Guest User behind a website donation holds no field-level security on the Contact
        // and Opportunity fields an administrator mapped - so gating on them dropped every single
        // mapped value and handed the matcher a blank Contact. What this genuinely needs to know
        // is whether the field can be written AT ALL, which is a property of the field and not of
        // the user: a formula or auto-number cannot. put() throws on those, and the catch below
        // already turns that into a skip, which is the "stale mapping must not stop a gift"
        // behaviour this method was written for.
        if (d.isCalculated() || d.isAutoNumber()) {
            return false;
        }
        try {
            rec.put(fieldName, convert(rawValue, d.getType()));
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Object convert(String raw, Schema.DisplayType t) {
        String v = raw.trim();
        if (t == Schema.DisplayType.Currency || t == Schema.DisplayType.Double
                || t == Schema.DisplayType.Percent) {
            return Decimal.valueOf(v.replaceAll('[^0-9.\\-]', ''));
        }
        if (t == Schema.DisplayType.Integer) {
            return Integer.valueOf(v.replaceAll('[^0-9\\-]', ''));
        }
        if (t == Schema.DisplayType.Boolean) {
            return v.equalsIgnoreCase('true') || v == '1' || v.equalsIgnoreCase('yes');
        }
        if (t == Schema.DisplayType.Date) {
            return Date.valueOf(v.length() >= 10 ? v.substring(0, 10) : v);
        }
        if (t == Schema.DisplayType.DateTime) {
            return Datetime.valueOf(v);
        }
        return v;   // text, picklist, email, phone, reference-as-id
    }
}