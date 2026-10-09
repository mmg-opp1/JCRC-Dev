/**
 * @description pendingTransactionBulkEdit - modal that collects Campaign / Fund / Approach / Gift record type
 *              to set on every selected pending transaction (JSI-121 Phase 3, decision D7).
 *
 *              Each field has its own tick box so "leave alone" and "clear" are different things. Closes with
 *              only the ticked fields, keyed as the controller expects (campaignId, fundId, approach,
 *              giftRecordType); the parent sends them to PendingTransactionController.bulkUpdate.
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

export default class PendingTransactionBulkEdit extends LightningModal {
    @api label;
    @api count = 0;
    @api options = {};

    setCampaign = false;
    setFund = false;
    setApproach = false;
    setRecordType = false;

    campaignId = null;
    fundId = '';
    approach = '';
    giftRecordType = '';

    campaignFilter = { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };

    get fundOptions() { return [{ label: 'Default fund', value: '' }, ...(this.options.funds || [])]; }
    get approachOptions() { return [{ label: 'None', value: '' }, ...(this.options.approaches || [])]; }
    get recordTypeOptions() { return this.options.giftRecordTypes || []; }

    get campaignDisabled() { return !this.setCampaign; }
    get fundDisabled() { return !this.setFund; }
    get approachDisabled() { return !this.setApproach; }
    get recordTypeDisabled() { return !this.setRecordType; }
    get applyDisabled() { return !(this.setCampaign || this.setFund || this.setApproach || this.setRecordType); }

    handleToggle(event) {
        const key = event.target.dataset.key;
        const on = event.target.checked;
        if (key === 'campaign') { this.setCampaign = on; }
        if (key === 'fund') { this.setFund = on; }
        if (key === 'approach') { this.setApproach = on; }
        if (key === 'recordType') {
            this.setRecordType = on;
            if (on && !this.giftRecordType) { this.giftRecordType = this.options.defaultGiftRecordType || ''; }
        }
    }

    handleCampaign(event) { this.campaignId = event.detail.recordId || null; }
    handleFund(event) { this.fundId = event.detail.value; }
    handleApproach(event) { this.approach = event.detail.value; }
    handleRecordType(event) { this.giftRecordType = event.detail.value; }

    handleCancel() { this.close(); }

    handleApply() {
        const fields = {};
        if (this.setCampaign) { fields.campaignId = this.campaignId; }
        if (this.setFund) { fields.fundId = this.fundId || null; }
        if (this.setApproach) { fields.approach = this.approach || null; }
        if (this.setRecordType) { fields.giftRecordType = this.giftRecordType || null; }
        this.close(fields);
    }
}