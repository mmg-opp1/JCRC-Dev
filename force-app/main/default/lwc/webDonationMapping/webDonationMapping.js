import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMappings from '@salesforce/apex/WebDonationMappingController.getMappings';
import getObjects from '@salesforce/apex/WebDonationMappingController.getObjects';
import getFields from '@salesforce/apex/WebDonationMappingController.getFields';
import dryRun from '@salesforce/apex/WebDonationMappingController.dryRun';
import saveMappings from '@salesforce/apex/WebDonationMappingController.saveMappings';
import getValueMaps from '@salesforce/apex/WebDonationMappingController.getValueMaps';
import saveValueMaps from '@salesforce/apex/WebDonationMappingController.saveValueMaps';
import getLookupObjects from '@salesforce/apex/WebDonationMappingController.getLookupObjects';
import getLookupRecords from '@salesforce/apex/WebDonationMappingController.getLookupRecords';
import getSettings from '@salesforce/apex/WebDonationMappingController.getSettings';
import saveSettings from '@salesforce/apex/WebDonationMappingController.saveSettings';

const TYPE_OPTIONS = [
    { label: 'Payload value', value: 'Payload' },
    { label: 'Static value', value: 'Static' },
    { label: 'Lookup (translate to a record)', value: 'Lookup' }
];

/**
 * Web Donation Mapping - everything that decides how a website submission becomes a donor
 * and a gift:
 *   Field mapping   - which payload key fills which field, or a static value, or a lookup
 *   Value translation - "Other:" becomes the Website Donation - Other campaign
 *   Donor & account settings - how contacts are matched, and where the gift is accounted
 *   Dry run - what a REAL payload would do, without writing anything
 */
export default class WebDonationMapping extends LightningElement {
    @track rows = [];
    @track valueRows = [];
    @track settings = {};
    @track objectOptions = [];
    @track fieldOptionsByObject = {};
    @track lookupObjectOptions = [];
    @track lookupRecordsByObject = {};
    @track dry = null;

    loading = true;
    saving = false;
    samplePayload = '';
    activeTab = 'fields';

    typeOptions = TYPE_OPTIONS;

    // ---- static option lists, kept in step with the Custom Metadata picklists ----------
    matchRuleOptions = [
        { label: 'Email only (exact)', value: 'Email' },
        { label: 'Email, else First + Last name', value: 'EmailOrFirstLast' },
        { label: 'First + Last + Email all match', value: 'FirstLastEmail' },
        { label: 'Never match - always create', value: 'None' }
    ];
    noMatchOptions = [
        { label: 'Create a new contact', value: 'Create' },
        { label: 'Fail the submission for review', value: 'Fail' }
    ];
    multiMatchOptions = [
        { label: 'Use the oldest record', value: 'Oldest' },
        { label: 'Use the newest record', value: 'Newest' },
        { label: 'Fail the submission for review', value: 'Fail' }
    ];
    accountOptions = [
        { label: 'Leave to NPSP (household account)', value: 'NPSPDefault' },
        { label: 'Use the organisation when the form supplies one', value: 'MatchOrganization' },
        { label: 'Always use an organisation account', value: 'AlwaysOrganization' }
    ];
    orgNoMatchOptions = [
        { label: 'Create the organisation account', value: 'CreateAccount' },
        { label: 'Fall back to the household account', value: 'UseHousehold' },
        { label: 'Fail the submission for review', value: 'Fail' }
    ];

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [maps, objs, vmaps, lobjs, settings] = await Promise.all([
                getMappings(),
                getObjects(),
                getValueMaps(),
                getLookupObjects(),
                getSettings()
            ]);
            this.objectOptions = objs.map((o) => ({ label: o, value: o }));
            this.lookupObjectOptions = lobjs.map((o) => ({ label: o, value: o }));
            this.settings = { ...settings };

            await Promise.all(objs.map((o) => this.loadFields(o)));
            await Promise.all(lobjs.map((o) => this.loadLookupRecords(o)));

