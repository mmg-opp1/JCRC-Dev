/**
 * @description Flow action "Find Potential Contact Matches". Give it whatever person data a form
 *              or record supplied (name, email, phone, address, company) and it returns the
 *              existing Contacts that may be the same person, ranked and explained.
 *
 *              Built so any flow can do "no match -> create the Contact; matches -> let a user
 *              choose". Flow's own Get Records can only do exact matches; this tolerates typos
 *              (Jonson / Johnson), nicknames (Bob / Robert), phone formatting, and street
 *              abbreviations (Street / St).
 *
 *              HOW IT WORKS
 *              1. Finds candidates with a few selective searches (never a scan of every Contact):
 *                 - email, against all four NPSP email fields (SOQL)
 *                 - phone, against every phone field (SOSL, which ignores formatting)
 *                 - last name, by its first three letters (SOQL LIKE), so a typo later in the
 *                   name still finds the Contact
 *                 - last-name initial within the same zip, so an early typo ("Jonson" for
 *                   "Johnson") is still found when the address is known
 *              2. Scores each candidate 0-100 from the evidence (weights below), so no single
 *                 weak signal decides on its own:
 *                   Email exact 35 | Phone 30 | Street 25 | Zip 5 | Company 5
 *                   Last name exact 20, similar 12
 *                   First name exact or nickname 15, similar 8, initial only 4
 *                 e.g. same first + last name + email = 70 (Strong); same name only = 35
 *                 (Possible - the donor may have a new email); same last name + address with a
 *                 different first name = 50 (Possible - often a spouse).
 *              3. Returns matches at or above the flow's minimum score (default 35), best first.
 *
 *              It only reads. It never creates, updates or links a record - the flow decides.
 *
 *              RUNS IN SYSTEM CONTEXT ("without sharing") so it finds every Contact whoever the
 *              flow runs as (e.g. an integration user posting Jotform data, who may see few
 *              Contacts). Results stay inside the flow; a screen flow that displays them shows
 *              the matched Contacts' name, email, phone and address to its user.
 *
 *              Nicknames come from Nickname_Group__mdt (editable in Setup, no deploy needed).
 *              Phone search uses the search index, so a Contact created in the last few
 *              seconds may not be found by phone yet (email and name are found immediately).
 *              A typo in the first three letters of a last name is only caught when the email,
 *              phone or zip also matches.
 * @author Jason Ott
 * @created 2026-10-09
 *
 * Change Log:
 * -----------
 * 2026-10-09 - Jason Ott - Initial version for the Jotform gala registration matching.
 * 2026-10-09 - Jason Ott - Nickname weight 12 -> 15: "Greg Ott" scored 32 and missed Gregory Ott.
 */
