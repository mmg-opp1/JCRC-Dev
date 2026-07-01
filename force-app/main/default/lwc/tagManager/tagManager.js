/**
 * @description LWC for JSI-122 Tag Management. Embedded on Contact and Account Lightning record
 *              pages: type-ahead search of existing tags (showing category), one-click apply,
 *              inline create-and-apply of a new tag (for authorized users), and view/remove of the
 *              record's current tags. All data access goes through TagManagerController (USER_MODE).
 * @author Jason Ott
 * @created 2026-06-24
 *
 * Change Log:
 * -----------
 * 2026-06-24 - Jason Ott - Initial version (JSI-122 phase 4).
 */
import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import CATEGORY_FIELD from '@salesforce/schema/Tag__c.Category__c';

import getAssignments from '@salesforce/apex/TagManagerController.getAssignments';
import searchTags from '@salesforce/apex/TagManagerController.searchTags';
import addTag from '@salesforce/apex/TagManagerController.addTag';
import createAndAddTag from '@salesforce/apex/TagManagerController.createAndAddTag';
import removeAssignment from '@salesforce/apex/TagManagerController.removeAssignment';
import canCreateTags from '@salesforce/apex/TagManagerController.canCreateTags';

// Master record type — Tag__c has no custom record types, so this returns all category values.
const MASTER_RECORD_TYPE_ID = '012000000000000AAA';

export default class TagManager extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track assignments = [];
    @track results = [];
    searchTerm = '';
    selectedCategory = '';
    categoryOptions = [];
    canCreate = false;
    loading = false;

    _wiredAssignments;
    _debounce;

    // ---- wires ----------------------------------------------------------------

    @wire(getAssignments, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wiredAssignments(result) {
        this._wiredAssignments = result;
        if (result.data) {
            this.assignments = result.data;
        } else if (result.error) {
            this.toast('Error', this.errMsg(result.error), 'error');
        }
    }

    @wire(getPicklistValues, { recordTypeId: MASTER_RECORD_TYPE_ID, fieldApiName: CATEGORY_FIELD })
    wiredCategories({ data }) {
        if (data) {
            this.categoryOptions = data.values.map((v) => ({ label: v.label, value: v.value }));
        }
    }

    connectedCallback() {
        canCreateTags()
            .then((res) => { this.canCreate = res; })
            .catch(() => { this.canCreate = false; });
    }

    // ---- derived state --------------------------------------------------------

    get hasAssignments() {
        return this.assignments && this.assignments.length > 0;
    }

    // Shape assignments for lightning-pill-container (label shown; index used on remove).
    get pillItems() {
        return this.assignments.map((a) => ({
            label: `${a.name} · ${a.category}`,
            name: a.assignmentId
        }));
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    // An exact (case-insensitive) match already exists — offer to apply it, not create a duplicate.
    get exactMatchExists() {
        const term = this.searchTerm.trim().toLowerCase();
        return this.results.some((r) => r.name.toLowerCase() === term);
    }

    // Show the inline "create" affordance only when it makes sense and the user is authorized.
    get showCreate() {
        return (
            this.canCreate &&
            this.searchTerm.trim().length > 0 &&
            !this.exactMatchExists &&
            !this.loading
        );
    }

    get createLabel() {
        return `+ Create "${this.searchTerm.trim()}"`;
    }

    get categoryChosen() {
        return this.selectedCategory !== '';
    }

    // ---- handlers -------------------------------------------------------------

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        window.clearTimeout(this._debounce);
        const term = this.searchTerm;
        // Debounce so we don't fire a query on every keystroke.
        this._debounce = window.setTimeout(() => this.runSearch(term), 300);
    }

    runSearch(term) {
        if (!term || term.trim().length === 0) {
            this.results = [];
            return;
        }
        searchTags({ term, recordId: this.recordId, objectApiName: this.objectApiName })
            .then((res) => { this.results = res; })
            .catch((error) => { this.toast('Search failed', this.errMsg(error), 'error'); });
    }

    handleSelect(event) {
        const tagId = event.currentTarget.dataset.id;
        this.loading = true;
        addTag({ tagId, recordId: this.recordId, objectApiName: this.objectApiName })
            .then(() => this.afterChange('Tag applied'))
            .catch((error) => this.toast('Could not apply tag', this.errMsg(error), 'error'))
            .finally(() => { this.loading = false; });
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
    }

    handleCreate() {
        if (!this.categoryChosen) {
            this.toast('Choose a category', 'Pick a category for the new tag.', 'warning');
            return;
        }
        this.loading = true;
        createAndAddTag({
            name: this.searchTerm.trim(),
            category: this.selectedCategory,
            recordId: this.recordId,
            objectApiName: this.objectApiName
        })
            .then(() => this.afterChange('Tag created and applied'))
            .catch((error) => this.toast('Could not create tag', this.errMsg(error), 'error'))
            .finally(() => { this.loading = false; });
    }

    handleRemove(event) {
        // pillItems is built in the same order as assignments, so the index aligns.
        const assignmentId = this.assignments[event.detail.index].assignmentId;
        removeAssignment({ assignmentId })
            .then(() => {
                this.toast('Tag removed', '', 'success');
                return refreshApex(this._wiredAssignments);
            })
            .catch((error) => this.toast('Could not remove tag', this.errMsg(error), 'error'));
    }

    // ---- helpers --------------------------------------------------------------

    afterChange(message) {
        this.searchTerm = '';
        this.results = [];
        this.selectedCategory = '';
        this.toast('Success', message, 'success');
        return refreshApex(this._wiredAssignments);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errMsg(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Unexpected error';
    }
}