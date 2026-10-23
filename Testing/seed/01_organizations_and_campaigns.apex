/**
 * Seed 1 of 4 — organizations and campaigns.
 *
 * Invented data for client testing. Every organization name is fictional; any resemblance to
 * a real foundation is coincidental and unintended. Re-runnable: it skips anything already
 * present, so running it twice does not duplicate.
 *
 * Jason Ott, 2026-08-21.
 */

// ---- organizations ---------------------------------------------------------------------
Map<String, String> ORGS = new Map<String, String>{
    'Hartwell Family Foundation'        => 'Foundation',
    'Brightwater Charitable Trust'      => 'Foundation',
    'Kestrel Foundation'                => 'Foundation',
    'The Lindenbaum Fund'               => 'Foundation',
    'Marchetti Family Foundation'       => 'Foundation',
    'Northbridge Community Foundation'  => 'Foundation',
    'Verity Partners LLP'               => 'Corporate',
    'Ashford Capital Group'             => 'Corporate',
    'Delmar Industries'                 => 'Corporate',
    'Pinnacle Realty Advisors'          => 'Corporate',
    'Sussman Brothers Textiles'         => 'Corporate',
    'Greenpoint Analytics'              => 'Corporate',
    'Congregation Beth Shalom'          => 'Congregation',
    'Temple Emanu-Shalom'               => 'Congregation',
    'Park Slope Jewish Center'          => 'Congregation',
    'Riverdale Community Synagogue'     => 'Congregation',
    'Queens Interfaith Council'         => 'Community',
    'Brooklyn Neighbours Alliance'      => 'Community',
    'Long Island Community Trust'       => 'Community',
    'Hudson Valley Civic League'        => 'Community'
};

Set<String> existingOrgs = new Set<String>();
for (Account a : [SELECT Name FROM Account WHERE Name IN :ORGS.keySet()]) {
    existingOrgs.add(a.Name);
}

Id orgRt;
for (RecordType r : [SELECT Id FROM RecordType
                     WHERE SobjectType = 'Account' AND DeveloperName = 'Organization' LIMIT 1]) {
    orgRt = r.Id;
}

List<Account> newOrgs = new List<Account>();
Integer i = 0;
List<String> cities  = new List<String>{'New York','Brooklyn','Great Neck','White Plains','Queens'};
List<String> states  = new List<String>{'NY','NY','NY','NY','NY'};
List<String> zips    = new List<String>{'10018','11215','11021','10601','11375'};
for (String name : ORGS.keySet()) {
    if (existingOrgs.contains(name)) { continue; }
    Account a = new Account(
        Name              = name,
        BillingStreet     = String.valueOf(100 + Math.mod(i * 37, 800)) + ' Test Avenue',
        BillingCity       = cities[Math.mod(i, 5)],
        BillingState      = states[Math.mod(i, 5)],
        BillingPostalCode = zips[Math.mod(i, 5)],
        Phone             = '(212) 555-0' + String.valueOf(100 + i).right(3)
    );
    if (orgRt != null) { a.RecordTypeId = orgRt; }
    newOrgs.add(a);
    i++;
}
if (!newOrgs.isEmpty()) { insert newOrgs; }
System.debug('organizations created: ' + newOrgs.size());

// ---- campaigns ---------------------------------------------------------------------------
// "FY27 Israel Parade" matters beyond volume: the acknowledgment router picks the parade
// letter from a campaign name containing "Parade", and no such campaign existed.
Map<String, String> CAMPAIGNS = new Map<String, String>{
    'FY27 Annual Campaign'          => 'Other',
    'FY27 Israel Parade'            => 'Event',
    'FY27 Community Security'       => 'Other',
    'FY27 Government Affairs'       => 'Other',
    'FY27 Shared Society'           => 'Other',
    'FY27 Rikers Island Siddur'     => 'Other',
    'FY26 Annual Campaign'          => 'Other',
    'FY26 Gala'                     => 'Event'
};

Set<String> existingCamps = new Set<String>();
for (Campaign c : [SELECT Name FROM Campaign WHERE Name IN :CAMPAIGNS.keySet()]) {
    existingCamps.add(c.Name);
}
List<Campaign> newCamps = new List<Campaign>();
for (String name : CAMPAIGNS.keySet()) {
    if (existingCamps.contains(name)) { continue; }
    newCamps.add(new Campaign(
        Name      = name,
        Type      = CAMPAIGNS.get(name),
        IsActive  = true,
        Status    = name.startsWith('FY26') ? 'Completed' : 'In Progress',
        StartDate = name.startsWith('FY26') ? Date.newInstance(2025,7,1) : Date.newInstance(2026,7,1),
        EndDate   = name.startsWith('FY26') ? Date.newInstance(2026,6,30) : Date.newInstance(2027,6,30)
    ));
}
if (!newCamps.isEmpty()) { insert newCamps; }
System.debug('campaigns created: ' + newCamps.size());

System.debug('TOTALS -> accounts ' + [SELECT COUNT() FROM Account]
    + ' | campaigns ' + [SELECT COUNT() FROM Campaign]);
