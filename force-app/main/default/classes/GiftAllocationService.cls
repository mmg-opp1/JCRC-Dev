/**
 * @description JSI-90 — Keeps a gift's Gift Allocations in sync with the Opportunity's current state
 *              and refreshes each affected donor's Annual Giving Summary level.
 *
 *              RECONCILE (create/update): for each Opportunity, compute the DESIRED set of allocations
 *              from its current state and sync the existing ones to match — insert new, update amounts,
 *              reparent to a different fiscal-year summary when the Close Date moves, and DELETE
 *              allocations that no longer apply. A gift that stops qualifying (un-won, deleted, changed
 *              to In-Kind, or amount 0) therefore has its allocations removed and the donor's level
 *              recomputed from the new totals.
 *
 *              Crediting rules (confirmed by Jason, 2026-07-01):
 *                - Only Closed/Won opps with Amount > 0 qualify; In-Kind is excluded (securities count).
 *                - HARD credit → the primary contact; SOFT credit → each OCR in the JSI-85 soft set
 *                  (Soft Credit / Household Member / Matched Donor). Full gift Amount either way.
 *              Soft-credit OCR add/remove reconciles on the next save of the gift (opp-triggered).
 *
 *              REMOVE (before-delete): deletes a gift's allocations and recomputes its summaries.
 *
 *              Idempotent (allocations keyed by Allocation_Key__c = Opp|Contact|CreditType). Runs
 *              system-mode DML deliberately (trusted backend crediting) — JSI-89 precedent.
 *
 *              Invoked from Opportunity_Sync_Gift_Allocations (after-save) and
 *              Opportunity_Remove_Gift_Allocations (before-delete).
 * @author Jason Ott
 * @created 2026-07-01
 *
 * Change Log:
 * -----------
 * 2026-07-01 - Jason Ott - Initial version (JSI-90 Phase 3).
 * 2026-07-01 - Jason Ott - Reworked create-only logic into a full reconciler + delete handler
 *                          (handles amount/close-date/donor/stage changes and deletes). JSI-90 Phase 3.
 */
