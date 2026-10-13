/**
 * boardManagement — Board Management console (JSI-123). Tabs: Dashboard, Meetings & Attendance,
 * Committees, Roster. Author: Jason Ott.
 *
 * Change Log:
 * -----------
 * 2026-09-01 - Jason Ott - Lock each save button and show a spinner while its Apex call is running.
 *                          A tester read the pause on the roster's Add Member as a hang and clicked
 *                          again, which created the board member twice; every save button here had
 *                          the same gap. One flag per action, so saving attendance does not disable
 *                          an unrelated modal.
 * 2026-09-01 - Jason Ott - Committee members moved out of a card below the committee table and into a
 *                          modal, matching how everything else in the console works. Add Member hands
 *                          off to its own modal and comes back, so only one is ever on screen.
 * 2026-09-01 - Jason Ott - Meetings and committees are loaded on mount rather than wired, so a record
 *                          edited elsewhere is picked up on arrival instead of coming back stale from
 *                          the Lightning cache (UAT).
 * 2026-09-01 - Jason Ott - Mount was not enough - Lightning hands the same live component back when
 *                          you navigate in again. Reload on CurrentPageReference, plus Refresh
 *                          buttons on both cards.
 * 2026-09-02 - Jason Ott - Committees now have meetings of their own, with attendance taken the same
 *                          way as board meetings. Manage Meetings on a committee row opens the list;
 *                          from there New Meeting and Take Attendance each take over the screen and
 *                          hand back, so only one modal is ever up.
 * 2026-10-13 - Jason Ott - Manage Members: member names now link to the contact record, the same way
 *                          the Roster tab does (client feedback).
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMeetings from '@salesforce/apex/BoardManagementController.getMeetings';
import createMeetingApex from '@salesforce/apex/BoardManagementController.createMeeting';
import getAttendance from '@salesforce/apex/BoardManagementController.getAttendance';
import saveAttendanceApex from '@salesforce/apex/BoardManagementController.saveAttendance';
import getCommittees from '@salesforce/apex/BoardManagementController.getCommittees';
import saveCommitteeApex from '@salesforce/apex/BoardManagementController.saveCommittee';
import getAssignments from '@salesforce/apex/BoardManagementController.getAssignments';
import saveAssignmentApex from '@salesforce/apex/BoardManagementController.saveAssignment';
import removeAssignmentApex from '@salesforce/apex/BoardManagementController.removeAssignment';
import getCommitteeMeetings from '@salesforce/apex/BoardManagementController.getCommitteeMeetings';
import createCommitteeMeetingApex from '@salesforce/apex/BoardManagementController.createCommitteeMeeting';
import getCommitteeAttendance from '@salesforce/apex/BoardManagementController.getCommitteeAttendance';
import saveCommitteeAttendanceApex from '@salesforce/apex/BoardManagementController.saveCommitteeAttendance';
import deleteCommitteeMeetingApex from '@salesforce/apex/BoardManagementController.deleteCommitteeMeeting';

const MEETING_COLUMNS = [
    { label: 'Meeting', fieldName: 'name' },
    { label: 'Date', fieldName: 'meetingDate', type: 'date-local' },
    { label: 'Fiscal Year', fieldName: 'fiscalYearLabel' },
    { label: 'Attended', fieldName: 'attendedCount', type: 'number', cellAttributes: { alignment: 'left' } },
    { type: 'button', typeAttributes: { label: 'Take Attendance', name: 'open', variant: 'brand-outline' } }
];
const COMMITTEE_COLUMNS = [
    { label: 'Committee', fieldName: 'name' },
    { label: 'Category', fieldName: 'category' },
    { label: 'Executive', fieldName: 'isExecutive', type: 'boolean' },
    { label: 'Parent', fieldName: 'parentName' },
    { label: 'Active', fieldName: 'active', type: 'boolean' },
    { type: 'action', typeAttributes: { rowActions: [
        { label: 'Edit', name: 'edit' },
        { label: 'Manage Members', name: 'manage' },
        { label: 'Manage Meetings', name: 'meetings' }] } }
];
const COMMITTEE_MEETING_COLUMNS = [
    { label: 'Meeting', fieldName: 'name' },
    { label: 'Date', fieldName: 'meetingDate', type: 'date-local' },
    { label: 'Fiscal Year', fieldName: 'fiscalYearLabel' },
    { label: 'Attended', fieldName: 'attendedCount', type: 'number',
      cellAttributes: { alignment: 'left' } },
    { type: 'action', typeAttributes: { rowActions: [
        { label: 'Take Attendance', name: 'attendance' },
        { label: 'Delete Meeting', name: 'deleteMeeting' }] } }
];
const ASSIGNMENT_COLUMNS = [
    // Same link as the Roster tab: the name opens the contact record.
    { label: 'Member', fieldName: 'contactUrl', type: 'url',
      typeAttributes: { label: { fieldName: 'contactName' }, target: '_self' } },
    { label: 'Role', fieldName: 'role' },
    { label: 'Fiscal Year', fieldName: 'fiscalYearLabel' },
    { label: 'Active', fieldName: 'active', type: 'boolean' },
    { type: 'action', typeAttributes: { rowActions: [{ label: 'Remove', name: 'remove' }] } }
];
const CATEGORY_OPTIONS = [
    { label: 'Board Committee', value: 'Board Committee' },
    { label: 'Special Event Committee', value: 'Special Event Committee' }
];
const ROLE_OPTIONS = [
    { label: 'Chair', value: 'Chair' },
    { label: 'Co-Chair', value: 'Co-Chair' },
    { label: 'Member', value: 'Member' }
];

export default class BoardManagement extends LightningElement {
    meetingColumns = MEETING_COLUMNS;
    committeeColumns = COMMITTEE_COLUMNS;
    committeeMeetingColumns = COMMITTEE_MEETING_COLUMNS;
    assignmentColumns = ASSIGNMENT_COLUMNS;
    categoryOptions = CATEGORY_OPTIONS;
    roleOptions = ROLE_OPTIONS;

    // One in-flight flag per action rather than a single shared one: the attendance table and the
    // modals are on screen at the same time, and locking a button the user is not waiting on reads
    // as another fault rather than as feedback.
    seenFirstPageRef = false;
    loadingMeetings = false;
    loadingCommittees = false;
    savingMeeting = false;
    savingAttendance = false;
    savingCommittee = false;
    savingAssignment = false;

    // meetings
    meetings = [];
    attendees = [];
    selectedMeetingId;
    selectedMeetingName;
    showNewMeeting = false;
    newName = '';
    newDate = null;

    // committees
    committees = [];
    showCommitteeModal = false;
    cmId = null;
    cmName = '';
    cmCategory = 'Board Committee';
    cmIsExec = false;
    cmParentId = null;
    cmActive = true;
    selectedCommitteeId;
    selectedCommitteeName;
    assignments = [];
    showMembers = false;
    loadingAssignments = false;
    removingAssignment = false;
    // committee meetings: the list, the add form and the attendance sheet, each taking the screen
    // in turn and handing back to the list.
    showCommitteeMeetings = false;
    committeeMeetings = [];
    loadingCommitteeMeetings = false;
    showNewCommitteeMeeting = false;
    mtgName = '';
    mtgDate = null;
    savingCommitteeMeeting = false;
    showCommitteeAttendance = false;
    committeeAttendees = [];
    loadingCommitteeAttendance = false;
    savingCommitteeAttendance = false;
    selectedCommitteeMeetingId = null;
    selectedCommitteeMeetingName = '';
    showDeleteMeeting = false;
    deleteMeetingId = null;
    deleteMeetingName = '';
    deletingMeeting = false;

    showAddMember = false;
    amContactId = null;
    amRole = 'Member';
    amDate = null;

    connectedCallback() {
        this.loadMeetings();
        this.loadCommittees();
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
        this.loadMeetings();
        this.loadCommittees();
        // Only if a committee's members are actually on screen; otherwise there is nothing to reload.
        if (this.showMembers && this.selectedCommitteeId) { this.loadAssignments(); }
    }

    /** Both return their promise so a save can hold its in-flight lock until the table has redrawn. */
    loadMeetings() {
        this.loadingMeetings = true;
        return getMeetings()
            .then((data) => { this.meetings = data; })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.loadingMeetings = false; });
    }
    loadCommittees() {
        this.loadingCommittees = true;
        return getCommittees()
            .then((data) => { this.committees = data; })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.loadingCommittees = false; });
    }

    get createMeetingLabel() { return this.savingMeeting ? 'Creating\u2026' : 'Create'; }
    get saveAttendanceLabel() { return this.savingAttendance ? 'Saving\u2026' : 'Save Attendance'; }
    get saveCommitteeLabel() { return this.savingCommittee ? 'Saving\u2026' : 'Save'; }
    get addAssignmentLabel() { return this.savingAssignment ? 'Adding\u2026' : 'Add'; }

    get attendanceTitle() {
        return this.selectedMeetingName ? `Attendance — ${this.selectedMeetingName}` : 'Attendance';
    }
    get assignmentsTitle() {
        return this.selectedCommitteeName ? `Members — ${this.selectedCommitteeName}` : 'Members';
    }
    get hasAssignments() { return this.assignments && this.assignments.length > 0; }

    // ---------- meetings ----------
    openNewMeeting() {
        this.newName = ''; this.newDate = null; this.savingMeeting = false; this.showNewMeeting = true;
    }
    closeNewMeeting() {
        if (this.savingMeeting) { return; }
        this.showNewMeeting = false;
    }
    handleName(e) { this.newName = e.detail.value; }
    handleDate(e) { this.newDate = e.detail.value; }
    createMeeting() {
        // Synchronous guard: `disabled` only lands on the next render, so a fast second click can
        // still reach a button that is on its way to being disabled.
        if (this.savingMeeting) { return; }
        this.savingMeeting = true;
        createMeetingApex({ name: this.newName, meetingDate: this.newDate })
            .then(() => { this.showNewMeeting = false; this.toast('Meeting created', 'success');
                return this.loadMeetings(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingMeeting = false; });
    }
    handleMeetingAction(event) {
        if (event.detail.action.name !== 'open') { return; }
        const row = event.detail.row;
        this.selectedMeetingId = row.id;
        this.selectedMeetingName = row.name;
        getAttendance({ meetingId: row.id })
            // copy explicit fields into mutable rows (avoids any read-only-proxy spread quirk)
            .then((data) => {
                this.attendees = data.map((r) => ({
                    membershipYearId: r.membershipYearId,
                    contactId: r.contactId,
                    name: r.name,
                    attended: r.attended
                }));
            })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }
    handleAttendChange(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.attendees = this.attendees.map((a) =>
            a.membershipYearId === id ? { ...a, attended: checked } : a);
    }
    saveAttendance() {
        // Saving attendance upserts on the meeting + membership year, so a repeat click cannot create
        // duplicate rows. The lock is here because the roster is long enough for the save to look
        // stalled, and a second click during the first save writes ticks the user has since changed.
        if (this.savingAttendance) { return; }
        const rows = this.attendees.map((a) => ({
            membershipYearId: a.membershipYearId, attended: a.attended === true
        }));
        this.savingAttendance = true;
        saveAttendanceApex({ meetingId: this.selectedMeetingId, rowsJson: JSON.stringify(rows) })
            .then(() => { this.toast('Attendance saved', 'success'); return this.loadMeetings(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingAttendance = false; });
    }

    // ---------- committees ----------
    openNewCommittee() {
        this.cmId = null; this.cmName = ''; this.cmCategory = 'Board Committee';
        this.cmIsExec = false; this.cmParentId = null; this.cmActive = true;
        this.savingCommittee = false;
        this.showCommitteeModal = true;
    }
    closeCommitteeModal() {
        if (this.savingCommittee) { return; }
        this.showCommitteeModal = false;
    }
    handleCmName(e) { this.cmName = e.detail.value; }
    handleCmCategory(e) { this.cmCategory = e.detail.value; }
    handleCmExec(e) { this.cmIsExec = e.detail.checked; }
    handleCmActive(e) { this.cmActive = e.detail.checked; }
    handleCmParent(e) { this.cmParentId = e.detail.recordId; }
    saveCommittee() {
        // Editing an existing committee carries its Id and so is an update, but creating one has no
        // Id yet - two clicks there are two inserts, and the org ends up with the committee twice.
        if (this.savingCommittee) { return; }
        this.savingCommittee = true;
        saveCommitteeApex({ committeeId: this.cmId, name: this.cmName, category: this.cmCategory,
            isExecutive: this.cmIsExec, parentId: this.cmParentId, active: this.cmActive })
            .then(() => { this.showCommitteeModal = false; this.toast('Committee saved', 'success');
                return this.loadCommittees(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingCommittee = false; });
    }
    handleCommitteeAction(event) {
        const row = event.detail.row;
        if (event.detail.action.name === 'edit') {
            this.cmId = row.id; this.cmName = row.name; this.cmCategory = row.category || 'Board Committee';
            this.cmIsExec = row.isExecutive; this.cmParentId = row.parentId; this.cmActive = row.active;
            this.savingCommittee = false;
            this.showCommitteeModal = true;
        } else if (event.detail.action.name === 'manage') {
            this.selectedCommitteeId = row.id;
            this.selectedCommitteeName = row.name;
            this.openMembers();
        } else if (event.detail.action.name === 'meetings') {
            this.selectedCommitteeId = row.id;
            this.selectedCommitteeName = row.name;
            this.openCommitteeMeetings();
        }
    }
    /** Returns the promise so callers can hold their in-flight lock until the table has reloaded. */
    loadAssignments() {
        this.loadingAssignments = true;
        return getAssignments({ committeeId: this.selectedCommitteeId })
            .then((data) => {
                this.assignments = data.map((a) => ({
                    ...a, contactUrl: a.contactId ? '/' + a.contactId : null
                }));
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.loadingAssignments = false; });
    }

    /**
     * Show the members modal straight away and let the table fill in behind a spinner, rather than
     * holding a blank screen until the query returns - the committee name is already known, so the
     * modal has something to say from the first frame.
     */
    openMembers() {
        this.assignments = [];
        this.showMembers = true;
        this.loadAssignments();
    }
    closeMembers() {
        this.showMembers = false;
        this.selectedCommitteeId = null;
        this.selectedCommitteeName = null;
        this.assignments = [];
    }
    // ---------- committee meetings ----------
    get committeeMeetingsTitle() {
        return this.selectedCommitteeName ? `Meetings — ${this.selectedCommitteeName}` : 'Meetings';
    }
    get hasCommitteeMeetings() { return this.committeeMeetings && this.committeeMeetings.length > 0; }
    get attendanceTitleForMeeting() {
        return this.selectedCommitteeMeetingName
            ? `Attendance — ${this.selectedCommitteeMeetingName}`
            : 'Attendance';
    }
    get hasCommitteeAttendees() { return this.committeeAttendees && this.committeeAttendees.length > 0; }
    get createCommitteeMeetingLabel() {
        return this.savingCommitteeMeeting ? 'Creating\u2026' : 'Create';
    }
    get saveCommitteeAttendanceLabel() {
        return this.savingCommitteeAttendance ? 'Saving\u2026' : 'Save Attendance';
    }
    get deleteMeetingLabel() { return this.deletingMeeting ? 'Deleting\u2026' : 'Delete Meeting'; }
    get deleteMeetingTitle() {
        return this.deleteMeetingName ? `Delete ${this.deleteMeetingName}?` : 'Delete meeting?';
    }

    openCommitteeMeetings() {
        this.committeeMeetings = [];
        this.showCommitteeMeetings = true;
        this.loadCommitteeMeetings();
    }
    closeCommitteeMeetings() {
        this.showCommitteeMeetings = false;
        this.committeeMeetings = [];
        this.selectedCommitteeId = null;
        this.selectedCommitteeName = null;
    }
    /** Returns the promise so a save can hold its lock until the list has actually redrawn. */
    loadCommitteeMeetings() {
        this.loadingCommitteeMeetings = true;
        return getCommitteeMeetings({ committeeId: this.selectedCommitteeId })
            .then((data) => { this.committeeMeetings = data; })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.loadingCommitteeMeetings = false; });
    }
    /** Come back to the meetings list, unless the committee context has been dropped. */
    backToCommitteeMeetings() {
        if (this.selectedCommitteeId) { this.showCommitteeMeetings = true; }
    }

    // --- new committee meeting ---
    openNewCommitteeMeeting() {
        this.mtgName = ''; this.mtgDate = null; this.savingCommitteeMeeting = false;
        this.showCommitteeMeetings = false;
        this.showNewCommitteeMeeting = true;
    }
    closeNewCommitteeMeeting() {
        if (this.savingCommitteeMeeting) { return; }
        this.showNewCommitteeMeeting = false;
        this.backToCommitteeMeetings();
    }
    handleMtgName(e) { this.mtgName = e.detail.value; }
    handleMtgDate(e) { this.mtgDate = e.detail.value; }
    createCommitteeMeeting() {
        if (this.savingCommitteeMeeting) { return; }
        if (!this.mtgDate) { this.toast('Pick a meeting date', 'warning'); return; }
        this.savingCommitteeMeeting = true;
        createCommitteeMeetingApex({ committeeId: this.selectedCommitteeId,
            name: this.mtgName, meetingDate: this.mtgDate })
            .then(() => {
                this.showNewCommitteeMeeting = false;
                this.backToCommitteeMeetings();
                this.toast('Meeting created', 'success');
                return this.loadCommitteeMeetings();
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingCommitteeMeeting = false; });
    }

    // --- attendance at a committee meeting ---
    handleCommitteeMeetingAction(event) {
        const row = event.detail.row;
        if (event.detail.action.name === 'attendance') {
            this.openCommitteeAttendance(row);
        } else if (event.detail.action.name === 'deleteMeeting') {
            this.deleteMeetingId = row.id;
            this.deleteMeetingName = row.name;
            this.deletingMeeting = false;
            this.showCommitteeMeetings = false;
            this.showDeleteMeeting = true;
        }
    }
    openCommitteeAttendance(row) {
        this.selectedCommitteeMeetingId = row.id;
        this.selectedCommitteeMeetingName = row.name;
        this.committeeAttendees = [];
        this.savingCommitteeAttendance = false;
        this.showCommitteeMeetings = false;
        this.showCommitteeAttendance = true;
        this.loadingCommitteeAttendance = true;
        getCommitteeAttendance({ meetingId: row.id })
            // Copy explicit fields into mutable rows - the same read-only-proxy guard the board
            // attendance sheet uses.
            .then((data) => {
                this.committeeAttendees = data.map((r) => ({
                    assignmentId: r.assignmentId,
                    contactId: r.contactId,
                    name: r.name,
                    role: r.role,
                    attended: r.attended
                }));
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.loadingCommitteeAttendance = false; });
    }
    closeCommitteeAttendance() {
        if (this.savingCommitteeAttendance) { return; }
        this.showCommitteeAttendance = false;
        this.backToCommitteeMeetings();
    }
    handleCommitteeAttendChange(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.committeeAttendees = this.committeeAttendees.map((a) =>
            a.assignmentId === id ? { ...a, attended: checked } : a);
    }
    saveCommitteeAttendance() {
        if (this.savingCommitteeAttendance) { return; }
        const rows = this.committeeAttendees.map((a) => ({
            assignmentId: a.assignmentId, attended: a.attended === true
        }));
        this.savingCommitteeAttendance = true;
        saveCommitteeAttendanceApex({ meetingId: this.selectedCommitteeMeetingId,
            rowsJson: JSON.stringify(rows) })
            .then(() => {
                this.showCommitteeAttendance = false;
                this.backToCommitteeMeetings();
                this.toast('Attendance saved', 'success');
                return this.loadCommitteeMeetings();
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingCommitteeAttendance = false; });
    }

    // --- delete a committee meeting ---
    closeDeleteMeeting() {
        if (this.deletingMeeting) { return; }
        this.showDeleteMeeting = false;
        this.backToCommitteeMeetings();
    }
    confirmDeleteMeeting() {
        if (this.deletingMeeting) { return; }
        this.deletingMeeting = true;
        deleteCommitteeMeetingApex({ meetingId: this.deleteMeetingId })
            .then(() => {
                this.showDeleteMeeting = false;
                this.backToCommitteeMeetings();
                this.toast('Meeting deleted', 'success');
                return this.loadCommitteeMeetings();
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.deletingMeeting = false; });
    }

    /**
     * Only one modal is on screen at a time: the members list steps aside for the add form and comes
     * back afterwards. Stacking two SLDS modals leaves two backdrops over each other and no clear
     * answer to what Escape or a backdrop click should close.
     */
    openAddMember() {
        this.amContactId = null; this.amRole = 'Member'; this.amDate = null;
        this.savingAssignment = false;
        this.showMembers = false;
        this.showAddMember = true;
    }
    closeAddMember() {
        if (this.savingAssignment) { return; }
        this.showAddMember = false;
        this.backToMembers();
    }
    /** Return to the members list, unless the user reached Add Member some other way. */
    backToMembers() {
        if (this.selectedCommitteeId) { this.showMembers = true; }
    }
    handleAmContact(e) { this.amContactId = e.detail.recordId; }
    handleAmRole(e) { this.amRole = e.detail.value; }
    handleAmDate(e) { this.amDate = e.detail.value; }
    saveAssignment() {
        if (this.savingAssignment) { return; }
        if (!this.amContactId) { this.toast('Pick a contact first', 'warning'); return; }
        this.savingAssignment = true;
        saveAssignmentApex({ committeeId: this.selectedCommitteeId, contactId: this.amContactId,
            role: this.amRole, fyDate: this.amDate })
            .then(() => {
                this.showAddMember = false;
                this.backToMembers();          // land back on the list, with the new member on it
                this.toast('Member added', 'success');
                return this.loadAssignments();
            })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.savingAssignment = false; });
    }
    handleAssignmentAction(event) {
        if (event.detail.action.name !== 'remove') { return; }
        // Guarded like the save buttons: a second Remove on the same row would work on a record that
        // is already gone, and report that as an error rather than as the no-op it is.
        if (this.removingAssignment) { return; }
        this.removingAssignment = true;
        removeAssignmentApex({ assignmentId: event.detail.row.id })
            .then(() => { this.toast('Member removed', 'success'); return this.loadAssignments(); })
            .catch((err) => this.toast(this.msg(err), 'error'))
            .finally(() => { this.removingAssignment = false; });
    }

    toast(message, variant) { this.dispatchEvent(new ShowToastEvent({ title: message, variant })); }
    msg(err) {
        if (!err) { return 'Something went wrong'; }
        if (Array.isArray(err.body)) { return err.body.map((e) => e.message).join(', '); }
        if (err.body && err.body.message) { return err.body.message; }
        if (err.body && err.body.pageErrors && err.body.pageErrors.length) { return err.body.pageErrors[0].message; }
        if (err.body && err.body.output && err.body.output.errors && err.body.output.errors.length) {
            return err.body.output.errors[0].message;
        }
        if (err.message) { return err.message; }
        return 'Something went wrong';
    }
}