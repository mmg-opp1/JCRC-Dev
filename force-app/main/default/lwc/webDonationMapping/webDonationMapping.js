import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMappings from '@salesforce/apex/WebDonationMappingController.getMappings';
import getObjects from '@salesforce/apex/WebDonationMappingController.getObjects';
import getFields from '@salesforce/apex/WebDonationMappingController.getFields';
import dryRun from '@salesforce/apex/WebDonationMappingController.dryRun';
import saveMappings from '@salesforce/apex/WebDonationMappingController.saveMappings';

/**
 * Web Donation Mapping - decides which Gravity Forms payload key populates which Salesforce
 * field, so adding a form field is configuration rather than a code change.
 *
 * Three things here matter more than the grid:
 *   - target fields come from a DESCRIBE, so an API name cannot be mistyped;
 *   - the dry run shows what a REAL payload would write, without writing anything;
 *   - unmapped payload keys are listed, which is how a changed form gets noticed by the
 *     team rather than by a donor.
 */
export default class WebDonationMapping extends LightningElement {
    @track rows = [];
    @track objectOptions = [];
    @track fieldOptionsByObject = {};
    @track dry = null;

    loading = true;
    saving = false;
    samplePayload = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [maps, objs] = await Promise.all([getMappings(), getObjects()]);
            this.objectOptions = objs.map((o) => ({ label: o, value: o }));
            await Promise.all(objs.map((o) => this.loadFields(o)));
            this.rows = maps.map((m, i) => this.decorate(m, i));
        } catch (e) {
            this.toast('Could not load mappings', this.readError(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    async loadFields(objectName) {
        if (this.fieldOptionsByObject[objectName]) return;
        const fields = await getFields({ objectName });
        this.fieldOptionsByObject = {
            ...this.fieldOptionsByObject,
            [objectName]: fields.map((f) => ({ label: f.label, value: f.value }))
        };
    }

    decorate(m, index) {
        return {
            ...m,
            key: m.developerName || `new-${index}-${Date.now()}`,
            fieldOptions: this.fieldOptionsByObject[m.targetObject] || [],
            // A mapping pointing at a deleted field is the quiet failure worth shouting about.
            warning: m.targetExists === false
                ? `${m.targetObject}.${m.targetField} no longer exists`
                : null
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get busy() {
        return this.loading || this.saving;
    }

    get dryRunHasProblems() {
        return !!this.dry && this.dry.problems && this.dry.problems.length > 0;
    }

    get hasUnmapped() {
        return !!this.dry && this.dry.unmapped && this.dry.unmapped.length > 0;
    }

    handleAdd() {
        this.rows = [
            ...this.rows,
            this.decorate(
                {
                    developerName: null,
                    payloadKey: '',
                    targetObject: 'Contact',
                    targetField: '',
                    active: true,
                    notes: '',
                    targetExists: true
                },
                this.rows.length
            )
        ];
    }

    handleRemove(event) {
        const key = event.target.dataset.key;
        this.rows = this.rows.filter((r) => r.key !== key);
    }

    async handleChange(event) {
        const { key, field } = event.target.dataset;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : event.detail?.value ?? event.target.value;

        if (field === 'targetObject') {
            await this.loadFields(value);
        }

        this.rows = this.rows.map((r) => {
            if (r.key !== key) return r;
            const next = { ...r, [field]: value };
            if (field === 'targetObject') {
                next.targetField = '';
                next.fieldOptions = this.fieldOptionsByObject[value] || [];
            }
            return next;
        });
    }

    handleSampleChange(event) {
        this.samplePayload = event.target.value;
    }

    async handleDryRun() {
        if (!this.samplePayload) {
            this.toast('Paste a payload first', 'Copy the Raw Payload from a Web Donation record.', 'warning');
            return;
        }
        try {
            this.dry = await dryRun({ payloadJson: this.samplePayload });
        } catch (e) {
            this.toast('Dry run failed', this.readError(e), 'error');
        }
    }

    async handleSave() {
        this.saving = true;
        try {
            const payload = this.rows.map((r) => ({
                developerName: r.developerName,
                label: r.label,
                payloadKey: r.payloadKey,
                targetObject: r.targetObject,
                targetField: r.targetField,
                active: r.active,
                notes: r.notes
            }));
            await saveMappings({ rowsJson: JSON.stringify(payload) });
            // Custom Metadata writes go through the Metadata API and are asynchronous, so
            // this is deliberately worded as "submitted" rather than "saved".
            this.toast(
                'Save submitted',
                'Salesforce is deploying the mapping change. Refresh in a few seconds to confirm.',
                'success'
            );
        } catch (e) {
            this.toast('Save failed', this.readError(e), 'error', 'sticky');
        } finally {
            this.saving = false;
        }
    }

    handleRefresh() {
        this.load();
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
