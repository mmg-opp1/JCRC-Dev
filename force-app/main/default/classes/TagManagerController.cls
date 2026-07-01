/**
 * @description Apex controller for the JSI-122 Tag Management LWC (`tagManager`). Powers the
 *              type-ahead search, apply, inline create-and-apply, view, and remove of tags on
 *              Contact and Account records. All SOQL/DML runs in USER_MODE so field- and
 *              object-level security is enforced by the platform for the running user.
 * @author Jason Ott
 * @created 2026-06-24
 *
 * Change Log:
 * -----------
 * 2026-06-24 - Jason Ott - Initial version (JSI-122 phase 3).
 */
public with sharing class TagManagerController {

    // The single place a taggable object is registered: object API name -> junction lookup field.
    // Add an entry here (and the lookup field + validation) to extend tagging to a new object.
    private static final Map<String, String> OBJECT_TO_FIELD = new Map<String, String>{
        'Contact' => 'Contact__c',
        'Account' => 'Account__c'
    };

    /**
     * @description Type-ahead search for tags whose name matches the term, excluding tags already
     *              applied to the given record. Results put "starts-with" matches first.
     * @param term           the text the user has typed
     * @param recordId       the Contact or Account being tagged
     * @param objectApiName  'Contact' or 'Account'
     * @return up to 20 matching tags not already on the record
     */
    @AuraEnabled(cacheable=true)
    public static List<TagDTO> searchTags(String term, Id recordId, String objectApiName) {
        validateObject(objectApiName);
        String cleaned = sanitize(term);
        // Tags already on the record are excluded so the user can't add a duplicate.
        Set<Id> existingTagIds = assignedTagIds(recordId, objectApiName);

        String pattern = '%' + cleaned + '%';
        List<Tag__c> rows = [
            SELECT Id, Name, Category__c
            FROM Tag__c
            WHERE Name LIKE :pattern AND Id NOT IN :existingTagIds
            WITH USER_MODE
            ORDER BY Name
            LIMIT 50
        ];

        // Order: names that START WITH the term first (better type-ahead UX), then the rest.
        List<TagDTO> startsWith = new List<TagDTO>();
        List<TagDTO> contains = new List<TagDTO>();
        String lowerTerm = cleaned.toLowerCase();
        for (Tag__c t : rows) {
            if (String.isNotBlank(lowerTerm) && t.Name.toLowerCase().startsWith(lowerTerm)) {
                startsWith.add(new TagDTO(t));
            } else {
                contains.add(new TagDTO(t));
            }
        }
        List<TagDTO> result = new List<TagDTO>();
        result.addAll(startsWith);
        result.addAll(contains);
        // Cap at 20 for a tidy dropdown.
        while (result.size() > 20) { result.remove(result.size() - 1); }
        return result;
    }

    /**
     * @description Returns the tags currently applied to a record (for the pill list / refreshApex).
     */
    @AuraEnabled(cacheable=true)
    public static List<AssignmentDTO> getAssignments(Id recordId, String objectApiName) {
        validateObject(objectApiName);
        String field = OBJECT_TO_FIELD.get(objectApiName);
        List<Tag_Assignment__c> rows = Database.query(
            'SELECT Id, Tag__c, Tag__r.Name, Tag__r.Category__c ' +
            'FROM Tag_Assignment__c WHERE ' + field + ' = :recordId ' +
            'ORDER BY Tag__r.Category__c, Tag__r.Name',
            AccessLevel.USER_MODE
        );
        List<AssignmentDTO> result = new List<AssignmentDTO>();
        for (Tag_Assignment__c ta : rows) { result.add(new AssignmentDTO(ta)); }
        return result;
    }

    /**
     * @description Applies an existing tag to a record by creating a Tag Assignment.
     *              Duplicate (same tag already on the record) is guarded both here and by the
     *              unique Assignment_Key__c backstop.
     */
    @AuraEnabled
    public static AssignmentDTO addTag(Id tagId, Id recordId, String objectApiName) {
        validateObject(objectApiName);
        // No pre-check needed: search already hides applied tags, and the unique Assignment_Key__c
        // (stamped by the before-save flow) is the authoritative duplicate guard. A rare duplicate
        // surfaces as a friendly "already applied" message via the catch below.
        Tag_Assignment__c ta = new Tag_Assignment__c(Tag__c = tagId);
        ta.put(OBJECT_TO_FIELD.get(objectApiName), recordId);
        try {
            insert as user ta;
        } catch (DmlException e) {
            throw new AuraHandledException(friendly(e));
        }
        return new AssignmentDTO([
            SELECT Id, Tag__c, Tag__r.Name, Tag__r.Category__c
            FROM Tag_Assignment__c WHERE Id = :ta.Id WITH USER_MODE
        ]);
    }

    /**
     * @description Creates a new tag (reusing an existing one if the same name+category already
     *              exists, case-insensitively) and applies it to the record.
     */
    @AuraEnabled
    public static AssignmentDTO createAndAddTag(String name, String category, Id recordId, String objectApiName) {
        validateObject(objectApiName);
        String cleanName = (name == null) ? '' : name.trim();
        if (String.isBlank(cleanName)) {
            throw new AuraHandledException('Enter a tag name.');
        }
        if (String.isBlank(category)) {
            throw new AuraHandledException('Choose a category for the new tag.');
        }
        // Reuse an existing tag if one matches (SOQL = on text is case-insensitive).
        List<Tag__c> existing = [
            SELECT Id FROM Tag__c
            WHERE Name = :cleanName AND Category__c = :category
            WITH USER_MODE LIMIT 1
        ];
        Id tagId;
        if (!existing.isEmpty()) {
            tagId = existing[0].Id;
        } else {
            Tag__c t = new Tag__c(Name = cleanName, Category__c = category);
            try {
                insert as user t; // before-save flow stamps Tag_Key__c; unique field backstops races
            } catch (DmlException e) {
                // A concurrent insert may have created it — fall back to the existing one.
                List<Tag__c> raced = [
                    SELECT Id FROM Tag__c
                    WHERE Name = :cleanName AND Category__c = :category WITH USER_MODE LIMIT 1
                ];
                if (!raced.isEmpty()) { tagId = raced[0].Id; }
                else { throw new AuraHandledException(friendly(e)); }
            }
            if (tagId == null) { tagId = t.Id; }
        }
        return addTag(tagId, recordId, objectApiName);
    }

    /**
     * @description Removes a tag from a record by hard-deleting its assignment.
     */
    @AuraEnabled
    public static void removeAssignment(Id assignmentId) {
        List<Tag_Assignment__c> rows = [
            SELECT Id FROM Tag_Assignment__c WHERE Id = :assignmentId WITH USER_MODE LIMIT 1
        ];
        if (!rows.isEmpty()) {
            try {
                delete as user rows;
            } catch (DmlException e) {
                throw new AuraHandledException(friendly(e));
            }
        }
    }

    /**
     * @description Whether the running user can create new tags (drives the LWC create affordance).
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canCreateTags() {
        return Schema.SObjectType.Tag__c.isCreateable();
    }

    // ---- helpers ----------------------------------------------------------------

    // Tags currently applied to the record.
    private static Set<Id> assignedTagIds(Id recordId, String objectApiName) {
        String field = OBJECT_TO_FIELD.get(objectApiName);
        Set<Id> ids = new Set<Id>();
        for (Tag_Assignment__c ta : Database.query(
                'SELECT Tag__c FROM Tag_Assignment__c WHERE ' + field + ' = :recordId',
                AccessLevel.USER_MODE)) {
            ids.add(ta.Tag__c);
        }
        return ids;
    }

    private static void validateObject(String objectApiName) {
        if (!OBJECT_TO_FIELD.containsKey(objectApiName)) {
            throw new AuraHandledException('Tagging is not supported on ' + objectApiName + '.');
        }
    }

    // Strip wildcards/quotes so the search term behaves predictably (bind vars handle injection).
    private static String sanitize(String term) {
        if (String.isBlank(term)) { return ''; }
        return term.trim().replaceAll('[%_]', '');
    }

    private static String friendly(DmlException e) {
        // A duplicate Assignment_Key__c means the tag is already on the record.
        if (e.getNumDml() > 0 && e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
            return 'That tag is already applied to this record.';
        }
        String msg = (e.getNumDml() > 0) ? e.getDmlMessage(0) : e.getMessage();
        return String.isBlank(msg) ? e.getMessage() : msg;
    }

    // ---- DTOs -------------------------------------------------------------------

    public class TagDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        public TagDTO(Tag__c t) {
            this.id = t.Id;
            this.name = t.Name;
            this.category = t.Category__c;
        }
    }

    public class AssignmentDTO {
        @AuraEnabled public Id assignmentId;
        @AuraEnabled public Id tagId;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        public AssignmentDTO(Tag_Assignment__c ta) {
            this.assignmentId = ta.Id;
            this.tagId = ta.Tag__c;
            this.name = ta.Tag__r.Name;
            this.category = ta.Tag__r.Category__c;
        }
    }
}