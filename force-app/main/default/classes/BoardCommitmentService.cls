/**
 * @description Board tracking automation (JSI-123 Phase 2). Two jobs:
 *   1. BEFORE save — stamp derived fields on Board Membership Year (Counts Toward Limit, Year Key,
 *      Fiscal Year Label/End) and Committee Assignment (Assignment Key, Fiscal Year Label).
 *   2. AFTER save — derive each affected member's annual board commitment for the fiscal year and stamp
 *      it onto that year's Annual Giving Summary (creating the AGS if needed), unless overridden.
 *
 *   Commitment rule (D18): $0 if honorary/Past President; else MAX(highest board base $5k/$1.8k,
 *   $10k if the member is a committee Chair/Co-Chair OR on the Executive Committee that year). Only
 *   applies to actual board members (a non-board committee member owes nothing here).
 *
 * @author Jason Ott
 * @created 2026-07-28
 *
 * Change Log:
 * -----------
 * 2026-07-28 - Jason Ott - Initial version (JSI-123 Phase 2 automation).
 */
public with sharing class BoardCommitmentService {

    private static final Set<String> OFFICER_ROLES =
        new Set<String>{ 'Chair', 'President', 'Vice President', 'Secretary', 'Treasurer' };
    private static final Set<String> COMMITTEE_CHAIR_ROLES = new Set<String>{ 'Chair', 'Co-Chair' };
    private static final Decimal ELEVATED_COMMITMENT = 10000;

    /** Officer roles pause the board clock (do not count toward the 6-year limit). */
    public static Boolean isOfficer(String role) {
        return role != null && OFFICER_ROLES.contains(role);
    }

    /** Fiscal-year label from the July-1 start date: FY_Start Jul 1 2026 -> "FY2027". */
    public static String labelFor(Date fyStart) {
        return 'FY' + String.valueOf(fyStart.year() + 1);
    }

    // ---------------------------------------------------------------- BEFORE-save stamping

    public static void stampMembershipYears(List<Board_Membership_Year__c> rows) {
        for (Board_Membership_Year__c r : rows) {
            if (r.FY_Start__c != null) {
                if (r.FY_End__c == null) {
                    r.FY_End__c = r.FY_Start__c.addYears(1).addDays(-1);
                }
                if (String.isBlank(r.Fiscal_Year_Label__c)) {
                    r.Fiscal_Year_Label__c = labelFor(r.FY_Start__c);
                }
            }
            // Counts toward the term limit = a regular board-member year (not officer, not Past President)
            // that has actually started (its fiscal year has begun). Future pre-created years don't count
            // yet — the BoardYearAdvance schedulable flips them as each fiscal year begins.
            Boolean pastPresident = r.Role__c == 'Past President';
            Boolean started = r.FY_Start__c != null && r.FY_Start__c <= Date.today();
            r.Counts_Toward_Limit__c =
                (r.Role__c != null) && !isOfficer(r.Role__c) && !pastPresident && started;

            if (r.Board_Term__c != null && String.isNotBlank(r.Fiscal_Year_Label__c)) {
                r.Year_Key__c = String.valueOf(r.Board_Term__c) + '|' + r.Fiscal_Year_Label__c;
            }
        }
    }

    public static void stampCommitteeAssignments(List<Committee_Assignment__c> rows) {
        for (Committee_Assignment__c r : rows) {
            if (r.FY_Start__c != null && String.isBlank(r.Fiscal_Year_Label__c)) {
                r.Fiscal_Year_Label__c = labelFor(r.FY_Start__c);
            }
            if (r.Contact__c != null && r.Committee__c != null && String.isNotBlank(r.Fiscal_Year_Label__c)) {
                r.Assignment_Key__c = String.valueOf(r.Contact__c) + '|'
                    + String.valueOf(r.Committee__c) + '|' + r.Fiscal_Year_Label__c;
            }
        }
    }

    // ---------------------------------------------------------------- AFTER-save recompute entry points

    public static void recomputeFromMembershipYears(List<Board_Membership_Year__c> rows) {
        Map<Id, Set<Date>> pairs = new Map<Id, Set<Date>>();
        for (Board_Membership_Year__c r : rows) {
            addPair(pairs, r.Contact__c, r.FY_Start__c);
        }
        recompute(pairs);
    }

    public static void recomputeFromCommitteeAssignments(List<Committee_Assignment__c> rows) {
        Map<Id, Set<Date>> pairs = new Map<Id, Set<Date>>();
        for (Committee_Assignment__c r : rows) {
            addPair(pairs, r.Contact__c, r.FY_Start__c);
        }
        recompute(pairs);
    }

    private static void addPair(Map<Id, Set<Date>> pairs, Id contactId, Date fyStart) {
        if (contactId == null || fyStart == null) {
            return;
        }
        if (!pairs.containsKey(contactId)) {
            pairs.put(contactId, new Set<Date>());
        }
        pairs.get(contactId).add(fyStart);
    }

    // ---------------------------------------------------------------- commitment derivation

    /** For each (contact, fiscal-year-start), derive and stamp the board commitment onto the AGS. */
    public static void recompute(Map<Id, Set<Date>> contactToFyStarts) {
        if (contactToFyStarts == null || contactToFyStarts.isEmpty()) {
            return;
        }
        Set<Id> contactIds = contactToFyStarts.keySet();
        Set<Date> allFy = new Set<Date>();
        for (Set<Date> s : contactToFyStarts.values()) {
            allFy.addAll(s);
        }

        // board memberships by contact|fyStart
        Map<String, List<Board_Membership_Year__c>> bmyByKey =
            new Map<String, List<Board_Membership_Year__c>>();
        for (Board_Membership_Year__c b : [
                SELECT Contact__c, FY_Start__c, Role__c,
                       Board_Term__r.Member_Type__r.Default_Annual_Commitment__c
                FROM Board_Membership_Year__c
                WHERE Contact__c IN :contactIds AND FY_Start__c IN :allFy
                WITH USER_MODE]) {
            String k = key(b.Contact__c, b.FY_Start__c);
            if (!bmyByKey.containsKey(k)) {
                bmyByKey.put(k, new List<Board_Membership_Year__c>());
            }
            bmyByKey.get(k).add(b);
        }

        // committee-driven $10k elevation by contact|fyStart
        Map<String, Boolean> elevated = new Map<String, Boolean>();
        for (Committee_Assignment__c ca : [
                SELECT Contact__c, FY_Start__c, Committee_Role__c, Committee__r.Is_Executive_Committee__c
                FROM Committee_Assignment__c
                WHERE Contact__c IN :contactIds AND FY_Start__c IN :allFy AND Active__c = true
                WITH USER_MODE]) {
            Boolean e = (ca.Committee_Role__c != null && COMMITTEE_CHAIR_ROLES.contains(ca.Committee_Role__c))
                || (ca.Committee__r != null && ca.Committee__r.Is_Executive_Committee__c == true);
            if (e) {
                elevated.put(key(ca.Contact__c, ca.FY_Start__c), true);
            }
        }

        // existing AGS by contact|fyStart
        Map<String, Annual_Giving_Summary__c> agsByKey = new Map<String, Annual_Giving_Summary__c>();
        for (Annual_Giving_Summary__c a : [
                SELECT Contact__c, FY_Start__c, Board_Commitment__c, Board_Commitment_Override__c
                FROM Annual_Giving_Summary__c
                WHERE Contact__c IN :contactIds AND FY_Start__c IN :allFy
                WITH USER_MODE]) {
            agsByKey.put(key(a.Contact__c, a.FY_Start__c), a);
        }

        List<Annual_Giving_Summary__c> toInsert = new List<Annual_Giving_Summary__c>();
        List<Annual_Giving_Summary__c> toUpdate = new List<Annual_Giving_Summary__c>();

        for (Id contactId : contactToFyStarts.keySet()) {
            for (Date fy : contactToFyStarts.get(contactId)) {
                if (fy > Date.today()) {
                    continue; // don't stamp commitment on future years — done as each year starts
                }
                String k = key(contactId, fy);
                List<Board_Membership_Year__c> memberships = bmyByKey.get(k);
                if (memberships == null || memberships.isEmpty()) {
                    continue; // not a board member that year -> no board commitment to set
                }
                Decimal commitment = deriveCommitment(memberships, elevated.containsKey(k));

                Annual_Giving_Summary__c ags = agsByKey.get(k);
                if (ags == null) {
                    toInsert.add(new Annual_Giving_Summary__c(
                        Contact__c = contactId, FY_Start__c = fy,
                        FY_End__c = fy.addYears(1).addDays(-1),
                        Fiscal_Year_Label__c = labelFor(fy),
                        Board_Commitment__c = commitment));
                } else if (ags.Board_Commitment_Override__c != true
                        && ags.Board_Commitment__c != commitment) {
                    ags.Board_Commitment__c = commitment;
                    toUpdate.add(ags);
                }
            }
        }
        // Trusted backend DML (mirrors JSI-90 crediting): sharing respected, FLS not blocking automation.
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /** MAX(highest non-Past-President board base, $10k if elevated). $0 when all memberships are Past President. */
    private static Decimal deriveCommitment(List<Board_Membership_Year__c> memberships, Boolean isElevated) {
        Decimal base = null;
        for (Board_Membership_Year__c b : memberships) {
            if (b.Role__c == 'Past President') {
                continue; // honorary — no financial commitment
            }
            Decimal d = (b.Board_Term__r != null && b.Board_Term__r.Member_Type__r != null)
                ? b.Board_Term__r.Member_Type__r.Default_Annual_Commitment__c : null;
            if (d != null && (base == null || d > base)) {
                base = d;
            }
        }
        if (base == null) {
            return 0; // honorary / all Past President
        }
        Decimal elev = isElevated ? ELEVATED_COMMITMENT : 0;
        return (elev > base) ? elev : base;
    }

    private static String key(Id contactId, Date fyStart) {
        return String.valueOf(contactId) + '|' + String.valueOf(fyStart);
    }
}
