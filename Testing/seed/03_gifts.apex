/**
 * Seed 3 of 4 — gifts.
 *
 * Builds a realistic giving pyramid across two fiscal years: a long tail of small gifts, plus a
 * small major-donor cohort that recurs at the top of every report.
 *
 * WHY THE MAJOR DONORS ARE SPECIFIED RATHER THAN GENERATED
 * --------------------------------------------------------
 * The obvious approach - index a mixed list of amounts by record number - does not work. Donors
 * accumulate several gifts a year, so cumulative totals land wherever the modular arithmetic
 * happens to put them. Three attempts produced, in turn: 40% of the file in a giving society;
 * every major gift in one fiscal year; and an empty entry tier. The distribution is a
 * REQUIREMENT of the test data, so it is declared in MAJORS below and the gifts are built to
 * satisfy it. Each fiscal year gets a known, checkable roster:
 *
 *      2 x President's ($100K+)   3 x Governor's ($50-100K)
 *      4 x Senate ($25-50K)       6 x Congressional ($10-25K)
 *
 * Two further deliberate choices:
 *
 *  - Historical gifts are marked ALREADY ACKNOWLEDGED. Seeding 400 gifts into the pending queue
 *    would bury the handful a tester is meant to work, and would misrepresent what a normal
 *    Monday looks like. The newest few are left pending on purpose.
 *  - Gifts insert in batches of 50. Each insert fires the JSI-90 allocation trigger and the
 *    JSI-87 acknowledgment router, so larger batches risk governor limits.
 *
 * The full 400-gift plan is rebuilt identically on every run and only the next unsent slice is
 * inserted, so the script is RE-RUNNABLE and each run picks up exactly where the last stopped.
 *
 * Jason Ott, 2026-08-21.
 */
Integer TARGET     = 400;
Integer BATCH_SIZE = 50;

Integer already = [SELECT COUNT() FROM Opportunity WHERE Name LIKE '%(seed)%'];
if (already >= TARGET) {
    System.debug('already at target: ' + already + ' seeded gifts.');
    return;
}

List<Contact> donors = [SELECT Id, FirstName, LastName FROM Contact
                        WHERE Email LIKE '%@example.com' ORDER BY LastName, FirstName];
if (donors.size() < 40) {
    System.debug('need more seeded contacts - run 02_contacts.apex first.');
    return;
}

Map<String, Id> rtByName = new Map<String, Id>();
for (RecordType r : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Opportunity']) {
    rtByName.put(r.DeveloperName, r.Id);
}
Map<String, Id> campByName = new Map<String, Id>();
for (Campaign c : [SELECT Id, Name FROM Campaign]) {
    campByName.put(c.Name, c.Id);
}

List<String> RTS = new List<String>{
    'NPSP_Default','NPSP_Default','NPSP_Default','NPSP_Default','NPSP_Default',
    'NPSP_Default','NPSP_Default','Major_Gift','In_Kind_Gift','Matching_Gift'
};
List<String> CAMPS = new List<String>{
    'FY27 Annual Campaign','FY27 Annual Campaign','FY27 Israel Parade','FY27 Community Security',
    'FY27 Government Affairs','FY27 Shared Society','FY26 Annual Campaign','FY26 Gala',
    'FY27 Rikers Island Siddur','FY27 Fall Appeal'
};
List<String> APPROACHES = new List<String>{
    'Online','Direct Mail','Event','Phone','In Person','Major Gift','Online','Direct Mail'
};

// FY starts. JCRC's giving year runs July to June.
Date FY26_START = Date.newInstance(2025, 7, 1);
Date FY27_START = Date.newInstance(2026, 7, 1);

// ---- the plan -----------------------------------------------------------------------------
// Built identically on every run; only the unsent slice is inserted.
List<Opportunity> plan = new List<Opportunity>();

/* Major-donor totals per fiscal year, chosen to sit mid-band so no rounding pushes a donor into
   the neighbouring society. Each becomes 2-4 gifts. Donor index is into the sorted donor list;
   the same 15 people are used in both years so year-over-year comparisons have real subjects. */
List<Integer> MAJOR_TOTALS = new List<Integer>{
    140000, 112000,                     // President's  x2
     78000,  64000,  55000,             // Governor's   x3
     42000,  36000,  31000,  27000,     // Senate       x4
     19000,  16000,  14000, 12500, 11000, 10500   // Congressional x6
};

