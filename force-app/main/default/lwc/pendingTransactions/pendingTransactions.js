/**
 * @description pendingTransactions - the Pending Transactions work queue (JSI-121 Phase 3).
 *
 *              Money that reached the bank outside Salesforce waits here. This component owns the queue:
 *              summary tiles (which double as filters), search, the list, checkbox selection and the
 *              selection bar (confirm donors, bulk-set fields, commit). The row being worked sits in
 *              c-pending-transaction-editor on the right; commits from either place run through
 *              runCommit here so results are shown one way.
 *
 *              House rules carried over from the Board Management console (JSI-123):
 *                - loads on mount AND on every arrival (CurrentPageReference) - Lightning hands back the
 *                  same live component when you navigate in, and cached Apex would be stale;
 *                - every action that calls Apex locks its buttons while it runs (double-click safety).
 *
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 * 2026-09-16 - Jason Ott - Phase 4: Add transaction (opens the new row in the editor) and Delete from the
 *                          editor, with a confirmation, landing on the next row.
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getWorkspace from '@salesforce/apex/PendingTransactionController.getWorkspace';
import commitTransactions from '@salesforce/apex/PendingTransactionController.commitTransactions';
import confirmDonors from '@salesforce/apex/PendingTransactionController.confirmDonors';
import bulkUpdate from '@salesforce/apex/PendingTransactionController.bulkUpdate';
import deleteTransaction from '@salesforce/apex/PendingTransactionController.deleteTransaction';
import BulkEditModal from 'c/pendingTransactionBulkEdit';
import AddModal from 'c/pendingTransactionAdd';
import { errorMessage } from 'c/pendingTransactionUtils';

const STATUS_READY = 'Ready';
const STATUS_NEEDS_REVIEW = 'Needs Review';
const STATUS_ERROR = 'Error';

export default class PendingTransactions extends LightningElement {
    rows = [];
    options = {};
    truncated = false;
    maxPerCommit = 20;

    activeRowId;
    checkedIds = new Set();
    statusFilter = 'all';
    sourceFilter = 'all';
    search = '';

    loading = true;
    busy = false;
    committing = false;
    commitProgress = '';
    lastResults;

    seenFirstPageRef = false;

    // ---- lifecycle ----------------------------------------------------------------------------

    connectedCallback() {
        this.load();
    }

    /** Reload on each arrival; the first emission is skipped because connectedCallback just loaded. */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef) { return; }
        if (!this.seenFirstPageRef) { this.seenFirstPageRef = true; return; }
        this.load();
    }

    /** Loads the queue and option lists. Keeps the open row open if it still exists. */
    load() {
        this.loading = true;
        return getWorkspace()
            .then((ws) => {
                this.rows = ws.rows || [];
                this.truncated = ws.truncated;
                this.maxPerCommit = ws.maxPerCommit || 20;
                this.options = {
                    paymentMethods: ws.paymentMethods,
                    approaches: ws.approaches,
                    giftRecordTypes: ws.giftRecordTypes,
                    funds: ws.funds,
                    defaultGiftRecordType: ws.defaultGiftRecordType
                };
                const ids = new Set(this.rows.map((r) => r.id));
                this.checkedIds = new Set([...this.checkedIds].filter((id) => ids.has(id)));
                if (!ids.has(this.activeRowId)) {
                    this.activeRowId = this.visibleRows.length ? this.visibleRows[0].id : undefined;
                }
            })
            .catch((err) => this.toast(errorMessage(err), 'error'))
            .finally(() => { this.loading = false; });
    }

    handleRefresh() {
        this.withEditorSaved().then(() => this.load());
    }

    // ---- derived state ------------------------------------------------------------------------

    get tiles() {
        const sum = (list) => list.reduce((t, r) => t + (r.amount || 0), 0);
        const by = (s) => this.rows.filter((r) => r.status === s);
        const defs = [
            { key: 'all', label: 'Waiting', list: this.rows, tone: 'neutral' },
            { key: STATUS_READY, label: 'Ready to commit', list: by(STATUS_READY), tone: 'ready' },
            { key: STATUS_NEEDS_REVIEW, label: 'Needs review', list: by(STATUS_NEEDS_REVIEW), tone: 'review' },
            { key: STATUS_ERROR, label: 'Errors', list: by(STATUS_ERROR), tone: 'error' }
        ];
        return defs.map((d) => ({
            key: d.key,
            filter: d.key,
            label: d.label,
            count: d.list.length,
            total: sum(d.list),
            active: this.statusFilter === d.key,
            cssClass: `pt-tile pt-tile_${d.tone}${this.statusFilter === d.key ? ' pt-tile_active' : ''}`
        }));
    }

    get sourceOptions() {
        const sources = [...new Set(this.rows.map((r) => r.source).filter(Boolean))].sort();
        return [{ label: 'All sources', value: 'all' }, ...sources.map((s) => ({ label: s, value: s }))];
    }

    get visibleRows() {
        const term = (this.search || '').trim().toLowerCase();
        return this.rows
            .filter((r) => this.statusFilter === 'all' || r.status === this.statusFilter)
            .filter((r) => this.sourceFilter === 'all' || r.source === this.sourceFilter)
            .filter((r) => !term || this.haystack(r).includes(term))
            .map((r) => this.decorate(r));
    }

    /** Everything a person might type to find a row. */
    haystack(r) {
        return [r.name, r.payerName, r.payerEmail, r.memo, r.contactName, r.accountName, r.referenceNumber,
            r.depositReference, r.pledgeName, r.amount != null ? String(r.amount) : '']
            .filter(Boolean).join(' ').toLowerCase();
    }

    decorate(r) {
        const isActive = r.id === this.activeRowId;
        const tone = r.status === STATUS_READY ? 'ready' : r.status === STATUS_ERROR ? 'error' : 'review';
        return {
            ...r,
            isActive,
            isChecked: this.checkedIds.has(r.id),
            isPledgePayment: r.applyAs === 'Pledge Payment',
            checkLabel: `Select ${r.name}`,
            payerLabel: r.payerName || r.name,
            donorLabel: r.contactName || r.accountName || (r.matchStatus === 'Multiple Matches' ? 'Several possible donors' : 'No donor yet'),
            dotClass: `pt-dot pt-dot_${tone}`,
            cssClass: `pt-row${isActive ? ' pt-row_active' : ''}${this.checkedIds.has(r.id) ? ' pt-row_checked' : ''}`
        };
    }

    get activeRow() {
        return this.rows.find((r) => r.id === this.activeRowId);
    }

    get noVisibleRows() { return this.visibleRows.length === 0; }

    get emptyTitle() {
        return this.rows.length === 0 ? 'Nothing waiting' : 'No transactions match';
    }

    get emptySubtitle() {
        return this.rows.length === 0
            ? 'Every transaction has been committed.'
            : 'Try a different search or filter.';
    }

    get hasPrev() {
        const i = this.visibleRows.findIndex((r) => r.id === this.activeRowId);
        return i > 0;
    }

    get hasNext() {
        const list = this.visibleRows;
        const i = list.findIndex((r) => r.id === this.activeRowId);
        return i > -1 && i < list.length - 1;
    }

    get checkedRows() { return this.rows.filter((r) => this.checkedIds.has(r.id)); }
    get hasChecked() { return this.checkedIds.size > 0; }
    get checkedCount() { return this.checkedIds.size; }
    get checkedTotal() { return this.checkedRows.reduce((t, r) => t + (r.amount || 0), 0); }
    get checkedReady() { return this.checkedRows.filter((r) => r.status === STATUS_READY); }
    get checkedReadyCount() { return this.checkedReady.length; }
    get checkedSuggestedCount() { return this.checkedRows.filter((r) => r.matchStatus === 'Suggested').length; }
    get confirmDonorsLabel() { return `Confirm ${this.checkedSuggestedCount} suggested donor${this.checkedSuggestedCount === 1 ? '' : 's'}`; }
    get commitSelectedLabel() { return `Commit ${this.checkedReadyCount} ready`; }
    get commitSelectedDisabled() { return this.busy || this.checkedReadyCount === 0; }

    get allVisibleChecked() {
        const list = this.visibleRows;
        return list.length > 0 && list.every((r) => this.checkedIds.has(r.id));
    }

    get showResults() { return !!this.lastResults; }

    // ---- list interaction ---------------------------------------------------------------------

    handleTile(event) {
        const f = event.currentTarget.dataset.filter;
        this.statusFilter = this.statusFilter === f && f !== 'all' ? 'all' : f;
    }

    handleSearch(event) { this.search = event.target.value; }
    handleSource(event) { this.sourceFilter = event.detail.value; }
    stop(event) { event.stopPropagation(); }

    handleRowClick(event) {
        this.openRow(event.currentTarget.dataset.id);
    }

    handleRowCheck(event) {
        const id = event.target.dataset.id;
        const next = new Set(this.checkedIds);
        if (event.target.checked) { next.add(id); } else { next.delete(id); }
        this.checkedIds = next;
    }

    handleCheckAll(event) {
        const next = new Set(this.checkedIds);
        this.visibleRows.forEach((r) => (event.target.checked ? next.add(r.id) : next.delete(r.id)));
        this.checkedIds = next;
    }

    clearChecked() { this.checkedIds = new Set(); }

    /** Arrow keys move through the list, so a stack can be worked from the keyboard. */
    handleListKey(event) {
        if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') { return; }
        event.preventDefault();
        this.handleNavigate({ detail: event.key === 'ArrowDown' ? 'next' : 'prev' });
    }

    handleNavigate(event) {
        const list = this.visibleRows;
        const i = list.findIndex((r) => r.id === this.activeRowId);
        const j = event.detail === 'next' ? i + 1 : i - 1;
        if (j >= 0 && j < list.length) { this.openRow(list[j].id); }
    }

    /** Switching rows saves any unsaved edits first, so nothing typed is lost. */
    openRow(id) {
        if (id === this.activeRowId) { return; }
        this.withEditorSaved().then((ok) => { if (ok) { this.activeRowId = id; } });
    }

    /** Resolves true when the editor had nothing to save or saved successfully. */
    withEditorSaved() {
        const editor = this.template.querySelector('c-pending-transaction-editor');
        return editor ? editor.saveIfDirty().then(() => true).catch(() => false) : Promise.resolve(true);
    }

    handleRowSaved(event) {
        const saved = event.detail;
        this.rows = this.rows.map((r) => (r.id === saved.id ? saved : r));
    }

    dismissResults() { this.lastResults = undefined; }

    // ---- add & delete -------------------------------------------------------------------------

    /** Opens the Add form; the new row goes to the top of the list and opens in the editor. */
    handleAdd() {
        this.withEditorSaved()
            .then((ok) => (ok ? AddModal.open({ size: 'medium', paymentMethods: this.options.paymentMethods || [] }) : undefined))
            .then((row) => {
                if (!row) { return; }
                this.rows = [row, ...this.rows.filter((r) => r.id !== row.id)];
                // Make sure filters don't hide the row just added.
                this.statusFilter = 'all';
                this.sourceFilter = 'all';
                this.search = '';
                this.activeRowId = row.id;
            })
            .catch((err) => this.toast(errorMessage(err), 'error'));
    }

    /** From the editor. Confirms first - a deleted transaction is gone and never becomes a gift. */
    async handleDelete(event) {
        const row = this.rows.find((r) => r.id === event.detail.rowId);
        if (!row) { return; }
        const who = row.contactName || row.accountName || row.payerName;
        const ok = await LightningConfirm.open({
            label: 'Delete transaction',
            message: `Delete ${row.name} (${this.money(row.amount)}${who ? ' from ' + who : ''})? It is removed permanently and no gift or payment is created.`,
            theme: 'error'
        });
        if (!ok) { return; }

        const nextId = this.rowAfter([row.id]);
        this.busy = true;
        try {
            await deleteTransaction({ rowId: row.id });
            this.toast(`${row.name} deleted`, 'success');
            this.checkedIds = new Set([...this.checkedIds].filter((id) => id !== row.id));
            this.rows = this.rows.filter((r) => r.id !== row.id);
            this.activeRowId = nextId;
            await this.load();
        } catch (err) {
            this.toast(errorMessage(err), 'error');
        } finally {
            this.busy = false;
        }
    }

    // ---- selection actions --------------------------------------------------------------------

    handleConfirmDonors() {
        const ids = this.checkedRows.filter((r) => r.matchStatus === 'Suggested').map((r) => r.id);
        this.busy = true;
        this.withEditorSaved()
            .then(() => confirmDonors({ rowIds: ids }))
            .then((n) => { this.toast(`${n} donor${n === 1 ? '' : 's'} confirmed`, 'success'); return this.load(); })
            .catch((err) => this.toast(errorMessage(err), 'error'))
            .finally(() => { this.busy = false; });
    }

    handleBulkEdit() {
        const ids = [...this.checkedIds];
        this.withEditorSaved()
            .then(() => BulkEditModal.open({
                size: 'small',
                label: `Set fields on ${ids.length} transaction${ids.length === 1 ? '' : 's'}`,
                count: ids.length,
                options: this.options
            }))
            .then((fields) => {
                if (!fields) { return undefined; }
                this.busy = true;
                return bulkUpdate({ rowIds: ids, fieldsJson: JSON.stringify(fields) })
                    .then((n) => { this.toast(`Updated ${n} transaction${n === 1 ? '' : 's'}`, 'success'); return this.load(); });
            })
            .catch((err) => this.toast(errorMessage(err), 'error'))
            .finally(() => { this.busy = false; });
    }

    /** Saves the open editor first - its row may be selected, and its status may change on save. */
    handleCommitSelected() {
        this.withEditorSaved().then((ok) => {
            if (!ok) { return; }
            const ready = this.checkedReady;
            this.runCommit(ready, this.checkedCount - ready.length);
        });
    }

    /** From the editor: that row only (the editor has already saved it). */
    handleCommitOne(event) {
        const row = this.rows.find((r) => r.id === event.detail.rowId);
        if (row) { this.runCommit([row], 0, true); }
    }

    /**
     * Confirms, then commits in chunks the server accepts, one after another. Rows that committed
     * disappear on reload; rows that failed stay with their error, and the results panel lists both.
     */
    async runCommit(rows, skipped, single = false) {
        if (!rows.length) { return; }
        const total = rows.reduce((t, r) => t + (r.amount || 0), 0);
        const gifts = rows.filter((r) => r.applyAs !== 'Pledge Payment').length;
        const payments = rows.length - gifts;

        if (!single) {
            const parts = [];
            if (gifts) { parts.push(`${gifts} new gift${gifts === 1 ? '' : 's'}`); }
            if (payments) { parts.push(`${payments} pledge payment${payments === 1 ? '' : 's'}`); }
            const note = skipped ? ` ${skipped} selected transaction${skipped === 1 ? ' is' : 's are'} not ready and will be skipped.` : '';
            const ok = await LightningConfirm.open({
                label: 'Commit transactions',
                message: `Commit ${parts.join(' and ')} totalling ${this.money(total)}? Each committed transaction is removed from this list.${note}`,
                theme: 'default'
            });
            if (!ok) { return; }
        }

        const nextId = this.rowAfter(rows.map((r) => r.id));
        this.busy = true;
        this.committing = true;
        const results = [];
        try {
            for (let i = 0; i < rows.length; i += this.maxPerCommit) {
                const chunk = rows.slice(i, i + this.maxPerCommit).map((r) => r.id);
                this.commitProgress = `Committing ${Math.min(i + chunk.length, rows.length)} of ${rows.length}…`;
                // Sequential on purpose: each chunk's gifts run NPSP and JCRC automation server-side.
                // eslint-disable-next-line no-await-in-loop
                const res = await commitTransactions({ rowIds: chunk });
                results.push(...res);
            }
        } catch (err) {
            this.toast(errorMessage(err), 'error');
        }

        const succeeded = results.filter((r) => r.success).length;
        const failed = results.length - succeeded;
        this.lastResults = {
            succeeded,
            failed,
            items: results.map((r) => ({
                ...r,
                icon: r.success ? 'utility:success' : 'utility:error',
                cssClass: `pt-result ${r.success ? 'pt-result_ok' : 'pt-result_fail'}`,
                recordUrl: r.success && r.recordId ? `/lightning/r/Opportunity/${r.recordId}/view` : undefined
            }))
        };
        if (succeeded) {
            this.toast(`${succeeded} transaction${succeeded === 1 ? '' : 's'} committed`, failed ? 'warning' : 'success');
        } else if (failed) {
            this.toast('Nothing was committed - see the errors below', 'error');
        }

        const committedIds = new Set(results.filter((r) => r.success).map((r) => r.rowId));
        this.checkedIds = new Set([...this.checkedIds].filter((id) => !committedIds.has(id)));
        if (committedIds.has(this.activeRowId)) { this.activeRowId = nextId; }
        await this.load();
        this.committing = false;
        this.busy = false;
        this.commitProgress = '';
    }

    /** The first visible row not being committed, after the current one - where to land next. */
    rowAfter(ids) {
        const leaving = new Set(ids);
        const list = this.visibleRows;
        const i = Math.max(0, list.findIndex((r) => r.id === this.activeRowId));
        const after = list.slice(i).find((r) => !leaving.has(r.id)) || list.find((r) => !leaving.has(r.id));
        return after ? after.id : undefined;
    }

    // ---- helpers ------------------------------------------------------------------------------

    money(n) {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n || 0);
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }
}