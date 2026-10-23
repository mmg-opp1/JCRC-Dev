/**
 * @description Tests for ContactMatcher (Flow action "Find Potential Contact Matches") and
 *              ContactMatch. Covers each kind of evidence, the confidence bands, the
 *              no-match / not-searchable branches the flow relies on, limits, and bulk use.
 *
 *              Nickname groups are supplied through ContactMatcher.nicknameGroupsOverride so the
 *              tests do not depend on which Nickname_Group__mdt records are deployed.
 *              Phone matching goes through SOSL, which returns nothing in tests unless
 *              Test.setFixedSearchResults is used, so the phone test sets it.
 * @author Jason Ott
 * @created 2026-10-09
 *
 * Change Log:
 * -----------
 * 2026-10-09 - Jason Ott - Initial version.
 * 2026-10-09 - Jason Ott - Matches JSON output for the Datatable component.
 * 2026-10-23 - Jason Ott - American spelling throughout (no behavior change).
 */
@IsTest
private class ContactMatcherTest {

    @TestSetup
    static void setup() {
        List<Contact> people = new List<Contact>{
            new Contact(FirstName = 'Robert', LastName = 'Johnson', Email = 'rjohnson@example.org',
                        Phone = '(212) 555-1120', MailingStreet = '123 West 5th Street\nApt 4B',
                        MailingPostalCode = '10001-1234'),
            new Contact(FirstName = 'Linda', LastName = 'Johnson', npe01__HomeEmail__c = 'family.johnson@example.org',
                        MailingStreet = '123 W 5th St', MailingPostalCode = '10001'),
            new Contact(FirstName = 'Miriam', LastName = 'Abramowitz', Email = 'miriam@example.org'),
            new Contact(FirstName = 'Unrelated', LastName = 'Zuckerman', Email = 'zz@example.org')
        };
        // The org's duplicate rules allow saves, but say so explicitly so similar test people insert.
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.DuplicateRuleHeader.allowSave = true;
        Database.insert(people, opts);
    }

    private static Contact byName(String first, String last) {
        return [SELECT Id FROM Contact WHERE FirstName = :first AND LastName = :last LIMIT 1];
    }

    private static ContactMatcher.Result run(ContactMatcher.Request r) {
        ContactMatcher.nicknameGroupsOverride = new List<String>{ 'Robert, Bob, Bobby, Rob', 'Miriam, Mimi' };
        return ContactMatcher.findMatches(new List<ContactMatcher.Request>{ r })[0];
    }

    private static ContactMatch matchFor(ContactMatcher.Result res, Id contactId) {
        for (ContactMatch m : res.matches) {
            if (m.contactId == contactId) {
                return m;
            }
        }
        return null;
    }

    /** Same name + email = Strong, ranked first, with all three reasons listed. */
    @IsTest
    static void exactNameAndEmailIsStrong() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Robert';
        r.lastName = 'Johnson';
        r.email = 'RJohnson@Example.org ';

        Test.startTest();
        ContactMatcher.Result res = run(r);
        Test.stopTest();

