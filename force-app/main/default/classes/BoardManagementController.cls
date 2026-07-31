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
    @AuraEnabled(cacheable=true)
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
        Database.insert(m, AccessLevel.USER_MODE);
        return m.Id;
    }

    /** The board members eligible for a meeting (those with a membership year in the meeting's FY) + attended flag. */
    @AuraEnabled(cacheable=true)
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
    public static void saveAttendance(Id meetingId, List<AttendeeRow> rows) {
        Map<Id, Boolean> desired = new Map<Id, Boolean>();
        if (rows != null) {
            for (AttendeeRow r : rows) {
                if (r.membershipYearId != null) {
                    desired.put(r.membershipYearId, r.attended == true);
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

    @AuraEnabled(cacheable=true)
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

    @AuraEnabled(cacheable=true)
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
        Database.insert(a, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static void removeAssignment(Id assignmentId) {
        Database.delete(new Committee_Assignment__c(Id = assignmentId), AccessLevel.USER_MODE);
    }

    private static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }
}
