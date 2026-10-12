/**
 * @description flowModalLauncher - opens any active screen flow in a modal, from a URL.
 *
 *              Built for custom list buttons (a related list on a page layout, or Dynamic Related List -
 *              Single): a standard flow button opens the flow in a new window; a list button pointed at
 *              this component's URL opens the flow in a modal instead. One component serves every button -
 *              each button's URL says which flow to run and how. Nothing is configured anywhere else.
 *
 *              Button URL (Content Source = URL, Behavior = Display in existing window without sidebar or
 *              header):
 *                /lightning/cmp/c__flowModalLauncher?c__flow=Screen_BulkAddTickets
 *                    &c__recordId={!Event_Registration__c.Id}&c__inputVariable=vEventRegistrationId
 *
 *              URL parameters (all values are text; names are case-sensitive):
 *                c__flow           REQUIRED. API name of an ACTIVE screen flow.
 *                c__recordId       The record the button was clicked from (usually the parent). Passed to
 *                                  the flow and where the user returns to.
 *                c__inputVariable  The flow's input variable that receives c__recordId. Default: recordId.
 *                                  Must be a Text variable marked "Available for input".
 *                c__title          Modal heading. Default: New.
 *                c__size           small | medium | large. Default: medium.
 *                c__finish         Where the user lands when the flow finishes:
 *                                    parent (default) - back to c__recordId;
 *                                    record - the record whose Id the flow returns in c__outputVariable
 *                                             (falls back to parent if the flow returns none).
 *                c__outputVariable With c__finish=record: the flow's output variable holding the new
 *                                  record's Id (marked "Available for output").
 *
 *              Closing the modal (X, Cancel or Escape) returns to c__recordId without finishing the flow.
 *              With no c__recordId to return to, it goes back in the browser history.
 *
 *              The flow runs as the user, exactly as it would from any other flow button - this component
 *              grants no access. Navigation uses replace, so Back does not reopen the modal; the record
 *              landed on is told its data may have changed, so its related lists show the new rows.
 *
 *              Limitation (platform): a URL-addressable component is its own page, so the record page is
 *              not visible behind the modal - the modal sits on a dimmed backdrop. Supported in Lightning
 *              Experience, the Salesforce mobile app and console apps; not Experience Cloud sites.
 *
 * @author Jason Ott
 * @created 2026-10-12
 *
 * Change Log:
 * -----------
 * 2026-10-12 - Jason Ott - Initial version.
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

const SIZES = { small: 'slds-modal_small', medium: 'slds-modal_medium', large: 'slds-modal_large' };
const ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;

export default class FlowModalLauncher extends NavigationMixin(LightningElement) {
    flowApiName;
    recordId;
    inputVariable = 'recordId';
    title = 'New';
    size = 'medium';
    finish = 'parent';
    outputVariable;

    /** Set when the URL cannot be used; shown in place of the flow. */
    configError;
    flowError;
    /** Bumped on each arrival so lightning-flow restarts if the same URL is opened twice in a row. */
    runKey = 0;
    leaving = false;
    /** Focus moves into the dialog once per visit. */
    focused = false;

    // ---- arrival ------------------------------------------------------------------------------

    /**
     * Reads the button's settings from the URL. Lightning can hand back the same live component when the
     * user opens another launcher URL, so every arrival resets the state rather than relying on a fresh
     * instance.
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef) { return; }
        const s = pageRef.state || {};
        this.flowApiName = (s.c__flow || '').trim();
        this.recordId = (s.c__recordId || '').trim() || undefined;
        this.inputVariable = (s.c__inputVariable || '').trim() || 'recordId';
        this.title = (s.c__title || '').trim() || 'New';
        this.size = SIZES[s.c__size] ? s.c__size : 'medium';
        this.finish = s.c__finish === 'record' ? 'record' : 'parent';
        this.outputVariable = (s.c__outputVariable || '').trim() || undefined;
        this.flowError = undefined;
        this.leaving = false;
        this.focused = false;
        this.configError = this.validate();
        this.runKey += 1;
    }

    /** Says what is wrong with the button's URL, so whoever set it up can fix it. */
    validate() {
        if (!this.flowApiName) {
            return 'This button does not say which flow to run. Add c__flow=YourFlowApiName to its URL.';
        }
        if (this.recordId && !ID_PATTERN.test(this.recordId)) {
            return `"${this.recordId}" is not a record Id. Check the c__recordId merge field in the button URL.`;
        }
        if (this.finish === 'record' && !this.outputVariable) {
            return 'c__finish=record needs c__outputVariable - the flow output variable that holds the new record Id.';
        }
        return undefined;
    }

    connectedCallback() {
        this.keyHandler = (e) => { if (e.key === 'Escape') { this.handleClose(); } };
        window.addEventListener('keydown', this.keyHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this.keyHandler);
    }

    renderedCallback() {
        // Put focus in the dialog once, for keyboard and screen-reader users.
        if (!this.focused) {
            const close = this.template.querySelector('.fml-close');
            if (close) { close.focus(); this.focused = true; }
        }
    }

    // ---- template state -----------------------------------------------------------------------

    get showFlow() { return !this.configError && !this.flowError && !this.leaving; }

    get flowInputs() {
        return this.recordId ? [{ name: this.inputVariable, type: 'String', value: this.recordId }] : [];
    }

    get modalClass() { return `slds-modal slds-fade-in-open ${SIZES[this.size]}`; }

    get errorMessage() { return this.configError || this.flowError; }

    get flowKeyed() { return [{ key: `run-${this.runKey}` }]; }

    // ---- flow events --------------------------------------------------------------------------

    /**
     * FINISHED / FINISHED_SCREEN: leave as the button says. ERROR: keep the modal open with the message,
     * since leaving would hide why nothing happened.
     */
    handleStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            let target = this.recordId;
            if (this.finish === 'record') {
                const out = (event.detail.outputVariables || []).find((v) => v.name === this.outputVariable);
                const value = out && Array.isArray(out.value) ? out.value[0] : out && out.value;
                if (value && ID_PATTERN.test(String(value))) { target = String(value); }
            }
            this.leave(target);
        } else if (status === 'ERROR') {
            this.flowError = `The flow "${this.flowApiName}" could not run. Check that it is an active screen flow `
                + `and that "${this.inputVariable}" is a Text input variable.`;
        }
    }

    handleClose() {
        if (this.leaving) { return; }
        this.leave(this.recordId);
    }

    // ---- navigation ---------------------------------------------------------------------------

    /**
     * Goes to the record (replacing this page in history, so Back doesn't reopen the modal) after telling
     * Lightning the record may have changed, so its related lists reload. No record: browser back.
     */
    leave(targetId) {
        this.leaving = true;
        if (!targetId) {
            window.history.back();
            return;
        }
        notifyRecordUpdateAvailable([{ recordId: targetId }])
            .catch(() => { /* cache refresh is best effort; navigation still happens */ })
            .finally(() => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: targetId, actionName: 'view' }
                }, true);
            });
    }
}
