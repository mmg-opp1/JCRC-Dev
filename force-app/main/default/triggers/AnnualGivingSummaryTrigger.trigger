/**
 * @description When an Annual Giving Summary is created (by board automation, gift crediting, or the
 *              July-1 rollover), link it to the matching Board Membership Year (same contact + fiscal year)
 *              if one exists. Board-member-scoped: linkSummaries only updates Board Membership Years, so
 *              ordinary donors' summaries pass through with no extra work. JSI-123. Author: Jason Ott.
 */
trigger AnnualGivingSummaryTrigger on Annual_Giving_Summary__c (after insert) {
    Set<Id> contactIds = new Set<Id>();
    Set<Date> fyStarts = new Set<Date>();
    for (Annual_Giving_Summary__c a : Trigger.new) {
        if (a.Contact__c != null && a.FY_Start__c != null) {
            contactIds.add(a.Contact__c);
            fyStarts.add(a.FY_Start__c);
        }
    }
    BoardTermService.linkSummaries(contactIds, fyStarts);
}
