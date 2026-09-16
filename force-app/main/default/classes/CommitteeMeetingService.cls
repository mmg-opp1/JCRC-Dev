/**
 * @description Committee Meeting automation (JSI-123). Derives the fiscal year a meeting falls in and
 *              stamps the dedupe key that stops the same meeting being entered twice.
 * @author Jason Ott
 * @created 2026-09-02
 *
 * Change Log:
 * -----------
 * 2026-09-02 - Jason Ott - Initial version, alongside committee meeting attendance.
 */
public with sharing class CommitteeMeetingService {

    /**
     * BEFORE insert/update — derive the fiscal year, then stamp the dedupe key.
     *
     * The fiscal year is what decides who was on the committee when the meeting happened, so it is
     * derived here rather than asked for: the console only collects a name and a date.
     *
     * A committee cannot hold two meetings with the same name on the same day, so Committee + date +
     * name identifies a meeting. The key is left null when either part is missing, because nulls do
     * not collide in a unique field and a half-entered meeting should not be blocked.
     */
    public static void stampMeetings(List<Committee_Meeting__c> meetings) {
        for (Committee_Meeting__c m : meetings) {
            if (m.Meeting_Date__c != null) {
                Date fyStart = fyStartFor(m.Meeting_Date__c);
                m.FY_Start__c = fyStart;
                m.Fiscal_Year_Label__c = 'FY' + String.valueOf(fyStart.year() + 1);
            } else {
                m.FY_Start__c = null;
                m.Fiscal_Year_Label__c = null;
            }

            if (m.Committee__c == null || m.Meeting_Date__c == null || String.isBlank(m.Name)) {
                m.Meeting_Key__c = null;
                continue;
            }
            m.Meeting_Key__c = String.valueOf(m.Committee__c) + '|' + String.valueOf(m.Meeting_Date__c)
                + '|' + m.Name.trim().toLowerCase();
        }
    }

    /** The July-1 fiscal-year start on or before the given date. */
    public static Date fyStartFor(Date d) {
        Integer y = d.year();
        return (d.month() >= 7) ? Date.newInstance(y, 7, 1) : Date.newInstance(y - 1, 7, 1);
    }
}