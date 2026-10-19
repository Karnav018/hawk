# Storage connectors — setup

> Doing this for the first time? [`CONNECTORS_DASHBOARD.md`](CONNECTORS_DASHBOARD.md)
> is the same ground as a click-by-click walkthrough with the console paths
> and the failure modes. This file is the reference.

The connector layer is built and tested. What is left is **provider
credentials**, which cannot be scripted: each provider wants an app registered
in its own console, with our redirect URI on the allow-list.

Nothing here is optional-per-provider in the code. A provider without
credentials reports `configured: false` and screen 3F shows it **dimmed with a
reason** rather than hiding it, so a build missing a client id cannot be
mistaken for a product decision.

---

## The redirect URI

**Registered with every provider:**

```
https://knowra-506719.firebaseapp.com/oauth/callback
```

**Delivered to the app as:**

```
com.knowra.knowra://oauth/callback
```

Two hops, because Google refuses a custom-scheme redirect on any client
requesting restricted scopes — and `drive.readonly` is restricted. Dropbox and
Microsoft would both take the custom scheme directly, but pointing only Google
somewhere else means a redirect that varies by provider *and* by platform,
which is precisely the branching `connectors/` exists to keep out of the core.
So all three go through one https endpoint that does nothing but forward.

| Where | File |
| --- | --- |
| Backend, what providers see | `firebase/functions/connectors/registry.py` → `REDIRECT_URI` |
| Backend, the bounce | `firebase/functions/connector_callback.py` |
| Hosting route | `firebase/firebase.json` → `hosting.rewrites` |
| Android | `app/android/app/src/main/AndroidManifest.xml` → `CallbackActivity` |
| iOS | `app/ios/Runner/Info.plist` → `CFBundleURLTypes` / `storage-connectors` |

`<project>.firebaseapp.com` rather than a Cloud Run URL, for two reasons: it is
stable across redeploys, and it is knowable *before* the first deploy — a raw
function URL carries a generated hash, so it cannot be pasted into Google's
console until after something has been deployed.

**Why the extra hop is not a weakness.** The endpoint holds an authorization
code for the length of one 302 and makes no decision about it. The code alone
is worthless: exchanging it also needs the PKCE verifier, which is generated in
a Cloud Function, stored in `oauthChallenges` under rules that deny every
client read, and never sent to the app. The endpoint's destination is a
hard-coded constant and its parameters are a whitelist, so it cannot be steered
into becoming an open redirector.

---

## 1. Google Drive

We already have a Google Cloud project (`knowra-506719`), so this is two
steps.

1. **Enable the API** — Google Cloud console → *APIs & Services* → *Library* →
   **Google Drive API** → Enable.
2. **OAuth client** — *APIs & Services* → *Credentials* → *Create credentials*
   → *OAuth client ID* → **Web application**.
   - Authorised redirect URI: `https://knowra-506719.firebaseapp.com/oauth/callback`
   - Copy the client id and client secret.

> A *Web application* client, not an iOS/Android one, even though the caller is
> a phone: the token exchange happens in a Cloud Function, not on the device.
> That client type is also why the redirect is https — Google enforces it for
> Web clients using restricted scopes, and rejects the custom scheme at
> client-creation time with *"Invalid Redirect: You are using a sensitive
> scope. URI must use https:// as the scheme."*

3. **Consent screen** — add the scopes
   `.../auth/drive.readonly` and `.../auth/userinfo.email` for the READ level,
   and `.../auth/drive` for MANAGE. Drive scopes are *restricted*: while the
   app is in testing you must add each tester under **Audience → Test users**,
   and going to production needs Google's verification (a security assessment
   for restricted scopes — start it early, it takes weeks).

```bash
firebase functions:secrets:set GOOGLE_DRIVE_CLIENT_ID
firebase functions:secrets:set GOOGLE_DRIVE_CLIENT_SECRET
```

## 2. Dropbox

1. <https://www.dropbox.com/developers/apps> → *Create app* → **Scoped access**
   → *Full Dropbox*.
