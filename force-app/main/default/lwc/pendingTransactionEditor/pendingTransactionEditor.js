/**
 * @description pendingTransactionEditor - review, correct and commit one pending transaction
 *              (JSI-121 Phase 3).
 *
 *              Edits go into a local draft; Save (or moving to another row, or Commit) writes them. Choosing
 *              a donor saves straight away: the server fills the household account from the contact and
 *              re-evaluates the row, and the donor's open pledges and grants are loaded from what was saved.
 *
 *              "Payment on a pledge" shows those pledges as cards and a plain-English preview of exactly
 *              what committing will do to the installment schedule, fetched from the same server logic the
 *              commit uses.
 *
 *              Events:
 *                rowsaved  - detail = the saved row, re-evaluated by the server
 *                commit    - detail = { rowId }; the parent commits and shows the result
 *                navigate  - detail = 'prev' | 'next'
 *                deleterequest - detail = { rowId }; the parent confirms and deletes
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 * 2026-09-16 - Jason Ott - Phase 4: Delete button (raises deleterequest).
 * 2026-09-17 - Jason Ott - Phase 5b: shows the QuickBooks import note and customer id under As received.
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveTransaction from '@salesforce/apex/PendingTransactionController.saveTransaction';
import confirmDonor from '@salesforce/apex/PendingTransactionController.confirmDonor';
import getOpenPledges from '@salesforce/apex/PendingTransactionController.getOpenPledges';
import previewPledgePayment from '@salesforce/apex/PendingTransactionController.previewPledgePayment';
import NewContactModal from 'c/pendingTransactionNewContact';
import { errorMessage, formatMoney, formatDate } from 'c/pendingTransactionUtils';

/** Draft keys, matching the controller's editable field names. */
const FIELDS = ['amount', 'transactionDate', 'paymentMethod', 'referenceNumber', 'depositDate', 'depositReference',
    'contactId', 'accountId', 'applyAs', 'pledgeId', 'giftRecordType', 'campaignId', 'fundId', 'approach',
    'giftName', 'notes'];

const PREVIEW_DELAY_MS = 400;

export default class PendingTransactionEditor extends LightningElement {
    @api options = {};
    @api hasPrev = false;
    @api hasNext = false;
    /** The parent is committing or running a bulk action. */
    @api busy = false;

    _row;
    draft = {};
    saving = false;
    loadingPledges = false;
    pledges = [];
    pledgesFor;
    previewSteps;
    previewRefusal;
    previewTimer;

    contactDisplayInfo = { additionalFields: ['Email'] };
    contactMatchingInfo = { primaryField: { fieldPath: 'Name' }, additionalFields: [{ fieldPath: 'Email' }] };
    campaignFilter = { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };

    // ---- row in / draft ------------------------------------------------------------------------

    @api
    get row() { return this._row; }
    set row(value) {
        const switched = !this._row || !value || this._row.id !== value.id;
        this._row = value;
        this.resetDraft();
        if (switched) {
            // Balances may have changed since this donor's pledges were last loaded (a commit).
            this.pledgesFor = undefined;
            this.previewSteps = undefined;
            this.previewRefusal = undefined;
        }
        this.loadPledgesIfNeeded();
        this.schedulePreview();
    }

    resetDraft() {
        const r = this._row || {};
        const d = {};
        FIELDS.forEach((f) => { d[f] = r[f] === undefined ? null : r[f]; });
        this.draft = d;
    }

    get isDirty() {
        const r = this._row || {};
        return FIELDS.some((f) => this.norm(this.draft[f]) !== this.norm(r[f]));
    }

    norm(v) { return v === undefined || v === null || v === '' ? null : String(v); }

    /**
     * Saves pending edits. Resolves with the saved row (or undefined if nothing to save); rejects if the
     * save failed, so the parent can stay on this row instead of losing the edits.
     */
    @api
    saveIfDirty() {
        return this.isDirty ? this.save() : Promise.resolve(undefined);
    }

    save() {
        this.saving = true;
        const payload = { id: this._row.id };
        FIELDS.forEach((f) => { payload[f] = this.draft[f]; });
        return saveTransaction({ rowJson: JSON.stringify(payload) })
            .then((saved) => {
                this.dispatchEvent(new CustomEvent('rowsaved', { detail: saved }));
                return saved;
            })
            .catch((err) => {
                this.toast(errorMessage(err), 'error');
                throw err;
            })
            .finally(() => { this.saving = false; });
    }