            this.rows = maps.map((m, i) => this.decorate(m, i));
            this.valueRows = vmaps.map((v, i) => this.decorateValue(v, i));
        } catch (e) {
            this.toast('Could not load', this.readError(e), 'error');
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

    async loadLookupRecords(objectName) {
        if (objectName === 'Literal' || this.lookupRecordsByObject[objectName]) return;
        const recs = await getLookupRecords({ objectName });
        this.lookupRecordsByObject = {
            ...this.lookupRecordsByObject,
            [objectName]: recs.map((r) => ({ label: r, value: r }))
        };
    }

    decorate(m, index) {
        const type = m.mappingType || 'Payload';
        return {
            ...m,
            mappingType: type,
            key: m.developerName || `new-${index}-${Date.now()}`,
            fieldOptions: this.fieldOptionsByObject[m.targetObject] || [],
            isStatic: type === 'Static',
            isPayload: type === 'Payload',
            isLookup: type === 'Lookup',
            // A mapping pointing at a deleted field is the quiet failure worth shouting about.
            warning:
                m.targetExists === false
                    ? `${m.targetObject}.${m.targetField} no longer exists`
                    : null
        };
    }

    decorateValue(v, index) {
        return {
            ...v,
            key: v.developerName || `newv-${index}-${Date.now()}`,
            recordOptions: this.lookupRecordsByObject[v.targetObject] || [],
            warning:
                v.recordExists === false && v.targetObject !== 'Literal'
                    ? `No ${v.targetObject} named "${v.targetRecordName}"`
                    : null
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }
    get hasValueRows() {
        return this.valueRows.length > 0;
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
    get needsOrgKey() {
        return this.settings.accountHandling === 'MatchOrganization';
    }

    // ---- field mapping rows -------------------------------------------------------------

    handleAdd() {
        this.rows = [
            ...this.rows,
            this.decorate(
                {
                    developerName: null,
                    payloadKey: '',
                    targetObject: 'Contact',
                    targetField: '',
                    mappingType: 'Payload',
                    staticValue: '',
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
            event.target.type === 'checkbox'
                ? event.target.checked
                : event.detail?.value ?? event.target.value;

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
            if (field === 'mappingType') {
                next.isStatic = value === 'Static';
                next.isPayload = value === 'Payload';
                next.isLookup = value === 'Lookup';
            }
            return next;
        });
    }

    // ---- value translations --------------------------------------------------------------

    handleAddValue() {
        this.valueRows = [
            ...this.valueRows,
            this.decorateValue(
                {
                    developerName: null,
                    payloadKey: '',
                    incomingValue: '',
                    targetObject: 'Campaign',
                    targetRecordName: '',
                    active: true,
                    recordExists: true
                },
                this.valueRows.length
            )
        ];
    }

    handleRemoveValue(event) {
        const key = event.target.dataset.key;
        this.valueRows = this.valueRows.filter((r) => r.key !== key);
    }

    async handleValueChange(event) {
        const { key, field } = event.target.dataset;
        const value =
            event.target.type === 'checkbox'
                ? event.target.checked
                : event.detail?.value ?? event.target.value;

        if (field === 'targetObject') {
            await this.loadLookupRecords(value);
        }

        this.valueRows = this.valueRows.map((r) => {
            if (r.key !== key) return r;
            const next = { ...r, [field]: value };
            if (field === 'targetObject') {
                next.targetRecordName = '';
                next.recordOptions = this.lookupRecordsByObject[value] || [];
            }
            return next;
        });
    }

    // ---- settings --------------------------------------------------------------------------

    handleSettingChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        this.settings = { ...this.settings, [field]: value };
    }

    // ---- dry run ----------------------------------------------------------------------------

    handleSampleChange(event) {
        this.samplePayload = event.target.value;
    }

    async handleDryRun() {
        if (!this.samplePayload) {
            this.toast(
                'Paste a payload first',
                'Copy the Raw Payload from a Web Donation record.',
                'warning'
            );
            return;
        }
        try {
            this.dry = await dryRun({ payloadJson: this.samplePayload });
        } catch (e) {
            this.toast('Dry run failed', this.readError(e), 'error');
        }
    }

    // ---- saving ------------------------------------------------------------------------------

    async handleSave() {
        this.saving = true;
        try {
            const fieldPayload = this.rows.map((r) => ({
                developerName: r.developerName,
                label: r.label,
                payloadKey: r.payloadKey,
                targetObject: r.targetObject,
                targetField: r.targetField,
                mappingType: r.mappingType,
                staticValue: r.staticValue,
                lookupObject: r.lookupObject,
                active: r.active,
                notes: r.notes
            }));
            const valuePayload = this.valueRows.map((r) => ({
                developerName: r.developerName,
                label: r.label,
                payloadKey: r.payloadKey,
                incomingValue: r.incomingValue,
                targetObject: r.targetObject,
                targetRecordName: r.targetRecordName,
                active: r.active
            }));

            await saveMappings({ rowsJson: JSON.stringify(fieldPayload) });
            if (valuePayload.length) {
                await saveValueMaps({ rowsJson: JSON.stringify(valuePayload) });
            }
            await saveSettings({ settingsJson: JSON.stringify(this.settings) });

            // Custom Metadata writes go through the Metadata API and are asynchronous, so this
            // is deliberately "submitted" rather than "saved".
            this.toast(
                'Save submitted',
                'Salesforce is deploying the change. Refresh in a few seconds to confirm.',
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