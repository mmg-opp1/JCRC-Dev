import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange, getRecord, getFieldValue } from 'lightning/uiRecordApi';
import replay from '@salesforce/apex/WebDonationReplayController.replay';
import STATUS from '@salesforce/schema/Web_Donation__c.Status__c';
import OPP from '@salesforce/schema/Web_Donation__c.Opportunity__c';

/**
 * Replay control for a Web Donation. Reprocesses the stored payload once whatever made it
 * fail has been fixed - a missing designation mapping, for instance.
 *
 * Sits on the record page rather than being a quick action: a LightningComponent quick action
 * would not register against this object, and this is simpler anyway - the button can show its
 * own state and explain why it is unavailable, which a quick action cannot.
 */
export default class WebDonationReplay extends LightningElement {
    @api recordId;
    running = false;

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS, OPP] })
    record;

    get status() {
        return getFieldValue(this.record.data, STATUS);
    }

    get hasGift() {
        return !!getFieldValue(this.record.data, OPP);
    }

    /** Only offer replay where it can actually do something. */
    get canReplay() {
        return !this.running && !this.hasGift && this.status !== 'Processed';
    }

    /** Templates cannot hold expressions, so the negation lives here. */
    get replayDisabled() {
        return !this.canReplay;
    }

    get helpText() {
        if (this.hasGift) {
            return 'This submission already created a gift, so replaying it would duplicate the donation.';
        }
        if (this.status === 'Processed') {
            return 'Already processed.';
        }
        return 'Reprocesses the stored payload. Use after fixing whatever made it fail.';
    }

    handleReplay() {
        this.running = true;
        replay({ recordId: this.recordId })
            .then((msg) => {
                this.toast('Replayed', msg, 'success');
                getRecordNotifyChange([{ recordId: this.recordId }]);
            })
            .catch((err) => {
                // Show the real reason, not "something went wrong" - the whole point is
                // telling the user what to fix next.
                this.toast('Replay failed', this.readError(err), 'error', 'sticky');
            })
            .finally(() => {
                this.running = false;
            });
    }

    readError(err) {
        return (
            err?.body?.message ||
            err?.body?.pageErrors?.[0]?.message ||
            err?.message ||
            'Unknown error'
        );
    }

    toast(title, message, variant, mode) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant, mode: mode || 'dismissable' })
        );
    }
}
