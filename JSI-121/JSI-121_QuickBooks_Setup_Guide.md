# JSI-121 Phase 5 — QuickBooks → Salesforce: Setup Guide

> **Author:** Jason Ott · **Date:** 2026-09-16 · **Status:** step 1 (the Salesforce endpoint) ✅ built and live in
> JCRC-Dev 2026-09-17 — your steps (§3, §4) can start.
> Scope: ACH and wire transactions recorded in QuickBooks Online arrive in Salesforce as Pending
> Transactions. **Never Stripe / credit-card money** (decided 2026-09-16).
> Everything below is for **JCRC-Dev + the QuickBooks sandbox company first**. Production is §6.

---

## 1. How it works

```
QuickBooks Online (Finance records an ACH/wire)
   │  webhook: POST, CloudEvents JSON, signed (intuit-signature header)
   ▼
Salesforce Site "hooks"  →  Apex REST /qbo/webhook   (guest user, must answer 200 in < 3 s)
   │   1. verify the HMAC-SHA256 signature with the verifier token      ← before anything else
   │   2. check the company (realm) id is ours
   │   3. store one QuickBooks Event row per event, dedupe on the event id
   │   4. return 200
   ▼
Scheduled processor (runs as an administrator, every few minutes)
   │   GET the deposit / sales receipt / payment from the QuickBooks API  (Named Credential, OAuth 2.0)
   │   keep ACH and wire only  →  map  →  upsert Pending_Transaction__c on External ID
   ▼
Pending Transactions screen (already built) → staff review → commit
```

**Why two steps.** A QuickBooks webhook only says *"deposit 1234 was created in company X"* — it carries **no
transaction data**, so Salesforce must call the QuickBooks API to read it. And the guest user behind a public
endpoint can't make authenticated callouts or run the gift logic — the lesson from website donations (Sept 10).
So the endpoint only stores the notification; an admin-context job does the rest.

**Safety net (recommended).** Webhooks aren't guaranteed: Intuit retries a failed delivery (10 s, 20 s, 30 s,
5 min, 20 min, 2 h, 4 h, 6 h, then every 6 h) but ordering isn't guaranteed and an outage can still lose events.
A nightly job calls QuickBooks' **Change Data Capture** API (covers the last **30 days**) and picks up anything
the webhooks missed. Both paths record every QuickBooks transaction they've seen, so a transaction **deleted**
on the Pending Transactions screen is never re-imported (the Phase 4 requirement).

**What only you can do** is anything involving secrets or logins: the Intuit app keys, the OAuth connection,
and the webhook verifier token. None of those go in git.

---

## 2. Before you start — questions for Finance (Simcha)

The mapping can't be finished without these. Ideally, **record two or three real-looking examples in the
QuickBooks sandbox company exactly the way Finance does it**, and I'll map from the actual API responses
rather than guess.

1. When an ACH or wire donation arrives, what does Finance create in QuickBooks: a **Bank Deposit**, a
   **Sales Receipt**, or a **Receive Payment** against an invoice? (Could be different for ACH vs wire.)
2. Is it **one QuickBooks transaction per donor**, or **one deposit with a line per donor**?
3. How is it marked as ACH or wire — **Payment Method** values (exact names), the deposit account, or memo text?
4. Where does the **donor's name** live — the Customer ("Received From"), the memo, or the bank description?
5. Is the **fund** recorded — a **Class**, **Location**, product/service item, or account?
6. Anything campaign-like recorded at all?

---

## 3. Intuit Developer portal (you)

Portal labels change occasionally; if something is named differently, tell me what you see.

**A1. The app.** In your developer account, open the app (or create one) for **QuickBooks Online and
Payments** with the **Accounting** scope (`com.intuit.quickbooks.accounting`). One app covers sandbox and
production — they just have separate keys and settings.

**A2. Development keys.** Under the app's **Development** settings → **Keys & credentials**, copy the
**Client ID** and **Client Secret** (you'll paste them into Salesforce in B1 — don't send them to me).

**A3. Redirect URI.** On the same page add the **Callback URL Salesforce shows you in step B1**. It must match
exactly. (Do B1 first, then come back here.)

**A4. Sandbox company.** In the portal's **Sandboxes** area, note the sandbox company's **Company ID /
Realm ID** (a number). Record Finance's sample transactions there (§2).

