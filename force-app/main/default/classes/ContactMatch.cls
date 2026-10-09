/**
 * @description One potential Contact match returned by ContactMatcher. This is a Flow
 *              Apex-defined type: a flow can hold a collection of these, loop over them, and
 *              show the score, confidence and reasons beside each Contact so a user can decide
 *              whether the person already exists.
 *
 *              Sorts best-first (highest score, then name) so callers can rely on the order.
 * @author Jason Ott
 * @created 2026-10-09
 *
 * Change Log:
 * -----------
 * 2026-10-09 - Jason Ott - Initial version for the Jotform gala registration matching.
 */
public with sharing class ContactMatch implements Comparable {

    @AuraEnabled public Id contactId;
    @AuraEnabled public Contact contact;
    @AuraEnabled public String contactName;

    /** 0-100. See ContactMatcher for how each piece of evidence is weighted. */
    @AuraEnabled public Integer score;

    /** 'Strong', 'Possible' or 'Weak' - see ContactMatcher.STRONG_SCORE / POSSIBLE_SCORE. */
    @AuraEnabled public String confidence;

    /** Plain-English evidence, e.g. "Email matches; Last name similar (Jonson / Johnson)". */
    @AuraEnabled public String reasons;

    /**
     * @description Orders matches best-first: higher score wins; ties are broken by name so the
     *              order is stable from one run to the next.
     */
    public Integer compareTo(Object other) {
        ContactMatch that = (ContactMatch) other;
        if (this.score != that.score) {
            return this.score > that.score ? -1 : 1;
        }
        String a = this.contactName == null ? '' : this.contactName;
        String b = that.contactName == null ? '' : that.contactName;
        return a.compareTo(b);
    }
}
