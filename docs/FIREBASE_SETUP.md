# Firebase setup

**Status: mostly done.** The project exists, the apps are registered, and rules
and indexes are deployed. What remains is the Blaze upgrade, which is a billing
decision only you can make.

| Step | State |
| --- | --- |
| Firebase project `knowra-506719` | ✅ added to the existing GCP project, so the OAuth client already in your config stays valid |
| iOS + Android apps registered | ✅ `firebase_options.dart`, `GoogleService-Info.plist`, `google-services.json` generated |
| Firestore database | ✅ created |
| Security rules | ✅ deployed |
| Indexes, incl. 2 vector indexes | ✅ deployed |
| iOS deployment target → 15.0 | ✅ Podfile and Xcode project |
| **Blaze plan** | ⬜ **required for Cloud Functions** |
| Secrets + `firebase deploy --only functions` | ⬜ blocked on Blaze |
| Google / Apple providers enabled in console | ⬜ |

Upgrade at
**https://console.firebase.google.com/project/knowra-506719/usage/details** and
set a budget alert while you are there.

---

## Console walkthrough — the three things left

Console home:
**https://console.firebase.google.com/project/knowra-506719/overview**

The left sidebar is grouped: **Build** (Authentication, Firestore, Storage,
Functions), **Run**, then **⚙ Project settings** at the top and
**Usage and billing** at the bottom.

### 1. Upgrade to Blaze — unblocks everything else

**⚙ (top left, beside "Project Overview") → Usage and billing → Details &
settings → Modify plan → Blaze**

Direct: https://console.firebase.google.com/project/knowra-506719/usage/details

You will link a Google Cloud billing account (create one if you have none — it
asks for a card). Blaze is pay-as-you-go *on top of* the free tier, not instead
of it: the free allowances stay, you are only billed past them.

**Set a budget immediately.** Same page → **Set budget alert** → something like
$10/month. It emails you rather than capping spend, which is what you want
during development — a hard cap that silences your own app is worse than an
email.

Realistically this project costs $0 during development. The Blaze requirement
exists because Functions can call out to the internet, not because of volume.

### 2. Enable the sign-in providers

**Build → Authentication → Get started → Sign-in method**

Direct: https://console.firebase.google.com/project/knowra-506719/authentication/providers

| Provider | Action |
| --- | --- |
| **Google** | Enable → pick a **support email** (your own) → Save. Firebase wires the OAuth clients itself. |
| **Apple** | Enable → Save. Nothing else for iOS — the Xcode entitlement does the work. |
| Everything else | Leave off. |

> **Do not enable "Email/Password" or "Email link".** The six-digit code is a
> Cloud Function minting a custom token, and custom tokens need no provider.
> Enabling Email link would add a magic-link flow the design does not have.

While you are here, **Settings → Authorized domains** should already list
`knowra-506719.firebaseapp.com`. Nothing to change for a mobile-only app.

### 3. Check Firestore exists and is empty

**Build → Firestore Database**

Direct: https://console.firebase.google.com/project/knowra-506719/firestore

You should see an empty database in **Production mode**. Two tabs worth
knowing:

- **Rules** — should show the deployed `firestore.rules`. Do **not** edit here;
  the file in `firebase/firestore.rules` is the source and the next deploy
  overwrites anything typed into the console.
- **Indexes** — nine composite indexes. The two on `chunks` carrying
  `embedding` are the vector indexes behind semantic search. They may show
  **Building**; a KNN query against a building index fails with
  `FAILED_PRECONDITION`, which is expected rather than broken.

### iOS: pre-compiled Firestore

`app/ios/Podfile` pins Firestore to Invertase's pre-built frameworks:

```ruby
pod 'FirebaseFirestore',
  :git => 'https://github.com/invertase/firestore-ios-sdk-frameworks.git',
  :tag => '12.18.0'
```

Building from source pulls in gRPC and BoringSSL, which adds minutes to every
clean build — and here it did not work at all: gRPC-Core generates its
`module.modulemap` in a `prepare_command` that does not run reliably, and the
install died with a missing-file error partway through.