        Id robert = byName('Robert', 'Johnson').Id;
        Assert.isTrue(res.searchPerformed);
        Assert.isTrue(res.hasMatches);
        Assert.areEqual(robert, res.topContactId, 'Robert should rank first');
        Assert.areEqual('Strong', res.topConfidence);
        Assert.areEqual(ContactMatcher.W_EMAIL + ContactMatcher.W_LAST_EXACT + ContactMatcher.W_FIRST_EXACT, res.topScore);
        Assert.isTrue(res.matches[0].reasons.contains('Email matches'), res.matches[0].reasons);
        Assert.areEqual(robert, res.matchedContacts[0].Id, 'Contacts list follows the ranking');
    }

    /**
     * A nickname plus a typo in the last name still finds the person. "Jonson" does not share
     * Johnson's first three letters, so this also proves the initial + zip search.
     */
    @IsTest
    static void nicknameAndTypoAreTolerated() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Bob';
        r.lastName = 'Jonson';
        r.street = '123 West 5th Street';
        r.postalCode = '10001';

        ContactMatcher.Result res = run(r);

        ContactMatch m = matchFor(res, byName('Robert', 'Johnson').Id);
        Assert.isNotNull(m, 'Robert Johnson should be found from "Bob Jonson"');
        Assert.areEqual(ContactMatcher.W_FIRST_NICKNAME + ContactMatcher.W_LAST_SIMILAR
                        + ContactMatcher.W_STREET + ContactMatcher.W_ZIP, m.score);
        Assert.isTrue(m.reasons.contains('nickname'), m.reasons);
        Assert.isTrue(m.reasons.contains('Last name similar'), m.reasons);
        Assert.isTrue(m.reasons.contains('Street address matches'), 'Apt line and abbreviations ignored: ' + m.reasons);
    }

    /** Same household address but a different first name (a spouse) is offered as Possible, not Strong. */
    @IsTest
    static void spouseAtSameAddressIsPossible() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Robert';
        r.lastName = 'Johnson';
        r.street = '123 W. 5th St.';
        r.postalCode = '10001';

        ContactMatcher.Result res = run(r);

        ContactMatch linda = matchFor(res, byName('Linda', 'Johnson').Id);
        Assert.isNotNull(linda);
        Assert.areEqual('Possible', linda.confidence);
        Assert.areEqual(byName('Robert', 'Johnson').Id, res.topContactId, 'The named person still outranks the spouse');
    }

    /** Email on a secondary NPSP email field is matched too. */
    @IsTest
    static void secondaryEmailFieldMatches() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.email = 'family.johnson@example.org';

        ContactMatcher.Result res = run(r);

        Assert.areEqual(byName('Linda', 'Johnson').Id, res.topContactId);
        Assert.areEqual(ContactMatcher.W_EMAIL, res.topScore);
    }

    /** Phone matches whatever the formatting (SOSL is stubbed: tests return no search results otherwise). */
    @IsTest
    static void phoneMatchesAcrossFormats() {
        Id robert = byName('Robert', 'Johnson').Id;
        Test.setFixedSearchResults(new List<Id>{ robert });
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.phone = '+1 212.555.1120';
        r.lastName = 'Johnson'; // phone alone (30) is deliberately below the default minimum of 35

        ContactMatcher.Result res = run(r);

        Assert.areEqual(robert, res.topContactId);
        Assert.isTrue(res.matches[0].reasons.contains('Phone matches'), res.matches[0].reasons);
    }

    /** Matches JSON: one flat row per match, in rank order, with the columns the Datatable is set up with. */
    @IsTest
    static void matchesJsonIsFlatAndRanked() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Robert';
        r.lastName = 'Johnson';
        r.street = '123 West 5th Street';
        r.postalCode = '10001';

        ContactMatcher.Result res = run(r);

        List<Object> rows = (List<Object>) JSON.deserializeUntyped(res.matchesJson);
        Assert.areEqual(res.matchCount, rows.size(), 'One row per match');
        Map<String, Object> top = (Map<String, Object>) rows[0];
        Assert.areEqual(String.valueOf(res.topContactId), (String) top.get('contactId'), 'Same order as the ranking');
        Assert.areEqual('Robert Johnson', top.get('name'));
        Assert.areEqual('rjohnson@example.org', top.get('email'));
        Assert.areEqual('(212) 555-1120', top.get('phone'));
        Assert.areEqual('123 West 5th Street, Apt 4B, 10001-1234', top.get('address'), 'Street lines joined on one line');
        Assert.areEqual(res.topScore, (Integer) top.get('score'));
        Assert.areEqual('Strong', top.get('confidence'));
        Assert.isTrue(((String) top.get('reasons')).contains('Street address matches'));
    }

    /** No match: the flow's "create the Contact" branch - searched, nothing found. */
    @IsTest
    static void noMatchReturnsEmpty() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Penelope';
        r.lastName = 'Quackenbush';
        r.email = 'pq@example.org';

        ContactMatcher.Result res = run(r);

        Assert.isTrue(res.searchPerformed);
        Assert.isFalse(res.hasMatches);
        Assert.areEqual(0, res.matchCount);
        Assert.isNull(res.topContactId);
        Assert.areEqual('No potential matches found.', res.summary);
        Assert.areEqual('[]', res.matchesJson, 'The Datatable gets an empty list, not null');
    }

    /** First name alone is not searchable - and must not be mistaken for "no duplicate". */
    @IsTest
    static void insufficientDataIsNotSearched() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Robert';

        ContactMatcher.Result res = run(r);

        Assert.isFalse(res.searchPerformed);
        Assert.isFalse(res.hasMatches);
    }

    /** The flow's minimum score and maximum results are honored. */
    @IsTest
    static void minimumScoreAndMaxResults() {
        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Robert';
        r.lastName = 'Johnson';
        r.street = '123 West 5th Street';
        r.postalCode = '10001';

        r.maxResults = 1;
        ContactMatcher.Result one = run(r);
        Assert.areEqual(1, one.matchCount, 'Capped at one result');

        r.maxResults = null;
        r.minimumScore = 65;
        ContactMatcher.Result strongOnly = run(r);
        Assert.isNull(matchFor(strongOnly, byName('Linda', 'Johnson').Id), 'The Possible spouse is filtered out');
        Assert.isNotNull(matchFor(strongOnly, byName('Robert', 'Johnson').Id));
    }

    /** First initial gives a little credit; a short different surname (Ott/Orr) does not count as similar. */
    @IsTest
    static void initialsAndShortNames() {
        Assert.isFalse(ContactMatcher.namesSimilar('ott', 'orr'), 'Three-letter names must match exactly');
        Assert.isTrue(ContactMatcher.namesSimilar('johnson', 'jonson'));
        Assert.isTrue(ContactMatcher.namesSimilar('smith jones', 'smith'), 'Hyphenated part counts');

        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'M.';
        r.lastName = 'Abramowitz';
        r.minimumScore = 0;
        ContactMatcher.Result res = run(r);
        Assert.areEqual(ContactMatcher.W_LAST_EXACT + ContactMatcher.W_FIRST_INITIAL, res.topScore);
        Assert.areEqual('Weak', res.topConfidence);
    }

    /** Normalizers: the comparisons depend on these. */
    @IsTest
    static void normalizers() {
        Assert.areEqual('123 w 5th st', ContactMatcher.normalizeStreet('123 West 5th Street, Apt. 4B'));
        Assert.areEqual('123 w 5th st', ContactMatcher.normalizeStreet('123 W 5th St #4B'));
        Assert.areEqual('2125551120', ContactMatcher.normalizePhone('1 (212) 555-1120'));
        Assert.areEqual('', ContactMatcher.normalizePhone('555-1120'), 'Incomplete numbers are ignored');
        Assert.areEqual('10001', ContactMatcher.normalizeZip('10001-1234'));
        Assert.areEqual('obrien smith', ContactMatcher.normalizeName('O\'Brien-Smith'));
        Assert.areEqual('acme', ContactMatcher.normalizeCompany('The Acme Company, Inc.'));
    }

    /**
     * Company evidence comes from the Contact's Primary Affiliation - NPSP keeps people in their
     * household account, so that is where an employer is recorded.
     */
    @IsTest
    static void companyMatchesPrimaryAffiliation() {
        Account org = new Account(Name = 'Acme Widgets LLC');
        Schema.RecordTypeInfo orgType =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Organization');
        if (orgType != null) {
            org.RecordTypeId = orgType.getRecordTypeId();
        }
        insert org;
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Abramowitz' LIMIT 1];
        c.npsp__Primary_Affiliation__c = org.Id;
        update c;

        ContactMatcher.Request r = new ContactMatcher.Request();
        r.firstName = 'Mimi';
        r.lastName = 'Abramowitz';
        r.company = 'Acme Widgets, Inc.';
        ContactMatcher.Result res = run(r);

        Assert.areEqual(c.Id, res.topContactId);
        Assert.isTrue(res.matches[0].reasons.contains('Company matches'), res.matches[0].reasons);
        Assert.isTrue(res.matches[0].reasons.contains('nickname'), res.matches[0].reasons);
    }

    /** 200 requests (a bulk record-triggered flow) use a fixed number of queries, not one per request. */
    @IsTest
    static void bulkRequestsShareQueries() {
        ContactMatcher.nicknameGroupsOverride = new List<String>{ 'Robert, Bob' };
        List<ContactMatcher.Request> reqs = new List<ContactMatcher.Request>();
        for (Integer i = 0; i < 200; i++) {
            ContactMatcher.Request r = new ContactMatcher.Request();
            r.firstName = 'Robert';
            r.lastName = (Math.mod(i, 2) == 0) ? 'Johnson' : 'Nobody' + i;
            r.email = 'person' + i + '@example.org';
            r.phone = '212555' + String.valueOf(1000 + i);
            r.postalCode = '10001';
            reqs.add(r);
        }

        Test.startTest();
        List<ContactMatcher.Result> results = ContactMatcher.findMatches(reqs);
        Integer soql = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(200, results.size());
        Assert.isTrue(soql <= 5, 'Expected at most 5 SOQL queries for 200 requests, used ' + soql);
        Assert.isTrue(results[0].hasMatches, 'Even rows search Johnson');
        Assert.isFalse(results[1].hasMatches, 'Odd rows match nobody');
    }

    /** Ties are broken by name so the order is stable. */
    @IsTest
    static void contactMatchSortsBestFirst() {
        ContactMatch a = new ContactMatch();
        a.score = 50;
        a.contactName = 'Zed';
        ContactMatch b = new ContactMatch();
        b.score = 50;
        b.contactName = 'Amy';
        ContactMatch c = new ContactMatch();
        c.score = 90;
        c.contactName = 'Mid';
        List<ContactMatch> l = new List<ContactMatch>{ a, b, c };
        l.sort();
        Assert.areEqual('Mid', l[0].contactName);
        Assert.areEqual('Amy', l[1].contactName);
        Assert.areEqual('Zed', l[2].contactName);
    }
}