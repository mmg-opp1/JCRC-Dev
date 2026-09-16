/**
 * @description Turns a raw Gravity Forms payload into a normalised structure the processor can
 *              use, so record creation never has to know that the donor's first name lives in
 *              field "1.3".
 *
 *              Gravity Forms sends NUMERIC FIELD IDS, not labels - "1.3" is first name, "10.1"
 *              is street, "28.x" are the designation checkboxes. Nothing in the payload is
 *              self-describing, so the ids below are the whole contract with the form.
 *
 *              THE ID BLOCK BELOW IS THE ONLY PLACE THEY APPEAR. Phase 3 replaces this block
 *              with the Custom Metadata mapping and the admin UI; nothing else has to change,
 *              because everything downstream consumes the parsed structure rather than the
 *              payload.
 *
 *              Deliberately never reads field 20.x - that is the card field, and it arrives
 *              masked. Reading only known-safe keys keeps card data out of Salesforce by
 *              construction rather than by trust.
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (Website Donations phase 2).
 */
public with sharing class WebDonationParser {

    // ---- THE FORM CONTRACT: replaced by Custom Metadata in phase 3 ---------------------
    private static final String F_FIRST_NAME   = '1.3';
    private static final String F_LAST_NAME    = '1.6';
    private static final String F_EMAIL        = '2';
    private static final String F_AMOUNT_TOTAL = '5';    // what the donor actually gave
    private static final String F_COMPANY      = '9';
    private static final String F_PHONE        = '11';
    private static final String F_PHONE_TYPE   = '13';
    private static final String F_WRITE_IN     = '23';   // "Specific Program Name"
    private static final String F_TRIBUTE_TYPE = '24.1';
    private static final String F_TRIBUTE_NAME = '24.2';
    private static final String F_NOTIFY_EMAIL = '25';
    private static final String F_FEE_OPT_IN   = '21.1';
    private static final String F_FEE_AMOUNT   = '22.2';
    private static final String P_STREET       = '10.1';
    private static final String P_STREET2      = '10.2';
    private static final String P_CITY         = '10.3';
    private static final String P_STATE        = '10.4';
    private static final String P_ZIP          = '10.5';
    private static final String DESIGNATION_PREFIX = '28.';
    // -----------------------------------------------------------------------------------

    public class Parsed {
        public String firstName, lastName, email, phone, phoneType, company;
        public String street, street2, city, state, postalCode;
        public Decimal amount;
        public Decimal feeAmount;
        public Boolean paidFee = false;
        public List<String> designations = new List<String>();
        public String writeIn;
        public String tributeType, tributeName, notifyEmail;
        public String entryId, formId, sourceUrl;
        public Date submittedOn;
        public Boolean hasPayment = false;
        public String transactionId, paymentStatus;
    }

    public static Parsed parse(String rawJson) {
        Parsed p = new Parsed();
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        p.entryId   = str(m, 'id');
        p.formId    = str(m, 'form_id');
        p.sourceUrl = str(m, 'source_url');

        p.firstName = str(m, F_FIRST_NAME);
        p.lastName  = str(m, F_LAST_NAME);
        p.email     = str(m, F_EMAIL);
        p.phone     = str(m, F_PHONE);
        p.phoneType = str(m, F_PHONE_TYPE);
        p.company   = str(m, F_COMPANY);

        p.street     = str(m, P_STREET);
        p.street2    = str(m, P_STREET2);
        p.city       = str(m, P_CITY);
        p.state      = str(m, P_STATE);
        p.postalCode = str(m, P_ZIP);

        // Field 5 is the total actually charged. When the donor opts to cover the processing
        // fee that total INCLUDES the fee, and Jason confirmed the whole amount is the gift.
        p.amount    = dec(str(m, F_AMOUNT_TOTAL));
        p.feeAmount = dec(stripCurrency(str(m, F_FEE_AMOUNT)));
        p.paidFee   = String.isNotBlank(str(m, F_FEE_OPT_IN));

        p.writeIn     = str(m, F_WRITE_IN);
        p.tributeType = str(m, F_TRIBUTE_TYPE);
        p.tributeName = str(m, F_TRIBUTE_NAME);
        p.notifyEmail = str(m, F_NOTIFY_EMAIL);

        // Designations are a checkbox group: every option gets its own 28.x key, and only the
        // ticked ones carry a value. Collect the non-blank ones.
        for (String key : m.keySet()) {
            if (key != null && key.startsWith(DESIGNATION_PREFIX)) {
                String v = str(m, key);
                if (String.isNotBlank(v)) {
                    p.designations.add(v.trim());
                }
            }
        }

        // Stripe fills these in via its own webhook AFTER this one, so they are normally null
        // on arrival. Absence means "not settled yet", NOT "intent only".
        p.transactionId = str(m, 'transaction_id');
        p.paymentStatus = str(m, 'payment_status');
        p.hasPayment    = String.isNotBlank(p.transactionId);

        p.submittedOn = parseDate(str(m, 'date_created'));
        return p;
    }

    // ---- helpers -----------------------------------------------------------------------

    private static String str(Map<String, Object> m, String key) {
        Object v = (m == null) ? null : m.get(key);
        return (v == null) ? null : String.valueOf(v).trim();
    }

    /** Strips a leading currency symbol and thousands separators before converting. */
    private static String stripCurrency(String s) {
        return String.isBlank(s) ? s : s.replaceAll('[^0-9.\\-]', '');
    }

    private static Decimal dec(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return Decimal.valueOf(stripCurrency(s));
        } catch (Exception e) {
            return null;
        }
    }

    /** Gravity Forms sends "2026-08-19 20:37:25" in UTC. */
    private static Date parseDate(String s) {
        if (String.isBlank(s)) {
            return Date.today();
        }
        try {
            return Date.valueOf(s.substring(0, 10));
        } catch (Exception e) {
            return Date.today();
        }
    }
}