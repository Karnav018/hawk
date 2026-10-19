# Connectors — the console clicks

Everything the CLI cannot do, in order. Project **`knowra-506719`**.

Budget about 40 minutes for Google Drive, 10 for Dropbox, 15 for OneDrive.
Do Google first — it is the one that has a waiting period attached, and
starting it late is the thing that delays a launch.

---

## Part 1 — Google Cloud (Drive)

Console: <https://console.cloud.google.com> · make sure the project selector
top-left says **knowra-506719**.

### 1.1 Turn the Drive API on

*APIs & Services* → **Library** → search `Google Drive API` → **Enable**.

Without this every Drive call comes back `403 accessNotConfigured`, which
reads exactly like a revoked grant. If connecting succeeds and folder listing
immediately 403s, this is why.

### 1.2 Consent screen — add the scopes

*APIs & Services* → **OAuth consent screen** (newer consoles: *Google Auth
Platform* → **Branding** / **Data Access**).

Under **Data Access** → *Add or remove scopes*, paste into the manual box:

```
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/drive
```

- The first two are the **READ** level — what a user grants on screen 3G's
  fixed-on toggle.
- The third is **MANAGE**, the toggle they can turn on. Listed here so it can
  be requested later; it is not requested until they ask for it.

> `drive.readonly` and `drive` are **restricted** scopes. Two consequences,
> both worth knowing now:
>
> 1. While the app is in *Testing*, only accounts listed under **Audience →
>    Test users** can connect. Everyone else gets `403 access_denied` after
>    consenting, which looks like our bug. **Add your own Google account
>    there now.**
> 2. Publishing needs Google's OAuth verification, and restricted scopes add
>    a **security assessment** on top — a CASA review by a third-party
>    assessor. This runs to weeks, sometimes months, and has a cost. Start it
>    as soon as the app is demonstrable. Cap on unverified apps is 100 users.
> 3. **In *Testing*, refresh tokens expire after seven days.** This is the
>    cause of "Drive keeps disconnecting" — not a bug in the token store.
>    Google issues a refresh token that stops working a week later, the next
>    sync gets `invalid_grant`, and the account flips to `revoked`. Moving
>    the app to **Production** (even before verification completes, under the
>    100-user cap) is what stops it. No amount of backend work can, which is
>    why it is written down here rather than being rediscovered every week.

### 1.3 Create the OAuth client

*APIs & Services* → **Credentials** → *Create credentials* → **OAuth client
ID**.

| Field | Value |
| --- | --- |
| Application type | **Web application** |
| Name | `Knowra storage connectors` |
| Authorised redirect URI | `https://knowra-506719.firebaseapp.com/oauth/callback` |

Copy the **Client ID** and **Client secret** from the dialog.

> **Web application, not iOS/Android** — even though the caller is a phone.
> The code exchange happens in a Cloud Function, not on the device. This is a
> different client from the sign-in ones you already made; do not reuse those.
>
> **The redirect is https, not the app's custom scheme.** Google rejects a
> custom scheme on any client requesting restricted scopes:
> *"Invalid Redirect: You are using a sensitive scope. URI must use https://
> as the scheme."* That https URL is a Cloud Function behind Firebase Hosting
> which does nothing but forward to `com.knowra.knowra://oauth/callback`.
> It is knowable before deploying because every Firebase project answers on
> `<project>.firebaseapp.com`.

### 1.4 Store them

```bash
cd firebase
firebase functions:secrets:set GOOGLE_DRIVE_CLIENT_ID
firebase functions:secrets:set GOOGLE_DRIVE_CLIENT_SECRET
```

Each prompts for the value and hides it. They land in Secret Manager, which
you can see at *Cloud console → Security → Secret Manager*.

---

## Part 2 — The sealing key

Not optional. `connector_oauth.seal` **refuses to run** without it, so a
missing key fails the connection rather than quietly writing a permanent key
to somebody's Drive in plaintext.

```bash
python3 -c 'import base64,secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())' \
  | firebase functions:secrets:set CONNECTOR_KEY
```

> **Treat it as permanent.** There is no re-encryption path, so rotating it
> sends every connected account to `REVOKED` and every user has to reconnect.
> Back it up somewhere you would back up a signing key.

