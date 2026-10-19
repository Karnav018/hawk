# Hawk on Google Play

What the code already does, and the steps only you can do in Play Console,
Firebase and Google Cloud. Work top to bottom: several steps unlock the next.

## Already done in code

| Item | State |
|---|---|
| Package name | `in.hawkapp.app`, also the Gradle namespace and MainActivity's package. Permanent after the first upload. Firebase and the backend's `ANDROID_PACKAGE` use it. |
| Upload key | Created 27 Sep 2026 in `~/hawk-keys/upload-keystore.jks`. Its SHA-1 and SHA-256 are registered on the Firebase app. |
| Play signing keys | All three certificates Play issued are registered on the Firebase app: the classic RSA key (`3C:EF:8F:73…`), the hybrid RSA key (`CB:F5:5D:7B…`) and the hybrid ML-DSA key (`11:96:5A:4F…`). Copies are in `/Users/karnav/Products/knowra/certificates`. |
| Release signing | Reads `android/key.properties`. `flutter build appbundle` stops with a clear error if the key is missing, so a debug-signed bundle can't be uploaded. |
| Target SDK | 36, minimum 24. Meets Play's current rule for new apps. |
| 16 KB page size | Every 64-bit native library is aligned to 16 KB or more. |
| Native crash symbols | Included in the bundle, so Play Console symbolicates native crashes. |
| Permissions | Internet, camera, microphone, billing, plus normal ones added by Google libraries. No advertising ID, no photo/video media access, no foreground service. |
| Play Billing | Billing Library 8. Purchases are verified on the server and acknowledged after. |
| Renewals and refunds | `store_notification` is deployed and reachable. It re-checks every notice with Google before changing a plan. |
| Store icon | `play/icon-512.png`, 512 × 512 PNG. |
| Feature graphic | `play/feature-graphic.png`, 1024 × 500 PNG without transparency. Its source page is `play/feature-graphic.html`. |

## 1. Create the upload key (once) — done

```sh
cd /Users/karnav/Products/knowra/app
android/make_upload_key.sh
```

It asks for a password, creates `~/hawk-keys/upload-keystore.jks`, writes
`android/key.properties`, and prints the key's SHA-1 and SHA-256. Keep those
two fingerprints for step 4.

Back up the keystore file and its password somewhere other than this Mac.

## 2. Build the bundle

```sh
cd /Users/karnav/Products/knowra/app
flutter build appbundle --release
```

Add `--dart-define=SENTRY_DSN=...` if you want crash reports. That also
changes one Data safety answer below.

The file is `build/app/outputs/bundle/release/app-release.aab`. Every later
upload needs a higher build number: bump `version:` in `pubspec.yaml`,
for example `1.0.0+1` → `1.0.0+2`.

## 3. Create the app and upload the first release

1. Play Console → **Create app**. Name: Hawk. Package name: `in.hawkapp.app`. App, not game. Free.
2. **Test and release → Testing → Closed testing** (or Internal testing) → **Create new release.**
3. Accept **Play App Signing** with a Google-generated key (the default).
4. Upload the `.aab`, add testers, and send the release for review.

This first upload also unlocks subscriptions, which Play only allows once a
bundle with the billing permission exists.

## 4. Register the signing keys with Firebase — done

Google sign-in only works for signing keys Firebase knows. All five are
registered on the Firebase app, each with its own sign-in client: the debug
key, the upload key, and the three certificates Play issued (see the table at
the top).

Play shows more than one certificate on its App integrity page. Download them
as `.der` files and fingerprint the files rather than copying values off the
page. The classic RSA certificate (`deployment_cert.der`) is the one Google
sign-in normally checks.

## 5. Subscriptions

Monetize with Play → Products → **Subscriptions**. A payments profile must be
linked first.

| Product ID | Name | Base plan ID | Period | Price |
|---|---|---|---|---|
| `knowra.standard.monthly` | Hawk Standard | `monthly` | 1 month, auto-renewing | USD 4.99 |
| `knowra.premium.monthly` | Hawk Premium | `monthly` | 1 month, auto-renewing | USD 9.99 |

- The product IDs must match exactly. The backend catalogue uses them.
- Keep **one base plan and no offers** per product for launch. With a trial
  offer added, Play lists the same product twice and the app keeps
  whichever comes last.
- Settings → **License testing**: add the Gmail accounts you'll test with.
  Their test subscriptions renew every 5 minutes and cost nothing.

## 6. Let the backend talk to Google Play

The functions verify purchases as
`326925575468-compute@developer.gserviceaccount.com`.

1. The Play Developer API is enabled (done 27 Sep).