public without sharing class ContactMatcher {

    // --- Evidence weights (points out of 100) ---
    @TestVisible private static final Integer W_EMAIL = 35;
    @TestVisible private static final Integer W_PHONE = 30;
    @TestVisible private static final Integer W_STREET = 25;
    @TestVisible private static final Integer W_ZIP = 5;
    @TestVisible private static final Integer W_COMPANY = 5;
    @TestVisible private static final Integer W_LAST_EXACT = 20;
    @TestVisible private static final Integer W_LAST_SIMILAR = 12;
    @TestVisible private static final Integer W_FIRST_EXACT = 15;
    @TestVisible private static final Integer W_FIRST_NICKNAME = 15;   // a known nickname is as good as the exact name
    @TestVisible private static final Integer W_FIRST_SIMILAR = 8;
    @TestVisible private static final Integer W_FIRST_INITIAL = 4;

    // --- Confidence bands and defaults ---
    @TestVisible private static final Integer STRONG_SCORE = 65;
    @TestVisible private static final Integer POSSIBLE_SCORE = 35;
    @TestVisible private static final Integer DEFAULT_MAX_RESULTS = 10;
    @TestVisible private static final Integer MAX_RESULTS_CAP = 50;

    /** Safety cap on candidates pulled by any one search, to protect heap and CPU. */
    private static final Integer CANDIDATE_QUERY_LIMIT = 2000;

    /** Phones per SOSL query (one search covers many requests: FIND '... OR ...'). */
    private static final Integer PHONES_PER_SEARCH = 20;

    /** Words dropped from company names before comparing ("Acme, Inc." = "Acme"). */
    private static final Set<String> COMPANY_NOISE = new Set<String>{
        'inc', 'llc', 'llp', 'ltd', 'corp', 'corporation', 'co', 'company', 'the', 'pc', 'pllc'
    };

    /** Street words reduced to one spelling so "123 West 5th Street" = "123 W 5th St". */
    private static final Map<String, String> STREET_WORDS = new Map<String, String>{
        'street' => 'st', 'avenue' => 'ave', 'av' => 'ave', 'road' => 'rd', 'boulevard' => 'blvd',
        'drive' => 'dr', 'lane' => 'ln', 'place' => 'pl', 'court' => 'ct', 'terrace' => 'ter',
        'parkway' => 'pkwy', 'highway' => 'hwy', 'square' => 'sq', 'circle' => 'cir',
        'north' => 'n', 'south' => 's', 'east' => 'e', 'west' => 'w'
    };

    /** A street line is cut at these words: the unit ("Apt 4B") is not part of the address match. */
    private static final Set<String> UNIT_WORDS = new Set<String>{
        'apt', 'apartment', 'suite', 'ste', 'unit', 'fl', 'floor', 'rm', 'room', 'ph'
    };

    // ------------------------------------------------------------------
    // Flow interface
    // ------------------------------------------------------------------

    /** What the flow knows about the person. Every field is optional; supply what you have. */
    public class Request {
        @InvocableVariable(label='First Name')
        public String firstName;
        @InvocableVariable(label='Last Name')
        public String lastName;
        @InvocableVariable(label='Email')
        public String email;
        @InvocableVariable(label='Phone')
        public String phone;
        @InvocableVariable(label='Street')
        public String street;
        @InvocableVariable(label='City' description='Shown for context only; Zip carries the location match.')
        public String city;
        @InvocableVariable(label='State')
        public String state;
        @InvocableVariable(label='Zip / Postal Code')
        public String postalCode;
        @InvocableVariable(label='Company')
        public String company;
        @InvocableVariable(label='Minimum Score' description='0-100. Matches below this are left out. Default 35 (Possible). Use 65 for Strong matches only.')
        public Integer minimumScore;
        @InvocableVariable(label='Maximum Results' description='Default 10, at most 50.')
        public Integer maxResults;
    }

    /** What comes back to the flow. */
    public class Result {
        @InvocableVariable(label='Has Matches' description='True when at least one Contact met the minimum score.')
        public Boolean hasMatches = false;
        @InvocableVariable(label='Match Count')
        public Integer matchCount = 0;
        @InvocableVariable(label='Search Performed' description='False when there was not enough to search on (no last name, email or phone). Do not treat that as "no duplicate".')
        public Boolean searchPerformed = false;
        @InvocableVariable(label='Matched Contacts' description='The matched Contacts, best first. Usable in a Data Table.')
        public List<Contact> matchedContacts = new List<Contact>();
        @InvocableVariable(label='Matches' description='Each match with its score, confidence and reasons, best first.')
        public List<ContactMatch> matches = new List<ContactMatch>();
        @InvocableVariable(label='Top Contact Id')
        public Id topContactId;
        @InvocableVariable(label='Top Score')
        public Integer topScore;
        @InvocableVariable(label='Top Confidence' description='Strong, Possible or Weak.')
        public String topConfidence;
        @InvocableVariable(label='Summary' description='One line per match, for a screen or a note.')
        public String summary;
    }

    /**
     * @description Flow entry point. Bulk-safe: when a record-triggered flow sends many requests
     *              at once, the searches are combined, so the query count does not grow with the
     *              number of requests.
     */
    @InvocableMethod(
        label='Find Potential Contact Matches'
        description='Finds existing Contacts that may be the same person, using fuzzy name, nickname, email, phone, address and company matching. Returns ranked matches with scores and reasons. Read-only.'
        category='Contacts'
    )
    public static List<Result> findMatches(List<Request> requests) {
        List<Probe> probes = new List<Probe>();
        for (Request r : requests) {
            probes.add(new Probe(r));
        }
        Candidates pool = loadCandidates(probes);

        List<Result> results = new List<Result>();
        for (Probe p : probes) {
            results.add(buildResult(p, pool));
        }
        return results;
    }

    // ------------------------------------------------------------------
    // Normalised view of one request
    // ------------------------------------------------------------------

    /** A request with every value normalised once, up front, for comparison. */
    @TestVisible
    private class Probe {
        Request source;
        String first;        // normalised first name (first word only)
        String last;         // normalised last name
        String lastRaw;      // trimmed as typed, for the SOQL prefix
        String email;
        String phone;        // last 10 digits
        String street;
        String zip;          // first 5 digits
        String company;
        Integer minimumScore;
        Integer maxResults;

        Probe(Request r) {
            source = r;
            first = firstWord(normalizeName(r.firstName));
            last = normalizeName(r.lastName);
            lastRaw = r.lastName == null ? '' : r.lastName.trim();
            email = String.isBlank(r.email) ? '' : r.email.trim().toLowerCase();
            phone = normalizePhone(r.phone);
            street = normalizeStreet(r.street);
            zip = normalizeZip(r.postalCode);
            company = normalizeCompany(r.company);
            minimumScore = r.minimumScore == null ? POSSIBLE_SCORE : Math.max(0, Math.min(100, r.minimumScore));
            Integer maxR = r.maxResults == null ? DEFAULT_MAX_RESULTS : r.maxResults;
            maxResults = Math.max(1, Math.min(MAX_RESULTS_CAP, maxR));
        }

        /** Last name, email or phone is needed; anything less would match half the database. */
        Boolean searchable() {
            return String.isNotBlank(last) || String.isNotBlank(email) || String.isNotBlank(phone);
        }

        /** SOQL LIKE pattern for the first 3 letters of the last name, wildcards escaped. */
        String lastPrefixPattern() {
            if (String.isBlank(lastRaw)) {
                return null;
            }
            String prefix = lastRaw.left(3).replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
            return prefix + '%';
        }
    }

    // ------------------------------------------------------------------
    // Candidate search (bulk: one set of queries for all requests)
    // ------------------------------------------------------------------

    /** Every candidate found, indexed by the keys a request can look them up by. */
    private class Candidates {
        Map<Id, Contact> byId = new Map<Id, Contact>();
        Map<String, Set<Id>> byEmail = new Map<String, Set<Id>>();
        Map<String, Set<Id>> byPhone = new Map<String, Set<Id>>();
        Map<String, Set<Id>> byLastPrefix = new Map<String, Set<Id>>();
        Map<String, Set<Id>> byZipInitial = new Map<String, Set<Id>>();
    }

    /**
     * @description Runs the candidate searches for all probes together, loads the candidates'
     *              details in one query, and indexes them by email, phone and last-name prefix.
     */
    private static Candidates loadCandidates(List<Probe> probes) {
        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<String> lastPatterns = new Set<String>();
        Set<String> initialPatterns = new Set<String>();
        Set<String> zipPatterns = new Set<String>();
        for (Probe p : probes) {
            if (!p.searchable()) {
                continue;
            }
            if (String.isNotBlank(p.email)) {
                emails.add(p.email);
            }
            if (String.isNotBlank(p.phone)) {
                phones.add(p.phone);
            }
            String pattern = p.lastPrefixPattern();
            if (pattern != null) {
                lastPatterns.add(pattern);
            }
            if (String.isNotBlank(p.last) && String.isNotBlank(p.zip)) {
                initialPatterns.add(p.last.left(1) + '%');
                zipPatterns.add(p.zip + '%');
            }
        }

        Set<Id> ids = new Set<Id>();

        // Email: any of the four NPSP email fields. SOQL compares case-insensitively.
        if (!emails.isEmpty()) {
            for (Contact c : [
                SELECT Id FROM Contact
                WHERE Email IN :emails OR npe01__HomeEmail__c IN :emails
                   OR npe01__WorkEmail__c IN :emails OR npe01__AlternateEmail__c IN :emails
                LIMIT :CANDIDATE_QUERY_LIMIT
            ]) {
                ids.add(c.Id);
            }
        }

        // Last name: first three letters, so "Jonson" still finds "Johnson".
        if (!lastPatterns.isEmpty()) {
            for (Contact c : [
                SELECT Id FROM Contact WHERE LastName LIKE :lastPatterns LIMIT :CANDIDATE_QUERY_LIMIT
            ]) {
                ids.add(c.Id);
            }
        }

        // Last-name initial + zip. The sets are combined across requests, so this can return a
        // few extra Contacts (initial from one request, zip from another); each request later
        // keeps only the Contacts matching its own initial and zip.
        if (!zipPatterns.isEmpty()) {
            for (Contact c : [
                SELECT Id FROM Contact
                WHERE LastName LIKE :initialPatterns
                  AND (MailingPostalCode LIKE :zipPatterns OR OtherPostalCode LIKE :zipPatterns)
                LIMIT :CANDIDATE_QUERY_LIMIT
            ]) {
                ids.add(c.Id);
            }
        }

        // Phone: SOSL matches regardless of formatting ("2125551120" finds "(212) 555-1120").
        ids.addAll(searchPhones(new List<String>(phones)));

        Candidates pool = new Candidates();
        if (ids.isEmpty()) {
            return pool;
        }
        for (Contact c : [
            SELECT Id, Name, FirstName, LastName, Email, npe01__HomeEmail__c, npe01__WorkEmail__c,
                   npe01__AlternateEmail__c, Phone, MobilePhone, HomePhone, OtherPhone,
                   npe01__WorkPhone__c, MailingStreet, MailingCity, MailingState, MailingPostalCode,
                   OtherStreet, OtherPostalCode, AccountId, Account.Name, Account.npe01__SYSTEMIsIndividual__c,
                   npsp__Primary_Affiliation__c, npsp__Primary_Affiliation__r.Name,
                   npsp__Primary_Affiliation__r.npe01__SYSTEMIsIndividual__c, npsp__Deceased__c
            FROM Contact
            WHERE Id IN :ids
        ]) {
            pool.byId.put(c.Id, c);
            for (String e : contactEmails(c)) {
                index(pool.byEmail, e, c.Id);
            }
            for (String ph : contactPhones(c)) {
                index(pool.byPhone, ph, c.Id);
            }
            index(pool.byLastPrefix, String.isBlank(c.LastName) ? '' : c.LastName.left(3).toLowerCase(), c.Id);
            String initial = normalizeName(c.LastName).left(1);
            for (String z : new Set<String>{ normalizeZip(c.MailingPostalCode), normalizeZip(c.OtherPostalCode) }) {
                if (String.isNotBlank(z) && String.isNotBlank(initial)) {
                    index(pool.byZipInitial, z + '|' + initial, c.Id);
                }
            }
        }
        return pool;
    }

    /**
     * @description Finds Contacts by phone through the search index, combining up to
     *              PHONES_PER_SEARCH numbers per SOSL query and stopping short of the SOSL limit.
     *              Numbers are digits only, so they are safe to place in the search string.
     */
    private static Set<Id> searchPhones(List<String> phones) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 0; i < phones.size(); i += PHONES_PER_SEARCH) {
            if (Limits.getSoslQueries() >= Limits.getLimitSoslQueries()) {
                break;
            }
            List<String> chunk = new List<String>();
            for (Integer j = i; j < Math.min(i + PHONES_PER_SEARCH, phones.size()); j++) {
                chunk.add(phones[j]);
            }
            String sosl = 'FIND \'' + String.join(chunk, ' OR ') + '\' IN PHONE FIELDS RETURNING Contact(Id)';
            for (SObject s : Search.query(sosl)[0]) {
                ids.add(s.Id);
            }
        }
        return ids;
    }

    private static void index(Map<String, Set<Id>> m, String key, Id contactId) {
        if (String.isBlank(key)) {
            return;
        }
        if (!m.containsKey(key)) {
            m.put(key, new Set<Id>());
        }
        m.get(key).add(contactId);
    }

    // ------------------------------------------------------------------
    // Scoring
    // ------------------------------------------------------------------

    /**
     * @description Scores this request's candidates (only those that share its email, phone,
     *              last-name prefix, or last-name initial + zip), keeps those at or above the minimum, and fills the Result.
     */
    private static Result buildResult(Probe p, Candidates pool) {
        Result res = new Result();
        if (!p.searchable()) {
            res.summary = 'Not enough information to search: provide a last name, email or phone.';
            return res;
        }
        res.searchPerformed = true;

        // Gather this request's own candidates from the shared pool.
        Set<Id> mine = new Set<Id>();
        if (String.isNotBlank(p.email) && pool.byEmail.containsKey(p.email)) {
            mine.addAll(pool.byEmail.get(p.email));
        }
        if (String.isNotBlank(p.phone) && pool.byPhone.containsKey(p.phone)) {
            mine.addAll(pool.byPhone.get(p.phone));
        }
        String prefix = p.lastRaw.left(3).toLowerCase();
        if (String.isNotBlank(prefix) && pool.byLastPrefix.containsKey(prefix)) {
            mine.addAll(pool.byLastPrefix.get(prefix));
        }
        String zipKey = p.zip + '|' + p.last.left(1);
        if (String.isNotBlank(p.zip) && String.isNotBlank(p.last) && pool.byZipInitial.containsKey(zipKey)) {
            mine.addAll(pool.byZipInitial.get(zipKey));
        }

        // Score each candidate; keep those that clear the flow's minimum.
        List<ContactMatch> kept = new List<ContactMatch>();
        for (Id cid : mine) {
            ContactMatch m = score(p, pool.byId.get(cid));
            if (m.score >= p.minimumScore && m.score > 0) {
                kept.add(m);
            }
        }
        kept.sort();

        // Trim to the requested number and build the flow outputs.
        List<String> lines = new List<String>();
        for (Integer i = 0; i < kept.size() && i < p.maxResults; i++) {
            ContactMatch m = kept[i];
            res.matches.add(m);
            res.matchedContacts.add(m.contact);
            lines.add(m.contactName + ' - ' + m.score + ' (' + m.confidence + '): ' + m.reasons);
        }
        res.matchCount = res.matches.size();
        res.hasMatches = res.matchCount > 0;
        if (res.hasMatches) {
            res.topContactId = res.matches[0].contactId;
            res.topScore = res.matches[0].score;
            res.topConfidence = res.matches[0].confidence;
            res.summary = String.join(lines, '\n');
        } else {
            res.summary = 'No potential matches found.';
        }
        return res;
    }

    /**
     * @description Scores one Contact against the request and records why. Each kind of evidence
     *              counts once, at its best level (e.g. an exact last name is not also "similar").
     */
    @TestVisible
    private static ContactMatch score(Probe p, Contact c) {
        Integer points = 0;
        List<String> why = new List<String>();

        // Email: exact on any of the Contact's email fields.
        if (String.isNotBlank(p.email) && contactEmails(c).contains(p.email)) {
            points += W_EMAIL;
            why.add('Email matches');
        }

        // Phone: last 10 digits of any phone field.
        if (String.isNotBlank(p.phone) && contactPhones(c).contains(p.phone)) {
            points += W_PHONE;
            why.add('Phone matches');
        }

        // Last name: exact, else similar (typo, hyphenated part, spacing).
        String cLast = normalizeName(c.LastName);
        if (String.isNotBlank(p.last) && String.isNotBlank(cLast)) {
            if (p.last == cLast || p.last.deleteWhitespace() == cLast.deleteWhitespace()) {
                points += W_LAST_EXACT;
                why.add('Last name matches');
            } else if (namesSimilar(p.last, cLast)) {
                points += W_LAST_SIMILAR;
                why.add('Last name similar (' + p.source.lastName.trim() + ' / ' + c.LastName + ')');
            }
        }

        // First name: exact, nickname, similar, or just the initial.
        String cFirst = firstWord(normalizeName(c.FirstName));
        if (String.isNotBlank(p.first) && String.isNotBlank(cFirst)) {
            if (p.first == cFirst) {
                points += W_FIRST_EXACT;
                why.add('First name matches');
            } else if (areNicknames(p.first, cFirst)) {
                points += W_FIRST_NICKNAME;
                why.add('First name is a nickname (' + p.source.firstName.trim() + ' / ' + c.FirstName + ')');
            } else if ((p.first.length() == 1 || cFirst.length() == 1) && p.first.left(1) == cFirst.left(1)) {
                points += W_FIRST_INITIAL;
                why.add('First initial matches');
            } else if (namesSimilar(p.first, cFirst)) {
                points += W_FIRST_SIMILAR;
                why.add('First name similar (' + p.source.firstName.trim() + ' / ' + c.FirstName + ')');
            }
        }

        // Street: mailing or other address, unit numbers ignored.
        if (String.isNotBlank(p.street)
                && (p.street == normalizeStreet(c.MailingStreet) || p.street == normalizeStreet(c.OtherStreet))) {
            points += W_STREET;
            why.add('Street address matches');
        }

        // Zip: first five digits, mailing or other.
        if (String.isNotBlank(p.zip)
                && (p.zip == normalizeZip(c.MailingPostalCode) || p.zip == normalizeZip(c.OtherPostalCode))) {
            points += W_ZIP;
            why.add('Zip matches');
        }

        // Company: the Contact's primary affiliation or organisation account (households skipped).
        if (String.isNotBlank(p.company) && companyMatches(p.company, c)) {
            points += W_COMPANY;
            why.add('Company matches');
        }

        if (c.npsp__Deceased__c == true) {
            why.add('NOTE: Contact is marked deceased');
        }

        ContactMatch m = new ContactMatch();
        m.contactId = c.Id;
        m.contact = c;
        m.contactName = c.Name;
        m.score = Math.min(100, points);
        m.confidence = m.score >= STRONG_SCORE ? 'Strong' : (m.score >= POSSIBLE_SCORE ? 'Possible' : 'Weak');
        m.reasons = String.join(why, '; ');
        return m;
    }

    // ------------------------------------------------------------------
    // Comparison helpers
    // ------------------------------------------------------------------

    /**
     * @description True when two (normalised) names are close: they share a whole word of three
     *              or more letters ("Smith-Jones" / "Smith"), or the spelling differs by no more
     *              than the allowance for their length (see typoAllowance).
     */
    @TestVisible
    private static Boolean namesSimilar(String a, String b) {
        Set<String> aWords = new Set<String>();
        for (String w : a.split(' ')) {
            if (w.length() >= 3) {
                aWords.add(w);
            }
        }
        for (String w : b.split(' ')) {
            if (aWords.contains(w)) {
                return true;
            }
        }
        String ca = a.deleteWhitespace();
        String cb = b.deleteWhitespace();
        Integer allowed = typoAllowance(Math.min(ca.length(), cb.length()));
        return allowed > 0 && ca.getLevenshteinDistance(cb, allowed + 1) <= allowed;
    }

    /** Typos tolerated by length: none under 4 letters (Ott/Orr differ), 1 up to 7, 2 from 8. */
    private static Integer typoAllowance(Integer len) {
        if (len < 4) {
            return 0;
        }
        return len < 8 ? 1 : 2;
    }

    /** Name groups from Nickname_Group__mdt: lower-case name -> the groups it belongs to. */
    @TestVisible private static Map<String, Set<Integer>> nicknameIndex;

    /** Tests set this to supply groups without depending on the deployed metadata records. */
    @TestVisible private static List<String> nicknameGroupsOverride;

    /** True when both first names appear together in at least one active nickname group. */
    @TestVisible
    private static Boolean areNicknames(String a, String b) {
        loadNicknames();
        Set<Integer> aGroups = nicknameIndex.get(a);
        Set<Integer> bGroups = nicknameIndex.get(b);
        if (aGroups == null || bGroups == null) {
            return false;
        }
        for (Integer g : aGroups) {
            if (bGroups.contains(g)) {
                return true;
            }
        }
        return false;
    }

    /** Loads nickname groups once per transaction (getAll() costs no SOQL). */
    private static void loadNicknames() {
        if (nicknameIndex != null) {
            return;
        }
        List<String> groups = nicknameGroupsOverride;
        if (groups == null) {
            groups = new List<String>();
            for (Nickname_Group__mdt g : Nickname_Group__mdt.getAll().values()) {
                if (g.Active__c == true && String.isNotBlank(g.Names__c)) {
                    groups.add(g.Names__c);
                }
            }
        }
        nicknameIndex = new Map<String, Set<Integer>>();
        for (Integer i = 0; i < groups.size(); i++) {
            for (String n : groups[i].split(',')) {
                String key = normalizeName(n);
                if (String.isBlank(key)) {
                    continue;
                }
                if (!nicknameIndex.containsKey(key)) {
                    nicknameIndex.put(key, new Set<Integer>());
                }
                nicknameIndex.get(key).add(i);
            }
        }
    }

    /**
     * @description Company equal or contained either way (after dropping Inc/LLC etc.), checked
     *              against the Contact's Primary Affiliation and Account. Household accounts are
     *              skipped using NPSP's own flag (npe01__SYSTEMIsIndividual__c), not the name -
     *              households here are named "Smith (John) Family", so a name test would not work.
     */
    private static Boolean companyMatches(String company, Contact c) {
        List<String> names = new List<String>();
        if (c.AccountId != null && c.Account.npe01__SYSTEMIsIndividual__c != true) {
            names.add(c.Account.Name);
        }
        if (c.npsp__Primary_Affiliation__c != null
                && c.npsp__Primary_Affiliation__r.npe01__SYSTEMIsIndividual__c != true) {
            names.add(c.npsp__Primary_Affiliation__r.Name);
        }
        for (String n : names) {
            String norm = normalizeCompany(n);
            if (String.isBlank(norm)) {
                continue;
            }
            if (norm == company
                    || (Math.min(norm.length(), company.length()) >= 4
                        && (norm.contains(company) || company.contains(norm)))) {
                return true;
            }
        }
        return false;
    }

    private static Set<String> contactEmails(Contact c) {
        Set<String> out = new Set<String>();
        for (String e : new List<String>{ c.Email, c.npe01__HomeEmail__c, c.npe01__WorkEmail__c, c.npe01__AlternateEmail__c }) {
            if (String.isNotBlank(e)) {
                out.add(e.trim().toLowerCase());
            }
        }
        return out;
    }

    private static Set<String> contactPhones(Contact c) {
        Set<String> out = new Set<String>();
        for (String ph : new List<String>{ c.Phone, c.MobilePhone, c.HomePhone, c.OtherPhone, c.npe01__WorkPhone__c }) {
            String n = normalizePhone(ph);
            if (String.isNotBlank(n)) {
                out.add(n);
            }
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Normalisers (shared by request and Contact, so both sides are treated alike)
    // ------------------------------------------------------------------

    /** Lower case, apostrophes and periods removed (O'Brien = OBrien), hyphens become spaces. */
    @TestVisible
    private static String normalizeName(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        String t = s.toLowerCase().replaceAll('[\'’.]', '').replace('-', ' ');
        return t.replaceAll('[^a-z ]', '').normalizeSpace();
    }

    private static String firstWord(String s) {
        return String.isBlank(s) ? '' : s.split(' ')[0];
    }

    /** Last 10 digits; anything shorter than 10 digits is ignored as incomplete. */
    @TestVisible
    private static String normalizePhone(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        String digits = s.replaceAll('[^0-9]', '');
        return digits.length() < 10 ? '' : digits.right(10);
    }

    /** First five digits of a zip ("10001-1234" -> "10001"). */
    @TestVisible
    private static String normalizeZip(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        String digits = s.replaceAll('[^0-9]', '');
        return digits.length() < 5 ? '' : digits.left(5);
    }

    /**
     * @description First line of a street address in one standard spelling, with the unit
     *              dropped: "123 West 5th Street, Apt 4B" -> "123 w 5th st".
     */
    @TestVisible
    private static String normalizeStreet(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        String line = s.split('\n')[0].toLowerCase().replace('#', ' apt ').replaceAll('[.,]', ' ');
        List<String> words = new List<String>();
        for (String w : line.normalizeSpace().split(' ')) {
            if (UNIT_WORDS.contains(w)) {
                break;
            }
            words.add(STREET_WORDS.containsKey(w) ? STREET_WORDS.get(w) : w);
        }
        return String.join(words, ' ');
    }

    /** Lower case, punctuation removed, Inc/LLC/The etc. dropped. */
    @TestVisible
    private static String normalizeCompany(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        List<String> words = new List<String>();
        for (String w : s.toLowerCase().replaceAll('[^a-z0-9& ]', ' ').normalizeSpace().split(' ')) {
            if (!COMPANY_NOISE.contains(w)) {
                words.add(w);
            }
        }
        return String.join(words, ' ');
    }
}