**The tag must match the Firebase SDK version `firebase_core` pins.** Bumping
one without the other produces a link error that names neither. Check with:

```bash
grep "Firebase SDK version" app/ios/Podfile.lock
```

### iOS project fixes applied

Three things had to change in `app/ios/` that a fresh Flutter project does not
come with:

| Change | Why |
| --- | --- |
| `platform :ios, '15.0'` in the Podfile | Firestore requires 15; CocoaPods otherwise assumes 13 and refuses to resolve |
| `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in the Xcode project | Must match the Podfile or the link fails later, further from the cause |
| `Flutter/Profile.xcconfig`, and the Runner's Profile configuration pointed at it | `flutter create` ships only Debug and Release, and points Profile at Release — so a profile build linked against *release* pod settings. CocoaPods warns about this; it is easy to read as noise |

Also note `platform :ios, '15.0'` at the top of the Podfile and
`IPHONEOS_DEPLOYMENT_TARGET = 15.0` in the Xcode project — Firestore requires
15, and CocoaPods otherwise assumes 13 and refuses to resolve. The two must
agree or the link fails later, further from the cause.

### Then, from the terminal

```bash
cd firebase
firebase functions:secrets:set AUTH_CODE_SECRET --data-file /tmp/knowra_auth_secret
firebase deploy --only functions
```

First deploy takes a few minutes — it provisions Cloud Build, Artifact Registry
and Cloud Run behind the scenes. It will ask to enable those APIs; say yes.

### Where things show up afterwards

| What you want to see | Where |
| --- | --- |
| Sign-in codes as they are issued | **Functions → Logs**, or `make logs` |
| Users appearing as they sign up | **Authentication → Users** |
| Documents being written | **Firestore → Data** |
| What a function cost | **Functions → Dashboard** |
| Rules rejecting something | **Firestore → Rules → Monitor** |

`make logs` tails the same stream as the console and is usually faster to read.

---

Everything below is the reference for redoing any of it.

Your identifiers, for copy-paste:

```
iOS bundle ID     com.knowra.knowra
Android package   com.knowra.knowra
Android SHA-1     06:2C:5A:3C:1A:73:AC:A0:4A:CC:BB:8C:87:05:D1:98:87:A1:CC:2F
```

---

## 1. Sign in to the CLI

Interactive — it opens a browser, so run it yourself:

```
! firebase login
```

Then confirm:

```bash
firebase projects:list
```

## 2. Create the project

```bash
firebase projects:create knowra-app --display-name "Knowra"
```

If the id is taken, pick another and use it everywhere below. Or create it in
the console at **console.firebase.google.com** — same result.

> **Blaze plan is required.** Cloud Functions cannot be deployed on the free
> Spark plan. Blaze is pay-as-you-go with a free tier that comfortably covers
> development; set a budget alert at the same time so a runaway function is
> capped. Upgrade under **⚙ → Usage and billing → Details & settings**.

## 3. Register the apps and generate config

FlutterFire does the per-platform registration and writes
`lib/firebase_options.dart`, which the app reads at startup:

```bash
cd app
export PATH="$PATH:$HOME/.pub-cache/bin"

flutterfire configure \
  --project=knowra-app \
  --platforms=ios,android \
  --ios-bundle-id=com.knowra.knowra \
  --android-package-name=com.knowra.knowra
