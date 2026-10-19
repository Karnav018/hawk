# QA checklist — Flutter handoff (auth, onboarding, connectors, library)

Predefined test list for the screens the Flutter side has handed off:
`3E SIGN IN`, `3H EMAIL`, `3I VERIFY`, `3J NAME`, `3F CONNECT STORAGE`,
`3G PERMISSIONS`, `3K CHOOSE FOLDERS`, `3L FIRST INDEX`, `READY`, `3D LIBRARY`,
plus the splash. Added after the second handoff: `2C VOICE HOME` (now the landing route `/`),
`3B ANSWER`, `3C CAPTURE`. Not in scope (not built): search/ask retrieval,
speech recognition, non-link capture tiles, storage manager, settings.

Status legend: `[ ]` not run · `[x]` pass · `[!]` fail (bug id in
`QA_FINDINGS.md`) · `[-]` blocked. Fill in the Status column per run.

> **Test-account caveat.** `karnav.p.018@gmail.com` (and its uid) are in
> `TEST_ACCOUNTS` and resolve to **Premium** on every entitlement check, so
> plan locks, quota gates and the paywall will NOT appear for it — testing the
> free-tier gates against it shows nothing, and filing that would be wrong. Use
> a **fresh email sign-in** (free tier) for any plan-lock / quota / paywall test.
> Codes now go to a real inbox via Gmail SMTP (`sign_in_code_sent via=smtp`),
> not the logs — automated sign-in needs inbox access for the recipient address.

## 0. Gates — run before any manual pass

| # | Check | Command / where | Expected | Status |
| --- | --- | --- | --- | --- |
| G1 | Static analysis | `cd app && flutter analyze` | `No issues found` | [x] 2026-09-10; re-run after retrieval/voice: clean |
| G2 | Unit + widget + golden tests | `cd app && flutter test` | all pass (baseline 167) | [x] 2026-09-10; re-run after retrieval/voice: 233 pass |
| G3 | Build carries the dart-defines | launch with `--dart-define-from-file=config/dev.json`; bootstrap log line `google_client_id: set` or the Google button not dimmed | Google button enabled, no "not set up" text | [x] 2026-09-10 sim, widget tree + screenshot |
| G4 | Functions deployed | `cd firebase && firebase functions:list` shows `request_email_code`, `verify_email_code`, `ensure_profile`, `list_connectors`, `begin_connection`, `complete_connection`, `set_scope_level`, `list_provider_folders`, `set_indexed_folders`, `disconnect_account`, `complete_storage_setup`, `on_index_job_created` | all present | [x] 2026-09-10 (19 deployed; after retrieval deploy `search`/`ask`/`list_connectors` answer UNAUTHENTICATED JSON, no IAM 403; `on_user_created` blocking trigger is NOT deployed, so `ensure_profile` is the only seeding path) |
| G5 | Rules + indexes deployed | Firestore console → Rules matches `firebase/firestore.rules`; Indexes all `Enabled` | no `Building` | [ ] |
| G8 | Email deliverable to real recipients | Resend domain verified + `EMAIL_FROM` set; `curl .../request_email_code -d '{"data":{"email":"<any>"}}'` returns `sent:true`, not 500 | [x] 2026-09-11 QA-028 fixed: sent:true for any recipient (dev log-mode) |
| G7 | Email-code secrets bound | `email_codes.py` decorators declare `secrets=["AUTH_CODE_SECRET","RESEND_API_KEY"]`; `firebase functions:secrets:access AUTH_CODE_SECRET` succeeds | bound and set | [!] QA-021 |
| G6 | Backend tests | `cd firebase/functions && ./venv/bin/python -m pytest -q` | all pass | [x] 2026-09-10 (67 pass); re-run after retrieval deploy: 95 pass |

## 1. Device / theme matrix

Run the per-screen list once per row that is available.

| Target | Theme | Text scale | Notes |
| --- | --- | --- | --- |
| iPhone 17 Pro simulator (iOS 26.5) | dark | 1.0 | primary |
| iPhone 17 Pro simulator | light | 1.0 | 3E/3D have light designs |
| iPhone 17 Pro simulator | dark | 1.3 (Settings → Accessibility → Larger Text) | overflow check |
| iPhone SE-class (small) | dark | 1.0 | keyboard + footer fit |
| Android emulator (API 34+) | dark | 1.0 | back gesture, OAuth callback activity |

