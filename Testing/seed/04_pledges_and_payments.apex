/**
 * Seed 4 of 5 — pledges and installment payments.
 *
 * These are the fixtures for JSI-82 (pledges), JSI-125 (paid-installment notifications) and
 * JSI-126 (outstanding-payment reporting). A pledge report is only worth testing if the pledges
 * behind it are in genuinely different states, so this deliberately builds five:
 *
 *   ON SCHEDULE   earlier installments paid, later ones scheduled in the future
 *   FULLY PAID    every installment paid - exercises the pledge-to-Posted automation
 *   OVERDUE       an installment scheduled in the past and still unpaid - the JSI-126 report
 *   WRITTEN OFF   one installment written off - must be EXCLUDED from outstanding balances
 *   NOT STARTED   all installments in the future
 *
 * BEFORE RUNNING: deactivate "Payment - Notify Donor On Paid" and "Opportunity - Notify Final
 * Payment". Every seeded donor is at example.com, which has no MX record, so inserting ~150
 * already-paid installments would fire that many hard bounces and risks Salesforce throttling
 * the org's email deliverability. Reactivate both when seeding finishes - the notifications are
 * themselves under test.
 *
 * RE-RUNNABLE in batches of 10 pledges.
 *
 * Jason Ott, 2026-08-21.
 */
Integer TARGET     = 30;
Integer BATCH_SIZE = 10;

Id pledgeRt;
for (RecordType r : [SELECT Id FROM RecordType
                     WHERE SobjectType = 'Opportunity' AND DeveloperName = 'Pledge' LIMIT 1]) {
    pledgeRt = r.Id;
}
if (pledgeRt == null) { System.debug('no Pledge record type found.'); return; }

Integer already = [SELECT COUNT() FROM Opportunity
                   WHERE RecordTypeId = :pledgeRt AND Name LIKE '%(seed)%'];
if (already >= TARGET) {
    System.debug('already at target: ' + already + ' seeded pledges.');
    return;
}

List<Contact> donors = [SELECT Id, FirstName, LastName FROM Contact
                        WHERE Email LIKE '%@example.com' ORDER BY LastName, FirstName];
if (donors.size() < TARGET) { System.debug('run 02_contacts.apex first.'); return; }

Map<String, Id> campByName = new Map<String, Id>();
for (Campaign c : [SELECT Id, Name FROM Campaign]) { campByName.put(c.Name, c.Id); }

// Five states, repeated so each batch of 10 contains a spread rather than 10 of one kind.
List<String> STATES = new List<String>{
    'ON_SCHEDULE','FULLY_PAID','OVERDUE','ON_SCHEDULE','WRITTEN_OFF',
    'ON_SCHEDULE','OVERDUE','FULLY_PAID','NOT_STARTED','OVERDUE'
};
List<Decimal> TOTALS = new List<Decimal>{
    18000, 36000, 12000, 25000, 50000, 9000, 15000, 60000, 24000, 10000
};
Date TODAY = Date.today();

// ---- pledges -------------------------------------------------------------------------------
List<Opportunity> pledges = new List<Opportunity>();
List<String> planned = new List<String>();
Integer upper = Math.min(already + BATCH_SIZE, TARGET);
for (Integer n = already; n < upper; n++) {
    Contact d    = donors[Math.mod(n * 23, donors.size())];
    String state = STATES[Math.mod(n, STATES.size())];
    Decimal total = TOTALS[Math.mod(n, TOTALS.size())];

    // Start date is chosen so the state is reachable: an overdue pledge must have begun long
    // enough ago for an installment to have come due.
    // ON_SCHEDULE must start recently enough that installments remain in the FUTURE. At 9 months
    // back, quarterly installments fall at +0/+3/+6/+9 - all already due, so all paid, and the
    // pledge auto-flips to Posted and becomes indistinguishable from FULLY_PAID. 4 months back
    // leaves two paid and two still to come, which is the state the report needs to show.
    Integer monthsBack = (state == 'NOT_STARTED') ? -1
                       : (state == 'FULLY_PAID')  ? 24
                       : (state == 'OVERDUE')     ? 15
                       : (state == 'WRITTEN_OFF') ? 9 : 4;

    Opportunity p = new Opportunity(
        Name         = d.FirstName + ' ' + d.LastName + ' - ' + total.setScale(0).format()
                       + ' pledge (seed)',
        npsp__Primary_Contact__c = d.Id,
        Amount       = total,
        CloseDate    = TODAY.addMonths(-monthsBack),
        StageName    = 'Pledged',
        RecordTypeId = pledgeRt,
        Approach__c  = 'Major Gift',
        npe01__Do_Not_Automatically_Create_Payment__c = true,   // we build the schedule ourselves
        npsp__Acknowledgment_Status__c = 'Acknowledged',
        npsp__Acknowledgment_Date__c   = TODAY.addMonths(-monthsBack).addDays(3)
    );
    if (campByName.containsKey('FY27 Annual Campaign')) {
        p.CampaignId = campByName.get('FY27 Annual Campaign');
    }
    pledges.add(p);
    planned.add(state);
}
insert pledges;

// ---- installment schedules -------------------------------------------------------------------
// Four quarterly installments each. Which are paid, unpaid or written off is what creates the
// five states above.
List<npe01__OppPayment__c> pays = new List<npe01__OppPayment__c>();
for (Integer i = 0; i < pledges.size(); i++) {
    Opportunity p = pledges[i];
    String state  = planned[i];
    Decimal each  = (p.Amount / 4).setScale(2);

    for (Integer q = 0; q < 4; q++) {
        Date due = p.CloseDate.addMonths(q * 3);
        // Last installment absorbs any rounding remainder so the schedule sums to the pledge.
        Decimal amt = (q == 3) ? p.Amount - (each * 3) : each;

        npe01__OppPayment__c pay = new npe01__OppPayment__c(
            npe01__Opportunity__c    = p.Id,
            npe01__Payment_Amount__c = amt,
            npe01__Scheduled_Date__c = due,
            npe01__Payment_Method__c = (Math.mod(q, 2) == 0) ? 'Check' : 'Credit Card'
        );

        Boolean isPast = due <= TODAY;
        if (state == 'FULLY_PAID') {
            pay.npe01__Paid__c = true;
            pay.npe01__Payment_Date__c = due;
        } else if (state == 'ON_SCHEDULE') {
            // Everything already due has been paid - the well-behaved donor.
            pay.npe01__Paid__c = isPast;
            if (isPast) { pay.npe01__Payment_Date__c = due; }
        } else if (state == 'OVERDUE') {
            // Paid the first, then stopped - so at least one past installment is outstanding.
            pay.npe01__Paid__c = (q == 0);
            if (q == 0) { pay.npe01__Payment_Date__c = due; }
        } else if (state == 'WRITTEN_OFF') {
            if (q == 0) {
                pay.npe01__Paid__c = true;
                pay.npe01__Payment_Date__c = due;
            } else if (q == 1) {
                pay.npe01__Written_Off__c = true;   // must not count as outstanding
            }
        }
        // NOT_STARTED leaves every installment unpaid and in the future.
        pays.add(pay);
    }
}
insert pays;

Integer totalPledges = [SELECT COUNT() FROM Opportunity
                        WHERE RecordTypeId = :pledgeRt AND Name LIKE '%(seed)%'];
System.debug('created ' + pledges.size() + ' pledges and ' + pays.size() + ' installments'
    + ' | seeded pledges ' + totalPledges + ' of ' + TARGET);
System.debug(totalPledges < TARGET ? 'RUN AGAIN' : 'TARGET REACHED');