2. *Settings* → **Redirect URIs** → add `https://knowra-506719.firebaseapp.com/oauth/callback`.
   (Dropbox would accept the custom scheme, but the flow uses one redirect for
   every provider.)
3. *Permissions* → tick `account_info.read`, `files.metadata.read`,
   `files.content.read` (and `files.content.write`, `files.metadata.write` if
   you want the MANAGE level available). **Submit** — the tab does not save on
   navigate.

```bash
firebase functions:secrets:set DROPBOX_CLIENT_ID       # "App key"
firebase functions:secrets:set DROPBOX_CLIENT_SECRET   # "App secret"
```

## 3. OneDrive

1. Azure portal → *Microsoft Entra ID* → **App registrations** → *New*.
2. Supported account types: **personal Microsoft accounts and organizational**
   if you want both consumer OneDrive and business.
3. *Authentication* → *Add a platform* → **Web** → redirect URI
   `https://knowra-506719.firebaseapp.com/oauth/callback`. Set *Allow public
   client flows* to **Yes**.
4. *API permissions* → Microsoft Graph → delegated → `Files.Read.All`,
   `User.Read`, `offline_access` (add `Files.ReadWrite.All` for MANAGE).

```bash
firebase functions:secrets:set ONEDRIVE_CLIENT_ID      # "Application (client) ID"
```

No secret: it is registered as a public client and Graph accepts PKCE alone.
`connectors/onedrive.py` declares `requires_client_secret=False`, so the
registry will not demand one.

---

## 4. The token-sealing key — required

Refresh tokens are encrypted with AES-GCM before they touch Firestore.
`connector_oauth.seal` **refuses to run** without this, which is deliberate: a
missing key must fail the connection, never silently store a permanent key to
somebody's drive in the clear.

```bash
python3 -c 'import base64,secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())' \
  | firebase functions:secrets:set CONNECTOR_KEY
```

> **Rotating it invalidates every stored grant.** There is no re-encryption
> path yet — every connected account would go to `REVOKED` and each user would
> have to reconnect. Treat it as permanent until that path exists.

Firestore already encrypts at rest, so this is defence in depth. It is worth
having because it is the layer that survives the *next* mistake: a rules
regression, a leaked service-account key, a stray export. Ciphertext without
`CONNECTOR_KEY` is noise.

---

## 5. Bind the secrets and deploy

`firebase-functions` for Python reads secrets from the environment, so each
function that needs one must declare it. Then:

```bash
cd firebase
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions
firebase deploy --only hosting   # routes /oauth/callback to the bounce
```

The rules deploy matters on its own — it adds
`storageAccounts/{id}/private/**` as deny-all, which is what makes storing a
refresh token safe at all.

---

## What the flow looks like end to end

```
  3F ──Connect──► begin_connection ──► authorization URL
   │                (quota checked here, before the user is
   │                 sent to Google — refusing them after
   │                 they have authorised is worse)
   ▼
  system browser ──► provider consent
   │                        │
   │                        ▼
   │        https://…firebaseapp.com/oauth/callback   (302, forwards only)
   │                        │
   │                        ▼
   │              com.knowra.knowra://oauth/callback
   │
   ▼
  complete_connection ──► exchange (needs the server-held verifier)
   │                 ──► seal refresh token → storageAccounts/{id}/private/oauth
   ▼
  3G ──permissions──► 3K ──folders──► set_indexed_folders
                                          │
                                          ▼
                                     indexJobs/{id}  ◄── 3L streams this
                                          │
                                          ▼
                              on_index_job_created walks the folders,
                              writes one `memories` doc per file, which
                              the existing ingestion trigger picks up
```

Afterwards `sync_connected_accounts` runs every 6 hours and reconciles each
account against its provider's change feed (§39).

## The other option on 3F — the phone vault

Screen 3F offers **two** sources, and only the first one is any of the above.
Google Drive is an OAuth grant; the phone vault is the device the app is
already running on. `list_connectors` returns both in one `providers` list,
told apart by `kind`:

```json
{"id": "google_drive", "label": "Google Drive", "kind": "oauth",  "configured": true}
{"id": "internal",     "label": "Phone vault",  "kind": "device", "configured": true}
```