## 2. Per-screen checklist

### Splash
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| SP-1 | Cold launch, signed out | Orb animation plays ~2s, then 3E. No white flash before the first frame. | [x] 2026-09-10 sim (lands on 3E, no runtime errors; animation not eyeballed) |
| SP-2 | Cold launch, signed in | Animation plays, then lands on 2C voice home (or the first outstanding onboarding step). Must not stay on the settled orb. No flash of 3E. | [x] 2026-09-10 SM G990E reaches 2C after QA-023 fix (2C itself fails, see VH-1) |
| SP-3 | Cold launch, airplane mode, previously signed in | Still lands on 2C within ~6 s (restore ceiling); not stuck on splash, not sent to 3E. | [ ] |

### 3E — Sign in
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| SI-1 | Open screen | Lockup, "Your second / *memory.*", lead copy, buttons Apple (iOS only) / Google / email, security banner, legal line pinned to bottom. Matches design copy exactly. | [x] 2026-09-10 sim, copy verbatim |
| SI-2 | Tap Google, cancel the sheet | Returns to 3E with no error text. | [ ] |
| SI-3 | Tap Google, complete with a test-user account | Spinner on the Google button only; other buttons disabled; lands on 3J (new), 3F (no storage setup) or 2C (done). | [ ] |
| SI-4 | Tap Apple (iOS), cancel | No error. Complete → same as SI-3. Name is prefilled on 3J on first authorisation. | [ ] |
| SI-5 | Build without `GOOGLE_SERVER_CLIENT_ID` | Google button dimmed, tapping shows the "not set up" message, not a crash. | [ ] |
| SI-6 | Google with an account not in the OAuth test users | Error text is human ("could not be verified"), not a raw code. | [ ] |
| SI-7 | Light theme | Matches the light design; banner and legal line readable. | [ ] |

### 3H — Email address
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| EM-1 | Enter screen | Back chevron, label "EMAIL SIGN-IN", headline "What's your / *email?*", helper "We'll send a six-digit code. No password to forget.", field autofocused, "Send code" disabled. | [x] 2026-09-10 sim |
| EM-2 | Type `a`, `a@`, `a@b` | No error while typing; "Send code" stays disabled. | [ ] |
| EM-3 | Type `a@b`, blur (tap elsewhere) | "That doesn't look like an email address." under the field, red border. | [ ] |
| EM-4 | Type `me@gmial.com` | "Did you mean me@gmail.com?" — tap it → field updates. | [ ] |
| EM-5 | Type ` Me@Example.COM ` and Send | Code requested for `me@example.com`; 3I shows the lowercase address. | [ ] |
| EM-6 | Send code with a valid address | Spinner on the button, then 3I. | [x] 2026-09-11 verify returns token after QA-029 IAM fix; completing sign-in in-app |
| EM-7 | Back from 3I, then tap "Send code" again | Must navigate to 3I again. | [x] 2026-09-10 sim, QA-001 fix verified |
| EM-8 | Send 6 codes within an hour | Server silently stops sending after 5; UI still says sent (by design). Note it. | [ ] |
| EM-9 | Airplane mode, Send | "No internet connection." shown, button re-enabled. | [ ] |
| EM-10 | Back on 3H | Returns to 3E. Field content preserved if you come back. | [ ] |

### 3I — Verify code
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| VC-1 | Enter screen | Label "VERIFY", headline "Check your / *inbox.*", "Six digits sent to <email>", six boxes, first box active, "Resend code" dimmed with `01:00` countdown. | [x] 2026-09-10 sim |
| VC-2 | Countdown | Ticks to `00:00`, then "Resend code" becomes tappable and the timer disappears. | [ ] |
| VC-3 | Type a wrong 6-digit code | Auto-submits on the 6th digit; "Checking" shown; then boxes clear, red borders, "That code is not valid. Request a new one." | [ ] |
| VC-4 | Type letters / paste `12 34-56` | Only digits accepted, capped at 6. | [ ] |
| VC-5 | iOS autofill from Mail | One-time-code suggestion fills all six and submits. | [ ] |
| VC-6 | Correct code (dev: read from Cloud Logging via gcloud) | Completes sign-in; landed on 3J (onboarding) 2026-09-11 sim after QA-029 fix. | [x] |
| VC-7 | 5 wrong attempts, then the right code | Rejected ("Request a new one"); Resend issues a new code that works. | [ ] |
| VC-8 | Wait > 10 min, enter the code | Rejected as invalid. | [ ] |
| VC-9 | Back | Returns to 3H with the address still filled. | [x] 2026-09-10 sim |
| VC-10 | Kill the app on 3I and relaunch | Back at 3E (no session yet). No crash. | [ ] |