Integer seq = 0;
for (Integer yr = 0; yr < 2; yr++) {
    Date fyStart = (yr == 0) ? FY26_START : FY27_START;
    for (Integer m = 0; m < MAJOR_TOTALS.size(); m++) {
        Contact d = donors[m];
        // Second year is slightly different so totals are not identical across years - real
        // donors move between societies, which is what makes a year-over-year report interesting.
        Integer total = MAJOR_TOTALS[m] + (yr == 1 ? (Math.mod(m, 3) - 1) * 2000 : 0);
        Integer gifts = 2 + Math.mod(m, 3);          // 2, 3 or 4 gifts making up the total
        Integer each  = total / gifts;
        for (Integer g = 0; g < gifts; g++) {
            // Last gift absorbs the remainder so the total is exact.
            Integer amt = (g == gifts - 1) ? total - (each * (gifts - 1)) : each;
            Opportunity o = new Opportunity(
                Name = d.FirstName + ' ' + d.LastName + ' - major gift (seed)',
                npsp__Primary_Contact__c = d.Id,
                Amount      = amt,
                CloseDate   = fyStart.addDays(30 + Math.mod((m * 47) + (g * 83), 300)),
                StageName   = 'Posted',
                RecordTypeId = rtByName.get('Major_Gift'),
                Approach__c = 'Major Gift',
                npe01__Do_Not_Automatically_Create_Payment__c = true,
                npsp__Acknowledgment_Status__c = 'Acknowledged'
            );
            o.npsp__Acknowledgment_Date__c = o.CloseDate.addDays(3);
            String cn = CAMPS[Math.mod(seq * 11, CAMPS.size())];
            if (campByName.containsKey(cn)) { o.CampaignId = campByName.get(cn); }
            plan.add(o);
            seq++;
        }
    }
}
Integer majorCount = plan.size();

/* The long tail. Everyone outside the major cohort, small gifts, both years. */
List<Decimal> SMALL = new List<Decimal>{
    18, 18, 18, 36, 36, 36, 50, 54, 54, 54, 72, 100, 100, 100, 118, 118,
    180, 180, 250, 250, 25, 40, 75, 150, 200, 90, 60, 108, 45, 36,
    360, 500, 500, 750, 1000, 540, 620, 850, 300, 425
};
Integer tailStart = MAJOR_TOTALS.size();          // skip the cohort so they do not pad the tail
Integer n = 0;
while (plan.size() < TARGET) {
    Contact d   = donors[tailStart + Math.mod(n * 31, donors.size() - tailStart)];
    Decimal amt = SMALL[Math.mod(n * 17, SMALL.size())];
    String rt   = RTS[Math.mod(n * 7, RTS.size())];
    Boolean thisYear = Math.mod(n, 10) >= 4;      // 60% current year, 40% prior
    Date closeDate = thisYear
        ? FY27_START.addDays(Math.mod(n * 13, 300))
        : FY26_START.addDays(Math.mod(n * 19, 360));

    Opportunity o = new Opportunity(
        Name = d.FirstName + ' ' + d.LastName + ' - ' + amt.setScale(0).format() + ' gift (seed)',
        npsp__Primary_Contact__c = d.Id,
        Amount      = amt,
        CloseDate   = closeDate,
        StageName   = 'Posted',
        Approach__c = APPROACHES[Math.mod(n * 3, APPROACHES.size())],
        npe01__Do_Not_Automatically_Create_Payment__c = true
    );
    if (rtByName.containsKey(rt))  { o.RecordTypeId = rtByName.get(rt); }
    String cn = CAMPS[Math.mod(n * 11, CAMPS.size())];
    if (campByName.containsKey(cn)) { o.CampaignId = campByName.get(cn); }

    // The newest few stay pending so the acknowledgment queue has real work in it.
    if (plan.size() >= TARGET - 12) {
        o.npsp__Acknowledgment_Status__c = 'To Be Acknowledged';
    } else {
        o.npsp__Acknowledgment_Status__c = 'Acknowledged';
        o.npsp__Acknowledgment_Date__c   = closeDate.addDays(3);
    }
    // In-kind gifts carry their value as fair market value, not Amount (JSI-84).
    if (rt == 'In_Kind_Gift') {
        o.npsp__Fair_Market_Value__c = amt;
        o.Amount = null;
    }
    plan.add(o);
    n++;
}

// ---- insert the next slice ----------------------------------------------------------------
List<Opportunity> batch = new List<Opportunity>();
for (Integer i = already; i < Math.min(already + BATCH_SIZE, plan.size()); i++) {
    batch.add(plan[i]);
}
Database.SaveResult[] res = Database.insert(batch, false);
Integer ok = 0, bad = 0;
for (Database.SaveResult r : res) {
    if (r.isSuccess()) { ok++; }
    else {
        bad++;
        if (bad <= 3) { System.debug('  refused: ' + r.getErrors()[0].getMessage()); }
    }
}
Integer total = [SELECT COUNT() FROM Opportunity WHERE Name LIKE '%(seed)%'];
System.debug('created ' + ok + ' (refused ' + bad + ') | ' + majorCount + ' of the plan are major'
    + ' | seeded total ' + total + ' of ' + TARGET);
System.debug(total < TARGET ? 'RUN AGAIN' : 'TARGET REACHED');
