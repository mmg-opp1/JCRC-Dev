/**
 * Seed 5 of 5 — tags, affiliations and relationships.
 *
 * The connective tissue. Without it the constituent records are isolated cards, and the things
 * a fundraiser actually does - "who else works at Ashford Capital", "who is this donor's
 * spouse", "pull everyone tagged Hebrew Speaker in Queens" - have nothing to act on.
 *
 * Coverage is deliberately uneven. Roughly two thirds of constituents get tags and about a
 * third get an employer, because a real database is patchy and a tester should meet records
 * that are thin as well as records that are complete. A uniformly populated database hides
 * every problem that comes from missing data.
 *
 * Relationships are created in ONE direction only. NPSP's relationship automation writes the
 * reciprocal record itself, so creating both sides here would produce duplicates - and whether
 * that reciprocal appears is itself worth a tester confirming.
 *
 * RE-RUNNABLE: skips anything already present.
 *
 * Jason Ott, 2026-08-21.
 */

List<Contact> people = [SELECT Id, FirstName, LastName, MailingCity FROM Contact
                        WHERE Email LIKE '%@example.com' ORDER BY LastName, FirstName];
if (people.isEmpty()) { System.debug('run 02_contacts.apex first.'); return; }

// ---- tag assignments -------------------------------------------------------------------------
List<Tag__c> tags = [SELECT Id, Name, Category__c FROM Tag__c];
Map<String, Tag__c> tagByName = new Map<String, Tag__c>();
for (Tag__c t : tags) { tagByName.put(t.Name, t); }

Set<Id> alreadyTagged = new Set<Id>();
for (Tag_Assignment__c ta : [SELECT Contact__c FROM Tag_Assignment__c WHERE Contact__c != null]) {
    alreadyTagged.add(ta.Contact__c);
}

// Geographic tags are applied from the constituent's actual city rather than at random, so a
// tester filtering on "Queens" gets a result that matches the addresses on screen.
Map<String, String> CITY_TAG = new Map<String, String>{
    'Queens' => 'Queens', 'Bronx' => 'Bronx', 'Riverdale' => 'Bronx',
    'New York' => 'Manhattan', 'Great Neck' => 'Long Island', 'Roslyn' => 'Long Island'
};
List<String> ROTATE = new List<String>{
    'Marketing','Computers / IT','Accounting','Rabbi','CEO','Harvard','Princeton',
    'Hebrew Speaker','Yankees','Registered Voter','Congressional Advocacy'
};

List<Tag_Assignment__c> newTags = new List<Tag_Assignment__c>();
for (Integer i = 0; i < people.size(); i++) {
    Contact c = people[i];
    if (alreadyTagged.contains(c.Id)) { continue; }
    if (Math.mod(i, 3) == 2) { continue; }          // ~1 in 3 left untagged on purpose

    // Geographic tag, driven by the address actually on the record.
    if (CITY_TAG.containsKey(c.MailingCity)) {
        Tag__c geo = tagByName.get(CITY_TAG.get(c.MailingCity));
        if (geo != null) {
            newTags.add(new Tag_Assignment__c(Contact__c = c.Id, Tag__c = geo.Id));
        }
    }
    // One or two further tags, rotated so every tag gets used by somebody.
    Integer howMany = Math.mod(i, 4) == 0 ? 2 : 1;
    for (Integer k = 0; k < howMany; k++) {
        Tag__c t = tagByName.get(ROTATE[Math.mod(i * 5 + k * 7, ROTATE.size())]);
        if (t != null) { newTags.add(new Tag_Assignment__c(Contact__c = c.Id, Tag__c = t.Id)); }
    }
}
if (!newTags.isEmpty()) {
    Database.SaveResult[] tr = Database.insert(newTags, false);
    Integer tok = 0;
    for (Database.SaveResult r : tr) { if (r.isSuccess()) { tok++; } }
    System.debug('tag assignments created: ' + tok + ' of ' + newTags.size() + ' attempted');
}

