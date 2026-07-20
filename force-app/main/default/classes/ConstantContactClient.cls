/**
 * @description JSI-107 Constant Contact v3 API client (inbound / read side of the hybrid).
 *   Calls CC over the `Constant_Contact` Named Credential (OAuth2) and turns responses into
 *   the CC-agnostic ConstantContactSyncService.ContactUpdate DTOs the applier consumes.
 *
 *   Implemented now: getUnsubscribes() — the opt-out sync (DoD #4). Bounce (#5) and
 *   engagement (#3) fetches use CC's reporting endpoints and are the next increment; their
 *   response shapes should be confirmed against a live/sample payload before building.
 *
 *   Field mapping is grounded in the documented v3 contact schema (contact_id,
 *   email_address.{address,opt_out_date,permission_to_send}, custom_fields[]); the exact
 *   pagination/custom-field wiring is marked to VERIFY against a live response once the CC
 *   Owner authorizes the app.
 * @author Jason Ott
 * @created 2026-07-19
 *
 * Change Log:
 * -----------
 * 2026-07-19 - Jason Ott - JSI-107 Phase 4: opt-out (unsubscribe) fetch + Salesforce-Id resolution.
 * 2026-07-20 - Jason Ott - JSI-108: getListMemberships (topic preference fetch).
 * 2026-07-20 - Jason Ott - JSI-109: getEmailCampaigns — email + per-recipient tracking (engagement) fetch.
 */
