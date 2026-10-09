/**
 * @description pendingTransactionAdd - modal for typing in a pending transaction by hand
 *              (JSI-121 Phase 4).
 *
 *              For money that won't arrive through the QuickBooks feed. It asks only for what describes the
 *              money itself; routing (new gift or pledge payment) and gift details are finished in the
 *              editor, which opens on the new row. The server marks the row Manual, suggests a donor from
 *              the payer name when none is picked, and works out its status. Closes with the new row.
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 4).
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createTransaction from '@salesforce/apex/PendingTransactionController.createTransaction';
import { errorMessage } from 'c/pendingTransactionUtils';

export default class PendingTransactionAdd extends LightningModal {
    @api paymentMethods = [];

    amount;
    transactionDate = new Date().toLocaleDateString('en-CA'); // yyyy-mm-dd in the user's own timezone
    paymentMethod = 'ACH/Wire';
    referenceNumber;
    payerName;
    contactId;
    accountId;
    depositDate;
    depositReference;
    notes;

    saving = false;

    contactDisplayInfo = { additionalFields: ['Email'] };
    contactMatchingInfo = { primaryField: { fieldPath: 'Name' }, additionalFields: [{ fieldPath: 'Email' }] };

    handleInput(event) {
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this[event.target.dataset.field] = value === '' ? null : value;
    }

    handleContact(event) { this.contactId = event.detail.recordId || null; }
    handleAccount(event) { this.accountId = event.detail.recordId || null; }

    handleCancel() { this.close(); }

    handleSave() {
        const inputs = [...this.template.querySelectorAll('lightning-input')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) { return; }

        const payload = {
            amount: this.amount, transactionDate: this.transactionDate, paymentMethod: this.paymentMethod,
            referenceNumber: this.referenceNumber, payerName: this.payerName, contactId: this.contactId,
            accountId: this.accountId, depositDate: this.depositDate, depositReference: this.depositReference,
            notes: this.notes
        };
        this.saving = true;
        createTransaction({ rowJson: JSON.stringify(payload) })
            .then((row) => {
                this.dispatchEvent(new ShowToastEvent({ title: `Added ${row.name}`, variant: 'success' }));
                this.close(row);
            })
            .catch((err) => this.dispatchEvent(new ShowToastEvent({ title: errorMessage(err), variant: 'error' })))
            .finally(() => { this.saving = false; });
    }
}