// ---- affiliations ----------------------------------------------------------------------------
// Employers. Only the corporate and congregation accounts - nobody "works at" a family foundation.
List<Account> orgs = [SELECT Id, Name FROM Account
                      WHERE Name IN ('Verity Partners LLP','Ashford Capital Group',
                                     'Delmar Industries','Pinnacle Realty Advisors',
                                     'Sussman Brothers Textiles','Greenpoint Analytics',
                                     'Congregation Beth Shalom','Temple Emanu-Shalom',
                                     'Park Slope Jewish Center','Riverdale Community Synagogue')];

Set<Id> alreadyAffiliated = new Set<Id>();
for (npe5__Affiliation__c a : [SELECT npe5__Contact__c FROM npe5__Affiliation__c
                               WHERE npe5__Contact__c != null]) {
    alreadyAffiliated.add(a.npe5__Contact__c);
}

List<String> ROLES = new List<String>{
    'Board Member','Chief Executive Officer','Partner','Director of Development',
    'Chief Financial Officer','Rabbi','President','Trustee','Volunteer','Executive Director'
};

List<npe5__Affiliation__c> newAffs = new List<npe5__Affiliation__c>();
if (!orgs.isEmpty()) {
    for (Integer i = 0; i < people.size(); i++) {
        Contact c = people[i];
        if (alreadyAffiliated.contains(c.Id)) { continue; }
        if (Math.mod(i, 3) != 0) { continue; }       // ~1 in 3 gets an employer
        Account org = orgs[Math.mod(i * 7, orgs.size())];
        // A few former affiliations, so "current employer" is a filter that actually filters.
        Boolean former = Math.mod(i, 11) == 0;
        newAffs.add(new npe5__Affiliation__c(
            npe5__Contact__c      = c.Id,
            npe5__Organization__c = org.Id,
            npe5__Role__c         = ROLES[Math.mod(i * 3, ROLES.size())],
            npe5__Status__c       = former ? 'Former' : 'Current',
            npe5__Primary__c      = !former,
            npe5__StartDate__c    = Date.today().addMonths(-(12 + Math.mod(i * 5, 96))),
            npe5__EndDate__c      = former ? Date.today().addMonths(-Math.mod(i, 11)) : null
        ));
    }
}
if (!newAffs.isEmpty()) {
    Database.SaveResult[] ar = Database.insert(newAffs, false);
    Integer aok = 0;
    for (Database.SaveResult r : ar) { if (r.isSuccess()) { aok++; } }
    System.debug('affiliations created: ' + aok + ' of ' + newAffs.size() + ' attempted');
}

// ---- relationships ---------------------------------------------------------------------------
Set<Id> alreadyRelated = new Set<Id>();
for (npe4__Relationship__c r : [SELECT npe4__Contact__c FROM npe4__Relationship__c]) {
    alreadyRelated.add(r.npe4__Contact__c);
}

List<String> REL_TYPES = new List<String>{
    'Husband','Wife','Son','Daughter','Father','Mother','Coworker','Friend','Cousin','Partner'
};

List<npe4__Relationship__c> newRels = new List<npe4__Relationship__c>();
for (Integer i = 0; i < people.size() - 1; i += 2) {
    Contact a = people[i];
    Contact b = people[i + 1];
    if (alreadyRelated.contains(a.Id) || alreadyRelated.contains(b.Id)) { continue; }
    if (Math.mod(i, 6) != 0) { continue; }           // only some people are linked
    newRels.add(new npe4__Relationship__c(
        npe4__Contact__c        = a.Id,
        npe4__RelatedContact__c = b.Id,
        npe4__Type__c           = REL_TYPES[Math.mod(i, REL_TYPES.size())],
        npe4__Status__c         = 'Current'
    ));
}
if (!newRels.isEmpty()) {
    Database.SaveResult[] rr = Database.insert(newRels, false);
    Integer rok = 0;
    for (Database.SaveResult r : rr) { if (r.isSuccess()) { rok++; } }
    System.debug('relationships created: ' + rok + ' of ' + newRels.size() + ' attempted');
}

System.debug('TOTALS -> tag assignments ' + [SELECT COUNT() FROM Tag_Assignment__c]
    + ' | affiliations ' + [SELECT COUNT() FROM npe5__Affiliation__c]
    + ' | relationships ' + [SELECT COUNT() FROM npe4__Relationship__c]);