---

## Part 3 — Deploy

```bash
cd firebase
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions
firebase deploy --only hosting
```

The rules deploy matters on its own: it adds
`storageAccounts/{id}/private/**` as deny-all, which is what makes storing a
refresh token safe. Do it even if you are not ready to deploy functions.

Indexes build in the background — *Firebase console → Firestore Database →
Indexes* shows **Building** then **Enabled**. Four new ones. A query against a
still-building index fails with a `failed-precondition` carrying a link that
creates it; if you see that, the index list is where to look.

If any function fails on the first deploy with an IAM or Eventarc error, wait
two minutes and re-run — the service agents for a newly-used product take a
moment to propagate. That happened on the last deploy too.

---

## Part 4 — Watching it work

### Logs

*Firebase console → Functions → Logs*, or:

```bash
firebase functions:log --only begin_connection,complete_connection
firebase functions:log --only on_index_job_created
```

`complete_connection` is where a bad client id or a stale redirect URI shows
up, and the error text is the provider's own.

### Firestore

*Firebase console → Firestore Database → Data*. After one connection:

| Path | Should contain |
| --- | --- |
| `storageAccounts/{id}` | provider, email, `state: connected`, `scopeLevel: read` |
| `storageAccounts/{id}/private/oauth` | `accessToken`, `refreshToken` — **base64 noise** |
| `oauthChallenges/{id}` | `consumed: true` |
| `indexJobs/{id}` | `state`, `progress.processed`, `byKind` |

**Check the middle row.** If `refreshToken` is readable text, `CONNECTOR_KEY`
was not bound and the seal did not happen. That is a stop-everything finding,
not a cosmetic one.

### Rules

*Firestore → Rules → Playground* is worth two minutes here:

| Simulate | Path | Expect |
| --- | --- | --- |
| get, authenticated as the owner | `/storageAccounts/{id}` | **Allow** |
| get, authenticated as the owner | `/storageAccounts/{id}/private/oauth` | **Deny** |
| get, authenticated as anyone | `/oauthChallenges/{id}` | **Deny** |

The second row is the one that matters. It is the rule that was wrong before
this work — the old file granted the owner a full read of the account
document, and a Firestore rule cannot redact a field, so a token stored there
would have been readable by any signed-in client.

### The scheduled sync

*Firebase console → Functions* lists `sync_connected_accounts` with a schedule
of `every 6 hours`. To trigger it now: *Cloud Scheduler* → find the job →
**Force run**.

---

## Part 5 — Dropbox and OneDrive

Both stay dimmed on screen 3F until their credentials exist, which is
deliberate — a provider we cannot do is shown disabled with a reason rather
than hidden, so a misconfigured build cannot be mistaken for a product
decision.

To enable either one, follow the console steps in
[`CONNECTORS.md`](CONNECTORS.md), then **add its secret names to
`PROVIDER_SECRETS` in `firebase/functions/connector_api.py`** and redeploy.
That list is not automatic on purpose: Firebase refuses to deploy a function
declaring a secret that does not exist, so an unlisted provider is what keeps
the deploy working while you have only one.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `403 access_denied` right after consenting | Your Google account is not in **Audience → Test users** |
| `403 accessNotConfigured` on folder listing | Drive API not enabled (1.1) |
| Connect succeeds, breaks an hour later | No refresh token — the client is not a *Web application* type, or `access_type=offline` was stripped |
| `Invalid Redirect: … must use https://` | You pasted the custom scheme. Use the `firebaseapp.com` URL — restricted scopes forbid custom schemes on Web clients |
| `redirect_uri_mismatch` | The console URI does not match `https://knowra-506719.firebaseapp.com/oauth/callback` exactly — no trailing slash |
| Browser lands on a blank page after consent | `hosting` not deployed, so `/oauth/callback` 404s before it can forward |
| `CONNECTOR_KEY is not set` in logs | Secret not created, or not listed in `PROVIDER_SECRETS` |
| Browser opens, returns, nothing happens | Custom scheme not registered — `AndroidManifest.xml` `CallbackActivity`, or `Info.plist` `CFBundleURLTypes` |
| `failed-precondition` with a console link | A composite index is still building |
