/**
 * @description Keeps each Pending Transaction's donor match and Status current on every save, and
 *              suggests a donor for rows that arrive without one. All logic lives in
 *              PendingTransactionService (JSI-121).
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 2).
 */
trigger PendingTransactionTrigger on Pending_Transaction__c (before insert, before update) {
    PendingTransactionService.beforeSave(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}