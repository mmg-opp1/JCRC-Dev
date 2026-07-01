/**
 * @description JSI-89 — Resolves tribute honoree and notification-recipient *text* on an
 *              Opportunity into Contact lookups. For each unresolved person it runs the org's
 *              active Contact duplicate rule (fuzzy first name + last name + email) via
 *              Datacloud.FindDuplicates, then:
 *                • 0 matches  → create a Contact (memorial honorees flagged Deceased), set lookup
 *                • 1 match    → link it, filling only BLANK fields (never overwrites)
 *                • 2+ matches → ambiguous: leave the lookup blank and flag for manual review
 *              Invoked from the record-triggered Flow "Opportunity_Resolve_Tribute_Contacts".
 *              Honoree matching is name-only (no honoree email field); recipient matching uses
 *              name + email. Deceased is set only on newly created honorees, never on an existing
 *              matched Contact (a fuzzy collision must not mark a living person deceased).
 * @author Jason Ott
 * @created 2026-06-24
 *
 * Change Log:
 * -----------
 * 2026-06-24 - Jason Ott - Initial: invocable matcher using Datacloud.FindDuplicates.
 */
public with sharing class TributeContactResolver {

    // Prevents re-processing the same Opportunity within a transaction. The resolver updates the
    // triggering Opportunity (setting lookups), which re-fires the after-save flow; this guard
    // makes that recursion terminate after one pass.
    @TestVisible private static Set<Id> processedOppIds = new Set<Id>();

    /** Flow request wrapper — one per Opportunity. A scalar Id input lets the record-triggered
     *  flow pass {!$Record.Id} directly; Flow bulkifies the requests across records. */
    public class Request {
        @InvocableVariable(label='Opportunity Id' description='Opportunity to resolve tribute contacts for.' required=true)
        public Id opportunityId;
    }

    /**
     * @description Flow entry point. Resolves tribute contacts for the given Opportunities.
     * @param requests One Request per Opportunity (Flow bulkifies these into one invocation).
     */
    @InvocableMethod(label='Resolve Tribute Contacts'
        description='Match/create honoree & notification-recipient Contacts from tribute text and populate the lookups (JSI-89).')
    public static void resolveForOpportunities(List<Request> requests) {
        List<Id> opportunityIds = new List<Id>();
        for (Request req : requests) {
            if (req != null && req.opportunityId != null) {
                opportunityIds.add(req.opportunityId);
            }
        }
        processOpportunities(opportunityIds);
    }

    /**
     * @description Core resolution logic (separated from the invocable wrapper for unit testing).
     * @param opportunityIds Ids of Opportunities to process.
     */
    @TestVisible
    private static void processOpportunities(List<Id> opportunityIds) {
        // Filter out already-processed Opps (recursion guard) and de-dup the incoming list.
        Set<Id> toProcess = new Set<Id>();
        for (Id oppId : opportunityIds) {
            if (oppId != null && !processedOppIds.contains(oppId)) {
                toProcess.add(oppId);
            }
        }
        if (toProcess.isEmpty()) {
            return;
        }
        processedOppIds.addAll(toProcess);

        // Load the tribute fields for the Opportunities in scope.
        List<Opportunity> opps = [
            SELECT Id, npsp__Tribute_Type__c,
                   npsp__Honoree_Name__c, npsp__Honoree_Contact__c,
                   npsp__Notification_Recipient_Name__c, npsp__Notification_Recipient_Email__c,
                   npsp__Notification_Recipient_Contact__c, Tribute_Contact_Needs_Review__c
            FROM Opportunity
            WHERE Id IN :toProcess
        ];

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        // Walk each Opportunity, resolving the honoree and the notification recipient independently.
        for (Opportunity opp : opps) {
            Boolean changed = false;
            Boolean needsReview = false;

            // --- Honoree (name-only match; mark Deceased on create when this is a Memorial gift) ---
            if (String.isNotBlank(opp.npsp__Honoree_Name__c) && opp.npsp__Honoree_Contact__c == null) {
                Boolean memorial = (opp.npsp__Tribute_Type__c == 'Memorial');
                Resolution r = resolvePerson(opp.npsp__Honoree_Name__c, null, memorial);
                if (r.contactId != null) {
                    opp.npsp__Honoree_Contact__c = r.contactId;
                    changed = true;
                } else if (r.ambiguous) {
                    needsReview = true;
                }
            }

            // --- Notification recipient (name + email match) ---
            if (String.isNotBlank(opp.npsp__Notification_Recipient_Name__c)
                    && opp.npsp__Notification_Recipient_Contact__c == null) {
                Resolution r = resolvePerson(
                    opp.npsp__Notification_Recipient_Name__c,
                    opp.npsp__Notification_Recipient_Email__c,
                    false);
                if (r.contactId != null) {
                    opp.npsp__Notification_Recipient_Contact__c = r.contactId;
                    changed = true;
                } else if (r.ambiguous) {
                    needsReview = true;
                }
            }

            // Flag for manual review when any person was ambiguous (and not already flagged).
            if (needsReview && opp.Tribute_Contact_Needs_Review__c != true) {
                opp.Tribute_Contact_Needs_Review__c = true;
                changed = true;
            }
            if (changed) {
                oppsToUpdate.add(opp);
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }

    /** Small carrier for a single-person resolution outcome. */
    private class Resolution {
        Id contactId;            // set when matched (1) or created (0)
        Boolean ambiguous = false; // true when 2+ candidates → caller flags for review
    }

    /**
     * @description Resolves one person (honoree or recipient) to a Contact.
     * @param rawName      Free-text person name from the tribute field.
     * @param email        Email (recipient only; null for honoree).
     * @param markDeceased When creating, set npsp__Deceased__c (memorial honoree).
     */
    private static Resolution resolvePerson(String rawName, String email, Boolean markDeceased) {
        Resolution res = new Resolution();

        String[] parsed = parseName(rawName);
        String firstName = parsed[0];
        String lastName = parsed[1];

        // Build an in-memory Contact to run duplicate detection against active rules.
        Contact probe = new Contact(FirstName = firstName, LastName = lastName);
        if (String.isNotBlank(email)) {
            probe.Email = email;
            probe.npe01__HomeEmail__c = email;
        }

        Set<Id> matchIds = findDuplicateContactIds(probe);

        if (matchIds.isEmpty()) {
            // No match → create the Contact.
            Contact created = new Contact(FirstName = firstName, LastName = lastName);
            if (String.isNotBlank(email)) {
                created.Email = email;
                created.npe01__HomeEmail__c = email;
            }
            if (markDeceased == true) {
                created.npsp__Deceased__c = true;
            }
            insert created;
            res.contactId = created.Id;
        } else if (matchIds.size() == 1) {
            // Single match → link it, filling only blank fields (never overwrite good data).
            Id matchId = new List<Id>(matchIds)[0];
            if (String.isNotBlank(email)) {
                Contact existing = [
                    SELECT Id, Email, npe01__HomeEmail__c FROM Contact WHERE Id = :matchId LIMIT 1
                ];
                Boolean dirty = false;
                if (String.isBlank(existing.Email)) { existing.Email = email; dirty = true; }
                if (String.isBlank(existing.npe01__HomeEmail__c)) { existing.npe01__HomeEmail__c = email; dirty = true; }
                if (dirty) {
                    update existing;
                }
            }
            res.contactId = matchId;
        } else {
            // 2+ candidates → ambiguous; don't guess.
            res.ambiguous = true;
        }
        return res;
    }

    // Configurable token sets loaded from Name_Parse_Token__mdt (lazy, per-transaction cache).
    @TestVisible private static Set<String> suffixTokens;
    @TestVisible private static Set<String> particleTokens;

    /** Loads active suffix/particle tokens from custom metadata (limit-free getAll). */
    @TestVisible
    private static void loadTokens() {
        if (suffixTokens != null) {
            return;
        }
        suffixTokens = new Set<String>();
        particleTokens = new Set<String>();
        for (Name_Parse_Token__mdt t : Name_Parse_Token__mdt.getAll().values()) {
            if (t.Active__c != true) {
                continue;
            }
            String norm = normalizeToken(t.Token__c);
            if (String.isBlank(norm)) {
                continue;
            }
            if (t.Token_Type__c == 'Suffix') {
                suffixTokens.add(norm);
            } else if (t.Token_Type__c == 'Particle') {
                particleTokens.add(norm);
            }
        }
    }

    /** Lowercases and drops trailing punctuation so "Jr." and "jr" both match the "Jr" token. */
    @TestVisible
    private static String normalizeToken(String s) {
        return (s == null) ? '' : s.trim().toLowerCase().replaceAll('[.,]', '');
    }

    /**
     * @description Splits a free-text name into [firstName, lastName] using configurable tokens:
     *              (1) trailing **suffix** tokens (Jr, MD, …) are stripped; (2) the first
     *              **last-name particle** (van, de, della, …) marks where the last name begins,
     *              so "Maria van der Berg" → first "Maria" / last "van der Berg"; (3) otherwise the
     *              last token is the last name ("Mary Grace Ott" → "Mary Grace" / "Ott"). A single
     *              remaining token becomes the last name (Contact requires LastName).
     */
    @TestVisible
    private static String[] parseName(String rawName) {
        // Treat commas as separators (e.g., "John Smith, Jr") and collapse whitespace.
        String cleaned = (rawName == null) ? '' : rawName.trim().replaceAll('[,]', ' ').replaceAll('\\s+', ' ');
        if (cleaned == '') {
            return new String[]{ '', '' };
        }
        loadTokens();
        List<String> tokens = cleaned.split(' ');

        // (1) strip trailing suffix tokens, keeping at least one token for the last name
        while (tokens.size() > 1 && suffixTokens.contains(normalizeToken(tokens[tokens.size() - 1]))) {
            tokens.remove(tokens.size() - 1);
        }
        if (tokens.size() == 1) {
            return new String[]{ '', tokens[0] };
        }

        // (2) find the first last-name particle (scanning from the 2nd token); last name starts there
        Integer splitIdx = tokens.size() - 1; // default: last token is the last name
        for (Integer i = 1; i < tokens.size(); i++) {
            if (particleTokens.contains(normalizeToken(tokens[i]))) {
                splitIdx = i;
                break;
            }
        }

        List<String> firstParts = new List<String>();
        for (Integer i = 0; i < splitIdx; i++) {
            firstParts.add(tokens[i]);
        }
        List<String> lastParts = new List<String>();
        for (Integer i = splitIdx; i < tokens.size(); i++) {
            lastParts.add(tokens[i]);
        }
        return new String[]{ String.join(firstParts, ' '), String.join(lastParts, ' ') };
    }

    /**
     * @description Runs the org's active Contact duplicate rule(s) for the probe record and
     *              returns the Ids of matched Contacts.
     */
    private static Set<Id> findDuplicateContactIds(Contact probe) {
        Set<Id> ids = new Set<Id>();
        List<Datacloud.FindDuplicatesResult> fdResults =
            Datacloud.FindDuplicates.findDuplicates(new List<Contact>{ probe });
        for (Datacloud.FindDuplicatesResult fdr : fdResults) {
            for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
                for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                    for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                        SObject so = rec.getRecord();
                        if (so != null && so.Id != null) {
                            ids.add(so.Id);
                        }
                    }
                }
            }
        }
        return ids;
    }
}