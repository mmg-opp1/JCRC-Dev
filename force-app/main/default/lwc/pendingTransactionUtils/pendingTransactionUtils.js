/**
 * @description Shared helpers for the Pending Transactions components (JSI-121).
 * @author Jason Ott
 * @created 2026-09-16
 *
 * Change Log:
 * -----------
 * 2026-09-16 - Jason Ott - Initial version (JSI-121 Phase 3).
 */

/**
 * The readable message from an Apex/LDS error. Salesforce puts it in different places depending on
 * where it was raised (JSI-123 gotcha: err.body.message is not always set).
 */
export function errorMessage(err) {
    if (!err) { return 'Something went wrong'; }
    if (Array.isArray(err.body)) { return err.body.map((e) => e.message).join(', '); }
    if (err.body && err.body.message) { return err.body.message; }
    if (err.body && err.body.pageErrors && err.body.pageErrors.length) { return err.body.pageErrors[0].message; }
    if (err.body && err.body.output && err.body.output.errors && err.body.output.errors.length) {
        return err.body.output.errors[0].message;
    }
    if (err.message) { return err.message; }
    return 'Something went wrong';
}

/** $1,234.56 */
export function formatMoney(n) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n || 0);
}

/** "Sep 8, 2026" from a Salesforce date string (yyyy-mm-dd), without a timezone shift. */
export function formatDate(value) {
    if (!value) { return ''; }
    const [y, m, d] = String(value).split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
}
