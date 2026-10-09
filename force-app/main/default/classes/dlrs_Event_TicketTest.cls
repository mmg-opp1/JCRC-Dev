/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Event_TicketTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_Event_TicketTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Event_Ticket__c());
    }
}