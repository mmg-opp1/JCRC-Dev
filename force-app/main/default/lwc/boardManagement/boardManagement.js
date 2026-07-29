/**
 * boardManagement — Board Management console (JSI-123). Tabbed surface: Dashboard, Meetings & Attendance
 * (functional), Committees (next), Roster (embeds boardMembers). Author: Jason Ott.
 */
import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMeetings from '@salesforce/apex/BoardManagementController.getMeetings';
import createMeetingApex from '@salesforce/apex/BoardManagementController.createMeeting';
import getAttendance from '@salesforce/apex/BoardManagementController.getAttendance';
import saveAttendanceApex from '@salesforce/apex/BoardManagementController.saveAttendance';

const MEETING_COLUMNS = [
    { label: 'Meeting', fieldName: 'name' },
    { label: 'Date', fieldName: 'meetingDate', type: 'date-local' },
    { label: 'Fiscal Year', fieldName: 'fiscalYearLabel' },
    { label: 'Attended', fieldName: 'attendedCount', type: 'number', cellAttributes: { alignment: 'left' } },
    { type: 'button', typeAttributes: { label: 'Take Attendance', name: 'open', variant: 'brand-outline' } }
];

const ATTENDEE_COLUMNS = [
    { label: 'Board Member', fieldName: 'name' },
    { label: 'Attended', fieldName: 'attended', type: 'boolean', editable: true }
];

export default class BoardManagement extends LightningElement {
    meetingColumns = MEETING_COLUMNS;
    attendeeColumns = ATTENDEE_COLUMNS;
    meetings = [];
    wiredMeetings;

    @track attendees = [];
    selectedMeetingId;
    selectedMeetingName;
    draftValues = [];

    showNewMeeting = false;
    newName = '';
    newDate = null;

    @wire(getMeetings)
    wiredGetMeetings(result) {
        this.wiredMeetings = result;
        if (result.data) {
            this.meetings = result.data;
        }
    }

    get attendanceTitle() {
        return this.selectedMeetingName ? `Attendance — ${this.selectedMeetingName}` : 'Attendance';
    }

    // --- new meeting modal ---
    openNewMeeting() {
        this.newName = '';
        this.newDate = null;
        this.showNewMeeting = true;
    }
    closeNewMeeting() {
        this.showNewMeeting = false;
    }
    handleName(e) {
        this.newName = e.detail.value;
    }
    handleDate(e) {
        this.newDate = e.detail.value;
    }
    createMeeting() {
        createMeetingApex({ name: this.newName, meetingDate: this.newDate })
            .then(() => {
                this.showNewMeeting = false;
                this.toast('Meeting created', 'success');
                return refreshApex(this.wiredMeetings);
            })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    // --- attendance ---
    handleMeetingAction(event) {
        if (event.detail.action.name !== 'open') {
            return;
        }
        const row = event.detail.row;
        this.selectedMeetingId = row.id;
        this.selectedMeetingName = row.name;
        this.draftValues = [];
        getAttendance({ meetingId: row.id })
            .then((data) => {
                this.attendees = data;
            })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    saveAttendance() {
        // merge inline-edit drafts into the attendee rows
        const drafts = {};
        this.draftValues.forEach((d) => {
            drafts[d.membershipYearId] = d.attended;
        });
        const rows = this.attendees.map((a) => ({
            membershipYearId: a.membershipYearId,
            contactId: a.contactId,
            name: a.name,
            attended: drafts[a.membershipYearId] !== undefined ? drafts[a.membershipYearId] : a.attended
        }));
        saveAttendanceApex({ meetingId: this.selectedMeetingId, rows })
            .then(() => {
                this.attendees = rows;
                this.draftValues = [];
                this.toast('Attendance saved', 'success');
                return refreshApex(this.wiredMeetings);
            })
            .catch((err) => this.toast(this.msg(err), 'error'));
    }

    handleCellChange(event) {
        this.draftValues = event.detail.draftValues;
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
    msg(err) {
        return (err && err.body && err.body.message) ? err.body.message : 'Something went wrong';
    }
}
