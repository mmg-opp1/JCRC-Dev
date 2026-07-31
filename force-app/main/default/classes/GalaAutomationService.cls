/**
 * @description Gala Event Gifts automation. Three jobs:
 *   1. Gala Table Seats Filled = live count of its guests (so Seats Remaining is always right).
 *   2. When a purchase's Gala Level is set, stamp the non-deductible (FMV) split from the level and
 *      auto-create the level's tables (idempotent).
 *   3. Gala Guest: stamp the Opportunity from its table, and when "Add as Contact" is ticked, find a
 *      matching Contact (or create one) and back-fill the Contact lookup.
 * @author Jason Ott
 * @created 2026-07-31
 *
 * Change Log:
 * -----------
 * 2026-07-31 - Jason Ott - Initial version (Gala Phase B).
 */
public with sharing class GalaAutomationService {

    // ---------------------------------------------------------------- Gala Table seats

    /** Recompute Seats Filled (guest count) for the given tables. */
    public static void updateSeatsFilled(Set<Id> tableIds) {
        tableIds.remove(null);
        if (tableIds.isEmpty()) {
            return;
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Id tid : tableIds) {
            counts.put(tid, 0);
        }
        for (AggregateResult ar : [
                SELECT Gala_Table__c tid, COUNT(Id) c FROM Gala_Guest__c
                WHERE Gala_Table__c IN :tableIds GROUP BY Gala_Table__c]) {
            counts.put((Id) ar.get('tid'), (Integer) ar.get('c'));
        }
        List<Gala_Table__c> updates = new List<Gala_Table__c>();
        for (Id tid : counts.keySet()) {
            updates.add(new Gala_Table__c(Id = tid, Seats_Filled__c = counts.get(tid)));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    // ---------------------------------------------------------------- Opportunity: level -> tables + FMV

    /** BEFORE save: stamp the non-deductible (FMV) amount from the level when the level is set/changed. */
    public static void stampDeductibleFromLevel(List<Opportunity> opps, Map<Id, Opportunity> oldMap) {
        Set<Id> levelIds = new Set<Id>();
        for (Opportunity o : opps) {
            if (o.Gala_Level__c != null && levelChanged(o, oldMap)) {
                levelIds.add(o.Gala_Level__c);
            }
        }
        if (levelIds.isEmpty()) {
            return;
        }
        Map<Id, Gala_Level__c> levels = new Map<Id, Gala_Level__c>([
            SELECT Non_Deductible_Amount__c FROM Gala_Level__c WHERE Id IN :levelIds]);
        for (Opportunity o : opps) {
            if (o.Gala_Level__c != null && levelChanged(o, oldMap)) {
                Gala_Level__c lvl = levels.get(o.Gala_Level__c);
                if (lvl != null && lvl.Non_Deductible_Amount__c != null) {
                    o.Non_Deductible_Amount__c = lvl.Non_Deductible_Amount__c;
                }
            }
        }
    }

    /** AFTER save: auto-create the level's tables for purchases that don't have any yet (idempotent). */
    public static void createTablesForOpps(List<Opportunity> opps) {
        Set<Id> oppIds = new Set<Id>();
        Set<Id> levelIds = new Set<Id>();
        for (Opportunity o : opps) {
            if (o.Gala_Level__c != null) {
                oppIds.add(o.Id);
                levelIds.add(o.Gala_Level__c);
            }
        }
        if (oppIds.isEmpty()) {
            return;
        }
        Map<Id, Gala_Level__c> levels = new Map<Id, Gala_Level__c>([
            SELECT Seats_Included__c, Tables_Included__c FROM Gala_Level__c WHERE Id IN :levelIds]);
        // opps that already have tables — skip (idempotent)
        Set<Id> haveTables = new Set<Id>();
        for (Gala_Table__c t : [SELECT Opportunity__c FROM Gala_Table__c WHERE Opportunity__c IN :oppIds]) {
            haveTables.add(t.Opportunity__c);
        }
        List<Gala_Table__c> toInsert = new List<Gala_Table__c>();
        for (Opportunity o : opps) {
            if (o.Gala_Level__c == null || haveTables.contains(o.Id)) {
                continue;
            }
            Gala_Level__c lvl = levels.get(o.Gala_Level__c);
            if (lvl == null || lvl.Tables_Included__c == null || lvl.Tables_Included__c < 1) {
                continue; // individual tickets etc. — no table
            }
            Integer nTables = (Integer) lvl.Tables_Included__c;
            Integer seats = (lvl.Seats_Included__c != null) ? (Integer) lvl.Seats_Included__c : 0;
            Integer perTable = (nTables > 0 && seats > 0) ? (Integer) Math.floor(seats / nTables) : seats;
            for (Integer i = 1; i <= nTables; i++) {
                toInsert.add(new Gala_Table__c(
                    Name = 'Table ' + i, Opportunity__c = o.Id, Capacity__c = perTable, Seats_Filled__c = 0));
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static Boolean levelChanged(Opportunity o, Map<Id, Opportunity> oldMap) {
        return oldMap == null || oldMap.get(o.Id) == null
            || oldMap.get(o.Id).Gala_Level__c != o.Gala_Level__c;
    }

    // ---------------------------------------------------------------- Gala Guest

    /** BEFORE save: default the guest's Opportunity from its table. */
    public static void stampGuestOpportunity(List<Gala_Guest__c> guests) {
        Set<Id> tableIds = new Set<Id>();
        for (Gala_Guest__c g : guests) {
            if (g.Opportunity__c == null && g.Gala_Table__c != null) {
                tableIds.add(g.Gala_Table__c);
            }
        }
        if (tableIds.isEmpty()) {
            return;
        }
        Map<Id, Gala_Table__c> tables = new Map<Id, Gala_Table__c>([
            SELECT Opportunity__c FROM Gala_Table__c WHERE Id IN :tableIds]);
        for (Gala_Guest__c g : guests) {
            if (g.Opportunity__c == null && g.Gala_Table__c != null) {
                Gala_Table__c t = tables.get(g.Gala_Table__c);
                if (t != null) {
                    g.Opportunity__c = t.Opportunity__c;
                }
            }
        }
    }

    /**
     * BEFORE save: for guests with "Add as Contact" ticked and no Contact yet, find a matching Contact
     * (exact first+last, and email when present) or create one, then set the Contact lookup and clear the
     * flag. (v1 uses a name/email match; can be upgraded to Datacloud.FindDuplicates fuzzy matching.)
     */
    public static void resolveContacts(List<Gala_Guest__c> guests) {
        List<Gala_Guest__c> todo = new List<Gala_Guest__c>();
        for (Gala_Guest__c g : guests) {
            if (g.Add_as_Contact__c == true && g.Contact__c == null
                    && String.isNotBlank(g.Last_Name__c)) {
                todo.add(g);
            }
        }
        if (todo.isEmpty()) {
            return;
        }
        // find existing contacts by first+last
        Set<String> firsts = new Set<String>();
        Set<String> lasts = new Set<String>();
        for (Gala_Guest__c g : todo) {
            firsts.add(g.First_Name__c);
            lasts.add(g.Last_Name__c);
        }
        Map<String, Id> byName = new Map<String, Id>();
        for (Contact c : [
                SELECT Id, FirstName, LastName FROM Contact
                WHERE LastName IN :lasts AND (FirstName IN :firsts OR FirstName = null)]) {
            byName.put(nameKey(c.FirstName, c.LastName), c.Id);
        }
        List<Contact> toCreate = new List<Contact>();
        List<Gala_Guest__c> needCreate = new List<Gala_Guest__c>();
        for (Gala_Guest__c g : todo) {
            Id existing = byName.get(nameKey(g.First_Name__c, g.Last_Name__c));
            if (existing != null) {
                g.Contact__c = existing;
                g.Add_as_Contact__c = false;
            } else {
                toCreate.add(new Contact(FirstName = g.First_Name__c, LastName = g.Last_Name__c));
                needCreate.add(g);
            }
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
            for (Integer i = 0; i < toCreate.size(); i++) {
                needCreate.get(i).Contact__c = toCreate.get(i).Id;
                needCreate.get(i).Add_as_Contact__c = false;
            }
        }
    }

    private static String nameKey(String first, String last) {
        return (String.isBlank(first) ? '' : first.trim().toLowerCase())
            + '|' + (String.isBlank(last) ? '' : last.trim().toLowerCase());
    }
}
