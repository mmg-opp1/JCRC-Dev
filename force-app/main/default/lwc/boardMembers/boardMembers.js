/**
 * boardMembers — current board roster widget (JSI-123 Board Tracking).
 * Lists everyone currently serving on the board with their term and this year's commitment progress;
 * the name links straight to the Contact record. Read-only. Author: Jason Ott.
 */
import { LightningElement, wire } from 'lwc';
import getCurrentBoardMembers from '@salesforce/apex/BoardMembersController.getCurrentBoardMembers';

const COLUMNS = [
    { label: 'Board Member', fieldName: 'contactUrl', type: 'url',
      typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
    { label: 'Type', fieldName: 'memberType' },
    { label: 'Role', fieldName: 'role' },
    { label: 'Term', fieldName: 'termYears' },
    { label: 'Expiring Soon', fieldName: 'expiringLabel' },
    { label: 'Must Roll Off', fieldName: 'rollOffLabel' },
    { label: 'Commitment', fieldName: 'commitmentDisplay' },
    { label: '% Met', fieldName: 'pctDisplay' }
];

export default class BoardMembers extends LightningElement {
    columns = COLUMNS;
    rows = [];
    error;

    @wire(getCurrentBoardMembers)
    wired({ data, error }) {
        if (data) {
            this.rows = data.map((r) => ({
                ...r,
                contactUrl: '/' + r.contactId,
                expiringLabel: r.expiringSoon ? '⚠ Yes' : '',
                rollOffLabel: r.mustRollOff ? '⛔ Yes' : '',
                commitmentDisplay: r.commitment != null ? '$' + Number(r.commitment).toLocaleString() : '—',
                pctDisplay: r.pctMet != null ? Math.round(r.pctMet) + '%' : '—'
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    get count() {
        return this.rows ? this.rows.length : 0;
    }
}
