/**
 * @description Nightly safety net for the QuickBooks webhook feed (JSI-121 Phase 5c).
 *
 *              Webhooks can be missed: Intuit gives up after a long outage, ordering isn't guaranteed, and a
 *              notification sent while Salesforce was unreachable may never arrive. Once a night this job asks
 *              QuickBooks what changed since the last successful run (its Change Data Capture feed) and writes a
 *              QuickBooks Event for anything Salesforce hasn't already seen. The ordinary processor then handles
 *              those events exactly as if the webhook had arrived, so there is only ever one import path.
 *
 *              WHAT COUNTS AS "NOT SEEN": no event at all for that QuickBooks record, or every event for it is
 *              older than the record's current LastUpdatedTime (allowing a minute of clock slack). So a deposit
 *              whose webhook arrived is not re-processed, but one edited during an outage is.
 *
 *              THE WINDOW: from the last successful run, minus an hour of overlap (cheap - unchanged records make
 *              no new events), back no further than QuickBooks' 30 days of change history. Before the first run it
 *              looks back Catch-Up Lookback Days (7 by default). The last-run time only moves on success, so a
 *              failed night is covered by the next one.
 *
 *              Timestamp format matters: QuickBooks rejects "-0000" ("not valid for property
 *              MetaData.LastUpdatedTime") and accepts "Z" - verified against the sandbox 2026-09-23.
 * @author Jason Ott
 * @created 2026-09-23
 *
 * Change Log:
 * -----------
 * 2026-09-23 - Jason Ott - Initial version (JSI-121 Phase 5c).
 */
