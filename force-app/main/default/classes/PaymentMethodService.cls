/**
 * @description Keeps a Payment's Payment Method in step with the Opportunity it belongs to.
 *
 *              On most gifts nobody ever opens the Payment: NPSP creates it automatically when the
 *              Opportunity posts, so the method entered on the gift is the only one recorded. This
 *              carries it down - onto payments as they are created, and onto payments that already
 *              exist when the method on the gift changes.
 *
 * @author Jason Ott
 * @created 2026-09-03
 *
 * Change Log:
 * -----------
 * 2026-09-03 - Jason Ott - Initial version.
 * 2026-09-03 - Jason Ott - Does not apply to Pledge or Grant.
 */
public with sharing class PaymentMethodService {

    /**
     * The two picklists are not identical, and the Payment one is UNRESTRICTED - an unmapped value
     * would be written straight in and stored as a value the picklist does not offer, showing up
     * later as a stray entry in every report grouped by payment method. So values are translated
     * where the two lists disagree, and anything still unrecognised is not written at all.
     *
     * Today the only disagreement is Opportunity "ACH/Wire" against Payment "ACH".
     */
    private static final Map<String, String> VALUE_TRANSLATIONS = new Map<String, String>{
        'ACH/Wire' => 'ACH'
    };

    /**
     * Record types this does not apply to. Pledges and grants are paid in instalments that can each
     * arrive a different way, so the method belongs on the individual payment, not on the gift.
     */
    private static final Set<String> EXCLUDED_RECORD_TYPES = new Set<String>{ 'Pledge', 'Grant' };

    private static Set<Id> excludedRecordTypeIds;

    private static Set<String> paymentMethodValues;

    /** Ids of the excluded record types, resolved once per transaction. */
    @TestVisible
    private static Set<Id> excludedRecordTypeIds() {
        if (excludedRecordTypeIds == null) {
            excludedRecordTypeIds = new Set<Id>();
            Map<String, Schema.RecordTypeInfo> byDeveloperName =
                Opportunity.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
            for (String developerName : EXCLUDED_RECORD_TYPES) {
                Schema.RecordTypeInfo info = byDeveloperName.get(developerName);
                if (info != null) {
                    excludedRecordTypeIds.add(info.getRecordTypeId());
                }
            }
        }
        return excludedRecordTypeIds;
    }

    /** Active values the Payment picklist actually offers, read once per transaction. */
    private static Set<String> allowedPaymentValues() {
        if (paymentMethodValues == null) {
            paymentMethodValues = new Set<String>();
            for (Schema.PicklistEntry e :
                    npe01__OppPayment__c.npe01__Payment_Method__c.getDescribe().getPicklistValues()) {
                if (e.isActive()) {
                    paymentMethodValues.add(e.getValue());
                }
            }
        }
        return paymentMethodValues;
    }

    /**
     * The Opportunity's value expressed as a Payment value, or null when it cannot be represented.
     * Returning null on purpose: writing nothing is better than writing a value the picklist does
     * not recognise, and it leaves whatever a person entered by hand alone.
     */
    @TestVisible
    private static String toPaymentValue(String opportunityValue) {
        if (String.isBlank(opportunityValue)) {
            return null;
        }
        String candidate = VALUE_TRANSLATIONS.containsKey(opportunityValue)
            ? VALUE_TRANSLATIONS.get(opportunityValue)
            : opportunityValue;
        return allowedPaymentValues().contains(candidate) ? candidate : null;
    }

    /**
     * BEFORE insert on Payment - fill the method in from the parent gift.
     *
     * Only fills a blank. A payment created with a method already on it was given one deliberately
     * (an import, or somebody splitting a pledge across a cheque and a card), and this is meant to
     * save data entry, not to overrule it.
     *
     * Runs while NPSP is auto-creating payments inside the Opportunity's own save, which is exactly
     * the case this exists for; the Opportunity is already queryable by then.
     */
    public static void applyFromOpportunity(List<npe01__OppPayment__c> payments) {
        Set<Id> opportunityIds = new Set<Id>();
        for (npe01__OppPayment__c p : payments) {
            if (p.npe01__Opportunity__c != null && String.isBlank(p.npe01__Payment_Method__c)) {
                opportunityIds.add(p.npe01__Opportunity__c);
            }
        }
        if (opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Payment_Method__c, RecordTypeId FROM Opportunity WHERE Id IN :opportunityIds]);

        for (npe01__OppPayment__c p : payments) {
            if (!String.isBlank(p.npe01__Payment_Method__c) || p.npe01__Opportunity__c == null) {
                continue;
            }
            Opportunity o = opps.get(p.npe01__Opportunity__c);
            if (o == null || excludedRecordTypeIds().contains(o.RecordTypeId)) {
                continue;
            }
            String value = toPaymentValue(o.Payment_Method__c);
            if (value != null) {
                p.npe01__Payment_Method__c = value;
            }
        }
    }

    /**
     * AFTER update on Opportunity - push a changed method down onto payments that already exist.
     *
     * Fires only when the method on the gift actually changed, so an ordinary edit to an opportunity
     * never disturbs its payments. Clearing the method deliberately does NOT clear the payments:
     * emptying a field on the gift is not a statement that the money never arrived by any means.
     *
     * This DOES overwrite a different method already on a payment, which is what "apply it to the
     * existing payments" has to mean - worth knowing for a pledge deliberately split across two
     * methods, where the payments should be set individually afterwards.
     */
    public static void pushToExistingPayments(List<Opportunity> updated, Map<Id, Opportunity> oldMap) {
        Map<Id, String> valueByOpportunity = new Map<Id, String>();
        for (Opportunity o : updated) {
            if (excludedRecordTypeIds().contains(o.RecordTypeId)) {
                continue;
            }
            Opportunity prior = (oldMap != null) ? oldMap.get(o.Id) : null;
            if (prior != null && prior.Payment_Method__c == o.Payment_Method__c) {
                continue;                       // untouched by this save
            }
            if (String.isBlank(o.Payment_Method__c)) {
                continue;                       // cleared, not set
            }
            String value = toPaymentValue(o.Payment_Method__c);
            if (value != null) {
                valueByOpportunity.put(o.Id, value);
            }
        }
        if (valueByOpportunity.isEmpty()) {
            return;
        }

        List<npe01__OppPayment__c> toUpdate = new List<npe01__OppPayment__c>();
        for (npe01__OppPayment__c p : [
                SELECT Id, npe01__Opportunity__c, npe01__Payment_Method__c
                FROM npe01__OppPayment__c
                WHERE npe01__Opportunity__c IN :valueByOpportunity.keySet()]) {
            String value = valueByOpportunity.get(p.npe01__Opportunity__c);
            if (p.npe01__Payment_Method__c != value) {
                p.npe01__Payment_Method__c = value;
                toUpdate.add(p);
            }
        }
        if (!toUpdate.isEmpty()) {
            // System mode on purpose: this is a trusted backend stamp made on the user's behalf while
            // they edit the gift, and a USER_MODE write would throw FLS on any profile holding the
            // payment field read-only (the JSI-123 lesson).
            update toUpdate;
        }
    }
}