```

That writes:

| File | Purpose |
| --- | --- |
| `app/lib/firebase_options.dart` | Platform config read by `Firebase.initializeApp` |
| `app/ios/Runner/GoogleService-Info.plist` | iOS native config |
| `app/android/app/google-services.json` | Android native config |

**Commit all three.** They contain no secrets — API keys here identify the
project, they do not authorise anything. Access is controlled by security
rules, which is why `firestore.rules` is the file that actually matters.

## 4. Turn on the sign-in providers

**Console → Authentication → Get started → Sign-in method.**

| Provider | What to do |
| --- | --- |
| **Google** | Enable. Set a support email. Firebase creates the OAuth clients. |
| **Apple** | Enable. For iOS-only, nothing else is needed — the entitlement Xcode added does the work. |
| **Anonymous** | Leave off. |
| **Email/Password** | Leave off — see below. |

> **Email is not "Email/Password" or "Email link".** The six-digit code flow is
> a Cloud Function that mints a *custom token*, and custom tokens need no
> provider enabled at all. Turning on Email link would give you a magic-link
> flow the design does not have.

### Android also needs the SHA-1

**Console → ⚙ Project settings → Your apps → Android → Add fingerprint**, then
paste the SHA-1 above. Re-download `google-services.json` afterwards. Register
your **release** fingerprint too before shipping, or Google sign-in works in
debug and fails in the Play Store build.

## 5. Firestore and Storage

```bash
cd ../firebase
firebase use knowra-app

firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only storage
```

Create the database first if the console has not:
**Firestore Database → Create database → Production mode**, in a region near
your users. **The region is permanent** — you cannot move a Firestore database
later without exporting and re-importing.

The two vector indexes in `firestore.indexes.json` back semantic search. They
build asynchronously; a KNN query against a still-building index fails with
`FAILED_PRECONDITION`, which is expected rather than broken.

## 6. Cloud Functions

The email-code function signs its codes with a secret. Set it before deploying
— the function raises at startup without it, deliberately, because an empty key
would make every HMAC forgeable:

```bash
# 32 bytes of entropy. Store it somewhere you can retrieve it.
firebase functions:secrets:set AUTH_CODE_SECRET

# Optional now, required for real email rather than log output
firebase functions:secrets:set RESEND_API_KEY

firebase deploy --only functions
```

Functions are Python 3.12 and live in `firebase/functions/`.

## 7. Run it

```bash
cd app
flutter run --dart-define-from-file=config/dev.json
```

### Locally, without deploying

The emulator suite runs Auth, Firestore, Functions and Storage on your machine.
Sign-in codes print to its console, so no email provider is needed:

```bash
cd firebase
firebase emulators:start
```

Emulator UI at **localhost:4000**. Point the app at it by setting
`USE_FIREBASE_EMULATOR: "true"` in `app/config/dev.json`.

---

## What this replaced, and what it did not

**Replaced:** FastAPI, Postgres, Redis, Docker, Alembic, the JWT issuer, the
Dio refresh interceptor, and the token storage. None of it is on the sign-in
path any more.

**Not replaced:**

- **OAuth setup is the same work.** Firebase creates the Google clients, but
  the Android SHA-1 and the iOS reversed-client-ID URL scheme are still
  yours to configure. The earlier guide in `AUTH_SETUP.md` still applies for
  those two.
- **The six-digit email code is still ours.** Firebase Auth has no email OTP,
  so `firebase/functions/email_codes.py` generates, HMACs, rate-limits and
  verifies it, then hands off to Firebase via a custom token. The design's
  screens 3H and 3I are unchanged.
- **Hybrid retrieval is now an open question.** Firestore has KNN vector
  search, but not the vector + keyword + metadata combination that §25 and §26
  describe. That is the one part of the architecture this move genuinely
  reopens, and it will need a decision before the memory engine is built.

## When it does not work

| Symptom | Cause |
| --- | --- |
| `No Firebase App '[DEFAULT]'` | `flutterfire configure` not run, or `Firebase.initializeApp` not awaited |
| `functions/not-found` on a callable | Region mismatch — the client asks `us-central1`, the function must declare it |
| `permission-denied` on every read | Rules not deployed, or the document has no `userId` field |
| `FAILED_PRECONDITION` on a query | A composite index is still building, or missing from `firestore.indexes.json` |
| Google sign-in `DEVELOPER_ERROR` | SHA-1 not registered, or `google-services.json` is stale |
| Apple sign-in loops back signed-out | Apple provider not enabled in the console |
| `AUTH_CODE_SECRET is not set` | Secret not set, or functions deployed before it was |