public with sharing class GiftAllocationService {

    // OCR roles that earn a SOFT allocation toward giving levels (JSI-85 soft-credit set).
    private static final Set<String> SOFT_CREDIT_ROLES = new Set<String>{
        'Soft Credit', 'Household Member', 'Matched Donor'
    };
    // Opportunity record types excluded from giving-level qualification.
    private static final Set<String> EXCLUDED_RECORD_TYPES = new Set<String>{ 'In_Kind_Gift' };

    // Recursion guard — Opportunities already reconciled in this transaction.
    @TestVisible private static Set<Id> processedOppIds = new Set<Id>();

    // A single desired allocation derived from an Opportunity's current state.
    private class Desired {
        Id contactId; String creditType; Decimal amount; Id oppId;
        Date fyStart; Date fyEnd; String fyLabel;
    }

    /**
     * @description Flow-invocable request wrapper — one per triggering Opportunity. Set isDelete = true
     *              from the before-delete flow so the gift's allocations are removed rather than synced.
     */
    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;
        @InvocableVariable(label='Is Delete' description='True when the gift is being deleted (remove its allocations).')
        public Boolean isDelete = false;
    }

    /**
     * @description Single flow entry point. Reconciles each gift's allocations to its current state, or
     *              removes them when isDelete = true (before-delete). One invocable method keeps the flow
     *              action unambiguous.
     */
    @InvocableMethod(label='JSI-90 Sync Gift Allocations' description='Reconcile a gift and its allocations, or remove them on delete, then recompute the donor level.')
    public static void syncGiftAllocations(List<Request> requests) {
        Set<Id> reconcileIds = new Set<Id>();
        Set<Id> removeIds = new Set<Id>();
        for (Request r : requests) {
            if (r.opportunityId == null) continue;
            if (r.isDelete == true) removeIds.add(r.opportunityId);
            else reconcileIds.add(r.opportunityId);
        }
        if (!removeIds.isEmpty()) remove(removeIds);
        if (!reconcileIds.isEmpty()) reconcile(reconcileIds);
    }

    /**
     * @description Syncs the allocations for the given opportunities to their current desired state
     *              (insert / update / reparent / delete) and recomputes every affected summary.
     */
    @TestVisible
    private static void reconcile(Set<Id> oppIds) {
        oppIds = new Set<Id>(oppIds);
        oppIds.removeAll(processedOppIds);
        if (oppIds.isEmpty()) return;
        processedOppIds.addAll(oppIds);

        // Existing allocations for these gifts (any year), keyed by Allocation_Key.
        Map<String, Gift_Allocation__c> existingByKey = new Map<String, Gift_Allocation__c>();
        Set<Id> affectedAgs = new Set<Id>();
        for (Gift_Allocation__c ga : [
            SELECT Id, Allocation_Key__c, Annual_Giving_Summary__c, Amount__c
            FROM Gift_Allocation__c WHERE Opportunity__c IN :oppIds
        ]) {
            existingByKey.put(ga.Allocation_Key__c, ga);
            affectedAgs.add(ga.Annual_Giving_Summary__c);
        }

        // Load opportunities + their OCRs.
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Amount, CloseDate, IsWon, IsClosed, RecordType.DeveloperName, npsp__Primary_Contact__c
            FROM Opportunity WHERE Id IN :oppIds
        ]);
        Map<Id, List<OpportunityContactRole>> ocrsByOpp = new Map<Id, List<OpportunityContactRole>>();
        for (OpportunityContactRole ocr : [
            SELECT OpportunityId, ContactId, Role, IsPrimary
            FROM OpportunityContactRole WHERE OpportunityId IN :oppIds
        ]) {
            if (!ocrsByOpp.containsKey(ocr.OpportunityId)) ocrsByOpp.put(ocr.OpportunityId, new List<OpportunityContactRole>());
            ocrsByOpp.get(ocr.OpportunityId).add(ocr);
        }

        // Build the desired allocations (empty for gifts that no longer qualify).
        Map<String, Desired> desiredByKey = new Map<String, Desired>();
        for (Opportunity o : opps.values()) {
            if (!qualifies(o)) continue;
            Date[] fy = fiscalYear(o.CloseDate);
            Id primaryContactId = o.npsp__Primary_Contact__c;
            Set<Id> softContactIds = new Set<Id>();
            if (ocrsByOpp.containsKey(o.Id)) {
                for (OpportunityContactRole ocr : ocrsByOpp.get(o.Id)) {
                    if (ocr.IsPrimary && primaryContactId == null) primaryContactId = ocr.ContactId;
                    if (!ocr.IsPrimary && SOFT_CREDIT_ROLES.contains(ocr.Role)) softContactIds.add(ocr.ContactId);
                }
            }
            softContactIds.remove(primaryContactId);
            if (primaryContactId != null) addDesired(desiredByKey, o, primaryContactId, 'Hard', fy);
            for (Id cid : softContactIds) addDesired(desiredByKey, o, cid, 'Soft', fy);
        }

        // Resolve/create the summaries the desired allocations need.
        Map<String, Id> agsIdByKey = ensureSummaries(desiredByKey.values());

        // Diff existing vs desired.
        List<Gift_Allocation__c> toUpsert = new List<Gift_Allocation__c>();
        List<Gift_Allocation__c> toDelete = new List<Gift_Allocation__c>();
        for (String key : desiredByKey.keySet()) {
            Desired d = desiredByKey.get(key);
            Id targetAgs = agsIdByKey.get(agsKey(d.contactId, d.fyStart));
            if (targetAgs == null) continue;
            affectedAgs.add(targetAgs);
            Gift_Allocation__c ex = existingByKey.get(key);
            if (ex == null) {
                toUpsert.add(new Gift_Allocation__c(
                    Annual_Giving_Summary__c = targetAgs, Opportunity__c = d.oppId, Contact__c = d.contactId,
                    Credit_Type__c = d.creditType, Amount__c = d.amount, Allocation_Key__c = key));
            } else {
                ex.Amount__c = d.amount;
                ex.Annual_Giving_Summary__c = targetAgs;   // reparent if the fiscal year changed
                toUpsert.add(ex);
            }
        }
        for (String key : existingByKey.keySet()) {
            if (!desiredByKey.containsKey(key)) toDelete.add(existingByKey.get(key));
        }

        if (!toDelete.isEmpty()) delete toDelete;
        if (!toUpsert.isEmpty()) upsert toUpsert Allocation_Key__c;

        affectedAgs.remove(null);
        assignLevels(affectedAgs);
    }

    /**
     * @description Removes all allocations for the given (being-deleted) opportunities and recomputes
     *              their summaries. Called from the before-delete flow so the gift can then delete.
     */
    @TestVisible
    private static void remove(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) return;
        List<Gift_Allocation__c> allocs = [SELECT Id, Annual_Giving_Summary__c FROM Gift_Allocation__c WHERE Opportunity__c IN :oppIds];
        if (allocs.isEmpty()) return;
        Set<Id> affectedAgs = new Set<Id>();
        for (Gift_Allocation__c ga : allocs) affectedAgs.add(ga.Annual_Giving_Summary__c);
        delete allocs;
        affectedAgs.remove(null);
        assignLevels(affectedAgs);
    }

    private static Boolean qualifies(Opportunity o) {
        return o.IsWon && o.IsClosed && o.Amount != null && o.Amount > 0
            && !EXCLUDED_RECORD_TYPES.contains(o.RecordType.DeveloperName);
    }

    private static void addDesired(Map<String, Desired> bucket, Opportunity o, Id contactId, String type, Date[] fy) {
        Desired d = new Desired();
        d.contactId = contactId; d.creditType = type; d.amount = o.Amount; d.oppId = o.Id;
        d.fyStart = fy[0]; d.fyEnd = fy[1]; d.fyLabel = fyLabel(fy[0], fy[1]);
        bucket.put(o.Id + '|' + contactId + '|' + type, d);
    }

    /**
     * @description Finds or creates the Annual Giving Summary for each needed (contact, fiscal year),
     *              linking each new summary to the donor's prior-year summary for inheritance.
     */
    private static Map<String, Id> ensureSummaries(List<Desired> desired) {
        Map<String, Id> idByKey = new Map<String, Id>();
        if (desired.isEmpty()) return idByKey;

        Set<Id> contactIds = new Set<Id>();
        Set<Date> fyStarts = new Set<Date>();
        for (Desired d : desired) { contactIds.add(d.contactId); fyStarts.add(d.fyStart); fyStarts.add(d.fyStart.addYears(-1)); }

        for (Annual_Giving_Summary__c a : [
            SELECT Id, Contact__c, FY_Start__c FROM Annual_Giving_Summary__c
            WHERE Contact__c IN :contactIds AND FY_Start__c IN :fyStarts
        ]) {
            idByKey.put(agsKey(a.Contact__c, a.FY_Start__c), a.Id);
        }

        Map<String, Annual_Giving_Summary__c> toCreate = new Map<String, Annual_Giving_Summary__c>();
        for (Desired d : desired) {
            String key = agsKey(d.contactId, d.fyStart);
            if (idByKey.containsKey(key) || toCreate.containsKey(key)) continue;
            Id priorId = idByKey.get(agsKey(d.contactId, d.fyStart.addYears(-1)));
            toCreate.put(key, new Annual_Giving_Summary__c(
                Contact__c = d.contactId, FY_Start__c = d.fyStart, FY_End__c = d.fyEnd,
                Fiscal_Year_Label__c = d.fyLabel, Prior_Year_Summary__c = priorId));
        }
        if (!toCreate.isEmpty()) {
            insert toCreate.values();
            for (String key : toCreate.keySet()) idByKey.put(key, toCreate.get(key).Id);
        }
        return idByKey;
    }

    /**
     * @description Recomputes Earned/Effective level and date-achieved for the given summaries from
     *              their current totals. Effective = higher rank of this year's earned and the prior
     *              year's effective (inheritance). Each level's date-achieved is stamped (if blank) when
     *              reached and CLEARED when no longer reached, using the latest contributing gift date.
     */
    private static void assignLevels(Set<Id> agsIds) {
        if (agsIds.isEmpty()) return;

        List<Giving_Level__c> levels = [
            SELECT Id, Name, Minimum_Amount__c, Maximum_Amount__c, Sort_Order__c
            FROM Giving_Level__c WHERE Active__c = true ORDER BY Sort_Order__c
        ];
        Map<Id, Giving_Level__c> levelById = new Map<Id, Giving_Level__c>(levels);
        Map<String, Schema.SObjectField> agsFields = Schema.SObjectType.Annual_Giving_Summary__c.fields.getMap();

        // Latest contributing gift Close Date per summary (for stamping newly-reached levels).
        Map<Id, Date> latestDateByAgs = new Map<Id, Date>();
        for (Gift_Allocation__c ga : [
            SELECT Annual_Giving_Summary__c, Opportunity__r.CloseDate
            FROM Gift_Allocation__c WHERE Annual_Giving_Summary__c IN :agsIds
        ]) {
            Date cd = ga.Opportunity__r.CloseDate;
            if (cd == null) continue;
            if (!latestDateByAgs.containsKey(ga.Annual_Giving_Summary__c) || latestDateByAgs.get(ga.Annual_Giving_Summary__c) < cd) {
                latestDateByAgs.put(ga.Annual_Giving_Summary__c, cd);
            }
        }

        // Requery the summaries with totals + prior-year effective level + all date-achieved fields.
        List<String> selectFields = new List<String>{
            'Id', 'Total_Giving__c', 'Effective_Level__c', 'Earned_Level__c', 'Prior_Year_Summary__r.Effective_Level__c'
        };
        for (String fn : agsFields.keySet()) {
            if (fn.startsWith('date_achieved_')) selectFields.add(agsFields.get(fn).getDescribe().getName());
        }
        List<Annual_Giving_Summary__c> summaries = Database.query(
            'SELECT ' + String.join(selectFields, ', ') + ' FROM Annual_Giving_Summary__c WHERE Id IN :agsIds');

        List<Annual_Giving_Summary__c> toUpdate = new List<Annual_Giving_Summary__c>();
        for (Annual_Giving_Summary__c a : summaries) {
            Decimal total = (a.Total_Giving__c == null) ? 0 : a.Total_Giving__c;
            Giving_Level__c earned = levelForAmount(levels, total);
            Giving_Level__c priorEff = (a.Prior_Year_Summary__r != null)
                ? levelById.get(a.Prior_Year_Summary__r.Effective_Level__c) : null;
            Giving_Level__c effective = higherRank(earned, priorEff);

            a.Earned_Level__c = (earned == null) ? null : earned.Id;
            a.Effective_Level__c = (effective == null) ? null : effective.Id;

            Date crossing = latestDateByAgs.get(a.Id);
            for (Giving_Level__c lvl : levels) {
                String key = 'date_achieved_' + lvl.Name.replaceAll('[^a-zA-Z0-9]', '_').toLowerCase() + '__c';
                if (!agsFields.containsKey(key)) continue;
                String apiName = agsFields.get(key).getDescribe().getName();
                Boolean reached = (lvl.Minimum_Amount__c == null) || (total >= lvl.Minimum_Amount__c);
                if (reached && a.get(apiName) == null && crossing != null) {
                    a.put(apiName, crossing);            // newly reached this year
                } else if (!reached && a.get(apiName) != null) {
                    a.put(apiName, null);                // no longer earned this year -> clear
                }
            }
            toUpdate.add(a);
        }
        update toUpdate;
    }

    private static Giving_Level__c levelForAmount(List<Giving_Level__c> levels, Decimal amount) {
        for (Giving_Level__c l : levels) {
            Boolean atOrAboveMin = (l.Minimum_Amount__c == null) || (amount >= l.Minimum_Amount__c);
            Boolean belowMax = (l.Maximum_Amount__c == null) || (amount < l.Maximum_Amount__c);
            if (atOrAboveMin && belowMax) return l;
        }
        return null;
    }

    private static Giving_Level__c higherRank(Giving_Level__c a, Giving_Level__c b) {
        if (a == null) return b;
        if (b == null) return a;
        return (a.Sort_Order__c >= b.Sort_Order__c) ? a : b;
    }

    // JCRC giving year runs July 1 – June 30. Returns [start, end] for a close date.
    @TestVisible
    private static Date[] fiscalYear(Date d) {
        Integer y = d.year();
        if (d.month() >= 7) return new Date[]{ Date.newInstance(y, 7, 1), Date.newInstance(y + 1, 6, 30) };
        return new Date[]{ Date.newInstance(y - 1, 7, 1), Date.newInstance(y, 6, 30) };
    }

    private static String fyLabel(Date s, Date e) {
        return 'FY' + e.year() + ' (Jul ' + s.year() + '-Jun ' + e.year() + ')';
    }

    private static String agsKey(Id contactId, Date fyStart) {
        return contactId + '|' + String.valueOf(fyStart);
    }
}
