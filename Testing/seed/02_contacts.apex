/**
 * Seed 2 of 4 — constituents.
 *
 * Invented people. Names are assembled from common given/family names so nothing here is a
 * real person; addresses use "Test" street names and 555 phone numbers (reserved for fiction),
 * and every email is at example.com, a domain reserved by RFC 2606 that cannot deliver
 * anywhere real. That last point matters: this org has live email automation, and seeded
 * donors must not be able to receive anything.
 *
 * RE-RUNNABLE. Each run adds the next 60 constituents, up to the target. Run it three times.
 *
 * Jason Ott, 2026-08-21.
 */
Integer TARGET     = 180;
Integer BATCH_SIZE = 60;
// Seeded constituents are identified by their email domain rather than a marker field -
// Contact.Description is not available in this org, and example.com is unambiguous.
Integer already = [SELECT COUNT() FROM Contact WHERE Email LIKE '%@example.com'];
if (already >= TARGET) {
    System.debug('already at target: ' + already + ' seeded constituents. Nothing to do.');
    return;
}

List<String> FIRST = new List<String>{
    'Miriam','David','Sarah','Jonathan','Rachel','Daniel','Naomi','Benjamin','Leah','Aaron',
    'Esther','Samuel','Hannah','Michael','Rebecca','Joshua','Deborah','Elliot','Shira','Adam',
    'Judith','Marc','Ruth','Gabriel','Tamar','Andrew','Ilana','Jeffrey','Yael','Steven',
    'Carol','Anthony','Grace','Marcus','Priya','Kevin','Aisha','Thomas','Maria','James',
    'Sofia','Robert','Nia','Christopher','Elena','Patrick','Amara','Daniel','Rosa','Victor'
};
List<String> LAST = new List<String>{
    'Adelstein','Bergman','Cohen','Dreyfus','Eisenberg','Feldman','Goldstein','Hirsch',
    'Isaacson','Jaffe','Kaplan','Levine','Mandelbaum','Nussbaum','Oppenheim','Perlman',
    'Rosenthal','Shapiro','Tannenbaum','Ullman','Vogel','Weinstein','Zimmerman','Abrams',
    'Baumgarten','Chernov','Diamant','Ehrlich','Frankel','Gottlieb','Halpern','Kessler',
    'Lieberman','Moskowitz','Newman','Ostrow','Pincus','Rabinowitz','Steinberg','Turner',
    'Okonkwo','Ramirez','Chen','Delgado','Nguyen','Fitzgerald','Osei','Castellano','Park','Silva'
};
List<String> CITIES = new List<String>{
    'New York','Brooklyn','Queens','Bronx','Staten Island','Great Neck','Roslyn',
    'White Plains','Scarsdale','Riverdale'
};
List<String> ZIPS = new List<String>{
    '10018','11215','11375','10463','10301','11021','11576','10601','10583','10471'
};

List<Contact> batch = new List<Contact>();
Integer created = 0;
for (Integer n = already; n < Math.min(already + BATCH_SIZE, TARGET); n++) {
    String fname = FIRST[Math.mod(n * 7, FIRST.size())];
    String lname = LAST[Math.mod(n * 13 + (n / FIRST.size()), LAST.size())];
    Integer cityIx = Math.mod(n, CITIES.size());
    batch.add(new Contact(
        FirstName         = fname,
        LastName          = lname,
        Email             = fname.toLowerCase() + '.' + lname.toLowerCase() + n + '@example.com',
        Phone             = '(212) 555-' + String.valueOf(1000 + n).right(4),
        MailingStreet     = String.valueOf(10 + Math.mod(n * 17, 900)) + ' Test Street'
                            + (Math.mod(n, 4) == 0 ? ', Apt ' + String.valueOf(Math.mod(n, 20) + 1) : ''),
        MailingCity       = CITIES[cityIx],
        MailingState      = 'NY',
        MailingPostalCode = ZIPS[cityIx],
        MailingCountry    = 'United States'
    ));
    created++;
}
Database.SaveResult[] results = Database.insert(batch, false);
Integer failed = 0;
for (Database.SaveResult r : results) {
    if (!r.isSuccess()) {
        failed++;
        if (failed <= 3) { System.debug('  refused: ' + r.getErrors()[0].getMessage()); }
    }
}
if (failed > 0) { System.debug(failed + ' refused (usually a duplicate rule) - not fatal'); }

Integer total = [SELECT COUNT() FROM Contact WHERE Email LIKE '%@example.com'];
System.debug('created ' + created + ' this run | seeded total ' + total + ' of ' + TARGET);
if (total < TARGET) {
    System.debug('RUN AGAIN - ' + (TARGET - total) + ' still to create.');
} else {
    System.debug('TARGET REACHED. All contacts: ' + [SELECT COUNT() FROM Contact]);
}
