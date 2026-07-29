/**
 * boardMembers — current board roster (JSI-123). Lists everyone currently serving with term + commitment
 * progress; add a new board member (creates the term + auto-generated years) and end a term from the row.
 * Author: Jason Ott.
 */
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCurrentBoardMembers from '@salesforce/apex/BoardMembersController.getCurrentBoardMembers';
import getMemberTypes from '@salesforce/apex/BoardMembersController.getMemberTypes';
import createBoardTerm from '@salesforce/apex/BoardMembersController.createBoardTerm';
import endBoardTerm from '@salesforce/apex/BoardMembersController.endBoardTerm';

const COLUMNS = [
    { label: 'Board Member', fieldName: 'contactUrl', type: 'url',
      typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
    { label: 'Type', fieldName: 'memberType' },
    { label: 'Role', fieldName: 'role' },
    { label: 'Term', fieldName: 'termYears' },
    { label: 'Expiring Soon', fieldName: 'expiringLabel' },
    { label: 'Must Roll Off', fieldName: 'rollOffLabel' },
    { label: 'Commitment', fieldName: 'commitmentDisplay' },
    { label: '% Met', fieldName: 'pctDisplay' },
    { type: 'action', typeAttributes: { rowActions: [{ label: 'End Term', name: 'endTerm' }] } }
];

export default class BoardMembers extends LightningElement {
    columns = COLUMNS;
    rows = [];
    wiredResult;
    error;

    memberTypeOptions = [];

    // add-member modal
    showAddMember = false;
    newContactId = null;
    newMemberTypeId = null;
    newStartDate = null;

    // end-term modal
    showEndTerm = false;
    endTermId = null;
    endTermName = '';
    endDate = null;

    @wire(getCurrentBoardMembers)
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((r) => ({
                ...r,
                contactUrl: '/' + r.contactId,
                expiringLabel: r.expiringSoon ? '⚠ Yes' : '',
                rollOffLabel: r.mustRollOff ? '⛔ Yes' : '',
                commitmentDisplay: r.commitment != null ? '$' + Number(r.commitment).toLocaleString() : '—',
                pctDisplay: r.pctMet != null ? Math.round(r.pctMet) + '%' : '—'
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.rows = [];
        }
    }

    @wire(getMemberTypes)
    wiredTypes({ data }) {
        if (data) {
            this.memberTypeOptions = data;
        }
    }

    get hasRows() { return this.rows && this.rows.length > 0; }
    get count() { return this.rows ? this.rows.length : 0; }

    // ---- add member ----
    openAddMember() {
        this.newContactId = null; this.newMemberTypeId = null; this.newStartDate = null;
        this.showAddMember = true;
    }
    closeAddMember() { this.showAddMember = false; }
    handleContact(e) { this.newContactId = e.detail.recordId; }
    handleType(e) { this.newMemberTypeId = e.detail.value; }
    handleStart(e) { this.newStartDate = e.detail.value; }
    createMember() {
        if (!this.newContactId || !this.newMemberTypeId || !this.newStartDate) {
            this.toast('Contact, type, and start date are required', 'warning');
            return;
        }
        createBoardTerm({ contactId: this.newContactId, memberTypeId: this.newMemberTypeId,
            startDate: this.newStartDate })
            .then(() => { this.showAddMember = false; this.toast('Board member added', 'success');
                return refreshApex(this.wiredResult); })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    // ---- end term ----
    handleRowAction(event) {
        if (event.detail.action.name !== 'endTerm') { return; }
        const row = event.detail.row;
        this.endTermId = row.termId;
        this.endTermName = row.name;
        this.endDate = null;
        this.showEndTerm = true;
    }
    closeEndTerm() { this.showEndTerm = false; }
    handleEndDate(e) { this.endDate = e.detail.value; }
    confirmEndTerm() {
        if (!this.endDate) { this.toast('Pick an end date', 'warning'); return; }
        endBoardTerm({ boardTermId: this.endTermId, endDate: this.endDate })
            .then(() => { this.showEndTerm = false; this.toast('Term ended', 'success');
                return refreshApex(this.wiredResult); })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    get endTermTitle() {
        return this.endTermName ? `End Term — ${this.endTermName}` : 'End Term';
    }

    toast(message, variant) { this.dispatchEvent(new ShowToastEvent({ title: message, variant })); }
    msg(err) { return (err && err.body && err.body.message) ? err.body.message : 'Something went wrong'; }
}
