# Sign-in setup (superseded)

> **This document predates the move to Firebase.** Its "Do I need Firebase?"
> answer was *no*, and that answer was overtaken — the backend is now Firebase
> end to end, and [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md) is the guide to
> follow.
>
> It is kept because the **Apple Developer** and **Google Cloud console** steps
> below are unchanged: Firebase creates the OAuth clients, but the Sign in with
> Apple capability, the Android SHA-1 and the iOS reversed-client-ID URL scheme
> are still configured exactly this way. Ignore every reference to
> `backend/.env`, `APPLE_CLIENT_IDS` and our own JWTs — those live in Firebase
> Authentication now.

---

## 1. Apple — Sign in with Apple

Needs a paid Apple Developer account.

1. **Certificates, Identifiers & Profiles → Identifiers → your App ID**
   Enable the **Sign in with Apple** capability.
2. **Xcode → Runner → Signing & Capabilities → + Capability → Sign in with Apple.**
   This writes `ios/Runner/Runner.entitlements`; commit it.
3. Backend: set `APPLE_CLIENT_IDS` to your **bundle ID**.

```bash
# backend/.env
APPLE_CLIENT_IDS=["com.knowra.knowra"]
```

Android/web Apple sign-in additionally needs a **Services ID** and a return
URL. Skip it unless you want Apple on Android — the app hides the button on
platforms where the SDK does not exist.

> Apple returns the user's name **exactly once**, on first authorisation, and
> never again. The client forwards it on that first exchange; if the account is
> deleted server-side and re-created, the name is gone for good.

## 2. Google — OAuth client IDs

**Firebase is not required.** Google sign-in needs OAuth client IDs, which live
in Google Cloud. Firebase creates them for you as a side effect of adding an
app — which is why people assume it is mandatory — but it also drops a
`GoogleService-Info.plist` and a `google-services.json` into the project that
we would otherwise never use. Since nothing else here needs Firebase, go
straight to Google Cloud.

Your identifiers, for copy-paste:

```
iOS bundle ID     com.knowra.knowra
Android package   com.knowra.knowra
```

### 2.1 — Project and consent screen (once)

1. **console.cloud.google.com** → project picker → **New project** → name it
   `Knowra`.
2. **APIs & Services → OAuth consent screen**
   - User type **External**, then **Create**.
   - App name `Knowra`, your email as both support and developer contact.
   - **Scopes:** add nothing. Sign-in only needs the default
     `openid`, `email`, `profile`, which are implicit.
   - **Test users:** add your own Google account. While the app is in
     *Testing*, only listed accounts can sign in — this is the single most
     common reason a correctly-wired build still refuses to log in.
3. Leave publishing status as **Testing** until you are ready for review.

### 2.2 — iOS client

**APIs & Services → Credentials → + Create credentials → OAuth client ID**

- Application type: **iOS**
- Bundle ID: `com.knowra.knowra`

You get two values. Both matter:

```
Client ID           123456-abc.apps.googleusercontent.com
iOS URL scheme      com.googleusercontent.apps.123456-abc     ← reversed
```

Add the reversed one to `app/ios/Runner/Info.plist`, inside the top-level
`<dict>` (the file currently has no `CFBundleURLTypes` key, so add the whole
block):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.123456-abc</string>
    </array>
  </dict>
</array>
```

Without this the Google sheet opens and then never returns to the app.

### 2.3 — Web client

**+ Create credentials → OAuth client ID → Web application**, name it
`Knowra backend`. No redirect URIs needed — it is used purely as an *audience*
identifier so the server can tell that an ID token was minted for us.

This one is the `serverClientId`, and it is required on **both** platforms.

### 2.4 — Android client

**+ Create credentials → OAuth client ID → Android**

- Package name: `com.knowra.knowra`
- SHA-1: from your signing certificate

```bash
# debug — the one you need to develop
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android \
  | grep SHA1