The app branches on `kind`, never on the id — `oauth` opens the browser,
`device` opens the system file picker.

```
  3F ──Use this phone──► OS file permission (client side; no backend)
   │
   ▼
  connect_device_vault {deviceName?} ──► storageAccounts/device_{uid}
   │                                        provider: "internal"
   │                                        kind:     "device"
   │                                        state:    connected
   ▼
  picker ──► one capture per file ──► memories/{id} ──► ingestion trigger
                                          │
                                          ▼
                              fileCount / bytes on the row move with it
```

No index job, no folder screen, no 3G: there is no third party to ask, and a
file arrives because the user picked it rather than because we went looking.
`complete_storage_setup` ends onboarding exactly as it does for Drive.

What the backend guarantees, and why each one is load-bearing:

| Rule | Why |
| --- | --- |
| Never counts against `connectedAccounts` | The limit prices *cloud* connections. Charging a free user their only slot for the phone in their hand would make the upsell "pay to use your own device". |
| `sync_connected_accounts` skips it | Nothing to poll, and `connector_for("internal")` does not exist. |
| `begin_connection` / `list_provider_folders` / `set_indexed_folders` refuse it by name | They would otherwise fail as a `KeyError` inside an async task, surfacing as `INTERNAL`. |
| Provider id is `internal`, not a new string | It is the id a captured-here memory already resolves to, so the library's source chip and the row agree with no migration. Changing it is a data migration. |
| `device_{uid}`, a deterministic id | Connecting is idempotent; a double tap cannot list the same phone twice. |
| Disconnecting touches no memories | A capture carries no `storageAccountId`, and its file lives in Knowra's own file vault — not on the phone. Unlisting the device must not silence everything ever captured on it. |

Counts are maintained by the two memory triggers (`ingestion.on_memory_created`
and `file_vault.on_memory_deleted`), and both ask `device_vault._countable`, so
the create side and the delete side cannot disagree about what a file is. A
capture made before the phone vault was connected is not counted and does not
create the row — skipping 3F is a choice, not a state to be undone by a photo.

## Why a connection dies, and what a reconnect restores

Three causes, and only one of them is ours:

| Cause | Looks like | Fix |
| --- | --- | --- |
| Consent screen still in **Testing** | Works for 7 days, then `invalid_grant` on every sync | Move the app to Production — see `CONNECTORS_DASHBOARD.md` §1.2. **This is the usual one.** |
| User revoked access at Google, or changed their password | `invalid_grant` immediately | Reconnect in the app |
| `set_scope_level(read)` narrowing a MANAGE grant | Account goes `revoked` on purpose — Google has no partial revoke | Reconnect at READ |

In every case the account lands in `revoked`, the index it built survives,
and **`complete_connection` puts it back**: it matches the existing row on
`providerAccountId`, keeps the folder selection and the counts, and revives
the memories the disconnect parked (`_revive`).

That last part was missing. `disconnect_account` has always promised that
reconnecting restores the memories it marked `dormant`, and nothing did —
`retrieval` filters on `recallState == "active"`, so a reconnected Drive came
back CONNECTED over an index that answered nothing. It now revives every
memory of that account with `sourceAvailable == false`, which is the flag
only a disconnect sets. Memories the **plan's retention window** has aged out
stay dormant: they are dormant for a different reason, and reviving them
would make disconnect-then-reconnect a way to buy back a year of history for
free.

## Connector states (§40)

| State | Means | What the UI offers |
| --- | --- | --- |
| `connected` | Working | Disconnect |
| `syncing` | First index or a sync in flight | — |
| `paused` | User paused it | Resume |
| `revoked` | Access pulled at the provider | **Reconnect** — the index survived |
| `error` | Provider kept refusing | Retry |

`revoked` is deliberately not merged with "disconnected". The index built from
those files is still there and still answers questions; only refreshing it is
blocked. Reconnecting is one tap and restores everything, which is why
`disconnect_account` keeps memories by default and needs
`deleteMemories: true` to do the destructive thing.
