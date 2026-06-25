/**
 * @description Tests for TagManagerController (JSI-122). Covers search (with starts-with ordering
 *              and exclusion of already-applied tags), apply, inline create-and-apply (new + reuse),
 *              duplicate guards, remove, validation of unsupported objects, and canCreateTags.
 * @author Jason Ott
 * @created 2026-06-24
 *
 * Change Log:
 * -----------
 * 2026-06-24 - Jason Ott - Initial version (JSI-122 phase 3).
 */
@isTest
private class TagManagerControllerTest {

    @testSetup
    static void setup() {
        // A handful of tags spanning categories. Before-save flow stamps Tag_Key__c.
        insert new List<Tag__c>{
            new Tag__c(Name = 'Board Member', Category__c = 'General'),
            new Tag__c(Name = 'Board Chair', Category__c = 'General'),
            new Tag__c(Name = 'Volunteer', Category__c = 'Skills'),
            new Tag__c(Name = 'Major Donor', Category__c = 'General')
        };
        insert new Account(Name = 'Test Org');
        insert new Contact(LastName = 'Tester');
    }

    private static Id contactId() { return [SELECT Id FROM Contact LIMIT 1].Id; }
    private static Id accountId() { return [SELECT Id FROM Account LIMIT 1].Id; }
    private static Id tagId(String name) { return [SELECT Id FROM Tag__c WHERE Name = :name LIMIT 1].Id; }

    @isTest
    static void testSearch_startsWithFirst_andExcludesApplied() {
        Id cId = contactId();
        // Apply "Board Chair" so it should be excluded from results.
        TagManagerController.addTag(tagId('Board Chair'), cId, 'Contact');

        Test.startTest();
        List<TagManagerController.TagDTO> results = TagManagerController.searchTags('board', cId, 'Contact');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only "Board Member" should match (Board Chair is applied)');
        System.assertEquals('Board Member', results[0].name);
        System.assertEquals('General', results[0].category);
    }

    @isTest
    static void testSearch_containsBranch() {
        // "member" matches "Board Member" in the middle (not starts-with) -> exercises the
        // contains branch and the term-not-at-start ordering.
        Test.startTest();
        List<TagManagerController.TagDTO> results =
            TagManagerController.searchTags('member', contactId(), 'Contact');
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals('Board Member', results[0].name);
    }

    @isTest
    static void testAddTag_andGetAssignments() {
        Id aId = accountId();
        Test.startTest();
        TagManagerController.AssignmentDTO dto = TagManagerController.addTag(tagId('Volunteer'), aId, 'Account');
        Test.stopTest();

        System.assertNotEquals(null, dto.assignmentId);
        System.assertEquals('Volunteer', dto.name);
        List<TagManagerController.AssignmentDTO> current = TagManagerController.getAssignments(aId, 'Account');
        System.assertEquals(1, current.size());
        System.assertEquals('Volunteer', current[0].name);
    }

    @isTest
    static void testAddTag_duplicateBlocked() {
        Id cId = contactId();
        TagManagerController.addTag(tagId('Major Donor'), cId, 'Contact');
        Test.startTest();
        Boolean blocked = false;
        try {
            TagManagerController.addTag(tagId('Major Donor'), cId, 'Contact');
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();
        System.assert(blocked, 'Applying the same tag twice should be blocked');
    }

    @isTest
    static void testCreateAndAddTag_new() {
        Id cId = contactId();
        Test.startTest();
        TagManagerController.AssignmentDTO dto =
            TagManagerController.createAndAddTag('Hiking', 'Hobbies', cId, 'Contact');
        Test.stopTest();

        System.assertEquals('Hiking', dto.name);
        System.assertEquals('Hobbies', dto.category);
        System.assertEquals(1, [SELECT COUNT() FROM Tag__c WHERE Name = 'Hiking' AND Category__c = 'Hobbies']);
    }

    @isTest
    static void testCreateAndAddTag_reusesExistingCaseInsensitive() {
        Id cId = contactId();
        Integer before = [SELECT COUNT() FROM Tag__c];
        Test.startTest();
        // Different case of an existing tag in the same category -> should reuse, not create.
        TagManagerController.AssignmentDTO dto =
            TagManagerController.createAndAddTag('VOLUNTEER', 'Skills', cId, 'Contact');
        Test.stopTest();

        System.assertEquals(tagId('Volunteer'), dto.tagId, 'Should reuse the existing Volunteer tag');
        System.assertEquals(before, [SELECT COUNT() FROM Tag__c], 'No new tag should be created');
    }

    @isTest
    static void testCreateAndAddTag_validationErrors() {
        Id cId = contactId();
        Integer errs = 0;
        Test.startTest();
        try { TagManagerController.createAndAddTag('   ', 'General', cId, 'Contact'); }
        catch (AuraHandledException e) { errs++; }
        try { TagManagerController.createAndAddTag('Name', '', cId, 'Contact'); }
        catch (AuraHandledException e) { errs++; }
        Test.stopTest();
        System.assertEquals(2, errs, 'Blank name and blank category should both error');
    }

    @isTest
    static void testRemoveAssignment() {
        Id cId = contactId();
        TagManagerController.AssignmentDTO dto = TagManagerController.addTag(tagId('Volunteer'), cId, 'Contact');
        Test.startTest();
        TagManagerController.removeAssignment(dto.assignmentId);
        Test.stopTest();
        System.assertEquals(0, TagManagerController.getAssignments(cId, 'Contact').size());
        // Removing a non-existent id should be a no-op (no exception).
        TagManagerController.removeAssignment(dto.assignmentId);
    }

    @isTest
    static void testUnsupportedObject() {
        Boolean threw = false;
        try {
            TagManagerController.searchTags('x', accountId(), 'Opportunity');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Unsupported object should throw');
    }

    @isTest
    static void testCanCreateTags() {
        System.assertEquals(true, TagManagerController.canCreateTags(), 'Admin running user can create tags');
    }
}