### 3J — Your name
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| NM-1 | Enter screen | Label "PROFILE", no back button, headline "What should / *we call you?*", helper copy, name field, "HOW YOU'LL MOSTLY ASK" with Voice / Typing tiles, "Continue" pinned. | [x] 2026-09-11 sim, matches design |
| NM-2 | Leave name empty, Continue | Accepted; lands on 3F. | [ ] |
| NM-3 | Name `https://x.com` or `foo.com` | "A name can't contain a link." and Continue disabled. | [ ] |
| NM-4 | Name of 81+ chars | "Keep it under 80 characters." | [ ] |
| NM-5 | Name with surrounding spaces | Saved trimmed (check Firestore `users/{uid}.name`). | [ ] |
| NM-6 | Select Typing, Continue | Typing selects; Continue advances to 3F 2026-09-11 sim (Firestore values not inspected). | [x] |
| NM-7 | Keyboard open on a small device | Continue button still reachable; no overflow banner. | [ ] |
| NM-8 | Kill app after Continue, relaunch | Goes straight to 3F, never back to 3J. | [ ] |

### 3F — Connect storage (onboarding + manage)
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| CS-1 | Enter screen (onboarding) | Label "CONNECT", no back, headline "Bring your own / *storage.*", rows Google Drive / Dropbox / OneDrive / device row, "Continue" disabled, "Skip — use device storage only". | [x] 2026-09-11 sim |
| CS-2 | Device row | Reads "PHOTOS · FILES · VOICE NO…" with "Allow" (not "Connect") — QA-003 fixed. | [x] 2026-09-11 sim |
| CS-3 | Provider without credentials | Dropbox + OneDrive dimmed "NOT AVAILABLE IN THIS …", Connect disabled. | [x] 2026-09-11 sim |
| CS-4 | Tap Connect on Google Drive, cancel the browser | Spinner clears, no error snack. | [ ] |
| CS-5 | Connect Google Drive with a test user | Browser → consent → returns to app → lands on 3G with "Google Drive connected." | [ ] |
| CS-6 | Return to 3F after 3G | Row shows `CONNECTED` (or `N FILES · size`), button "Connected", "Continue" enabled. | [ ] |
| CS-7 | Free plan, connect a second provider | `RESOURCE_EXHAUSTED` → snack "Could not connect" with the plan message; limit note under the panel. | [ ] |
| CS-8 | Tap "Connected" on a connected row | Should confirm before disconnecting; after disconnect the row returns to `NOT CONNECTED`. | [ ] |
| CS-9 | Skip | Lands on 2C 2026-09-11 sim; avatar shows saved name "QT". | [x] |
| CS-10 | Airplane mode on first ever open of 3F | Should show an error with retry, not an empty panel. | [ ] |
| CS-11 | Manage flow: dock → Storage | Label "STORAGE", back chevron, headline "Connected / *storage.*", "Done" footer. Back and Done both return to where you came from. | [ ] |
| CS-12 | Kill app on 3F (onboarding), relaunch | Returns to 3F. | [ ] |

### 3G — Permissions
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| PM-1 | Enter screen | Label "PERMISSIONS", back, headline "What Vault may / *do with them.*", "Read and index" locked ON, "Manage storage" OFF, assurance pill, "Choose folders". | [ ] |
| PM-2 | Tap the Read toggle | Does nothing (locked). | [ ] |
| PM-3 | Turn Manage ON, cancel consent | Toggle returns to OFF, no error snack (cancel is not an error). | [ ] |
| PM-4 | Turn Manage ON, grant | Toggle ON; Firestore `scopeLevel == "manage"`. | [ ] |
| PM-5 | Turn Manage OFF | Server revokes the whole grant. UI must warn first and/or send the user back to 3F to reconnect; "Choose folders" must not proceed on a revoked account. | [ ] |
| PM-6 | Back | Returns to 3F with the account listed. | [ ] |
| PM-7 | Hot restart on 3G | Falls back to 3F (no `extra`), no crash. | [ ] |