    // ---- field handlers -----------------------------------------------------------------------

    handleField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (value === '') { value = null; }
        this.draft = { ...this.draft, [field]: value };
        if (field === 'amount') { this.schedulePreview(); }
    }

    handleCampaign(event) {
        this.draft = { ...this.draft, campaignId: event.detail.recordId || null };
    }

    /**
     * A new contact replaces an account that only came from the previous contact (their household),
     * so the server fills the new contact's household. An account picked on its own (an organization)
     * is kept. Then save, so the pledges reflect the donor that was actually recorded.
     */
    handleContact(event) {
        const contactId = event.detail.recordId || null;
        if (contactId === this.draft.contactId) { return; }
        const accountFromContact = this._row && this.draft.accountId && this.draft.accountId === this._row.contactAccountId;
        this.draft = {
            ...this.draft,
            contactId,
            accountId: accountFromContact || !this.draft.accountId ? null : this.draft.accountId
        };
        this.saveDonor();
    }

    handleAccount(event) {
        const accountId = event.detail.recordId || null;
        if (accountId === this.draft.accountId) { return; }
        this.draft = { ...this.draft, accountId };
        this.saveDonor();
    }

    saveDonor() {
        this.save().catch(() => {});
    }

    handleApplyAs(event) {
        const value = event.currentTarget.dataset.value;
        this.draft = { ...this.draft, applyAs: value };
        this.loadPledgesIfNeeded();
        this.schedulePreview();
    }

    handlePledge(event) {
        const id = event.currentTarget.dataset.id;
        this.draft = { ...this.draft, pledgeId: this.draft.pledgeId === id ? null : id };
        this.schedulePreview();
    }

    handleConfirmDonor() {
        const go = () => {
            this.saving = true;
            return confirmDonor({ rowId: this._row.id })
                .then((saved) => this.dispatchEvent(new CustomEvent('rowsaved', { detail: saved })))
                .catch((err) => this.toast(errorMessage(err), 'error'))
                .finally(() => { this.saving = false; });
        };
        this.saveIfDirty().then(go).catch(() => {});
    }

    async handleNewContact() {
        const result = await NewContactModal.open({
            size: 'small',
            label: 'New contact',
            defaultName: this._row ? this._row.payerName : '',
            defaultEmail: this._row ? this._row.payerEmail : ''
        });
        if (result && result.contactId) {
            this.draft = { ...this.draft, contactId: result.contactId, accountId: null };
            this.saveDonor();
        }
    }

    handleNav(event) {
        this.dispatchEvent(new CustomEvent('navigate', { detail: event.currentTarget.dataset.dir }));
    }

    handleDelete() {
        this.dispatchEvent(new CustomEvent('deleterequest', { detail: { rowId: this._row.id } }));
    }

    handleReset() {
        this.resetDraft();
        this.schedulePreview();
    }

    handleSave() {
        this.save().then(() => this.toast('Saved', 'success')).catch(() => {});
    }

    /** Saves first; commits only if the saved row came back Ready, otherwise its problems are on screen. */
    handleCommit() {
        this.saveIfDirty()
            .then((saved) => {
                const current = saved || this._row;
                if (current.status !== 'Ready') {
                    this.toast('Not ready yet - see what still needs attention at the top', 'warning');
                    return;
                }
                this.dispatchEvent(new CustomEvent('commit', { detail: { rowId: current.id } }));
            })
            .catch(() => {});
    }

    // ---- pledges & preview --------------------------------------------------------------------

    /** Loads open pledges for the SAVED donor when the pledge view is showing and the donor changed. */
    loadPledgesIfNeeded() {
        if (!this.isPledgePayment || !this._row) { return; }
        const key = `${this._row.contactId || ''}|${this._row.accountId || ''}`;
        if (key === this.pledgesFor) { return; }
        this.pledgesFor = key;
        this.pledges = [];
        if (!this._row.contactId && !this._row.accountId) { return; }
        this.loadingPledges = true;
        getOpenPledges({ contactId: this._row.contactId, accountId: this._row.accountId })
            .then((list) => {
                if (this.pledgesFor === key) { this.pledges = list; }
            })
            .catch((err) => this.toast(errorMessage(err), 'error'))
            .finally(() => { this.loadingPledges = false; });
    }

    /** Debounced: typing an amount should not fire a request per keystroke. */
    schedulePreview() {
        clearTimeout(this.previewTimer);
        this.previewSteps = undefined;
        this.previewRefusal = undefined;
        if (!this.isPledgePayment || !this.draft.pledgeId || !(Number(this.draft.amount) > 0)) { return; }
        const pledgeId = this.draft.pledgeId;
        const amount = Number(this.draft.amount);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.previewTimer = setTimeout(() => {
            previewPledgePayment({ pledgeId, amount })
                .then((p) => {
                    if (pledgeId !== this.draft.pledgeId || amount !== Number(this.draft.amount)) { return; }
                    this.previewSteps = p.allowed ? p.steps : undefined;
                    this.previewRefusal = p.allowed ? undefined : p.refusal;
                })
                .catch((err) => { this.previewRefusal = errorMessage(err); });
        }, PREVIEW_DELAY_MS);
    }

    disconnectedCallback() {
        clearTimeout(this.previewTimer);
    }

    // ---- view state ---------------------------------------------------------------------------

    get locked() { return this.saving || this.busy; }
    get isNewGift() { return this.draft.applyAs !== 'Pledge Payment'; }
    get isPledgePayment() { return this.draft.applyAs === 'Pledge Payment'; }
    get isSuggested() { return this._row && this._row.matchStatus === 'Suggested' && !!(this._row.contactId || this._row.accountId); }
    get isMultiple() { return this._row && this._row.matchStatus === 'Multiple Matches' && !this.draft.contactId && !this.draft.accountId; }
    get noDonor() { return !this._row || (!this._row.contactId && !this._row.accountId); }
    get noPledges() { return !this.pledges || this.pledges.length === 0; }
    get hasProblems() { return this._row && this._row.problems && this._row.problems.length > 0 && !this.isDirty; }

    get statusLabel() { return this.isDirty ? 'Unsaved' : (this._row && this._row.status) || ''; }
    get statusClass() {
        const s = this.isDirty ? 'dirty' : this._row && this._row.status === 'Ready' ? 'ready'
            : this._row && this._row.status === 'Error' ? 'error' : 'review';
        return `ed-status ed-status_${s}`;
    }

    get amountDisplay() { return formatMoney(this.draft.amount); }
    get payerDisplay() { return (this._row && this._row.payerName) || 'Not recorded'; }

    get prevDisabled() { return !this.hasPrev || this.locked; }
    get nextDisabled() { return !this.hasNext || this.locked; }
    get saveDisabled() { return this.locked || !this.isDirty; }
    get discardDisabled() { return this.locked || !this.isDirty; }
    get commitDisabled() { return this.locked || (!this.isDirty && this._row && this._row.status !== 'Ready'); }
    get commitTitle() {
        return this.commitDisabled && !this.locked ? 'Resolve the items listed at the top first' : 'Create the gift or apply the payment';
    }

    get newGiftSegmentClass() { return `ed-seg${this.isNewGift ? ' ed-seg_on' : ''}`; }
    get pledgeSegmentClass() { return `ed-seg${this.isPledgePayment ? ' ed-seg_on' : ''}`; }
    get pledgeCountLabel() {
        return this.isPledgePayment && this.pledges && this.pledges.length ? String(this.pledges.length) : '';
    }

    get giftRecordTypeValue() {
        return this.draft.giftRecordType || (this.options && this.options.defaultGiftRecordType);
    }
    get fundOptions() {
        return [{ label: 'Default fund', value: '' }, ...((this.options && this.options.funds) || [])];
    }
    get fundValue() { return this.draft.fundId || ''; }
    get approachOptions() {
        return [{ label: 'None', value: '' }, ...((this.options && this.options.approaches) || [])];
    }
    get approachValue() { return this.draft.approach || ''; }

    get pledgeCards() {
        return (this.pledges || []).map((p) => {
            const paidPct = p.amount ? Math.max(0, Math.min(100, Math.round(((p.amount - p.outstanding) / p.amount) * 100))) : 0;
            const next = p.unpaid && p.unpaid.length ? p.unpaid[0] : null;
            const selected = p.id === this.draft.pledgeId;
            return {
                ...p,
                selected,
                cssClass: `ed-pledge${selected ? ' ed-pledge_on' : ''}`,
                outstandingDisplay: formatMoney(p.outstanding),
                amountDisplay: formatMoney(p.amount),
                progressStyle: `width:${paidPct}%`,
                nextLabel: next
                    ? `Next: ${formatMoney(next.amount)}${next.scheduledDate ? ' due ' + formatDate(next.scheduledDate) : ''} · ${p.unpaidCount} unpaid`
                    : 'No scheduled installments left'
            };
        });
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}
