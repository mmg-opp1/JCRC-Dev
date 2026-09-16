/**
 * @description Pushes a changed Payment Method down onto the gift's existing payments.
 *
 *              Kept separate from OpportunityGalaTrigger rather than folded into it: that trigger is
 *              named for, and scoped to, gala automation, and the two touch nothing in common - one
 *              stamps deductibility and builds tables, this one writes a field on child payments.
 *              Consolidating both into a single OpportunityTrigger would be the tidier end state and
 *              is worth doing when the org is not mid-UAT.
 *
 *              Author: Jason Ott.
 */
trigger OpportunityPaymentMethodTrigger on Opportunity (after update) {
    PaymentMethodService.pushToExistingPayments(Trigger.new, Trigger.oldMap);
}