### 3K — Choose folders
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| CF-1 | Enter screen | Spinner, then label "SCOPE", headline "Where should / *we look?*", folder rows `name` + `N FILES · size`, footer "SELECTED — NOTHING YET", "Start indexing" disabled. | [ ] |
| CF-2 | Toggle rows | Checkbox animates; footer total sums files and bytes; button enables with ≥1. | [ ] |
| CF-3 | Account with zero folders | "No folders found in this account." shown; button disabled. | [ ] |
| CF-4 | Listing fails (revoke token in Google security page, retry) | ErrorView with "Try again" for retryable errors. | [ ] |
| CF-5 | Start indexing | Spinner, then 3L (replace, no back to 3K). | [ ] |
| CF-6 | Long folder names | Single line, ellipsised, numbers stay on one line. | [ ] |
| CF-7 | Re-enter 3K later | Previously chosen folders are pre-checked (server `selected`). | [ ] |

### 3L — First index progress
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| IP-1 | Enter screen | "BUILDING YOUR VAULT", orb, "Looking through your folders" → "Reading N files", gauge, `processed / total`, stage label (`READING DOCUMENTS` …), footer button disabled until progress, "Keep using your phone — we'll notify you". | [ ] |
| IP-2 | Progress arrives | Gauge animates; by-kind rows appear (Documents / Images / Recordings); "MM:SS LEFT" appears after ≥10 files. | [ ] |
| IP-3 | Button enables after first progress | "Continue in the background" → READY. | [ ] |
| IP-4 | Job completes | Label "Your vault is ready", button "Start asking". | [ ] |
| IP-5 | Job fails (revoke Drive access mid-run) | "Indexing stopped" + error text in caution colour; a way out of the screen. | [ ] |
| IP-6 | Job doc never updates (trigger not deployed) | Must not strand the user: needs a visible error/escape within a reasonable time. | [ ] |
| IP-7 | Kill app on 3L, relaunch | Returns to 3F (storage setup not finished); account row shows `INDEXING…`. | [ ] |

### READY — First ask
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| RD-1 | Enter screen | Badge `VAULT READY · N FILES INDEXED` (or `CAPTURE ANYTHING TO BEGIN`), headline "Stop filing. / *Just ask.*", three prompt rows, "HOLD THE MIC…" line, "Open my vault". | [ ] |
| RD-2 | Open my vault | Spinner, then 2C; `storageSetupAt` set. | [ ] |
| RD-3 | Tap a prompt row | Currently same as Open my vault (ask screen not built) — must not crash. | [ ] |
| RD-4 | Badge count right after "Continue in the background" | Should reflect files being indexed, not "capture anything". | [ ] |