2. Play Console → **Users and permissions → Invite new users** → that email.
   Under app permissions, add Hawk with **View financial data** and
   **Manage orders and subscriptions**. It can take a day or more to take
   effect.

Until both are done, `verify_purchase` refuses every purchase with "Google
Play access is not configured". It never grants a plan it could not check.

## 7. Real-time notifications (renewals, cancellations, refunds)

The topic `play-billing`, its push subscription to `store_notification`,
and Google Play's permission to publish to it are all in place (done 27 Sep).

What's left is in Play Console → Monetize with Play → **Monetization setup** → Real-time
developer notifications → topic `projects/knowra-506719/topics/play-billing`
→ **Send test notification**. The function logs the test notification as
"unhandled", which is expected: it only acts on subscription notices.

**Don't launch without this.** A renewal is only recorded when Play sends
this notice. Without it, a subscriber who renews still drops to Free when
their first month ends, and one who is refunded keeps paid features until
then.

## 8. App content (Policy → App content)

| Form | Answer |
|---|---|
| Privacy policy | https://hawkapp.in/privacy |
| Ads | No ads |
| App access | Sign-in required. See "Reviewer login" below. |
| Content rating | Utility / productivity. No violence, sex, language, drugs or gambling. Users don't interact with each other. Has digital purchases. Expect Everyone / PEGI 3. |
| Target audience | 18 and over. This keeps the app out of the Families policy. |
| News, government, health, financial features | No |
| Advertising ID | No. The permission is absent from the release manifest. |
| Account deletion | In the app: Profile → Delete account. Web link: https://hawkapp.in/delete-account |

### Reviewer login

Hawk has no password of its own. Create a Gmail account just for review,
with 2-step verification off, and enter its address and password under App
access. Reviewers can then use "Continue with Google", or "Continue with
email" and read the six-digit code in that Gmail inbox.

To give reviewers Premium, add the account in the Firebase console:
Firestore → `testAccounts` → a document whose ID is the review email.

## 9. Data safety

Only data that leaves the phone counts. Sending files to Gemini, Resend or
Firebase is a service provider working for Hawk, which Play does not count
as sharing. So **Shared** is No throughout.

| Data type | Collected | Required or optional | Purpose |
|---|---|---|---|
| Personal info → Name | Yes | Required | Account management |
| Personal info → Email address | Yes | Required | Account management, app functionality, and advertising or marketing (offers and news emails: on by default, off in the app or by the unsubscribe link) |
| Personal info → User IDs | Yes | Required | Account management |
| Financial info → Purchase history | Yes | Optional | App functionality, account management |
| Photos and videos → Photos | Yes | Optional | App functionality |
| Audio → Music or other audio files | Yes, files the user saves | Optional | App functionality |
| Files and docs | Yes, including Drive files the user connects | Optional | App functionality |
| App activity → In-app search history | Yes, the questions asked | Optional | App functionality |
| App activity → Other user-generated content | Yes, saved links and text | Optional | App functionality |
| App info and performance → Crash logs, Diagnostics | Only if built with `SENTRY_DSN` | Required | Analytics |

Not collected: location, contacts, messages, calendar, health, web browsing,
device IDs for ads, and voice recordings. Dictation runs through Android's
own speech service, and Hawk receives only the text.

Security practices:

- Data is encrypted in transit: **Yes**.
- Users can request deletion: **Yes**.

Firebase's own list of what each SDK sends is at
https://firebase.google.com/docs/android/play-data-disclosure. Check it
against the Auth, Firestore, Storage and Functions SDKs Hawk uses.

## 10. Store listing (Grow users → Store presence → Main store listing)

| Field | Value |
|---|---|
| App name | Hawk |
| Short description | Save files, photos and links. Ask for them later in your own words. |
| App icon | `play/icon-512.png` |
| Feature graphic | `play/feature-graphic.png` |
| Phone screenshots | 2 to 8. Yours to take. Crop to at most 1:2, for example 1080 × 2160. |
| Category | Productivity |
| Contact email | Required, shown publicly |

A full description to start from:

> Hawk keeps what you save and finds it when you ask.
>
> Save files, photos, scans, recordings and links, or connect Google Drive.
> Later, ask in your own words, like "the garden photo from last week" or
> "what did the lease say about pets", and Hawk answers with the actual file.
>
> Search runs on your phone, and every answer points to the file it came
> from. There are no ads, and you can delete everything at any time.
>
> Free keeps memories for 30 days. Standard keeps them for a year, and
> Premium keeps them forever, with more answers every two hours.

## 11. From testing to production

New **personal** developer accounts must run a **closed test with at least
12 testers opted in for 14 days in a row** before Play allows production.
Organisation accounts skip this. Start the closed test as soon as internal
testing looks right: it's the longest step here.
