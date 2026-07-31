/**
 * @description Gala automation on the purchase Opportunity: stamp the non-deductible (FMV) split from the
 *              chosen Gala Level (before), and auto-create the level's tables (after). Acts only on
 *              opportunities that have a Gala Level. JSI Gala Event Gifts. Author: Jason Ott.
 */
trigger OpportunityGalaTrigger on Opportunity (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        GalaAutomationService.stampDeductibleFromLevel(Trigger.new, Trigger.oldMap);
    } else {
        GalaAutomationService.createTablesForOpps(Trigger.new);
    }
}