### 2C — Voice home (landing screen after sign-in)
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| VH-1 | Land after sign-in / cold launch signed in | Orb, "What do you need / …" headline, "Ask anything you have kept" field, "Recently captured" list, "Open library" link, dock. Route is `/`. | [x] renders 2026-09-10 SM G990E after QA-024/025; bottom row under dock is QA-026 |
| VH-2 | Tap the orb (fresh install) | System microphone permission prompt appears on FIRST tap, not at launch. Deny → `speechNote` replaces the hint in caution colour, typed path still works. | [ ] |
| VH-2b | Tap the orb (permission granted), speak | Dictation starts; partial words stream into the field; waveform bars follow mic level; nothing auto-submits. Submit with the keyboard search key. | [ ] |
| VH-2c | Device without a recogniser | `speechNote` shown, no crash, typed path works. | [ ] |
| VH-3 | Type a question, submit | Navigates to 3B with a real answer or a non-answer (see AN-1/AN-2); free-tier counter decrements either way (by design). | [ ] |
| VH-9 | While dictation is ACTIVE (orb listening, level moving), tap the field, type a different question, submit | Dictation cancels before `done` fires: NO second AnswerPage for the spoken phrase, exactly ONE question spent. (QA-030) | [ ] |
| VH-9b | Let dictation finish NATURALLY, then type another question and submit | Two answer screens / two questions is CORRECT here (both were genuinely asked) — do not file as a regression. Distinguishes the natural-completion race from VH-9. | [ ] |
| VH-9c | Typed submit with no dictation ever started | One `ask`, phase listening→retrieving; no pointless stop() call (stopDictation early-returns when nothing is listening). | [ ] |
| VH-4 | Submit empty / whitespace | Nothing sent; no error toast storm. | [ ] |
| VH-5 | "Open library" | 3D opens; back returns to 2C. | [x] opens 3D 2026-09-10 SM G990E (first tap did not register, second did; watch) |
| VH-6 | Dock: Capture / Storage | 3C sheet opens; manage 3F opens; both return to 2C. | [ ] |
| VH-7 | Recently captured | Shows the latest memories after a link capture; empty state when none. | [!] QA-026 row hidden under the dock |
| VH-8 | Theme toggle in header | Persists across relaunch. | [x] toggle works 2026-09-10 SM G990E; persistence not yet checked |


### 2C — Listening orb transform (design handoff, not yet implemented)
Source of truth: `design/blender/HANDOFF_listening_orb.md`. Motion ref `design/blender/previews/listening_loud_loop.gif` (Revision 2: sphere held STILL as the app draws it; the old rotating `_rigswirl.gif` is reference only), frames `listening_strip_sheet.png`. Assets `design/blender/export/orb_listen/level_0..4.png` (render exists; not yet copied to `app/assets/images/orb_listen/`). Only test once the Flutter session says it's implemented.

| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| LO-1 | Listening, speak loudly then go silent | Orb widens visibly 6-8% and springs back within ~250 ms of silence. | [ ] |
| LO-2 | Listening, silence vs loud | In silence the core is visibly smaller than in READY; on loud speech it nearly fills the glass with faint rings. | [ ] |
| LO-3 | Cross-frame + swirl continuity | No popping between the 5 strip frames; no jump in swirl angle entering or leaving listening. Code invariants (per design session): no phase-dependent `key` on VoiceOrb; the `_swirl`/`_breathe` ticker must NOT live in a subtree that gets swapped on phase change; strip drawn UNROTATED exactly where KnowraOrb is drawn, with the ring's Transform.rotate untouched and NO delta/absolute rotation applied to the strip (Revision 2 removed the earlier delta-rotation + 220 ms dissolve — the app only ever rotated the ring, never the sphere). | [~] 2026-09-11 code PASS: strip drawn unrotated, only the ring has Transform.rotate, squash scale wraps the whole stack; on-device pop check pending |
| LO-4 | Other phases unchanged | READY/RETRIEVING/ANSWERED at scale 1/1. RESOLVED 2026-09-11: `level:0` added to submitted()/transcriptChanged/search emits. Note: steady state always held (voice_orb:151 gates target to 0 off-listening, decaying over ~250ms); the reachable defect was typing-after-dictation (transcriptChanged kept phase=listening with a stale level → permanent squash) — now fixed, tests in dictation_test.dart. | [~] code PASS; on-device confirm pending |
| LO-5 | Performance | 60 fps on a mid-range Android during listening; DevTools shows no full-page rebuild per level tick (smoothing is a ValueNotifier, not a cubit rebuild). | [ ] |
| LO-6 | iOS mic normalisation | iOS reaches level > 0.5 on normal speech (speech_recogniser.dart:126 /10 gap — iOS reports 0..1). Normaliser is now per-platform (iOS passes 0..1 through, others /10) with unit tests. Real-speech confirmation still NEEDS A PHYSICAL iOS DEVICE — cannot verify from sim or Android; stays OPEN. | [~] 2026-09-11 normaliser logic PASS by inspection + unit tests (iOS pass-through, Android /10, clamped 0..1; 46 voice tests pass). Real-speech iOS check still BLOCKED on physical device |
| LO-7 | Assets wired | `app/assets/images/orb_listen/` copied (five files, 768x768, sphere touching all four edges to match orb_sphere.png) and `- assets/images/orb_listen/` in pubspec. RED FLAGS: any 512px file, a 14px margin, or a `stripZoom`/1.0579 constant left in code → the re-copy did not happen. | [x] 2026-09-11 code PASS: 5 files all 768x768 = orb_sphere.png, pubspec has the dir entry, no stripZoom/1.0579, no 512 ref |

