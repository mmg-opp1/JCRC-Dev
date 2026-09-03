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
 * 2026-09-01 - Jason Ott - createBoardTerm now refuses a duplicate term and says so in plain
 *                          words (UAT: a double-click on Add Member added the person twice).
 * 2026-09-01 - Jason Ott - Added getDeleteImpact / deleteBoardMember: remove a board member added
 *                          by mistake, terms and all, without touching the Contact.
 * 2026-09-01 - Jason Ott - getCurrentBoardMembers is no longer cacheable (UAT: a Board Term edited
 *                          from the Contact page still showed its old values on the roster).
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
    /**
     * Deliberately NOT cacheable, and therefore not wired - the console loads it on mount instead.
     *
     * A cacheable method is served from the Lightning client cache, which nothing outside this
     * component invalidates. Edit a Board Term from the related list on a Contact, walk into Board
     * Management, and the screen showed the pre-edit data until the browser was refreshed - the
     * refresh being what cleared the cache. refreshApex only helps when this component made the
     * change itself; it cannot know about an edit made on another page.
     */
    @AuraEnabled
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

    /** Message shown for either kind of duplicate rejection, so both routes read the same to the user. */
    private static final String DUPLICATE_MSG =
        'That person already has a board term of this type starting on this date. '
        + 'They are on the roster already - no need to add them again.';

    /**
     * Create a board term — the trigger auto-fills the End Date and generates the per-year records.
     *
     * Guarded twice, on purpose. The query below catches the ordinary re-submit and answers with a
     * sentence a fundraiser can act on. The unique Term_Key__c field catches what a query cannot: two
     * requests that both read before either writes, which is exactly what a double-click produces.
     * Its native error names a field and a record id, so it is translated to the same message here.
     */
    @AuraEnabled
    public static Id createBoardTerm(Id contactId, Id memberTypeId, Date startDate) {
        List<Board_Term__c> existing = [
            SELECT Id FROM Board_Term__c
            WHERE Contact__c = :contactId
              AND Member_Type__c = :memberTypeId
              AND Start_Date__c = :startDate
            WITH USER_MODE
            LIMIT 1];
        if (!existing.isEmpty()) {
            throw new AuraHandledException(DUPLICATE_MSG);
        }

        Board_Term__c bt = new Board_Term__c(
            Contact__c = contactId, Member_Type__c = memberTypeId,
            Status__c = 'Active', Start_Date__c = startDate);
        try {
            Database.insert(bt, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            // Only the unique-key collision is ours to reword; anything else is a real error and is
            // rethrown untouched so it is not disguised as a duplicate.
            if (e.getNumDml() > 0 && e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new AuraHandledException(DUPLICATE_MSG);
            }
            throw e;
        }
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

    // ------------------------------------------------------------------------------------------
    // Deleting a board member added by mistake
    //
    // This is for genuine accidents - the wrong person picked, or the same person added twice -
    // not for someone leaving the board, which is what End Term is for. It removes every Board Term
    // the contact holds. Board Membership Year hangs off Board Term as master-detail, and Board
    // Meeting Attendance hangs off Board Membership Year the same way, so the whole board record
    // goes in one delete. The Contact is never touched, and neither is their giving: Annual Giving
    // Summary is referenced by a lookup with a SetNull delete constraint, so summaries survive with
    // the link cleared. The after-delete trigger clears Contact.Current_Board_Member__c, which is
    // what the JSI-87 acknowledgment router reads to pick the board letter.
    // ------------------------------------------------------------------------------------------

    /** What a delete would remove, and whether attendance stands in the way. */
    public class DeleteImpact {
        @AuraEnabled public String contactName;
        @AuraEnabled public Integer termCount;
        @AuraEnabled public Integer yearCount;
        @AuraEnabled public Integer attendanceCount;
        @AuraEnabled public Integer meetingCount;
        @AuraEnabled public Boolean blocked;
    }

    /**
     * Read-only look at what deleting this member would take with it, so the console can either
     * explain why it cannot proceed or say exactly what is about to go before asking to confirm.
     */
    @AuraEnabled
    public static DeleteImpact getDeleteImpact(Id contactId) {
        DeleteImpact impact = new DeleteImpact();
        impact.termCount = 0;
        impact.yearCount = 0;
        impact.attendanceCount = 0;
        impact.meetingCount = 0;
        impact.blocked = false;

        List<Contact> contacts = [SELECT Name FROM Contact WHERE Id = :contactId WITH USER_MODE LIMIT 1];
        impact.contactName = contacts.isEmpty() ? 'This person' : contacts[0].Name;

        Set<Id> termIds = termIdsFor(contactId);
        impact.termCount = termIds.size();
        if (termIds.isEmpty()) {
            return impact;
        }

        impact.yearCount = [
            SELECT COUNT() FROM Board_Membership_Year__c
            WHERE Board_Term__c IN :termIds WITH USER_MODE];

        // Count the distinct meetings as well as the rows: "2 meetings" means more to a fundraiser
        // than "2 attendance records", and one meeting can only ever produce one row per member.
        Set<Id> meetings = new Set<Id>();
        for (Board_Meeting_Attendance__c a : [
                SELECT Board_Meeting__c FROM Board_Meeting_Attendance__c
                WHERE Board_Membership_Year__r.Board_Term__c IN :termIds WITH USER_MODE]) {
            impact.attendanceCount++;
            if (a.Board_Meeting__c != null) {
                meetings.add(a.Board_Meeting__c);
            }
        }
        impact.meetingCount = meetings.size();
        impact.blocked = impact.attendanceCount > 0;
        return impact;
    }

    /**
     * Delete every board term this contact holds. The Contact record itself is deliberately left
     * in place - this removes someone's board membership, not the person.
     *
     * The attendance check is repeated here rather than trusted from the screen. The console may
     * have been sitting open while somebody else saved a meeting's attendance, and because the
     * children cascade, a stale "safe to delete" would take that attendance with it silently.
     */
    @AuraEnabled
    public static void deleteBoardMember(Id contactId) {
        Set<Id> termIds = termIdsFor(contactId);
        if (termIds.isEmpty()) {
            throw new AuraHandledException('That person has no board record to delete.');
        }

        Integer attendance = [
            SELECT COUNT() FROM Board_Meeting_Attendance__c
            WHERE Board_Membership_Year__r.Board_Term__c IN :termIds WITH USER_MODE];
        if (attendance > 0) {
            throw new AuraHandledException(
                'This board member has meeting attendance recorded, so their board record cannot '
                + 'be deleted. Deleting it would remove that attendance as well. To take them off '
                + 'the board, use End Term instead.');
        }

        Database.delete([SELECT Id FROM Board_Term__c WHERE Id IN :termIds WITH USER_MODE],
            AccessLevel.USER_MODE);
    }

    /** Every board term held by one contact - past, current and future, since all of them go. */
    private static Set<Id> termIdsFor(Id contactId) {
        Set<Id> ids = new Set<Id>();
        for (Board_Term__c t : [
                SELECT Id FROM Board_Term__c WHERE Contact__c = :contactId WITH USER_MODE]) {
            ids.add(t.Id);
        }
        return ids;
    }
}
