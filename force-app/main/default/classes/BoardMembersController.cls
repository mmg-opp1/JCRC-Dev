/**
 * @description Supplies the current board roster (with per-member annual commitment progress) to the
 *              boardMembers LWC. Read-only, FLS-safe (USER_MODE). "Current board" = Board Terms with
 *              Is_Current__c = true. Commitment progress is read from each member's current board-year
 *              (July 1-June 30) Annual Giving Summary. JSI-123 Board Tracking.
 * @author Jason Ott
 * @created 2026-07-27
 *
 * Change Log:
 * -----------
 * 2026-07-27 - Jason Ott - Initial version (JSI-123 Phase 1 UI).
 */
public with sharing class BoardMembersController {

    /** One row of the board roster returned to the LWC. */
    public class BoardMemberRow {
        @AuraEnabled public Id termId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String termYears;
        @AuraEnabled public Boolean expiringSoon;
        @AuraEnabled public String memberType;
        @AuraEnabled public Boolean mustRollOff;
        @AuraEnabled public Decimal commitment;   // this board year's Board_Commitment__c
        @AuraEnabled public Decimal pctMet;        // percent value, e.g. 70 = 70%
        @AuraEnabled public Boolean met;
    }

    /**
     * Returns every current board member, ordered by name, each with their current board-year
     * commitment progress (null when the member has no summary for this year yet).
     */
    @AuraEnabled(cacheable=true)
    public static List<BoardMemberRow> getCurrentBoardMembers() {
        // 1) current board = Active terms whose date window includes today
        List<Board_Term__c> terms = [
            SELECT Id, Contact__c, Contact__r.Name, Board_Role__c, Start_Date__c, End_Date__c,
                   Term_Year_Label__c, Expiring_Soon__c, Must_Roll_Off__c, Member_Type__r.Name
            FROM Board_Term__c
            WHERE Is_Current__c = true
            WITH USER_MODE
            ORDER BY Contact__r.Name
        ];

        Set<Id> contactIds = new Set<Id>();
        for (Board_Term__c t : terms) {
            contactIds.add(t.Contact__c);
        }

        // 2) resolve the current July-June board year and pull each member's summary for it
        Date today = Date.today();
        Integer y = today.year();
        Date fyStart = (today.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);

        Map<Id, Annual_Giving_Summary__c> byContact = new Map<Id, Annual_Giving_Summary__c>();
        if (!contactIds.isEmpty()) {
            for (Annual_Giving_Summary__c ags : [
                SELECT Contact__c, Board_Commitment__c, Board_Commitment_Pct__c, Board_Commitment_Met__c
                FROM Annual_Giving_Summary__c
                WHERE Contact__c IN :contactIds AND FY_Start__c = :fyStart
                WITH USER_MODE
            ]) {
                byContact.put(ags.Contact__c, ags);
            }
        }

        // 3) assemble rows
        List<BoardMemberRow> rows = new List<BoardMemberRow>();
        for (Board_Term__c t : terms) {
            BoardMemberRow r = new BoardMemberRow();
            r.termId = t.Id;
            r.contactId = t.Contact__c;
            r.name = t.Contact__r.Name;
            r.role = t.Board_Role__c;
            r.startDate = t.Start_Date__c;
            r.endDate = t.End_Date__c;
            r.termYears = t.Term_Year_Label__c;
            r.expiringSoon = t.Expiring_Soon__c;
            r.mustRollOff = t.Must_Roll_Off__c;
            r.memberType = (t.Member_Type__r != null) ? t.Member_Type__r.Name : null;
            Annual_Giving_Summary__c ags = byContact.get(t.Contact__c);
            if (ags != null) {
                r.commitment = ags.Board_Commitment__c;
                r.pctMet = ags.Board_Commitment_Pct__c;
                r.met = ags.Board_Commitment_Met__c;
            }
            rows.add(r);
        }
        return rows;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /** Active board member types for the "New Board Member" dropdown. */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getMemberTypes() {
        List<PicklistOption> out = new List<PicklistOption>();
        for (Board_Member_Type__c t : [
                SELECT Id, Name FROM Board_Member_Type__c WHERE Active__c = true
                WITH USER_MODE ORDER BY Sort_Order__c NULLS LAST, Name]) {
            PicklistOption o = new PicklistOption();
            o.label = t.Name;
            o.value = t.Id;
            out.add(o);
        }
        return out;
    }

    /** Create a board term — the trigger auto-fills the End Date and generates the per-year records. */
    @AuraEnabled
    public static Id createBoardTerm(Id contactId, Id memberTypeId, Date startDate) {
        Board_Term__c bt = new Board_Term__c(
            Contact__c = contactId, Member_Type__c = memberTypeId,
            Status__c = 'Active', Start_Date__c = startDate);
        Database.insert(bt, AccessLevel.USER_MODE);
        return bt.Id;
    }

    /** End a board term on a given date and remove any board years that fall entirely after it. */
    @AuraEnabled
    public static void endBoardTerm(Id boardTermId, Date endDate) {
        Database.update(new Board_Term__c(Id = boardTermId, End_Date__c = endDate), AccessLevel.USER_MODE);
        List<Board_Membership_Year__c> future = [
            SELECT Id FROM Board_Membership_Year__c
            WHERE Board_Term__c = :boardTermId AND FY_Start__c > :endDate
            WITH USER_MODE];
        if (!future.isEmpty()) {
            Database.delete(future, AccessLevel.USER_MODE);
        }
    }
}