### 3B — Answer (retrieval live since 2026-09-10: Gemini embeddings + KNN + lexical rescore + RRF + gemini-3.6-flash)
Precondition: capture a FRESH link or note first. Anything captured before the retrieval deploy is stuck at `extracted` and is invisible to search until a backfill exists.

| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| AN-1 | Capture a fresh link, wait until its row reads READY, ask a question it answers | 3B shows "THINKING", then prose blocks with inline superscript citations, a SOURCES list with per-type marks (link / document / photo / audio), and a confidence meter. | [ ] |
| AN-2 | Ask something the vault cannot answer | "Nothing in your vault matches that yet" or "I found related material but could not answer that". Confidence meter must be HIDDEN in this state. | [ ] |
| AN-3 | Tap a source row | Opens/points to the cited memory (or at least the file and page named in the citation). | [ ] |
| AN-4 | Free tier, 5th question of the day (a non-answer still costs one) | Quota error is a sentence, not a raw code; counter resets per server `queriesResetAt`. | [ ] |
| AN-5 | Back | Returns to 2C; field state consistent. | [ ] |
| AN-6 | Offline | Network error state with retry; no spinner forever. | [ ] |
| AN-7 | Every source shows the same generic document icon | That means the server is not sending citation `type`; file it. | [ ] |
| AN-8 | Ask with only a photo/PDF/audio captured | Those stay `extracted` with an `indexNote`; expect a non-answer, not a failure. | [ ] |

### 3C — Capture
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| CP-1 | Open from dock | Sheet with "Anything you keep, …" headline, tiles (Link live; Photos / Scan / Documents / Audio / Dictate marked SOON and dimmed), link field, "Or write a note" field, Close. | [x] 2026-09-10 SM G990E (Link tile reads ARCHIVED, per design) |
| CP-2 | Tap a SOON tile | "Not available yet" feedback; no navigation. | [ ] |
| CP-3 | Paste `example.com` | Normalised to `https://example.com`; "Save link" enabled. | [x] button enables 2026-09-10; normalisation to be checked in Firestore |
| CP-4 | Paste `not a link` | "That doesn't look like a link." and Save disabled. | [ ] |
| CP-5 | Save link | "Saved — processing now" snack; sheet closes; memory appears in 3D as type Link, state QUEUED → INDEXING; Firestore doc has `status: uploaded`, `recallState: active`. | [x] row appears as LINK, INDEXING, header "1 MEMORY" 2026-09-10 SM G990E; title is "Untitled" (QA-027); snack not observed (phone locked); Firestore doc not inspected |
| CP-6 | Save a note (text only) | Same as CP-5 with type Note; 20,000-char limit message on overflow. | [ ] |
| CP-7 | Save while offline | "Could not save" with the network message; nothing half-written. | [ ] |
| CP-8 | Double-tap Save | One memory, not two. | [ ] |


### Billing / plan locks (new since retrieval; needs a FREE account)
Rule under test: an **upgrade affordance appears only where paying actually unlocks the thing.** A fair-use ceiling on a paid tier, and a full index on Premium, both show the lock with NO upgrade button. (`test/features/billing/plan_lock_test.dart`.)

| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| PL-1 | Free account, spend the 4 daily questions, return to 2C | Orb dims; the question field is replaced by a PlanLockNotice; the notice offers upgrade (free → paid unlocks it). | [ ] |
| PL-2 | Free account, 1-3 questions left | A "N LEFT" counter appears in the 2C top bar; absent at 4/4 and on unmetered plans. | [ ] |
| PL-3 | Paid account hits the fair-use ceiling (Standard 200/day, Premium 1000/day) | Lock shown; message differs from free tier (no "upgrade"); `fairUse:true` in payload. Upgrade affordance MUST be absent. | [ ] |
| PL-4 | Index full, free/standard, open 3C | Capture tiles read LOCKED and route to /upgrade (paying raises the ceiling → upgrade shown). | [ ] |
| PL-5 | Index full on Premium, open 3C | LOCKED with NO upgrade (nothing higher to buy). | [ ] |
| PL-6 | 3F account limit reached | Same lock treatment as the rest; upgrade shown only if a higher plan raises the limit. | [ ] |
| PL-7 | 3D with dormant memories (free window elapsed) | Compact dormant-memories banner; tapping routes to /upgrade. | [ ] |
| PL-8 | /upgrade (PaywallPage) direct | Renders plans; nothing purchasable yet (no store products) — do NOT file the paywall until the Flutter session says it's up. | [ ] |