public without sharing class QuickBooksCatchUp implements Schedulable {

    /** QuickBooks keeps 30 days of change history. */
    @TestVisible private static final Integer MAX_LOOKBACK_DAYS = 30;
    @TestVisible private static final Integer DEFAULT_LOOKBACK_DAYS = 7;
    /** Overlap so a record changed moments after a run isn't missed by the next window. */
    @TestVisible private static final Integer OVERLAP_MINUTES = 60;
    /** Clock slack when comparing an event's time to the record's last-updated time. */
    @TestVisible private static final Integer SLACK_MINUTES = 1;

    /** Entities that can carry ACH/wire money in, matching the processor. */
    @TestVisible private static final List<String> ENTITIES = new List<String>{ 'Deposit', 'Payment', 'SalesReceipt' };

    public void execute(SchedulableContext ctx) {
        run();
    }

    /** Returns how many events it created. */
    public static Integer run() {
        QuickBooks_Settings__c cfg = QuickBooks_Settings__c.getOrgDefaults();
        if (cfg == null || cfg.Enabled__c != true || String.isBlank(cfg.Realm_Id__c)) {
            return 0;
        }
        Datetime runStart = System.now();
        Datetime since = windowStart(cfg, runStart);

        List<QuickBooks_Event__c> newEvents;
        try {
            newEvents = eventsForChangesSince(cfg, since);
        } catch (Exception e) {
            // Leave Last Catch-Up alone so tomorrow covers the same window.
            System.debug(LoggingLevel.ERROR, 'QuickBooks catch-up failed: ' + e.getMessage());
            return 0;
        }

        Integer created = 0;
        if (!newEvents.isEmpty()) {
            // Duplicates (a webhook that landed while this ran) fail on the unique event id - expected.
            for (Database.SaveResult sr : Database.insert(newEvents, false)) {
                if (sr.isSuccess()) {
                    created++;
                }
            }
        }
        update new QuickBooks_Settings__c(Id = cfg.Id, Last_Catch_Up__c = runStart);
        // Nothing is started here: the five-minute sweeper picks these up like any other event, so there is one
        // path into processing and no second batch job competing with it.
        return created;
    }

    @TestVisible
    private static Datetime windowStart(QuickBooks_Settings__c cfg, Datetime runStart) {
        Datetime since = cfg.Last_Catch_Up__c != null
            ? cfg.Last_Catch_Up__c.addMinutes(-OVERLAP_MINUTES)
            : runStart.addDays(-lookbackDays(cfg));
        Datetime floorDate = runStart.addDays(-MAX_LOOKBACK_DAYS);
        return since < floorDate ? floorDate : since;
    }

    private static Integer lookbackDays(QuickBooks_Settings__c cfg) {
        Integer days = cfg.Catch_Up_Lookback_Days__c == null
            ? DEFAULT_LOOKBACK_DAYS : Integer.valueOf(cfg.Catch_Up_Lookback_Days__c);
        return Math.min(Math.max(days, 1), MAX_LOOKBACK_DAYS);
    }

    /** Reads change tracking and returns an event per QuickBooks record Salesforce hasn't already seen. */
    private static List<QuickBooks_Event__c> eventsForChangesSince(QuickBooks_Settings__c cfg, Datetime since) {
        List<Object> queryResponses = QuickBooksApi.changesSince(ENTITIES, since);
        Map<String, Map<String, Object>> changed = new Map<String, Map<String, Object>>();

        // Loop: one QueryResponse per entity; an entity with no changes comes back as {}.
        for (Object qro : queryResponses) {
            Map<String, Object> qr = QuickBooksApi.obj(qro);
            if (qr == null) {
                continue;
            }
            for (String entity : ENTITIES) {
                for (Object ro : QuickBooksApi.items(qr.get(entity))) {
                    Map<String, Object> record = QuickBooksApi.obj(ro);
                    String id = record == null ? null : QuickBooksApi.str(record.get('Id'));
                    if (id != null) {
                        record.put('__entity', entity);
                        changed.put(entity.toLowerCase() + '-' + id, record);
                    }
                }
            }
        }
        if (changed.isEmpty()) {
            return new List<QuickBooks_Event__c>();
        }

        // What Salesforce has already seen for those records.
        Map<String, Datetime> lastSeen = new Map<String, Datetime>();
        for (QuickBooks_Event__c e : [SELECT Entity_Key__c, Event_Time__c, Received_At__c FROM QuickBooks_Event__c
                                      WHERE Entity_Key__c IN :changed.keySet()]) {
            Datetime seen = e.Event_Time__c != null ? e.Event_Time__c : e.Received_At__c;
            if (seen != null && (!lastSeen.containsKey(e.Entity_Key__c) || lastSeen.get(e.Entity_Key__c) < seen)) {
                lastSeen.put(e.Entity_Key__c, seen);
            }
        }

        List<QuickBooks_Event__c> out = new List<QuickBooks_Event__c>();
        for (String key : changed.keySet()) {
            Map<String, Object> record = changed.get(key);
            String entity = String.valueOf(record.remove('__entity'));
            String id = QuickBooksApi.str(record.get('Id'));
            Map<String, Object> meta = QuickBooksApi.obj(record.get('MetaData'));
            Datetime updated = parseTimestamp(meta == null ? null : QuickBooksApi.str(meta.get('LastUpdatedTime')));
            Datetime created = parseTimestamp(meta == null ? null : QuickBooksApi.str(meta.get('CreateTime')));
            Datetime seen = lastSeen.get(key);
            if (seen != null && updated != null && updated <= seen.addMinutes(SLACK_MINUTES)) {
                continue; // a webhook already told us about this version
            }

            String operation = 'Deleted'.equalsIgnoreCase(QuickBooksApi.str(record.get('status'))) ? 'deleted'
                : (created != null && updated != null && created == updated ? 'created' : 'updated');
            out.add(new QuickBooks_Event__c(
                Event_Id__c = ('cdc-' + key + '-' + (updated == null ? String.valueOf(System.now().getTime())
                                                                     : String.valueOf(updated.getTime()))).left(255),
                Event_Type__c = 'qbo.' + entity.toLowerCase() + '.' + operation + '.v1',
                Entity_Name__c = entity.toLowerCase(),
                Operation__c = operation,
                Entity_Id__c = id,
                Entity_Key__c = key,
                Realm_Id__c = cfg.Realm_Id__c,
                Event_Time__c = updated,
                Received_At__c = System.now(),
                Discovered_By__c = 'Catch-up',
                Payload__c = JSON.serialize(record).left(131072),
                Status__c = 'Received'));
        }
        return out;
    }

    /** QuickBooks timestamps look like 2026-09-17T07:43:17-07:00. */
    @TestVisible
    private static Datetime parseTimestamp(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}