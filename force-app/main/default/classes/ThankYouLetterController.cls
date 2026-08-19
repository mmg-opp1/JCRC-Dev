/**
 * @description Supplies the merge data for the JCRC thank-you letter (ThankYouLetter VF page).
 *              The page renders the client's letterhead as a full-page background with the
 *              letter body positioned over it.
 *
 *              Which of the six letter variants is used is NOT decided here - it is read from
 *              Opportunity.Acknowledgment_Template__c, which the JSI-87 router stamps from
 *              Acknowledgment_Rule__mdt. The router decides, this page renders. That keeps a
 *              single source of truth and means new variants need no Apex change.
 *
 *              Variants: Ack_Letter_{Parade|Board|Standard}_{Tax|NoTax}
 *                - Tax   : states the amount inline and prints the tax-receipt footer block
 *                - NoTax : omits both (DAF gifts - the donor took their deduction when they
 *                          funded the DAF, so JCRC must not imply a second one)
 *
 * @author Jason Ott
 * @created 2026-08-19
 *
 * Change Log:
 * -----------
 * 2026-08-19 - Jason Ott - Created (JSI-87 real client templates).
 */
public with sharing class ThankYouLetterController {

    private final Opportunity opp;

    public ThankYouLetterController(ApexPages.StandardController sc) {
        // Pull the full record: the StandardController only carries the fields on the page layout.
        Id oppId = sc.getId();
        this.opp = [
            SELECT Id, Name, Amount, CloseDate, Last_Payment_Date__c, DAF_Gift__c,
                   Acknowledgment_Template__c, Campaign_Name__c,
                   npsp__Primary_Contact__c,
                   npsp__Primary_Contact__r.FirstName, npsp__Primary_Contact__r.LastName,
                   npsp__Primary_Contact__r.Salutation,
                   npsp__Primary_Contact__r.MailingStreet, npsp__Primary_Contact__r.MailingCity,
                   npsp__Primary_Contact__r.MailingState, npsp__Primary_Contact__r.MailingPostalCode,
                   Account.Name, Account.BillingStreet, Account.BillingCity,
                   Account.BillingState, Account.BillingPostalCode
            FROM Opportunity WHERE Id = :oppId WITH USER_MODE
        ];
    }

    /** Template key stamped by the router; falls back to the plainest variant. */
    public String templateKey {
        get { return String.isBlank(opp.Acknowledgment_Template__c)
                     ? 'Ack_Letter_Standard_Tax' : opp.Acknowledgment_Template__c; }
    }

    // ---- which blocks the page shows -------------------------------------------------
    /** NoTax variants omit the amount and the tax-receipt footer entirely. */
    public Boolean showTaxBlock { get { return !templateKey.endsWith('_NoTax'); } }
    public Boolean isParade     { get { return templateKey.contains('_Parade_'); } }
    public Boolean isBoard      { get { return templateKey.contains('_Board_'); } }

    // ---- merge values ----------------------------------------------------------------
    public String letterDate {
        get { return Datetime.now().format('MMMM d, yyyy'); }
    }

    /** Date the gift was received: the payment date where there is one, else the close date. */
    public String paymentDate {
        get {
            Date d = (opp.Last_Payment_Date__c != null) ? opp.Last_Payment_Date__c : opp.CloseDate;
            return (d == null) ? '' : Datetime.newInstance(d, Time.newInstance(0,0,0,0)).format('MMMM d, yyyy');
        }
    }

    public String firstName {
        get {
            Contact c = opp.npsp__Primary_Contact__r;
            return (c == null || String.isBlank(c.FirstName)) ? 'Friend' : c.FirstName;
        }
    }

    /** Addressee line - the contact where there is one, otherwise the organisation. */
    public String recipientName {
        get {
            Contact c = opp.npsp__Primary_Contact__r;
            if (c != null) {
                String n = (String.isBlank(c.Salutation) ? '' : c.Salutation + ' ')
                         + (String.isBlank(c.FirstName) ? '' : c.FirstName + ' ')
                         + (String.isBlank(c.LastName) ? '' : c.LastName);
                if (String.isNotBlank(n.trim())) return n.trim();
            }
            return (opp.Account != null) ? opp.Account.Name : '';
        }
    }

    /** Street line, then "City, ST Zip" - contact mailing address, else the account's. */
    public List<String> addressLines {
        get {
            Contact c = opp.npsp__Primary_Contact__r;
            String street, city, state, zip;
            if (c != null && String.isNotBlank(c.MailingStreet)) {
                street = c.MailingStreet; city = c.MailingCity;
                state  = c.MailingState;  zip  = c.MailingPostalCode;
            } else if (opp.Account != null) {
                street = opp.Account.BillingStreet; city = opp.Account.BillingCity;
                state  = opp.Account.BillingState;  zip  = opp.Account.BillingPostalCode;
            }
            List<String> out = new List<String>();
            if (String.isNotBlank(street)) out.addAll(street.split('\n'));
            String cityLine = (String.isBlank(city) ? '' : city)
                            + (String.isBlank(state) ? '' : ', ' + state)
                            + (String.isBlank(zip) ? '' : ' ' + zip);
            if (String.isNotBlank(cityLine.trim())) out.add(cityLine.trim());
            return out;
        }
    }

    public String campaignName {
        get { return String.isBlank(opp.Campaign_Name__c) ? '' : opp.Campaign_Name__c; }
    }

    /**
     * Formatted with thousands separators and ALWAYS two decimals, e.g. 12,500.00.
     * Decimal.format() drops trailing zeros, which on a tax receipt would print
     * "$12,500" where the client's template shows "$12,500.00" - so pad explicitly.
     */
    public String giftAmount {
        get {
            if (opp.Amount == null) return '';
            String s = opp.Amount.setScale(2).format();
            if (!s.contains('.')) {
                s += '.00';
            } else if (s.substringAfterLast('.').length() == 1) {
                s += '0';
            }
            return s;
        }
    }
}