### 3D — Library
| ID | Steps | Expected | Status |
| --- | --- | --- | --- |
| LB-1 | Enter, empty vault | Header "Library / NOTHING CAPTURED YET", chips ALL/DOCS/AUDIO/IMAGES/LINKS, empty state "Nothing to / *remember yet.*", dock with Capture / Voice / Storage. | [x] 2026-09-10 SM G990E, light theme |
| LB-2 | Enter, vault with ≤20 memories | Header count equals the row count. | [ ] |
| LB-3 | Vault with >20 memories | Header reads `20+ memories` (QA-004 fix), never `21`. Scrolling loads the next page once; no duplicates; spinner row at the bottom while appending. | [ ] |
| LB-4 | Rapid scroll to bottom | Only one extra page per scroll-to-bottom, not a chain of pages. | [ ] |
| LB-5 | Filter chips | DOCS shows `document` only, IMAGES `photo`, AUDIO `audio`, LINKS `link`; count updates; switching filter resets scroll and paging. | [ ] |
| LB-6 | Row content | Type badge, title (ellipsised), meta `Type · Provider · Topic`, right column relative time (`HH:MM`, `nD`, `nW`, `nY`) and state (`QUEUED` / `INDEXING` / `READY` / `FAILED`). Yesterday must not render as `0D`. | [ ] |
| LB-6b | Row for a photo / PDF / audio capture | Status `extracted` with `indexNote` (e.g. "Image OCR is not wired up yet") must NOT render as FAILED; it is a note, not an error. | [ ] |
| LB-7 | Offline | ErrorView "No internet connection." with Try again; cached rows if Firestore persistence has them. | [ ] |
| LB-8 | Theme toggle | Switches dark/light and persists across relaunch. | [ ] |
| LB-9 | Search, Sort, Capture, Voice, row tap | Not built — must not crash; ideally visibly disabled. | [ ] |
| LB-10 | Storage dock button | Opens the manage flavour of 3F. | [ ] |
| LB-11 | Sign out from another device / disable the user in Firebase, then resume the app | Returns to 3E within one resume. | [ ] |

## 3. Cross-cutting

| ID | Check | Expected | Status |
| --- | --- | --- | --- |
| X-1 | No raw Firebase/Functions codes in any error text | Every message is a sentence. | [ ] |
| X-2 | Back / swipe-back on every screen | Matches the per-screen expectation; no dead ends except 3J/3F onboarding by design. | [ ] |
| X-3 | Kill and relaunch at every step of onboarding | Guard resumes at the first outstanding step. | [ ] |
| X-4 | Text scale 1.3 | No yellow/black overflow stripes on any screen. | [ ] |
| X-5 | VoiceOver / TalkBack | Buttons have labels (dock, back, toggles, folder rows). | [ ] |
| X-6 | Console | No `Unhandled Exception`, no `setState after dispose`, no `Cannot emit new states after calling close`. | [ ] |
| X-7 | Firestore rules | Manual write to `users/{uid}.tier` from the client is denied; reading another user's memory is denied. | [ ] |

## 4. Known backend gaps (expected, not bugs to file against Flutter)

- Text/link memories now reach `READY`; photo/PDF/audio stop at `extracted` with an `indexNote` (OCR/ASR not wired).
- `search` and `ask` are live (Gemini). Memories captured before 2026-09-10 stay `extracted` and are not searchable (no backfill yet).
- Email codes: 60 s resend cooldown, 10 min TTL, 5 attempts per code, silent throttle after 5 codes/hour/address.
- Blocking `beforeUserCreated` only runs on Identity Platform projects; otherwise `ensure_profile` seeds on first snapshot.
