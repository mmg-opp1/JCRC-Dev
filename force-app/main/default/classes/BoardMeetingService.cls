/**
 * @description Board Meeting automation (JSI-123). Stamps the dedupe key that stops the same meeting
 *              being created twice — a board meeting is identified by its date and its name, so two
 *              records sharing both are one meeting entered twice, not two meetings.
 * @author Jason Ott
 * @created 2026-09-01
 *
 * Change Log:
 * -----------
 * 2026-09-01 - Jason Ott - Initial version, after a double-click on the console's New Board Member
 *                          button created duplicate records and the same gap was found on New Meeting.
 */
public with sharing class BoardMeetingService {

    /**
     * BEFORE insert/update — stamp Meeting_Key__c from the date and the name.
     *
     * The name is lower-cased and trimmed so "Board Meeting" and "board meeting " collide as they
     * should; the field is also marked case-insensitive, which makes this belt and braces. Left null
     * when either part is missing, because nulls do not collide and a half-filled meeting being saved
     * as a draft should not be blocked.
     */
    public static void setMeetingKeys(List<Board_Meeting__c> meetings) {
        for (Board_Meeting__c m : meetings) {
            if (m.Meeting_Date__c == null || String.isBlank(m.Name)) {
                m.Meeting_Key__c = null;
                continue;
            }
            m.Meeting_Key__c = String.valueOf(m.Meeting_Date__c) + '|' + m.Name.trim().toLowerCase();
        }
    }
}
