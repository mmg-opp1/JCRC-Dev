/**
 * boardMembers — current board roster (JSI-123). Lists everyone currently serving with term + commitment
 * progress; add a new board member (creates the term + auto-generated years) and end a term from the row.
 * Author: Jason Ott.
 *
 * Change Log:
 * -----------
 * 2026-09-01 - Jason Ott - New Board Member: lock the modal and show a spinner while the save is in
 *                          flight. Testers read the pause as a hang and clicked again, and every click
 *                          created another Board Term. Server-side backstop is in BoardMembersController.
 * 2026-09-01 - Jason Ott - Added Delete Board Member to the row menu, for someone added by mistake.
 *                          Refuses when there is meeting attendance, and never deletes the Contact.
 * 2026-09-01 - Jason Ott - The roster is loaded on mount rather than wired, so a Board Term edited
 *                          elsewhere - the related list on a Contact, say - is picked up on arrival
 *                          instead of being served stale from the Lightning cache (UAT).
 * 2026-09-01 - Jason Ott - Mount was not enough: Lightning hands back the same live component when
 *                          you navigate back, so connectedCallback never ran again and the roster
 *                          still showed the old values. Reload on CurrentPageReference, and give the
 *                          card a Refresh button so it never depends on that alone.
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCurrentBoardMembers from '@salesforce/apex/BoardMembersController.getCurrentBoardMembers';
import getMemberTypes from '@salesforce/apex/BoardMembersController.getMemberTypes';
import createBoardTerm from '@salesforce/apex/BoardMembersController.createBoardTerm';
import endBoardTerm from '@salesforce/apex/BoardMembersController.endBoardTerm';
import getDeleteImpact from '@salesforce/apex/BoardMembersController.getDeleteImpact';
import deleteBoardMemberApex from '@salesforce/apex/BoardMembersController.deleteBoardMember';

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
    { type: 'action', typeAttributes: { rowActions: [
        { label: 'End Term', name: 'endTerm' },
        { label: 'Delete Board Member', name: 'deleteMember' }] } }
];

export default class BoardMembers extends LightningElement {
    columns = COLUMNS;
    rows = [];
    loadingRoster = false;
    seenFirstPageRef = false;
    error;

    memberTypeOptions = [];

    // add-member modal
    showAddMember = false;
    newContactId = null;
    newMemberTypeId = null;
    newStartDate = null;
    // True from the moment the Add Member click is accepted until the Apex call settles. Drives the
    // spinner and disables every control in the modal, so a second click can never reach the server.
    isSaving = false;

    // delete-member modal. `deleteImpact` is what the server said would be removed; it drives both
    // the refusal message and the confirmation, so the two can never disagree about the numbers.
    showDelete = false;
    deleteContactId = null;
    deleteImpact = null;
    isDeleting = false;
    checkingDelete = false;

    // end-term modal
    showEndTerm = false;
    endTermId = null;
    endTermName = '';
    endDate = null;
    isEndingTerm = false;

    connectedCallback() {
        this.loadRoster();
    }

    /**
     * Reload whenever the user arrives at this page.
     *
     * connectedCallback is not enough on its own. Lightning keeps a recently visited page alive and
     * hands the same component instance back when you return - which is why the console reopened on
     * whichever tab you left it on, and why an edit made on a Contact in between was never picked
     * up. CurrentPageReference emits on each arrival, including for a restored instance whose
     * connectedCallback will not run a second time.
     *
     * The first emission is skipped because connectedCallback has just loaded the same data.
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef) { return; }
        if (!this.seenFirstPageRef) { this.seenFirstPageRef = true; return; }
        this.loadRoster();
    }

    /**
     * Read the roster from the server. Called on mount and after anything this screen changes, so
     * the list is never older than the moment the user arrived. Returns the promise so callers can
     * hold their in-flight lock until the table has actually redrawn.
     */
    loadRoster() {
        this.loadingRoster = true;
        return getCurrentBoardMembers()
            .then((data) => {
                this.rows = data.map((r) => ({
                    ...r,
                    contactUrl: '/' + r.contactId,
                    expiringLabel: r.expiringSoon ? '⚠ Yes' : '',
                    rollOffLabel: r.mustRollOff ? '⛔ Yes' : '',
                    commitmentDisplay: r.commitment != null ? '$' + Number(r.commitment).toLocaleString() : '—',
                    pctDisplay: r.pctMet != null ? Math.round(r.pctMet) + '%' : '—'
                }));
                this.error = undefined;
            })
            .catch((err) => {
                // Say so rather than showing an empty roster, which reads as "nobody is on the board".
                this.error = err;
                this.rows = [];
                this.toast(this.msg(err), 'error');
            })
            .finally(() => { this.loadingRoster = false; });
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
    get addMemberLabel() { return this.isSaving ? 'Adding…' : 'Add Member'; }

    openAddMember() {
        this.newContactId = null; this.newMemberTypeId = null; this.newStartDate = null;
        this.isSaving = false;
        this.showAddMember = true;
    }
    closeAddMember() {
        if (this.isSaving) { return; }   // never abandon the modal on top of a save already running
        this.showAddMember = false;
    }
    handleContact(e) { this.newContactId = e.detail.recordId; }
    handleType(e) { this.newMemberTypeId = e.detail.value; }
    handleStart(e) { this.newStartDate = e.detail.value; }
    createMember() {
        // Re-entry guard. `disabled` only takes effect on the next render, so a fast second click can
        // still land on the live button; this rejects it synchronously, before any Apex call is made.
        if (this.isSaving) { return; }
        if (!this.newContactId || !this.newMemberTypeId || !this.newStartDate) {
            this.toast('Contact, type, and start date are required', 'warning');
            return;
        }
        this.isSaving = true;
        createBoardTerm({ contactId: this.newContactId, memberTypeId: this.newMemberTypeId,
            startDate: this.newStartDate })
            .then(() => { this.showAddMember = false; this.toast('Board member added', 'success');
                return this.loadRoster(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            // Released only once the roster refresh has settled too, so the modal stays locked for the
            // whole visible pause rather than unlocking while the table is still redrawing.
            .finally(() => { this.isSaving = false; });
    }

    // ---- row menu ----
    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'endTerm') {
            this.openEndTerm(row);
        } else if (action === 'deleteMember') {
            this.openDelete(row);
        }
    }

    // ---- delete board member ----
    /**
     * Ask the server what the delete would remove before showing anything. Whether this ends up as
     * a refusal or as a confirmation depends on the answer, so there is nothing useful to display
     * until it arrives - hence the row-level spinner rather than a modal that changes its mind.
     */
    openDelete(row) {
        if (this.checkingDelete) { return; }
        this.checkingDelete = true;
        this.deleteContactId = row.contactId;
        this.deleteImpact = null;
        this.isDeleting = false;
        getDeleteImpact({ contactId: row.contactId })
            .then((impact) => { this.deleteImpact = impact; this.showDelete = true; })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.checkingDelete = false; });
    }
    closeDelete() {
        if (this.isDeleting) { return; }
        this.showDelete = false;
        this.deleteImpact = null;
    }
    confirmDelete() {
        if (this.isDeleting) { return; }
        this.isDeleting = true;
        deleteBoardMemberApex({ contactId: this.deleteContactId })
            .then(() => {
                this.showDelete = false;
                this.toast(`${this.deleteName} removed from the board`, 'success');
                return this.loadRoster();
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.isDeleting = false; });
    }

    get deleteName() {
        return this.deleteImpact ? this.deleteImpact.contactName : 'This board member';
    }
    get deleteBlocked() {
        return this.deleteImpact ? this.deleteImpact.blocked === true : false;
    }
    get deleteTitle() {
        return this.deleteBlocked
            ? `Can't delete ${this.deleteName}`
            : `Delete ${this.deleteName} from the board?`;
    }
    get deleteButtonLabel() { return this.isDeleting ? 'Deleting\u2026' : 'Delete Board Member'; }
    /** e.g. "2 terms and 12 board years" - singular where it matters, because the numbers are small. */
    get deleteSummary() {
        if (!this.deleteImpact) { return ''; }
        return `${this.plural(this.deleteImpact.termCount, 'term')} and `
            + `${this.plural(this.deleteImpact.yearCount, 'board year')}`;
    }
    get deleteBlockedDetail() {
        if (!this.deleteImpact) { return ''; }
        return `Attendance has been recorded for ${this.plural(this.deleteImpact.meetingCount, 'meeting')}, `
            + 'including any meeting they were marked absent for. Deleting their board record would '
            + 'delete that attendance with it.';
    }
    plural(n, word) {
        const count = n === null || n === undefined ? 0 : n;
        return `${count} ${word}${count === 1 ? '' : 's'}`;
    }

    // ---- end term ----
    openEndTerm(row) {
        this.endTermId = row.termId;
        this.endTermName = row.name;
        this.endDate = null;
        this.isEndingTerm = false;
        this.showEndTerm = true;
    }
    closeEndTerm() {
        if (this.isEndingTerm) { return; }
        this.showEndTerm = false;
    }
    handleEndDate(e) { this.endDate = e.detail.value; }
    confirmEndTerm() {
        // Ending a term also deletes the board years after the end date, so a second run while the
        // first is still going would work on a roster that is already being rewritten underneath it.
        if (this.isEndingTerm) { return; }
        if (!this.endDate) { this.toast('Pick an end date', 'warning'); return; }
        this.isEndingTerm = true;
        endBoardTerm({ boardTermId: this.endTermId, endDate: this.endDate })
            .then(() => { this.showEndTerm = false; this.toast('Term ended', 'success');
                return this.loadRoster(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.isEndingTerm = false; });
    }

    get endTermLabel() { return this.isEndingTerm ? 'Ending…' : 'End Term'; }

    get endTermTitle() {
        return this.endTermName ? `End Term — ${this.endTermName}` : 'End Term';
    }

    toast(message, variant) { this.dispatchEvent(new ShowToastEvent({ title: message, variant })); }
    msg(err) {
        if (!err) { return 'Something went wrong'; }
        if (Array.isArray(err.body)) { return err.body.map((e) => e.message).join(', '); }
        if (err.body && err.body.message) { return err.body.message; }
        if (err.body && err.body.pageErrors && err.body.pageErrors.length) { return err.body.pageErrors[0].message; }
        if (err.message) { return err.message; }
        return 'Something went wrong';
    }
}