# release — register this too, before you ship
keytool -list -v -alias <your-alias> -keystore <your-upload.keystore> | grep SHA1
```

Register **both** fingerprints. Registering only debug is why Google sign-in
works on your machine and fails in the Play Store build. Android takes no
client ID in code — Google matches the app by package name plus signature.

### 2.5 — Wire the values in

```jsonc
// app/config/dev.json  (and prod.json)
"GOOGLE_CLIENT_ID":        "123456-abc.apps.googleusercontent.com",  // iOS client
"GOOGLE_SERVER_CLIENT_ID": "123456-xyz.apps.googleusercontent.com"   // Web client
```

```bash
# backend/.env — every client id that can appear as the token's `aud`
GOOGLE_CLIENT_IDS=["123456-abc.apps.googleusercontent.com","123456-xyz.apps.googleusercontent.com"]
```

Then:

```bash
cd app && flutter run --dart-define-from-file=config/dev.json
```

### 2.6 — When it does not work

| Symptom | Cause |
| --- | --- |
| Button is dimmed | `GOOGLE_CLIENT_ID` is empty in the config file you ran with |
| Sheet opens, never returns | Reversed client ID missing from `Info.plist` |
| `DEVELOPER_ERROR` on Android | SHA-1 not registered, or wrong package name |
| Sign-in works, server returns 401 | Web client ID missing from `GOOGLE_CLIENT_IDS` |
| `access_denied` for your own account | Consent screen is in Testing and you are not a test user |

### If you would rather use Firebase anyway

It works, and it is fewer console screens. Create the Firebase project, add an
iOS app with bundle `com.knowra.knowra`, enable **Authentication → Sign-in
method → Google**, and download `GoogleService-Info.plist`. Firebase creates
the same OAuth clients underneath; read `CLIENT_ID` and `REVERSED_CLIENT_ID`
out of the plist and use them exactly as above.

You still do §2.1's consent screen and §2.4's SHA-1, and you now carry two
config files the app does not otherwise need. **We would not use Firebase Auth
itself** — our backend verifies Google's ID token directly against Google's
JWKS and issues its own JWT, so routing identity through Firebase would mean
running two auth systems and mapping between them.

## 3. Email codes — real delivery

### Development: nothing to configure

The code is written to the **server log** rather than emailed:

```
[info] sign_in_code_issued  email=you@example.com  code=722177
```

Or `make otp` for the most recent one. It is deliberately never returned in the
HTTP response — that would turn the endpoint into an oracle handing out
sign-ins for any address.

### Production: pick a provider

Set `EMAIL_PROVIDER` and the matching keys. The console sender **raises** if it
is ever reached with `ENVIRONMENT=prod`, so a misconfigured deploy fails loudly
rather than swallowing every code while the API keeps returning 200.

#### Option A — Resend (recommended to start)

One API key, no SMTP handshake, 3,000 emails/month free.

1. **resend.com** → sign up → **API Keys → Create**. Copy `re_...`.
2. **Domains → Add Domain** → `knowra.com`. Resend gives you three DNS records:

   | Type | Purpose |
   | --- | --- |
   | `TXT` (SPF) | says Resend may send as you |
   | `TXT` (DKIM) | signs each message |
   | `MX` or `TXT` (DMARC) | tells receivers what to do with failures |

   Add all three at your registrar and press **Verify**. Propagation is
   usually minutes.
3. Configure:

```bash
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_xxxxxxxxxxxx
EMAIL_FROM=Knowra <hello@knowra.com>
```

> **You can skip step 2 while testing** by leaving
> `EMAIL_FROM=Knowra <onboarding@resend.dev>`, Resend's shared sandbox sender.
> It only delivers to the address you signed up with, which is enough to see
> the real email. It is not usable for real users.

#### Option B — SMTP (a company relay, SES, or local MailHog)

```bash
EMAIL_PROVIDER=smtp
SMTP_HOST=email-smtp.eu-west-1.amazonaws.com
SMTP_PORT=587
SMTP_USERNAME=...
SMTP_PASSWORD=...
EMAIL_FROM=Knowra <hello@knowra.com>
```

To see the real email locally without sending anything, run MailHog and point
at it — every message lands in a web inbox at `localhost:8025`:

```bash
docker run -d -p 1025:1025 -p 8025:8025 mailhog/mailhog
# EMAIL_PROVIDER=smtp  SMTP_HOST=localhost  SMTP_PORT=1025  SMTP_USE_TLS=false
```

### The part that actually decides whether mail arrives

Deliverability is a DNS problem, not a code problem. Without **SPF, DKIM and
DMARC** on your sending domain, Gmail and Outlook route sign-in codes to spam —
and a sign-in code in spam is indistinguishable from a broken product.

- **Never send from a free domain** (`@gmail.com`). It fails DMARC by
  construction and is rejected outright.
- **Use a subdomain** — `mail.knowra.com` or `auth.knowra.com`. A deliverability
  problem then cannot damage the reputation of your main domain.
- **Transactional and marketing mail should not share a sending domain.** One
  unsubscribe complaint should not put sign-in codes at risk.

### What the email looks like

The template lives in `app/services/auth/email_templates.py` — versioned and
tested rather than pasted into a provider dashboard, so switching providers
does not mean rebuilding it.

- The code is in the **subject line** as well as the body. Most people read it
  from the notification without opening anything.
- **Plain text and HTML both.** HTML-only is a spam signal, and some clients
  show nothing.
- The plain-text part carries the code **unspaced** — people copy from it, and
  `722 177` pasted into a numeric field is a support ticket. The HTML gets its
  readability from `letter-spacing`, which does not survive a copy.
- **Inline styles, table layout.** Outlook renders with Word's engine: no
  `<style>` blocks, no flexbox.

## 4. Production checklist

```bash
SECRET_KEY=<32+ random bytes>   # rotating this invalidates every session
ENABLE_PASSWORD_AUTH=false      # password endpoints are for seeding and tests
```

Both are enforced server-side: `/auth/register` and `/auth/login` 404 when
`ENVIRONMENT=prod`.

---

## What happens with no credentials at all

The app still runs. A provider with no client ID is **not offered** — the
button is absent rather than present and broken — and email sign-in works end
to end against a local backend. That is the intended development path.
