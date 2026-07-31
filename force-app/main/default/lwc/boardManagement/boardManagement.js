/**
 * boardManagement — Board Management console (JSI-123). Tabs: Dashboard, Meetings & Attendance,
 * Committees, Roster. Author: Jason Ott.
 */
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
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
        { label: 'Edit', name: 'edit' }, { label: 'Manage Members', name: 'manage' }] } }
];
const ASSIGNMENT_COLUMNS = [
    { label: 'Member', fieldName: 'contactName' },
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
    assignmentColumns = ASSIGNMENT_COLUMNS;
    categoryOptions = CATEGORY_OPTIONS;
    roleOptions = ROLE_OPTIONS;

    // meetings
    meetings = [];
    wiredMeetings;
    attendees = [];
    selectedMeetingId;
    selectedMeetingName;
    showNewMeeting = false;
    newName = '';
    newDate = null;

    // committees
    committees = [];
    wiredCommittees;
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
    showAddMember = false;
    amContactId = null;
    amRole = 'Member';
    amDate = null;

    @wire(getMeetings)
    wiredGetMeetings(result) {
        this.wiredMeetings = result;
        if (result.data) {
            this.meetings = result.data;
        }
    }

    @wire(getCommittees)
    wiredGetCommittees(result) {
        this.wiredCommittees = result;
        if (result.data) {
            this.committees = result.data;
        }
    }

    get attendanceTitle() {
        return this.selectedMeetingName ? `Attendance — ${this.selectedMeetingName}` : 'Attendance';
    }
    get assignmentsTitle() {
        return this.selectedCommitteeName ? `Members — ${this.selectedCommitteeName}` : 'Members';
    }

    // ---------- meetings ----------
    openNewMeeting() { this.newName = ''; this.newDate = null; this.showNewMeeting = true; }
    closeNewMeeting() { this.showNewMeeting = false; }
    handleName(e) { this.newName = e.detail.value; }
    handleDate(e) { this.newDate = e.detail.value; }
    createMeeting() {
        createMeetingApex({ name: this.newName, meetingDate: this.newDate })
            .then(() => { this.showNewMeeting = false; this.toast('Meeting created', 'success');
                return refreshApex(this.wiredMeetings); })
            .catch((err) => this.toast(this.msg(err), 'error'));
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
        const rows = this.attendees.map((a) => ({
            membershipYearId: a.membershipYearId, contactId: a.contactId, name: a.name, attended: a.attended
        }));
        saveAttendanceApex({ meetingId: this.selectedMeetingId, rows })
            .then(() => { this.toast('Attendance saved', 'success'); return refreshApex(this.wiredMeetings); })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    // ---------- committees ----------
    openNewCommittee() {
        this.cmId = null; this.cmName = ''; this.cmCategory = 'Board Committee';
        this.cmIsExec = false; this.cmParentId = null; this.cmActive = true;
        this.showCommitteeModal = true;
    }
    closeCommitteeModal() { this.showCommitteeModal = false; }
    handleCmName(e) { this.cmName = e.detail.value; }
    handleCmCategory(e) { this.cmCategory = e.detail.value; }
    handleCmExec(e) { this.cmIsExec = e.detail.checked; }
    handleCmActive(e) { this.cmActive = e.detail.checked; }
    handleCmParent(e) { this.cmParentId = e.detail.recordId; }
    saveCommittee() {
        saveCommitteeApex({ committeeId: this.cmId, name: this.cmName, category: this.cmCategory,
            isExecutive: this.cmIsExec, parentId: this.cmParentId, active: this.cmActive })
            .then(() => { this.showCommitteeModal = false; this.toast('Committee saved', 'success');
                return refreshApex(this.wiredCommittees); })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }
    handleCommitteeAction(event) {
        const row = event.detail.row;
        if (event.detail.action.name === 'edit') {
            this.cmId = row.id; this.cmName = row.name; this.cmCategory = row.category || 'Board Committee';
            this.cmIsExec = row.isExecutive; this.cmParentId = row.parentId; this.cmActive = row.active;
            this.showCommitteeModal = true;
        } else if (event.detail.action.name === 'manage') {
            this.selectedCommitteeId = row.id;
            this.selectedCommitteeName = row.name;
            this.loadAssignments();
        }
    }
    loadAssignments() {
        getAssignments({ committeeId: this.selectedCommitteeId })
            .then((data) => { this.assignments = data; })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }
    openAddMember() { this.amContactId = null; this.amRole = 'Member'; this.amDate = null; this.showAddMember = true; }
    closeAddMember() { this.showAddMember = false; }
    handleAmContact(e) { this.amContactId = e.detail.recordId; }
    handleAmRole(e) { this.amRole = e.detail.value; }
    handleAmDate(e) { this.amDate = e.detail.value; }
    saveAssignment() {
        if (!this.amContactId) { this.toast('Pick a contact first', 'warning'); return; }
        saveAssignmentApex({ committeeId: this.selectedCommitteeId, contactId: this.amContactId,
            role: this.amRole, fyDate: this.amDate })
            .then(() => { this.showAddMember = false; this.toast('Member added', 'success'); this.loadAssignments(); })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }
    handleAssignmentAction(event) {
        if (event.detail.action.name !== 'remove') { return; }
        removeAssignmentApex({ assignmentId: event.detail.row.id })
            .then(() => { this.toast('Member removed', 'success'); this.loadAssignments(); })
            .catch((err) => this.toast(this.msg(err), 'error'));
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