public with sharing class ConstantContactClient {

    private static final String NAMED_CRED = 'callout:Constant_Contact';
    private static final Integer PAGE_LIMIT = 500;
    private static final Integer PAGE_GUARD = 50; // safety cap on pagination loops
    // Cache the CC custom_field_id of the "Salesforce ID" field (set by the native connector).
    @TestVisible private static String sfIdCustomFieldId;
    @TestVisible private static Boolean sfIdFieldResolved = false;

    public class CCException extends Exception {}

    /**
     * Fetch contacts that opted out (unsubscribed) after `since` and map them to opt-out updates.
     * Uses status=all + optout_after to capture all unsubscribes since the cursor (per CC docs),
     * and include=custom_fields so we can read the pushed Salesforce Id for exact matching.
     */
    public List<ConstantContactSyncService.ContactUpdate> getUnsubscribes(Datetime since) {
        List<ConstantContactSyncService.ContactUpdate> updates =
            new List<ConstantContactSyncService.ContactUpdate>();

        String isoSince = since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String path = '/contacts?status=all&optout_after=' + EncodingUtil.urlEncode(isoSince, 'UTF-8')
                    + '&include=custom_fields&limit=' + PAGE_LIMIT;

        Integer guard = 0;
        while (String.isNotBlank(path) && guard < PAGE_GUARD) {
            guard++;
            Map<String, Object> body = getJson(path);
            List<Object> contacts = (List<Object>) body.get('contacts');
            if (contacts != null) {
                for (Object o : contacts) {
                    Map<String, Object> c = (Map<String, Object>) o;
                    updates.add(toOptOutUpdate(c));
                }
            }
            path = nextPath(body, 'custom_fields');
        }
        return updates;
    }

    /**
     * JSI-108: fetch each contact's current CC list memberships (topics they're subscribed to),
     * for contacts updated since `since`. Includes custom_fields so we can resolve the Salesforce Id.
     */
    public List<ConstantContactSyncService.TopicMembership> getListMemberships(Datetime since) {
        List<ConstantContactSyncService.TopicMembership> out =
            new List<ConstantContactSyncService.TopicMembership>();

        String isoSince = since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String include = 'list_memberships,custom_fields';
        String path = '/contacts?status=all&updated_after=' + EncodingUtil.urlEncode(isoSince, 'UTF-8')
                    + '&include=' + include + '&limit=' + PAGE_LIMIT;

        Integer guard = 0;
        while (String.isNotBlank(path) && guard < PAGE_GUARD) {
            guard++;
            Map<String, Object> body = getJson(path);
            List<Object> contacts = (List<Object>) body.get('contacts');
            if (contacts != null) {
                for (Object o : contacts) {
                    Map<String, Object> c = (Map<String, Object>) o;
                    ConstantContactSyncService.TopicMembership m = new ConstantContactSyncService.TopicMembership();
                    m.ccContactId = (String) c.get('contact_id');
                    Map<String, Object> ea = (Map<String, Object>) c.get('email_address');
                    if (ea != null) m.email = (String) ea.get('address');
                    m.salesforceId = resolveSalesforceId(c);
                    if (c.get('list_memberships') instanceof List<Object>) {
                        for (Object lid : (List<Object>) c.get('list_memberships')) {
                            if (lid != null) m.subscribedListIds.add(String.valueOf(lid));
                        }
                    }
                    out.add(m);
                }
            }
            path = nextPath(body, include);
        }
        return out;
    }

    /** Build an opt-out ContactUpdate from a CC contact map. */
    private ConstantContactSyncService.ContactUpdate toOptOutUpdate(Map<String, Object> c) {
        ConstantContactSyncService.ContactUpdate u = new ConstantContactSyncService.ContactUpdate();
        u.ccContactId = (String) c.get('contact_id');
        u.optedOut = true; // present in the optout_after set
        Map<String, Object> ea = (Map<String, Object>) c.get('email_address');
        if (ea != null) {
            u.email = (String) ea.get('address');
            u.optOutDate = parseDate((String) ea.get('opt_out_date'));
        }
        u.salesforceId = resolveSalesforceId(c);
        return u;
    }

    /** Pull the pushed Salesforce Id out of the contact's custom_fields (exact match key). */
    private Id resolveSalesforceId(Map<String, Object> c) {
        String fieldId = getSalesforceIdCustomFieldId();
        if (String.isBlank(fieldId) || c.get('custom_fields') == null) return null;
        for (Object cf : (List<Object>) c.get('custom_fields')) {
            Map<String, Object> f = (Map<String, Object>) cf;
            if (fieldId.equals((String) f.get('custom_field_id'))) {
                String val = (String) f.get('value');
                try { return (Id) val; } catch (Exception e) { return null; }
            }
        }
        return null;
    }

    /** Look up (once) the CC custom_field_id of the "Salesforce ID" field created for the sync. */
    @TestVisible
    private String getSalesforceIdCustomFieldId() {
        if (sfIdFieldResolved) return sfIdCustomFieldId;
        sfIdFieldResolved = true;
        try {
            Map<String, Object> body = getJson('/contact_custom_fields?limit=100');
            List<Object> fields = (List<Object>) body.get('custom_fields');
            if (fields != null) {
                for (Object o : fields) {
                    Map<String, Object> f = (Map<String, Object>) o;
                    String label = (String) f.get('label');
                    String name = (String) f.get('name');
                    if ((label != null && label.equalsIgnoreCase('Salesforce ID'))
                        || (name != null && name.equalsIgnoreCase('Salesforce ID'))) {
                        sfIdCustomFieldId = (String) f.get('custom_field_id');
                        break;
                    }
                }
            }
        } catch (Exception e) {
            // Non-fatal: without it we fall back to email matching in the applier.
            System.debug(LoggingLevel.WARN, 'Could not resolve Salesforce ID custom field: ' + e.getMessage());
        }
        return sfIdCustomFieldId;
    }

    /**
     * JSI-109: fetch Constant Contact emails and their per-recipient engagement. Lists emails
     * (/emails); for each sent email within the window, loads the activity detail (subject +
     * contact_list_ids) and the tracking reports (sends/opens/clicks/bounces), producing one
     * ContactActivityDTO per recipient with opens/clicks aggregated.
     *
     * VERIFY-AGAINST-LIVE: the /emails collection, /emails/activities/{id}, and
     * /reports/email_reports/{id}/tracking/* shapes are grounded in the documented v3 schema but
     * unconfirmed against a live payload (CC authorize pending). Parsing is isolated here so
     * wire-format tweaks stay in this class; the applier is CC-agnostic.
     * @param since only include emails last sent on/after this cursor
     */
    public List<ConstantContactSyncService.EmailCampaignDTO> getEmailCampaigns(Datetime since) {
        List<ConstantContactSyncService.EmailCampaignDTO> out =
            new List<ConstantContactSyncService.EmailCampaignDTO>();

        String path = '/emails?limit=50';
        Integer guard = 0;
        while (String.isNotBlank(path) && guard < PAGE_GUARD) {
            guard++;
            Map<String, Object> body = getJson(path);
            List<Object> campaigns = (List<Object>) body.get('campaigns');
            if (campaigns != null) {
                for (Object o : campaigns) {
                    Map<String, Object> cm = (Map<String, Object>) o;
                    String caId = primaryActivityId(cm);
                    if (String.isBlank(caId)) continue;

                    ConstantContactSyncService.EmailCampaignDTO dto =
                        new ConstantContactSyncService.EmailCampaignDTO();
                    dto.ccCampaignActivityId = caId;
                    dto.name = (String) cm.get('name');
                    dto.sentDate = parseDateTime((String) cm.get('last_sent_date'));
                    if (dto.sentDate == null) dto.sentDate = parseDateTime((String) cm.get('updated_at'));

                    // Only sync emails actually sent within the incremental window.
                    if (since != null && dto.sentDate != null && dto.sentDate < since) continue;

                    loadActivityDetail(caId, dto);
                    loadTracking(caId, dto);
                    out.add(dto);
                }
            }
            path = nextEmailsPath(body);
        }
        return out;
    }

    /** Find the campaign_activity_id whose role is primary_email (the actual send). */
    private String primaryActivityId(Map<String, Object> campaign) {
        if (!(campaign.get('campaign_activities') instanceof List<Object>)) return null;
        for (Object o : (List<Object>) campaign.get('campaign_activities')) {
            Map<String, Object> ca = (Map<String, Object>) o;
            if ('primary_email'.equals((String) ca.get('role'))) {
                return (String) ca.get('campaign_activity_id');
            }
        }
        return null;
    }

    /** Load subject + sent-to list ids from the campaign activity detail. */
    private void loadActivityDetail(String caId, ConstantContactSyncService.EmailCampaignDTO dto) {
        Map<String, Object> a = getJson('/emails/activities/' + caId);
        dto.subject = (String) a.get('subject');
        if (String.isBlank(dto.name)) dto.name = (String) a.get('name');
        if (a.get('contact_list_ids') instanceof List<Object>) {
            for (Object lid : (List<Object>) a.get('contact_list_ids')) {
                if (lid != null) dto.ccListIds.add(String.valueOf(lid));
            }
        }
    }

    /** Pull the four tracking reports for a campaign and merge into per-contact activity DTOs. */
    private void loadTracking(String caId, ConstantContactSyncService.EmailCampaignDTO dto) {
        Map<String, ConstantContactSyncService.ContactActivityDTO> byContact =
            new Map<String, ConstantContactSyncService.ContactActivityDTO>();
        readTracking(caId, 'sends',   byContact);
        readTracking(caId, 'opens',   byContact);
        readTracking(caId, 'clicks',  byContact);
        readTracking(caId, 'bounces', byContact);
        dto.activities.addAll(byContact.values());
    }

    /** Read one tracking report type (paginated) and fold each row into the per-contact map. */
    private void readTracking(String caId, String type,
            Map<String, ConstantContactSyncService.ContactActivityDTO> byContact) {
        String path = '/reports/email_reports/' + caId + '/tracking/' + type + '?limit=' + PAGE_LIMIT;
        Integer guard = 0;
        while (String.isNotBlank(path) && guard < PAGE_GUARD) {
            guard++;
            Map<String, Object> body = getJson(path);
            List<Object> rows = (List<Object>) body.get('tracking_activities');
            if (rows != null) {
                for (Object o : rows) {
                    Map<String, Object> r = (Map<String, Object>) o;
                    String ccId = (String) r.get('contact_id');
                    if (String.isBlank(ccId)) continue;
                    ConstantContactSyncService.ContactActivityDTO a = byContact.get(ccId);
                    if (a == null) {
                        a = new ConstantContactSyncService.ContactActivityDTO();
                        a.ccContactId = ccId;
                        a.email = (String) r.get('email_address');
                        byContact.put(ccId, a);
                    }
                    Datetime t = parseDateTime((String) r.get('created_time'));
                    if (type == 'opens') {
                        a.opened = true; a.openCount++;
                        if (a.firstOpen == null || (t != null && t < a.firstOpen)) a.firstOpen = t;
                        if (a.lastOpen == null || (t != null && t > a.lastOpen)) a.lastOpen = t;
                    } else if (type == 'clicks') {
                        a.clicked = true; a.clickCount++;
                        if (a.firstClick == null || (t != null && t < a.firstClick)) a.firstClick = t;
                        if (a.lastClick == null || (t != null && t > a.lastClick)) a.lastClick = t;
                    } else if (type == 'bounces') {
                        a.bounced = true;
                    }
                    // 'sends' just ensures the contact appears with email/id captured.
                }
            }
            path = nextTrackingPath(body);
        }
    }

    /** Next page for /emails (cursor style, keeping limit). */
    private String nextEmailsPath(Map<String, Object> body) {
        String cursor = nextCursor(body);
        return cursor == null ? null : '/emails?cursor=' + cursor + '&limit=50';
    }

    /** Next page for a tracking report — strip the /v3 base the Named Credential already carries. */
    private String nextTrackingPath(Map<String, Object> body) {
        Map<String, Object> links = (Map<String, Object>) body.get('_links');
        if (links == null || links.get('next') == null) return null;
        Map<String, Object> next = (Map<String, Object>) links.get('next');
        String href = (String) next.get('href');
        return String.isBlank(href) ? null : href.replaceFirst('^/v3', '');
    }

    /** Extract the cursor= value from _links.next.href, or null when there's no next page. */
    private String nextCursor(Map<String, Object> body) {
        Map<String, Object> links = (Map<String, Object>) body.get('_links');
        if (links == null || links.get('next') == null) return null;
        Map<String, Object> next = (Map<String, Object>) links.get('next');
        String href = (String) next.get('href');
        if (String.isBlank(href) || !href.contains('cursor=')) return null;
        return href.substringAfter('cursor=').substringBefore('&');
    }

    /** Parse a CC ISO-8601 datetime (e.g. 2026-07-20T14:00:00Z) to Datetime; null-safe. */
    private Datetime parseDateTime(String iso) {
        if (String.isBlank(iso)) return null;
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            try { return Datetime.valueOfGmt(iso.replace('T', ' ').replace('Z', '').substringBefore('.')); }
            catch (Exception e2) { return null; }
        }
    }

    /** GET a CC path over the Named Credential and return the parsed JSON body. */
    private Map<String, Object> getJson(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + path);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CCException('Constant Contact API ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /** Derive the next page path from _links.next.href (cursor-based). Null when no more pages. */
    private String nextPath(Map<String, Object> body, String include) {
        Map<String, Object> links = (Map<String, Object>) body.get('_links');
        if (links == null || links.get('next') == null) return null;
        Map<String, Object> next = (Map<String, Object>) links.get('next');
        String href = (String) next.get('href'); // e.g. /v3/contacts?cursor=...&limit=500
        if (String.isBlank(href) || !href.contains('cursor=')) return null;
        String cursor = href.substringAfter('cursor=').substringBefore('&');
        return '/contacts?cursor=' + cursor + '&include=' + include + '&limit=' + PAGE_LIMIT;
    }

    /** Parse a CC ISO-8601 datetime string to a Date (opt-out is stored as a Date in SF). */
    private Date parseDate(String iso) {
        if (String.isBlank(iso) || iso.length() < 10) return null;
        try { return Date.valueOf(iso.substring(0, 10)); } catch (Exception e) { return null; }
    }
}
