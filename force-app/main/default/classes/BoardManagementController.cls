/**
 * @description Server side for the Board Management console (JSI-123). Increment 1: Meetings & Attendance —
 *              list/create board meetings and record which board members attended (feeding the 3-of-4
 *              requirement roll-up on Board Membership Year). FLS-safe (USER_MODE reads + `as user` DML).
 * @author Jason Ott
 * @created 2026-07-29
 *
 * Change Log:
 * -----------
 * 2026-07-29 - Jason Ott - Initial version (Meetings & Attendance).
 * 2026-09-01 - Jason Ott - createMeeting and saveAssignment now answer a duplicate with a
 *                          readable sentence instead of the platform's field-and-id error
 *                          (UAT: double-clicking a save button created duplicate records).
 * 2026-09-01 - Jason Ott - getAssignments is no longer cacheable (UAT: a newly added committee
 *                          member only appeared after a browser refresh - the repeat call was
 *                          being served from the Lightning client cache).
 * 2026-09-01 - Jason Ott - Same for getMeetings and getCommittees, which had the same exposure to
 *                          a record edited from anywhere other than this console.
 * 2026-09-02 - Jason Ott - Committee meetings and their attendance, mirroring the board meeting
 *                          flow but scoped to one committee's members.
 */
public with sharing class BoardManagementController {

    public class MeetingInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date meetingDate;
        @AuraEnabled public String fiscalYearLabel;
        @AuraEnabled public Integer attendedCount;
    }

    public class AttendeeRow {
        @AuraEnabled public Id membershipYearId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean attended;
    }

    /** Recent board meetings (with attended counts) for the console list. */
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
    public static List<MeetingInfo> getMeetings() {
        List<MeetingInfo> out = new List<MeetingInfo>();
        for (Board_Meeting__c m : [
                SELECT Id, Name, Meeting_Date__c, Fiscal_Year_Label__c,
                       (SELECT Id FROM Attendance__r WHERE Attended__c = true)
                FROM Board_Meeting__c
                WITH USER_MODE
                ORDER BY Meeting_Date__c DESC NULLS LAST
                LIMIT 200]) {
            MeetingInfo mi = new MeetingInfo();
            mi.id = m.Id;
            mi.name = m.Name;
            mi.meetingDate = m.Meeting_Date__c;
            mi.fiscalYearLabel = m.Fiscal_Year_Label__c;
            mi.attendedCount = m.Attendance__r.size();
            out.add(mi);
        }
        return out;
    }

    /** Create a board meeting; its fiscal year is derived from the meeting date (Jul 1-Jun 30). */
    @AuraEnabled
    public static Id createMeeting(String name, Date meetingDate) {
        Date basis = (meetingDate != null) ? meetingDate : Date.today();
        Date fyStart = fyStartFor(basis);
        Board_Meeting__c m = new Board_Meeting__c(
            Name = String.isBlank(name) ? 'Board Meeting' : name,
            Meeting_Date__c = meetingDate,
            FY_Start__c = fyStart,
            Fiscal_Year_Label__c = 'FY' + String.valueOf(fyStart.year() + 1));
        try {
            Database.insert(m, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            // The unique Meeting_Key__c has rejected a meeting that already exists. Its native error
            // names a field and a record id, which means nothing to the person who just clicked twice.
            if (e.getNumDml() > 0 && e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new AuraHandledException(
                    'A board meeting with this name already exists on this date. '
                    + 'It is in the list above - no need to create it again.');
            }
            throw e;
        }
        return m.Id;
    }

    /** The board members eligible for a meeting (those with a membership year in the meeting's FY) + attended flag. */
    @AuraEnabled
    public static List<AttendeeRow> getAttendance(Id meetingId) {
        Board_Meeting__c m = [SELECT Id, FY_Start__c FROM Board_Meeting__c WHERE Id = :meetingId WITH USER_MODE];
        Map<Id, AttendeeRow> byYear = new Map<Id, AttendeeRow>();
        for (Board_Membership_Year__c y : [
                SELECT Id, Contact__c, Contact__r.Name
                FROM Board_Membership_Year__c
                WHERE FY_Start__c = :m.FY_Start__c AND Contact__c != null
                WITH USER_MODE
                ORDER BY Contact__r.Name]) {
            AttendeeRow r = new AttendeeRow();
            r.membershipYearId = y.Id;
            r.contactId = y.Contact__c;
            r.name = y.Contact__r.Name;
            r.attended = false;
            byYear.put(y.Id, r);
        }
        for (Board_Meeting_Attendance__c a : [
                SELECT Board_Membership_Year__c, Attended__c
                FROM Board_Meeting_Attendance__c
                WHERE Board_Meeting__c = :meetingId
                WITH USER_MODE]) {
            AttendeeRow r = byYear.get(a.Board_Membership_Year__c);
            if (r != null) {
                r.attended = a.Attended__c;
            }
        }
        return byYear.values();
    }

    /**
     * Save the attendance check-offs for a meeting. The client sends membership-year ids + their attended
     * flag; the dedupe key and contact are re-derived SERVER-SIDE from the year record (so they can never be
     * null) and we upsert on record Id — robust against any client-side data loss. System-mode DML: the read
     * in getAttendance already enforced access, and the dedupe key is a read-only field.
     */
    @AuraEnabled
    public static void saveAttendance(Id meetingId, String rowsJson) {
        // Parse the payload untyped (robust — avoids typed inner-class param deserialization dropping fields).
        Map<Id, Boolean> desired = new Map<Id, Boolean>();
        if (String.isNotBlank(rowsJson)) {
            for (Object o : (List<Object>) JSON.deserializeUntyped(rowsJson)) {
                Map<String, Object> m = (Map<String, Object>) o;
                Object idVal = m.get('membershipYearId');
                if (idVal != null && String.isNotBlank(String.valueOf(idVal))) {
                    desired.put(Id.valueOf(String.valueOf(idVal)), m.get('attended') == true);
                }
            }
        }
        if (desired.isEmpty()) {
            return;
        }
        try {
            // contacts for these years, derived server-side (never null)
            Map<Id, Id> yearToContact = new Map<Id, Id>();
            for (Board_Membership_Year__c y : [
                    SELECT Id, Contact__c FROM Board_Membership_Year__c WHERE Id IN :desired.keySet()]) {
                yearToContact.put(y.Id, y.Contact__c);
            }
            // existing attendance for this meeting + these years (update in place, don't duplicate)
            Map<Id, Board_Meeting_Attendance__c> existing = new Map<Id, Board_Meeting_Attendance__c>();
            for (Board_Meeting_Attendance__c a : [
                    SELECT Id, Board_Membership_Year__c FROM Board_Meeting_Attendance__c
                    WHERE Board_Meeting__c = :meetingId AND Board_Membership_Year__c IN :desired.keySet()]) {
                existing.put(a.Board_Membership_Year__c, a);
            }
            List<Board_Meeting_Attendance__c> ups = new List<Board_Meeting_Attendance__c>();
            for (Id yearId : desired.keySet()) {
                Board_Meeting_Attendance__c a = existing.containsKey(yearId)
                    ? existing.get(yearId)
                    : new Board_Meeting_Attendance__c(
                        Board_Meeting__c = meetingId, Board_Membership_Year__c = yearId,
                        Contact__c = yearToContact.get(yearId),
                        Attendance_Key__c = String.valueOf(meetingId) + '|' + String.valueOf(yearId));
                a.Attended__c = desired.get(yearId);
                ups.add(a);
            }
            upsert ups;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ------------------------------------------------------------------ Committees

    public class CommitteeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean isExecutive;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String parentName;
    }

    public class AssignmentInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String role;
        @AuraEnabled public String fiscalYearLabel;
        @AuraEnabled public Boolean active;
    }

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
    public static List<CommitteeInfo> getCommittees() {
        List<CommitteeInfo> out = new List<CommitteeInfo>();
        for (Committee__c c : [
                SELECT Id, Name, Category__c, Is_Executive_Committee__c, Active__c,
                       Parent_Committee__c, Parent_Committee__r.Name
                FROM Committee__c WITH USER_MODE ORDER BY Name LIMIT 500]) {
            CommitteeInfo ci = new CommitteeInfo();
            ci.id = c.Id;
            ci.name = c.Name;
            ci.category = c.Category__c;
            ci.isExecutive = c.Is_Executive_Committee__c;
            ci.active = c.Active__c;
            ci.parentId = c.Parent_Committee__c;
            ci.parentName = (c.Parent_Committee__r != null) ? c.Parent_Committee__r.Name : null;
            out.add(ci);
        }
        return out;
    }

    /** Create or update a committee. */
    @AuraEnabled
    public static Id saveCommittee(Id committeeId, String name, String category,
            Boolean isExecutive, Id parentId, Boolean active) {
        Committee__c c = new Committee__c(
            Id = committeeId, Name = name, Category__c = category,
            Is_Executive_Committee__c = isExecutive == true,
            Parent_Committee__c = parentId, Active__c = active == true);
        Database.upsert(c, AccessLevel.USER_MODE);
        return c.Id;
    }

    /**
     * Deliberately NOT cacheable. This is called imperatively, never wired, and always right after a
     * write - adding or removing a committee member. A cacheable method serves the Lightning client
     * cache on the repeat call, so the freshly added member did not appear until the browser was
     * refreshed, which cleared the cache. refreshApex cannot fix that; it only invalidates a wire.
     */
    @AuraEnabled
    public static List<AssignmentInfo> getAssignments(Id committeeId) {
        List<AssignmentInfo> out = new List<AssignmentInfo>();
        for (Committee_Assignment__c a : [
                SELECT Id, Contact__c, Contact__r.Name, Committee_Role__c, Fiscal_Year_Label__c, Active__c
                FROM Committee_Assignment__c WHERE Committee__c = :committeeId
                WITH USER_MODE ORDER BY Fiscal_Year_Label__c DESC NULLS LAST, Contact__r.Name]) {
            AssignmentInfo ai = new AssignmentInfo();
            ai.id = a.Id;
            ai.contactId = a.Contact__c;
            ai.contactName = (a.Contact__r != null) ? a.Contact__r.Name : null;
            ai.role = a.Committee_Role__c;
            ai.fiscalYearLabel = a.Fiscal_Year_Label__c;
            ai.active = a.Active__c;
            out.add(ai);
        }
        return out;
    }

    /** Add a committee assignment; the fiscal year is derived from the given date (Jul 1-Jun 30). */
    @AuraEnabled
    public static void saveAssignment(Id committeeId, Id contactId, String role, Date fyDate) {
        Date fyStart = fyStartFor(fyDate != null ? fyDate : Date.today());
        Committee_Assignment__c a = new Committee_Assignment__c(
            Committee__c = committeeId, Contact__c = contactId, Committee_Role__c = role,
            FY_Start__c = fyStart, Active__c = true);
        // CommitteeAssignmentTrigger stamps the key + label and recomputes the member's commitment.
        // Assignment_Key__c is unique, so a repeat of the same person on the same committee in the
        // same year is refused by the database; translate that into something a fundraiser can read.
        try {
            Database.insert(a, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            if (e.getNumDml() > 0 && e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new AuraHandledException(
                    'That person is already on this committee for this fiscal year.');
            }
            throw e;
        }
    }

    @AuraEnabled
    public static void removeAssignment(Id assignmentId) {
        Database.delete(new Committee_Assignment__c(Id = assignmentId), AccessLevel.USER_MODE);
    }

    // ------------------------------------------------------------------------------------------
    // Committee meetings and attendance
    //
    // Deliberately a separate object from Board Meeting rather than a flag on it. Several committee
    // members are not board members at all - one of them chairs a committee - and board attendance
    // hangs off Board Membership Year, which only board members have. Keeping them apart also means
    // a committee meeting can never be miscounted toward the board's attend-3-of-4 requirement.
    // ------------------------------------------------------------------------------------------

    /** One committee meeting, as the console lists it. */
    public class CommitteeMeetingInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date meetingDate;
        @AuraEnabled public String fiscalYearLabel;
        @AuraEnabled public Decimal attendedCount;
    }

    /** One row of a committee meeting's attendance sheet. */
    public class CommitteeAttendeeRow {
        @AuraEnabled public Id assignmentId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean attended;
    }

    /** Every meeting held by one committee, most recent first. Not cacheable - see getAssignments. */
    @AuraEnabled
    public static List<CommitteeMeetingInfo> getCommitteeMeetings(Id committeeId) {
        List<CommitteeMeetingInfo> out = new List<CommitteeMeetingInfo>();
        for (Committee_Meeting__c m : [
                SELECT Id, Name, Meeting_Date__c, Fiscal_Year_Label__c, Attended_Count__c
                FROM Committee_Meeting__c
                WHERE Committee__c = :committeeId
                WITH USER_MODE
                ORDER BY Meeting_Date__c DESC NULLS LAST, Name]) {
            CommitteeMeetingInfo i = new CommitteeMeetingInfo();
            i.id = m.Id;
            i.name = m.Name;
            i.meetingDate = m.Meeting_Date__c;
            i.fiscalYearLabel = m.Fiscal_Year_Label__c;
            i.attendedCount = m.Attended_Count__c;
            out.add(i);
        }
        return out;
    }

    /** Create a committee meeting. The trigger derives the fiscal year and stamps the dedupe key. */
    @AuraEnabled
    public static Id createCommitteeMeeting(Id committeeId, String name, Date meetingDate) {
        Committee_Meeting__c m = new Committee_Meeting__c(
            Committee__c = committeeId,
            Name = String.isBlank(name) ? 'Committee Meeting' : name,
            Meeting_Date__c = meetingDate);
        try {
            Database.insert(m, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            if (e.getNumDml() > 0 && e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                throw new AuraHandledException(
                    'This committee already has a meeting with this name on this date. '
                    + 'It is in the list above - no need to create it again.');
            }
            throw e;
        }
        return m.Id;
    }

    /**
     * Who to show on a committee meeting's attendance sheet, with what is already recorded.
     *
     * Eligibility is the committee's active members whose assignment is for the meeting's fiscal
     * year, PLUS any whose assignment has no fiscal year recorded. That last part is deliberate:
     * the fiscal year on an assignment is optional in the console, and a missing one would
     * otherwise drop somebody off the sheet silently, which is far worse than showing an extra name.
     */
    @AuraEnabled
    public static List<CommitteeAttendeeRow> getCommitteeAttendance(Id meetingId) {
        Committee_Meeting__c m = [
            SELECT Id, Committee__c, FY_Start__c FROM Committee_Meeting__c
            WHERE Id = :meetingId WITH USER_MODE];

        Map<Id, CommitteeAttendeeRow> byAssignment = new Map<Id, CommitteeAttendeeRow>();
        for (Committee_Assignment__c a : [
                SELECT Id, Contact__c, Contact__r.Name, Committee_Role__c, FY_Start__c
                FROM Committee_Assignment__c
                WHERE Committee__c = :m.Committee__c
                  AND Active__c = true
                  AND Contact__c != null
                  AND (FY_Start__c = :m.FY_Start__c OR FY_Start__c = null)
                WITH USER_MODE
                ORDER BY Contact__r.Name]) {
            CommitteeAttendeeRow r = new CommitteeAttendeeRow();
            r.assignmentId = a.Id;
            r.contactId = a.Contact__c;
            r.name = (a.Contact__r != null) ? a.Contact__r.Name : null;
            r.role = a.Committee_Role__c;
            r.attended = false;
            byAssignment.put(a.Id, r);
        }

        for (Committee_Meeting_Attendance__c att : [
                SELECT Committee_Assignment__c, Attended__c
                FROM Committee_Meeting_Attendance__c
                WHERE Committee_Meeting__c = :meetingId WITH USER_MODE]) {
            CommitteeAttendeeRow r = byAssignment.get(att.Committee_Assignment__c);
            if (r != null) {
                r.attended = att.Attended__c;
            }
        }
        return byAssignment.values();
    }

    /**
     * Record who attended a committee meeting.
     *
     * Upserts on Attendance_Key__c so re-saving a sheet updates the same rows instead of stacking up
     * duplicates - the same approach as saveAttendance, and the reason a repeat click here is
     * harmless. The payload is parsed untyped for the same reason as the board version: typed
     * inner-class deserialization has been seen to drop fields.
     */
    @AuraEnabled
    public static void saveCommitteeAttendance(Id meetingId, String rowsJson) {
        Map<Id, Boolean> desired = new Map<Id, Boolean>();
        if (String.isNotBlank(rowsJson)) {
            for (Object o : (List<Object>) JSON.deserializeUntyped(rowsJson)) {
                Map<String, Object> row = (Map<String, Object>) o;
                Object idVal = row.get('assignmentId');
                if (idVal != null && String.isNotBlank(String.valueOf(idVal))) {
                    desired.put(Id.valueOf(String.valueOf(idVal)), row.get('attended') == true);
                }
            }
        }
        if (desired.isEmpty()) {
            return;
        }

        // Contacts are derived server-side rather than taken from the payload, so the stored row
        // always agrees with the assignment it belongs to.
        Map<Id, Id> assignmentToContact = new Map<Id, Id>();
        for (Committee_Assignment__c a : [
                SELECT Id, Contact__c FROM Committee_Assignment__c
                WHERE Id IN :desired.keySet() WITH USER_MODE]) {
            assignmentToContact.put(a.Id, a.Contact__c);
        }

        List<Committee_Meeting_Attendance__c> ups = new List<Committee_Meeting_Attendance__c>();
        for (Id assignmentId : desired.keySet()) {
            if (!assignmentToContact.containsKey(assignmentId)) {
                continue;   // not a member of this committee; ignore rather than trust the payload
            }
            ups.add(new Committee_Meeting_Attendance__c(
                Committee_Meeting__c = meetingId,
                Committee_Assignment__c = assignmentId,
                Contact__c = assignmentToContact.get(assignmentId),
                Attended__c = desired.get(assignmentId),
                Attendance_Key__c = String.valueOf(meetingId) + '|' + String.valueOf(assignmentId)));
        }
        if (!ups.isEmpty()) {
            // System mode on the upsert itself: Attendance Key is a stamped key field that users hold
            // read-only, and a USER_MODE write of it throws FLS on exactly the profiles that need it
            // (the JSI-123 lesson). The reads above were USER_MODE, so access has been checked.
            upsert ups Attendance_Key__c;
        }
    }

    /** Delete a committee meeting and, with it, the attendance recorded at it. */
    @AuraEnabled
    public static void deleteCommitteeMeeting(Id meetingId) {
        Database.delete(new Committee_Meeting__c(Id = meetingId), AccessLevel.USER_MODE);
    }

    private static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }
}