**A5. Webhooks — wait until I've deployed the endpoint (§5 step 1).** Then, under the app's **Development**
settings → **Webhooks**:
- **Endpoint URL:** `https://jcrcny--dev.sandbox.my.salesforce-sites.com/services/apexrest/qbo/webhook`
- **Entities:** tick **Deposit**, **SalesReceipt** and **Payment** (whichever Finance uses, §2) with
  **Create, Update, Delete and Void**. *Please tell me whether Deposit appears in the list — I couldn't confirm
  from Intuit's public docs that deposits are webhook-enabled. If it isn't there, the nightly Change Data
  Capture job becomes the main path for deposits.*
- **Payload format: CloudEvents.** Intuit moved webhooks to the CloudEvents format; the old format's cut-off
  was **July 31, 2026**, so we build for CloudEvents only.
- **Verifier token:** copy it (you'll paste it into Salesforce in B6).

---

## 4. Salesforce Setup — JCRC-Dev (you)

Same pattern as the Constant Contact connection (JSI-107), which is working.

**B1. External Auth Identity Provider** — Setup → Named Credentials → *External Auth Identity Providers* →
New:
- Label / Name: `QuickBooks`
- Authentication Protocol: **OAuth 2.0**, Authentication Flow: **Authorization Code**
- Client ID / Client Secret: from A2
- Authorize Endpoint URL: `https://appcenter.intuit.com/connect/oauth2`
- Token Endpoint URL: `https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer`
- Client authentication: **Client Secret Basic** (Intuit accepts basic or post)
- Save, then **copy the Callback URL** Salesforce displays → Intuit **A3**.

*(Endpoints verified against Intuit's discovery documents `developer.api.intuit.com/.well-known/
openid_configuration` and `…/openid_sandbox_configuration` — sandbox and production use the same two.)*

**B2. External Credential** — New:
- Label / Name: `QuickBooks`, Authentication Protocol **OAuth 2.0**, flow **Browser Flow**, Identity Provider
  **QuickBooks** (B1)
- Principal: **Named Principal**, name `QBO_Principal`, **Scope**: `com.intuit.quickbooks.accounting`

**B3. Named Credential** — New:
- Label / Name: `QuickBooks`
- URL (sandbox): `https://sandbox-quickbooks.api.intuit.com` *(production: `https://quickbooks.api.intuit.com`)*
- External Credential: **QuickBooks**; **Generate Authorization Header** on.

**B4. Principal access** — once you've created B2, tell me: I'll grant `QuickBooks-QBO_Principal` on the
**System Administrator** profile in metadata (profile-based, per our standard; it can only be granted after the
principal exists).

**B5. Authenticate** — on the External Credential, principal `QBO_Principal` → **Authenticate**. Sign in with a
QuickBooks user who is an **admin of the sandbox company**, choose that company, and **approve access**.
- ⚠ Constant Contact lesson: if you're already signed in to Intuit, it may skip the consent screen and leave
  the principal *"Not Configured"* despite a success message. Use a private window so the consent screen shows.
  I'll confirm the real status from the API afterwards.

**B6. Paste the secrets** — once I deploy the settings object (§5 step 1): Setup → Custom Settings →
**QuickBooks Settings** → Manage → New (organization default):
- **Verifier Token** — from A5
- **Company ID (Realm ID)** — from A4
- **Enabled** — tick when ready

Intuit doesn't return the company id to Salesforce's OAuth flow in a way Salesforce stores, so it's entered
here; the endpoint also rejects webhooks from any other company.

---

## 5. Order of operations

| # | Who | Step |
|---|---|---|
| 1 ✅ | Claude | **Done 2026-09-17.** Deploy the receiver: `QuickBooks_Event__c` staging object, protected **QuickBooks Settings** custom setting, `QuickBooksWebhookReceiver` on the `hooks` site, guest access limited to creating events, principal access on the Admin profile. Tests prove signature checks, bad-signature rejection, dedupe. |
| 2 | Jason | A1–A4, B1–B3, A3, B5 (connect), B6 (paste token/realm) |
| 3 | Claude | Confirm the OAuth principal is really Configured; make a read-only test call (company info). |
| 4 | Jason | A5 — turn on webhooks (CloudEvents). Record a sample transaction in the sandbox company. |
| 5 | Claude | Watch the event land; fetch the real transaction JSON; map it with Finance's answers (§2). |
| 6 | Claude | Build the processor (scheduled, admin context) + nightly Change Data Capture safety net; tests; live end-to-end in sandbox. |
| 7 | Both | UAT on the Pending Transactions screen with sandbox-company data. |

---

## 6. Production (later)

- **Production keys:** Intuit requires completing its production-keys steps in the portal (app details and a
  compliance questionnaire) before production keys are issued. Do this early — it can take review time.
- **Production Salesforce** needs the same B1–B6 against the production org, with the production Named
  Credential URL and the production callback URL added in the app's **Production** settings.
- **The `hooks` site does not exist in production yet** (website donations aren't in prod either) — it has to be
  created there first; the endpoint URL will then be the production `…salesforce-sites.com` domain.
- **Token lifetimes:** access tokens last 1 hour (Salesforce refreshes automatically); Intuit now caps refresh
  tokens at **5 years** (changed Nov 2025) and may rotate them daily. Expect a re-authenticate roughly every
  five years; I'll add an Integration Log alert if the connection starts failing.

---

## 7. Sources (checked 2026-09-16)

- Intuit OAuth discovery documents (live JSON): `https://developer.api.intuit.com/.well-known/openid_configuration`,
  `https://developer.api.intuit.com/.well-known/openid_sandbox_configuration`
- Intuit sample app, CloudEvents payload + signature: https://github.com/IntuitDeveloper/SampleApp-Webhooks-Java-Cloudevents
- CloudEvents migration + July 31, 2026 deadline: https://blogs.intuit.com/2025/12/01/upcoming-changes-to-apis-and-tools-that-may-impact-your-application/ ·
  https://www.maesn.com/blog/quickbooks-webhooks-cloudevents
- Delivery contract (3 s / 200, retry schedule, ordering, CDC 30-day window): https://www.maesn.com/blog/quickbooks-online-webhooks/
- Refresh-token 5-year policy: https://blogs.intuit.com/2025/11/12/important-changes-to-refresh-token-policy/
- Signature header / HMAC-SHA256 with verifier token; webhook payload carries ids not data:
  https://www.getknit.dev/blog/quickbooks-online-api-integration-guide-in-depth
- **Not verifiable from public pages** (Intuit and Salesforce help pages are JavaScript-gated): the exact webhook
  entity list (is Deposit included?) and the exact Salesforce callback URL format — both are read off the screen
  during setup instead.

---

## 8. Build log

### Step 1 — Salesforce endpoint ✅ (2026-09-17)
- **Deployed:** `QuickBooks_Settings__c` (protected hierarchy custom setting: Verifier Token, Company ID (Realm
  ID), Enabled, Max Payload Bytes — **empty, you fill it in**), `QuickBooks_Event__c` (staging: event id unique,
  type, entity, operation, entity id, entity key, realm, event time, received at, raw payload, status, error,
  processed at; All list view; tab for admins), `QuickBooksWebhookReceiver` on the `hooks` site at
  `/services/apexrest/qbo/webhook`.
- **Access:** hooks Profile (guest) = receiver class + create/read on events and their fields only (OWD Private;
  rows owned by the site's default owner, so the guest can't see any). System Administrator = full access + tab.
- **Tests:** 10 receiver tests + the 8 existing web donation receiver tests, **18/18**; coverage **95.1%**.
  Rejections assert nothing was stored: no signature, wrong token, signature for a different body, switched off /
  unconfigured (503), empty (400), oversized (413). Also: two events in one delivery, header capitalisation,
  retry dedupe, other company → Ignored, old non-CloudEvents body and malformed entries kept as Failed.
- **Live test through the public URL as the real guest user** (temporary token, then removed): signed POST →
  **200** and stored (created by *hooks Site Guest User*, owned by *Mission Matters*); same POST again → 200, not
  stored twice; forged signature → **401**; with no settings → **503**. Test row and settings deleted afterwards.
- **Gotcha hit:** deploying the new object and the class together failed — the test inserts were refused until the
  running admin had field access to the brand-new fields. Deploy order that works: objects → Admin profile access
  → class + tests → guest profile (which needs the class to exist).
- **Raw payloads are stored as received** — so when your first real sandbox event arrives we'll see exactly what
  Intuit sends, including whether `data` carries transaction details.

