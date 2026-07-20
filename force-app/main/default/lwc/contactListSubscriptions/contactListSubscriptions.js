/**
 * contactListSubscriptions — JSI-108
 * View-only display of a Contact's Constant Contact list/topic subscriptions
 * (their CampaignMembers on CC List record-type Campaigns). No edit controls:
 * constituents change preferences in the CC preference center, which syncs back.
 * Author: Jason Ott · 2026-07-20
 */
import { LightningElement, api, wire } from 'lwc';
import getSubscriptions from '@salesforce/apex/ContactSubscriptionsController.getSubscriptions';

export default class ContactListSubscriptions extends LightningElement {
    @api recordId;
    _subs;
    error;

    @wire(getSubscriptions, { contactId: '$recordId' })
    wiredSubs({ error, data }) {
        if (data) {
            this._subs = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this._subs = undefined;
        }
    }

    get hasSubscriptions() {
        return Array.isArray(this._subs) && this._subs.length > 0;
    }

    get isEmpty() {
        return Array.isArray(this._subs) && this._subs.length === 0;
    }

    // Decorate each row with a status-badge class (green subscribed / red otherwise).
    get rows() {
        return (this._subs || []).map((s) => ({
            key: s.campaignId,
            topic: s.topic,
            status: s.status,
            badgeClass:
                s.status === 'Unsubscribed'
                    ? 'slds-badge slds-theme_error'
                    : 'slds-badge slds-theme_success'
        }));
    }
}
