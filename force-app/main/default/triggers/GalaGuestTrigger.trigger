/**
 * @description Gala Guest automation: default the Opportunity from the table and resolve "Add as Contact"
 *              (before), and keep the table's Seats Filled in sync (after). JSI Gala Event Gifts. Author: Jason Ott.
 */
trigger GalaGuestTrigger on Gala_Guest__c (
        before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        GalaAutomationService.stampGuestOpportunity(Trigger.new);
        GalaAutomationService.resolveContacts(Trigger.new);
    } else {
        Set<Id> tableIds = new Set<Id>();
        if (Trigger.isDelete) {
            for (Gala_Guest__c g : Trigger.old) {
                tableIds.add(g.Gala_Table__c);
            }
        } else {
            for (Gala_Guest__c g : Trigger.new) {
                tableIds.add(g.Gala_Table__c);
            }
            if (Trigger.isUpdate) {
                for (Gala_Guest__c g : Trigger.old) {
                    tableIds.add(g.Gala_Table__c);
                }
            }
        }
        GalaAutomationService.updateSeatsFilled(tableIds);
    }
}
