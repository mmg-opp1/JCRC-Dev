/**
 * @description pendingTransactionNewContact - modal to create a donor contact from the Pending Transactions
 *              editor (JSI-121 Phase 3, decision D6).
 *
 *              Pre-fills the name and email from what the bank or QuickBooks recorded. On Save the server
 *              first runs the org's Contact duplicate rules; likely matches come back as "Use this contact"
 *              choices, and a second Save creates the new contact anyway. Closes with { contactId }.
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createContact from '@salesforce/apex/PendingTransactionController.createContact';
import { errorMessage } from 'c/pendingTransactionUtils';

export default class PendingTransactionNewContact extends LightningModal {
    @api label = 'New contact';
    @api defaultName;
    @api defaultEmail;

    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    street = '';
    city = '';
    state = '';
    postalCode = '';

    saving = false;
    duplicates = [];

    connectedCallback() {
        // "Rachel Cohen" -> first Rachel, last Cohen. Bank names are rough, so this is only a starting point.
        const parts = (this.defaultName || '').trim().split(/\s+/).filter(Boolean);
        if (parts.length > 1) {
            this.lastName = this.titleCase(parts.pop());
            this.firstName = this.titleCase(parts.join(' '));
        } else if (parts.length === 1) {
            this.lastName = this.titleCase(parts[0]);
        }
        this.email = this.defaultEmail || '';
    }

    titleCase(s) {
        return s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
    }

    get hasDuplicates() { return this.duplicates.length > 0; }
    get saveLabel() { return this.hasDuplicates ? 'Create new anyway' : 'Create contact'; }

    handleInput(event) {
        this[event.target.dataset.field] = event.target.value;
        // Changing the details means the duplicate check needs to run again.
        this.duplicates = [];
    }

    handleCancel() {
        this.close();
    }

    handleUseExisting(event) {
        this.close({ contactId: event.currentTarget.dataset.id });
    }

    handleSave() {
        if (!this.lastName || !this.lastName.trim()) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Enter a last name', variant: 'warning' }));
            return;
        }
        const payload = {
            firstName: this.firstName, lastName: this.lastName, email: this.email, phone: this.phone,
            street: this.street, city: this.city, state: this.state, postalCode: this.postalCode
        };
        this.saving = true;
        createContact({ contactJson: JSON.stringify(payload), ignoreDuplicates: this.hasDuplicates })
            .then((result) => {
                if (result.contactId) {
                    this.dispatchEvent(new ShowToastEvent({ title: `Created ${result.contactName}`, variant: 'success' }));
                    this.close({ contactId: result.contactId });
                } else {
                    this.duplicates = result.possibleDuplicates || [];
                }
            })
            .catch((err) => this.dispatchEvent(new ShowToastEvent({ title: errorMessage(err), variant: 'error' })))
            .finally(() => { this.saving = false; });
    }
}
