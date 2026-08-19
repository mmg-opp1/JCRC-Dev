/**
 * @description Board Term automation (JSI-123). On save of a Board Term:
 *   1. BEFORE — auto-fill the End Date = Start Date + the member type's term length (when not set manually).
 *   2. AFTER  — ensure one Board Membership Year exists for every fiscal year (Jul 1-Jun 30) of the term,
 *      so each year of service has its own record to fill in (role, meeting attendance, giving). Idempotent
 *      (keyed on Board Term + fiscal-year label, so re-saving never duplicates).
 * @author Jason Ott
 * @created 2026-07-28
 *
 * Change Log:
 * -----------
 * 2026-07-28 - Jason Ott - Initial version (JSI-123 correction: member types + auto-generated term schedule).
 * 2026-08-19 - Jason Ott - Added Contact.Current_Board_Member__c maintenance (JSI-87 board letter routing).
 */
public with sharing class BoardTermService {

    /** BEFORE insert/update — default the End Date from the member type's term length. */
    public static void setEndDates(List<Board_Term__c> terms) {
        Set<Id> typeIds = new Set<Id>();
        for (Board_Term__c t : terms) {
            if (t.Member_Type__c != null) {
                typeIds.add(t.Member_Type__c);
            }
        }
        if (typeIds.isEmpty()) {
            return;
        }
        Map<Id, Board_Member_Type__c> types = new Map<Id, Board_Member_Type__c>([
            SELECT Default_Term_Length_Years__c FROM Board_Member_Type__c WHERE Id IN :typeIds]);
        for (Board_Term__c t : terms) {
            if (t.Start_Date__c == null || t.Member_Type__c == null || t.End_Date__c != null) {
                continue; // respect a manually set End Date
            }
            Board_Member_Type__c mt = types.get(t.Member_Type__c);
            if (mt != null && mt.Default_Term_Length_Years__c != null) {
                t.End_Date__c = t.Start_Date__c.addYears((Integer) mt.Default_Term_Length_Years__c).addDays(-1);
            }
        }
    }

    /** AFTER insert/update — create the per-fiscal-year Board Membership Year records (idempotent). */
    public static void generateMembershipYears(List<Board_Term__c> terms) {
        Set<Id> termIds = new Set<Id>();
        for (Board_Term__c t : terms) {
            termIds.add(t.Id);
        }
        Map<Id, Board_Term__c> full = new Map<Id, Board_Term__c>([
            SELECT Id, Contact__c, Start_Date__c, End_Date__c, Member_Type__r.Default_Term_Length_Years__c
            FROM Board_Term__c WHERE Id IN :termIds]);

        Set<String> existing = new Set<String>();
        for (Board_Membership_Year__c y : [
                SELECT Year_Key__c FROM Board_Membership_Year__c WHERE Board_Term__c IN :termIds]) {
            if (y.Year_Key__c != null) {
                existing.add(y.Year_Key__c);
            }
        }

        List<Board_Membership_Year__c> toInsert = new List<Board_Membership_Year__c>();
        Set<Id> contactIds = new Set<Id>();
        Set<Date> fyStarts = new Set<Date>();
        for (Board_Term__c t : full.values()) {
            if (t.Start_Date__c == null || t.Member_Type__r == null
                    || t.Member_Type__r.Default_Term_Length_Years__c == null) {
                continue;
            }
            Integer len = (Integer) t.Member_Type__r.Default_Term_Length_Years__c;
            Date fyStart = fyStartFor(t.Start_Date__c);
            for (Integer i = 0; i < len; i++) {
                Date ys = fyStart.addYears(i);
                // stop at the term End Date (so a shortened/ended term doesn't regenerate future years)
                if (t.End_Date__c != null && ys > t.End_Date__c) {
                    break;
                }
                contactIds.add(t.Contact__c);
                fyStarts.add(ys);
                String label = 'FY' + String.valueOf(ys.year() + 1);
                String yearKey = String.valueOf(t.Id) + '|' + label;
                if (existing.contains(yearKey)) {
                    continue;
                }
                toInsert.add(new Board_Membership_Year__c(
                    Board_Term__c = t.Id, Contact__c = t.Contact__c, Role__c = 'Member',
                    FY_Start__c = ys, FY_End__c = ys.addYears(1).addDays(-1),
                    Fiscal_Year_Label__c = label, Year_Key__c = yearKey));
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        // link these board years to any matching Annual Giving Summary that already exists
        linkSummaries(contactIds, fyStarts);
    }

    /**
     * Two-way link between Board Membership Year and the Annual Giving Summary for the same contact +
     * fiscal year. Board-member-scoped: it only ever updates Board Membership Years (which only board
     * members have), so it does no work for ordinary donors. Called after board years are generated and
     * from the Annual Giving Summary trigger when a new summary is created.
     */
    public static void linkSummaries(Set<Id> contactIds, Set<Date> fyStarts) {
        if (contactIds == null || contactIds.isEmpty() || fyStarts == null || fyStarts.isEmpty()) {
            return;
        }
        Map<String, Id> agsByKey = new Map<String, Id>();
        for (Annual_Giving_Summary__c a : [
                SELECT Id, Contact__c, FY_Start__c FROM Annual_Giving_Summary__c
                WHERE Contact__c IN :contactIds AND FY_Start__c IN :fyStarts]) {
            agsByKey.put(a.Contact__c + '|' + String.valueOf(a.FY_Start__c), a.Id);
        }
        if (agsByKey.isEmpty()) {
            return;
        }
        List<Board_Membership_Year__c> toUpdate = new List<Board_Membership_Year__c>();
        for (Board_Membership_Year__c y : [
                SELECT Id, Contact__c, FY_Start__c, Annual_Giving_Summary__c
                FROM Board_Membership_Year__c
                WHERE Contact__c IN :contactIds AND FY_Start__c IN :fyStarts]) {
            Id agsId = agsByKey.get(y.Contact__c + '|' + String.valueOf(y.FY_Start__c));
            if (agsId != null && y.Annual_Giving_Summary__c != agsId) {
                y.Annual_Giving_Summary__c = agsId;
                toUpdate.add(y);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /** The July-1 fiscal-year start on or before the given date. */

    /**
     * Recomputes Contact.Current_Board_Member__c for the given contacts.
     *
     * Board Term relates to Contact by LOOKUP, so this cannot be a roll-up summary - it has to
     * be maintained. Two triggers of maintenance, because Is_Current__c is a formula over dates:
     *   - this method, called whenever a Board Term is inserted, updated, deleted or undeleted;
     *   - BoardMemberFlagRefresh, nightly, because a term can stop being current purely through
     *     the passage of time, with no DML on the record to react to.
     *
     * System-mode DML on purpose: this is a trusted backend stamp of a field users hold
     * read-only, and a USER_MODE write would throw FLS on exactly the profiles that need it
     * (the JSI-123 lesson).
     */
    public static void refreshBoardFlags(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }
        // Single source of truth: reuse the Is_Current__c formula rather than re-implementing
        // its date logic here, so the two can never drift apart. Filtering on it was verified
        // to agree with reading it, including for a term whose End Date had just moved into the
        // past, despite the formula containing TODAY().
        Set<Id> current = new Set<Id>();
        for (Board_Term__c t : [
                SELECT Contact__c FROM Board_Term__c
                WHERE Contact__c IN :contactIds AND Is_Current__c = true]) {
            current.add(t.Contact__c);
        }
        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : [SELECT Id, Current_Board_Member__c FROM Contact WHERE Id IN :contactIds]) {
            Boolean shouldBe = current.contains(c.Id);
            if (c.Current_Board_Member__c != shouldBe) {
                toUpdate.add(new Contact(Id = c.Id, Current_Board_Member__c = shouldBe));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /** Every contact who has ever held a board term, plus anyone still flagged - used nightly. */
    public static void refreshAllBoardFlags() {
        Set<Id> ids = new Set<Id>();
        for (Board_Term__c t : [SELECT Contact__c FROM Board_Term__c WHERE Contact__c != null]) {
            ids.add(t.Contact__c);
        }
        for (Contact c : [SELECT Id FROM Contact WHERE Current_Board_Member__c = true]) {
            ids.add(c.Id);      // catches anyone whose last term was deleted outright
        }
        refreshBoardFlags(ids);
    }

    public static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }
}
