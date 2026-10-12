/**
 * @description Remembers the amount each NPSP Payment was created with (Original_Payment_Amount__c), so a
 *              payment later marked Paid for less can show its shortfall (Underpayment__c, a formula on
 *              the Payment).
 *
 *              Copied once, before insert, and only when nothing is already there - a value supplied on
 *              insert (e.g. a data load carrying the true original) is kept. Never changed afterwards:
 *              there is no update handling on purpose, because the point is to keep the first value.
 *              Runs inside the trigger, so it needs no user field access to the field, which is read-only
 *              for the JCRC profiles.
 * @author Jason Ott
 * @created 2026-10-12
 *
 * Change Log:
 * -----------
 * 2026-10-12 - Jason Ott - Initial version.
 */
public with sharing class PaymentAmountService {

    /** Before insert: copies Payment Amount into Original Payment Amount where the original is blank. */
    public static void stampOriginalAmount(List<npe01__OppPayment__c> payments) {
        for (npe01__OppPayment__c p : payments) {
            if (p.Original_Payment_Amount__c == null && p.npe01__Payment_Amount__c != null) {
                p.Original_Payment_Amount__c = p.npe01__Payment_Amount__c;
            }
        }
    }
}
