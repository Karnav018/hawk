# QA findings — Flutter handoff, static review pass (2026-09-10)

Source: full read of `app/lib/src/features/{auth,connectors,memory,splash}`,
`core/`, the router, `firebase/firestore.rules`, and the callables in
`firebase/functions`. Gates: `flutter analyze` clean, `flutter test` 167/167.
Runtime pass on the iPhone 17 Pro simulator is tracked in `QA_CHECKLIST.md`.

Severity: P1 = flow broken or user stranded · P2 = wrong, workaround exists ·
P3 = polish / design mismatch. Owner: F = Flutter session, B = backend.
Status: OPEN / FIXED / WONTFIX (with reason).

| ID | Sev | Owner | Screen | Title | Status |
| --- | --- | --- | --- | --- | --- |
| QA-001 | P1 | F | 3H | Resend from 3H after going back never navigates to 3I (runtime-verified fixed 2026-09-10) | FIXED — `sendCode` now lowers `codeSent` before the request, re-arming the edge. Test: `app/test/features/auth/resend_navigation_test.dart` |
| QA-002 | P1 | F | 3L | Job-stream error is never shown and there is no way off the screen | FIXED — `canLeave` now also true on error / missing job / terminal, `onDone` settles loading, and the stream error renders. Test: `app/test/features/connectors/index_progress_exit_test.dart` |
| QA-003 | P1 | F | 3F | Device row reads `NOT CONNECTED` with a live no-op "Connect" button | FIXED — device row is `PHOTOS · FILES · VOICE NOTES` / "Allow" via new `subtitleOverride` + `actionOverride`, and routes to capture |
| QA-004 | P1 | F | 3D | Header memory count is fabricated (`page + 1`) | FIXED — `MemoryPage` now carries `hasMore`, not an inflated `total`; header shows "N+" while more pages exist. Tests: `memory_page_shape_test.dart`, updated `memory_list_bloc_test.dart` |
| QA-005 | P2 | F | 3D | Scroll burst chain-loads several pages | OPEN |
| QA-006 | P2 | F+B | 3G | Turning Manage off revokes the whole connection; UI carries on as if connected | OPEN |
| QA-007 | P2 | F | 3F | Catalogue failure with a cold cache leaves 3F empty with no retry | OPEN |
| QA-008 | P2 | F | 3F | Disconnect is a single unconfirmed tap with no busy state | OPEN |
| QA-009 | P2 | F | auth | Fresh social sign-in can skip profile seeding | OPEN |
| QA-010 | P2 | F | auth/3F | Success-path `emit` after the router has closed the cubit | OPEN |
| QA-011 | P3 | F | 3I | "Checking" flips back to "Resend code" for a frame before redirect | OPEN |
| QA-012 | P3 | F | 3L | Every by-kind row shows the green check as soon as it is counted | OPEN |
| QA-013 | P3 | F | 3L | `MM:SS LEFT` only refreshes when the job document changes | OPEN |
| QA-014 | P3 | F+B | READY | Badge says "capture anything" right after "Continue in the background"; prompt taps drop the prompt | OPEN |
| QA-015 | P3 | F | 3D | Yesterday renders as `0D` | OPEN |
| QA-016 | P3 | F | boot | `GOOGLE_CLIENT_ID is empty` warning on every correct dev launch | OPEN |
| QA-017 | P3 | F | 3H | Field keeps raw casing after Send while 3I shows lowercase | OPEN |
| QA-018 | P2 | F | tests | No tests for connector cubits/pages, the 3H back→resend path, or the 3L error path | OPEN |
| QA-019 | P3 | F | 3D | Search, Sort, Capture, Voice, row tap are silent no-ops | OPEN |
| QA-020 | P3 | F | 3G | "Choose folders" shows a spinner while the Manage toggle is in flight | OPEN |
| QA-021b | P1 | B | 3H | Missing composite index `emailChallenges(email, createdAt)` — the rate-limit aggregate could not be served | FIXED + DEPLOYED — added to `firestore.indexes.json`; the existing `(email, consumedAt, createdAt)` index cannot serve it because `consumedAt` sits mid-prefix |
| QA-022 | P3 | B | 3H | `_deliver` logs but does not raise on a Resend 4xx, so a rejected address still returns `sent: true` | WONTFIX (by design) — raising would make sign-in an account-enumeration oracle. Note for QA: the default sender `onboarding@resend.dev` only delivers to the Resend account owner's own address, so arbitrary test addresses will never receive mail. Verify a domain in Resend, or test with the owner address; `email_delivery_failed status=` appears in Cloud Logging either way |
| QA-021 | P1 | B | 3H/3I | `request_email_code` / `verify_email_code` deployed without `secrets=`; `AUTH_CODE_SECRET` and `RESEND_API_KEY` are unbound | FIXED + DEPLOYED — but the secret was only half of it: see QA-021b. Probe now returns `{"sent":true,...}` |
| QA-023 | P1 | F | splash/2C | Splash and voice home both register path `/`; signed-in users never leave the splash | FIXED in source (splash → `/splash`); runtime: signed-in phone reached 2C 2026-09-10 |
| QA-024 | P1 | F | 2C | Voice home throws on first build: `repeat()` called before the orb controllers have a duration | FIXED, runtime-verified on SM G990E 2026-09-10 |
| QA-025 | P1 | F | 2C | Dock renders over the middle of the orb: `VaultDock`'s `Center` fills the full-height `bottomNavigationBar` slot | FIXED, runtime-verified on SM G990E 2026-09-10 |
| QA-026 | P2 | F | 2C | "RECENTLY CAPTURED" row and list sit underneath the dock; no bottom inset for the bar | FIXED in source (body reserves dock clearance); VERIFIED 2026-09-11 sim — RECENTLY CAPTURED visible above the dock |
| QA-027 | P2 | F | 3D/3C | A captured link shows as "Untitled" in the library; `displayTitle` ignores `url` | FIXED in source (also `_toEntity` now maps `Source`); runtime re-check pending |
| QA-028 | P1 | B+F | 3H | Email delivery hard-fails (500 INTERNAL) for real recipients: Resend sandbox sender rejects, `_deliver` raises | FIXED + DEPLOYED 2026-09-11 (send returns sent:true, app reaches 3I). Dev codes now only in Cloud Logging stdout. |
| QA-029 | P1 | infra | 3I | `verify_email_code` 500s: runtime SA lacks `iam.serviceAccounts.signBlob`, so `create_custom_token` fails | FIXED 2026-09-11 (Token Creator granted; verify now returns a token HTTP 200) |
| QA-030 | P2 | F | 2C/3B | Submitting typed text while dictation is live pushed a 2nd AnswerPage for the abandoned phrase and spent a daily question | FIXED 2026-09-11 (from QA LO-4 aside) |

---

### QA-001 [P1] 3H: resend after back never navigates to 3I
- **File:** `app/lib/src/features/auth/presentation/pages/email_address_page.dart:56-59`, `app/lib/src/features/auth/presentation/bloc/email_sign_in_cubit.dart:112-124`
- **What:** the page navigates on `!previous.codeSent && current.codeSent`. `codeSent` is never reset, so once the user has been to 3I and comes back, a second "Send code" emits `codeSent: true → true` and the listener never fires.
- **Repro:** 3E → Continue with email → valid address → Send code → on 3I tap back → tap Send code. Spinner runs, request succeeds, screen stays on 3H.
- **Expected:** navigate to 3I with a fresh countdown.
- **Fix:** in `sendCode`, emit `codeSent: false` together with `isSending: true`, or have the page listen for `isSending` true→false with `exception == null`.
- **Confidence:** high. Not covered by `email_flow_nav_test.dart`.

### QA-002 [P1] 3L: job-stream error never shown, no exit
- **File:** `app/lib/src/features/connectors/presentation/pages/index_progress_page.dart` (no `state.exception` rendering, no header/back), `index_progress_cubit.dart:38-43`
- **What:** a Firestore listener error (permission-denied, offline on first open, deleted job) sets `exception` on the cubit, but the page never renders it. The only exit is `canLeave`, which needs progress. The listener is dead after an error, so the user is stuck until they kill the app.
- **Repro:** start indexing, then go offline before the first progress write; or open the route with a jobId that is not yours.
- **Expected:** ErrorView with retry, plus a way back to 3F.
- **Confidence:** high.

### QA-003 [P1] 3F: device row shows `NOT CONNECTED` + no-op "Connect"
- **File:** `app/lib/src/features/connectors/presentation/pages/connect_storage_page.dart:220-231`, `connector_row.dart:47-51, 118-130`
- **What:** `_DeviceRow` passes an option with no account, so `ConnectorRow` renders subtitle `NOT CONNECTED` and a filled "Connect" button wired to (now FIXED, verified 2026-09-11 sim: device row reads "PHOTOS · FILES · VOICE NO…" with an "Allow" action). Design shows the device row as always-on with `PHOTOS · FILES · VOICE NOTES` and the tagline "Captured here".
- **Expected:** informational row, no action button, subtitle from the design.
- **Confidence:** high.

### QA-004 [P1] 3D: header count is fabricated
- **File:** `app/lib/src/features/memory/data/firebase/firestore_memory_repository.dart:94-98`, `library_page.dart:175`
- **What:** `total = offset + items.length + (hasMore ? 1 : 0)` is a paging sentinel, but the header prints it as "N memories". With 200 memories the header says "21 memories" until the user scrolls, then "41", and so on.
- **Fix:** use a `count()` aggregation for the header (index exists on `userId`), or show "memories" without a number until known.
- **Confidence:** high.

### QA-005 [P2] 3D: scroll burst chain-loads pages
- **File:** `app/lib/src/features/memory/presentation/bloc/memory_list_bloc.dart:27`, `library_page.dart:65-73`
- **What:** every scroll tick within 400 px of the bottom adds a `nextPageRequested`. The handler uses `sequential()`, which queues them; each queued event re-checks only `hasMore`/`isAppending`, not scroll position, so one fling can fetch several pages.
- **Fix:** `transformer: droppable()`.
- **Confidence:** high.

### QA-006 [P2] 3G: Manage off revokes the whole connection
- **File:** `firebase/functions/connector_api.py:398-412`, `app/lib/src/features/connectors/presentation/pages/permissions_page.dart:45-52, 69-76`
- **What:** the server cannot downgrade a Google grant, so `set_scope_level(read)` sets the account to `REVOKED`. The client shows a snack "Manage access removed" but stays on 3G with "Choose folders" enabled; the next call (`list_provider_folders`) fails on a revoked account, and back on 3F "Continue" is disabled.
- **Expected:** confirm before turning off ("This disconnects Google Drive; you will need to reconnect"), then return to 3F. Disable "Choose folders" when `account.state == revoked`.
- **Confidence:** high (server behaviour read from source).

### QA-007 [P2] 3F: catalogue failure, cold cache, no retry
- **File:** `app/lib/src/features/connectors/data/firebase/firebase_connector_repository.dart:114-136`, `connect_storage_cubit.dart:45-53`
- **What:** `list_connectors` failing with nothing cached errors the catalogue stream. The cubit sets `exception` and `isLoading: false`; the page shows a snack once and renders a panel with only the (broken) device row. Nothing re-subscribes.
- **Repro:** first ever open of 3F in airplane mode.
- **Confidence:** high.

### QA-008 [P2] 3F: disconnect is one unconfirmed tap
- **File:** `app/lib/src/features/connectors/presentation/bloc/connect_storage_cubit.dart:86-95`, `connector_row.dart:126-130`
- **What:** tapping the "Connected" pill calls `disconnect` immediately, no confirmation, no busy flag (double tap → two calls). The product rule is that nothing destructive happens without confirmation; disconnect keeps memories but is still a surprise.
- **Confidence:** high.

### QA-009 [P2] auth: fresh social sign-in can skip profile seeding
- **File:** `app/lib/src/features/auth/data/firebase/firebase_auth_repository.dart:127-129, 257-264`
- **What:** for a new social user the client writes `{name}` to `users/{uid}` right after `signInWithCredential`. If that local write lands before the profile listener's first server snapshot, the first event reports `exists == true` and `_ensureProfile` is never called. On a project without Identity Platform (no blocking trigger) the profile then has no `userId`/`email`/`createdAt` and no `subscription/current`.
- **Verify:** fresh Google sign-in → inspect `users/{uid}` and `users/{uid}/subscription/current` in the console.
- **Fix:** call `_ensureProfile` when the snapshot lacks `userId` (not only when it does not exist), or write the name through `ensure_profile`.
- **Confidence:** medium (timing dependent). `firebase functions:list` on 2026-09-10 shows `on_user_created` is not deployed, so this project relies entirely on `ensure_profile`; the gap is live, not theoretical.

### QA-010 [P2] success-path emit after close
- **File:** `onboarding_cubit.dart:78`, `email_sign_in_cubit.dart:146`, `connect_storage_cubit.dart:104`
- **What:** these cubits emit "not busy" after an await whose success changes the session. The router disposes the providing route on that session change; if the profile snapshot beats the write's ack, `emit` runs on a closed cubit and throws `StateError: Cannot emit new states after calling close`, which is then reported as an unhandled error.
- **Fix:** `if (isClosed) return;` before the trailing emit, or drop the trailing emit (the screen is gone).
- **Confidence:** medium.

### QA-011 [P3] 3I: "Checking" flickers back before redirect
- **File:** `email_sign_in_cubit.dart:146`, `verify_code_page.dart:60-86`
- **What:** `isVerifying` goes false as soon as the callable returns, before the session stream moves the router, so "Resend code" reappears for a frame.

### QA-012 [P3] 3L: by-kind rows always complete
- **File:** `firebase_connector_repository.dart:427-437`
- **What:** the server writes `byKind: {kind: count}`; the client maps `done = total = count`, so `isComplete` is true for every row with any count and all show the green check while the job is still enumerating.

### QA-013 [P3] 3L: `LEFT` counter only updates on snapshots
- **File:** `index_progress_page.dart:36`

### QA-014 [P3] READY: badge and prompt rows
- **File:** `vault_ready_page.dart:42-43, 93-101`; `firebase/functions/connector_sync.py:147-152`
- **What:** `account.fileCount` is only written on job completion, so after "Continue in the background" the badge says `CAPTURE ANYTHING TO BEGIN`. Prompt rows call `finish()` and discard the prompt text.

### QA-015 [P3] 3D: yesterday shows `0D`
- **File:** `memory_row.dart:139-144`
- **What:** a memory from 23:00 yesterday viewed at 01:00 fails the same-day test and then prints `delta.inDays` = 0.

### QA-016 [P3] boot: misleading warning
- **File:** `bootstrap.dart:65-71`
- **What:** `dev.json` intentionally leaves `GOOGLE_CLIENT_ID` empty (iOS reads it from the plist; `isConfigured` checks the server id), so the "relaunch with --dart-define-from-file" warning fires on every correct launch.

### QA-017 [P3] 3H: field casing after Send
- **File:** `email_sign_in_cubit.dart:111-112`, `email_address_page.dart:33-35`

### QA-018 [P2] tests
- No tests under `app/test/features/connectors/` beyond entities: cubits, pages, and the repository decoders are untested. No test for QA-001's path. No test for 3L's error path.

### QA-018 [P2] tests — specs for the Flutter session to implement
QA does not edit the tree; these are the tests to add, in priority order. Each is one `test`/`testWidgets`/`blocTest` unless noted.

| # | File (add to / create) | Name | Arrange → Act → Assert |
| --- | --- | --- | --- |
| T1 | `test/app/router_navigation_test.dart` (new) | pumps the real router: authenticated lands on VoiceHomePage | fake `AuthRepository` with `current = authenticated(done)`; build `AppRouter(session, auth).config` in a `MaterialApp.router`; pump splash `duration + maxWait`; expect `find.byType(VoiceHomePage)` and no `SplashPage`. Pins QA-023. Add siblings: unauthenticated → `SignInPage`; onboarding needsName → `YourNamePage`; onboarding storage only → `ConnectStoragePage`. |
| T2 | `test/features/auth/email_flow_nav_test.dart` | resend from the address screen after going back navigates to verify again | existing harness; send → on 3I `tester.tap(back)` → tap "Send code" → `pumpAndSettle` → expect `VerifyCodePage`. Pins QA-001. |
| T3 | `test/features/auth/email_sign_in_cubit_test.dart` | sendCode resets codeSent before the request | `blocTest` with a completer-backed repo: expect the first emitted state has `codeSent: false, isSending: true`. |
| T4 | `test/features/connectors/connect_storage_cubit_test.dart` (new) | catalogue stream error → exception, not loading | mocktail repo `watchCatalog` returns `Stream.error(NetworkException)`; expect `isLoading false`, `exception is NetworkException`. Also: `connect` cancelled → `connecting null`, `exception null`; `connect` success → `justConnected == account`; `disconnect` called twice while first pending → repo called once (after QA-008). |
| T5 | `test/features/connectors/permissions_cubit_test.dart` (new) | setManage(false) flags reconnect; setManage(true) consent cancel is not an error | repo `setScopeLevel` returns revoked account / throws `CancelledException`; assert `needsReconnect` and `exception` respectively. |
| T6 | `test/features/connectors/folder_selection_cubit_test.dart` (new) | load, toggle, totals, start | folders [a(3 files,1MB), b(5,2MB)], `selected` empty → `canStart false`; toggle a → `selectedFiles 3`; start → `jobId` emitted; repo throws → `exception`, `isStarting false`. |
| T7 | `test/features/connectors/connector_repository_decode_test.dart` (new) | lenient parsing | `_account` with `state: 'weird'` → `connected`; `provider: 'box'` → `internal`; `_job` with `byKind {document: 3}` → one row, and (after QA-012) `done`/`total` semantics as decided. Expose the decoders via `@visibleForTesting` or test through `watchIndexJob` with a fake Firestore. |
| T8 | `test/features/connectors/index_progress_exit_test.dart` (exists) | stream error renders ErrorView with a way back | `watchIndexJob` → `Stream.error(...)`; expect `ErrorView` and a back affordance. Pins QA-002. |
| T9 | `test/features/memory/memory_list_bloc_test.dart` | a burst of nextPage events loads exactly one extra page | add 5× `nextPageRequested` synchronously; expect one `fetchMemories` call with `offset 20`. Pins QA-005 (needs `droppable()`). |
| T10 | `test/features/memory/memory_row_test.dart` (new) | relative time never prints 0D | `createdAt = now - 2h` where `now` is 01:00 → expect `1D` (or `HH:MM` if you decide same-24h wins). Pins QA-015. |
| T11 | `test/features/connectors/connect_storage_page_test.dart` (new) | device row is informational | pump 3F with a catalogue; expect the device row subtitle from the design and no tappable "Connect" on it. Pins QA-003. |
| T12 | `test/features/memory/library_golden_test.dart` | header reads `20+ memories` when hasMore | loaded state with 20 rows and `hasMore true`; expect text `20+ memories`. Pins QA-004. |


### QA-019 [P3] 3D: silent no-ops
- **File:** `library_page.dart:135-136, 190, 196, 248`
- **What:** Search, Sort, Capture, Voice and row tap do nothing. Acceptable pre-build, but they should be disabled or announce "coming soon" so testers do not file them as bugs.

### QA-020 [P3] 3G: spinner on the wrong button
- **File:** `permissions_page.dart:71`

### QA-021 [P1] backend: email-code functions have no secret binding
- **File:** `firebase/functions/email_codes.py:82-88` (`request_email_code` decorator) and `:131` (`verify_email_code`); compare `connector_api.py:198` which passes `secrets=PROVIDER_SECRETS`.
- **What:** `_secret()` reads `AUTH_CODE_SECRET` from the environment and raises `RuntimeError` when it is missing. Neither callable declares `secrets=[...]`, and there is no `functions/.env`, so on the deployed functions the variable is unset. Every call to `request_email_code` should fail with `internal`, which the app renders as "Something went wrong." `RESEND_API_KEY` is likewise unbound, so even with the secret fixed no email is sent; the code only goes to Cloud Logging.
- **Repro:** 3E → Continue with email → any address → Send code.
- **Expected:** code issued, 3I shown, email delivered.
- **Fix:** `secrets=["AUTH_CODE_SECRET", "RESEND_API_KEY"]` on both decorators (and `EMAIL_FROM` via `.env` if used), `firebase functions:secrets:set AUTH_CODE_SECRET`, redeploy.
- **Confidence:** confirmed. `curl -X POST .../request_email_code -d '{"data":{"email":"qa-probe@example.com"}}'` on 2026-09-10 returned `HTTP 500 {"error":{"message":"INTERNAL","status":"INTERNAL"}}`.

### QA-023 [P1] splash and 2C share the root path; authenticated users are stranded on the splash
- **File:** `app/lib/src/features/splash/presentation/pages/splash_page.dart:69` (`routePath = '/'`), `app/lib/src/features/voice/presentation/pages/voice_home_page.dart:31` (`routePath = '/'`), `app/lib/src/app/router/app_router.dart:58, 186, 292-295`
- **What:** both `GoRoute`s are registered with `path: '/'`. go_router returns the first match, so `/` always renders `SplashPage`. For `AuthAuthenticated` the guard redirects splash → `VoiceHomePage.routePath`, which is also `/`; a redirect to the current location is a no-op, so nothing navigates. The user watches the orb settle and stays there.
- **Repro:** sign in (any provider) and finish onboarding, or cold-launch as an already signed-in user. Expected: 2C. Actual: splash frame, no dock, no input.
- **Why tests pass:** `router_guard_test.dart` tests the pure `guardFor`, which correctly returns `'/'`; the collision is in route matching, which no test exercises.
- **Fix:** give the splash its own path (`/splash`) and make it `initialLocation`, or drop the splash route and render the splash inside the `/` builder until `_splashComplete`. Add a widget test that pumps the real `AppRouter` with an authenticated session and expects `VoiceHomePage`.
- **Confidence:** high from source; runtime confirmation pending (needs a signed-in session on the simulator).

### QA-024 [P1] 2C: voice orb crashes on first build
- **File:** `app/lib/src/features/voice/presentation/widgets/voice_orb.dart:31-35`
- **What:** `initState` does `AnimationController(vsync: this)..repeat(reverse: true)` and `..repeat()` and only then calls `_retime()`, which is what sets `duration`. `AnimationController.repeat()` asserts when neither `period` nor `duration` is set, so `VoiceHomePage` throws while building and the screen is the red error box (grey in release).
- **Seen:** 2026-09-10 on SM G990E, cold launch with a signed-in session that has finished storage setup. Log: `AnimationController.repeat() called without an explicit period and with no default Duration.` at `_VoiceOrbState.initState (voice_orb.dart:33:50)`.
- **Fix:** call `_retime()` before the two `repeat()` calls, or construct the controllers with `duration:` from the initial phase. Add a widget test that pumps `VoiceOrb(phase: VoicePhase.idle)` and expects no exception; `test/features/voice/` currently does not catch this.
- **Confidence:** confirmed live.

### QA-025 [P1] 2C: dock floats over the orb instead of sitting at the bottom
- **File:** `app/lib/src/core/widgets/vault_dock.dart:29` (`return Center(child: ClipRRect(...))`), `app/lib/src/features/voice/presentation/pages/voice_home_page.dart:61-68` (`bottomBar: Padding(child: VaultDock(...))`), `app/lib/src/core/widgets/app_screen.dart:92-93` (`extendBody: true`, `bottomNavigationBar: bottomBar`).
- **What:** `Scaffold` lays out `bottomNavigationBar` with `BoxConstraints.loose(size)` — max height is the whole screen. `Center` without a `heightFactor` expands to its max height when it is bounded, so the bar becomes screen-tall and its child is centred vertically: the dock lands on the orb, and the mic button covers the orb's tap target (a tap there fires `_ask` with an empty field). 3D is unaffected because it places the dock inside a `Column`, where the height is unbounded and `Center` shrink-wraps.
- **Seen:** 2026-09-10 on SM G990E, two screenshots 30 s apart, no keyboard (`mInputShown=false`).
- **Fix:** in `VaultDock` use `Center(heightFactor: 1, ...)` or wrap the dock in `SizedBox(height: SnackHost.dockHeight)`; alternatively give `AppScreen` a fixed-height `bottomBar` wrapper. Add a golden or a `tester.getRect(find.byType(VaultDock))` test on 2C asserting the dock's top is below the orb's bottom.
- **Confidence:** high (Flutter `RenderPositionedBox` + `_ScaffoldLayout` semantics; matches both screenshots).

### QA-026 [P2] 2C: bottom row hidden under the dock
- **File:** `app/lib/src/features/voice/presentation/pages/voice_home_page.dart:176-200` (trailing `Spacer()` then the "RECENTLY CAPTURED" / "Open library" row, no bottom spacing), `app/lib/src/core/widgets/app_screen.dart:92` (`extendBody: true`).
- **What:** with `extendBody`, the body runs under the bottom bar, and 2C's last row has no inset for it, so the dock covers "RECENTLY CAPTURED" and any recent items; "Open library" survives only because it is right-aligned past the dock's edge.
- **Seen:** 2026-09-10 SM G990E after the QA-025 fix (screenshot p_after25).
- **Fix:** end the body with `SizedBox(height: SnackHost.dockHeight + AppSpacing.screenBottom)` or use `MediaQuery.viewPadding`/the dock height as bottom padding; same treatment 3D already gets by placing the dock inside its Column.
- **Confidence:** high.

### QA-027 [P2] 3D: link memories are titled "Untitled"
- **File:** `app/lib/src/features/memory/domain/entities/memory.dart:67-76` (`displayTitle` checks title, description, text, then `source?.filename`), capture path writes `url` but no `title`.
- **What:** saving `example.com/qa-link-1` produced a row "Untitled / LINK / INDEXING". Until ingestion fills a title, the user cannot tell which link they saved.
- **Fix:** include the URL host (or full URL) in `displayTitle` for `MemoryType.link`, or have capture set `title` to the normalised URL.
- **Confidence:** confirmed live.

### QA-028 [P1] 3H: "Send code" 500s for real recipients (Resend sandbox)
- **File:** `firebase/functions/email_codes.py` `_deliver` (raises `RuntimeError` on Resend status 401/403); sender defaults to `onboarding@resend.dev` with no `EMAIL_FROM`.
- **What:** with a real `RESEND_API_KEY` set but no verified domain, the sandbox sender `onboarding@resend.dev` only delivers to the Resend account owner's own address. Every other recipient gets a 401/403 from Resend; `_deliver` now RAISES on that, which `request_email_code` surfaces as `INTERNAL`, and the app shows "Something went wrong." So email sign-in is dead for real users.
- **Repro:** `curl -X POST .../request_email_code -d '{"data":{"email":"karnav.p.018@gmail.com"}}'` → `HTTP 500 {"error":{"details":{"at":"deliver","kind":"RuntimeError"},"message":"Something went wrong sending your code. Try again.","status":"INTERNAL"}}`. A throwaway address returned 200 (queued by Resend). Reproduced in the app on the iPhone 17 Pro sim (screenshot sim4_send).
- **Two parts:**
  1. **Setup (user-owned):** verify a domain in Resend and set `EMAIL_FROM=Knowra <sign-in@yourdomain>`, then any recipient works. This is the real fix.
  2. **Behaviour (Flutter/backend):** a delivery failure hard-500s the request — it contradicts the earlier QA-022 decision that delivery failures are swallowed. Decide: keep raising (loud, but blocks all sign-in until a domain is verified) vs swallow + return `sent:true` (a lie) vs a dev bypass that logs the code when unverified. A 401 (bad key) and 403 (sender restriction) also want different handling.
- **Regression note:** earlier today (before a real key was set) `_deliver` printed the code to Cloud Logging and returned, so email sign-in worked; setting the key without a verified domain turned working sign-in into a 500.
- **Confidence:** confirmed live (HTTP 500, `at: deliver`).

### QA-029 [P1] 3I: verify_email_code 500s — custom token cannot be signed
- **Where:** `verify_email_code` → `firebase_admin.auth.create_custom_token`. Runtime SA `326925575468-compute@developer.gserviceaccount.com` (the default compute SA) has no `roles/iam.serviceAccountTokenCreator` on itself, so the Admin SDK's IAM `signBlob` call is denied.
- **Evidence:** `verify_email_code` stderr: `Unhandled error: Failed to sign custom token. Error calling the IAM signBlob API: {"code":403,"message":"Permission 'iam.serviceAccounts.signBlob' denied on resource ..."}`. Direct curl of verify with a valid fresh code → `HTTP 500 {"status":"INTERNAL"}`. In the app this maps to UnknownException → "Something went wrong."
- **Impact:** email sign-in cannot complete on ANY device. request_email_code works (no signing); verify always 500s. This blocks the entire authenticated surface.
- **Fix (owner-level IAM, one command):**
  `gcloud iam service-accounts add-iam-policy-binding 326925575468-compute@developer.gserviceaccount.com --member="serviceAccount:326925575468-compute@developer.gserviceaccount.com" --role="roles/iam.serviceAccountTokenCreator" --project knowra-506719`
  Tighter alternative: give the email functions a dedicated SA with only this role rather than granting it on the broad compute default SA. Propagation is ~1-2 min.
- **Secondary bug (Flutter/backend):** verify sets `consumedAt` BEFORE `create_custom_token`, so a signing failure still burns the user's code (a retry then reports "bad code"). Mint the token first, mark consumed only on success.
- **Confidence:** confirmed live (stderr traceback + 500).

### Note (resolved): 3J shown for karnav.p.018 with onboardedAt null
Not a bug. The user deleted that account's Firestore doc for a clean-run; `ensure_profile`/`seed()` recreates a deleted profile with `onboardedAt: null`, which correctly reads as a new account. Would only be a finding on an account whose doc was never deleted.

### QA-030 [P2] 2C: dictation left live on submit → double answer + wasted question
- **File:** `app/lib/src/features/voice/presentation/pages/voice_home_page.dart` `_ask` (did not stop dictation before submit); recogniser `done` handler; `voice_cubit.dart` hand-off signal.
- **What:** tapping the field and typing does not stop the orb's dictation. Submitting the typed text called `submitted()` while the recogniser was still listening; its eventual `done` set the hand-off signal and 2C's listener (still mounted under the answer screen) pushed a SECOND AnswerPage for the half-spoken phrase the user had abandoned — and it spent a question from the daily allowance for a question nobody asked.
- **Origin:** surfaced from the QA LO-4 aside ("_ask doesn't stopDictation"); the Flutter session found the double-submit behind the stale-level symptom.
- **Fix (verified in code + tests):** `_ask` is now async and `await cubit.stopDictation()` before `submitted()`, with a `context.mounted` check after the await. `test/features/voice/dictation_test.dart` asserts the recogniser is actually stopped (fake.stops == 1) and level clears.
- **Confidence:** fix confirmed by inspection + passing tests; on-device re-check folded into the checklist.

---

## Verified correct (no action)

- Callable names and payload keys match on both sides for `request_email_code`, `verify_email_code`, `ensure_profile`, `list_connectors`, `begin_connection`, `complete_connection`, `set_scope_level`, `list_provider_folders`, `set_indexed_folders`, `disconnect_account`, `complete_storage_setup`.
- `set_indexed_folders` creates the `indexJobs` document before returning, so the 3L listener never hits a missing document.
- Sync worker writes memory `type` as `document` / `photo` / `audio`, matching the 3D filter chips; `status` starts at `uploaded`.
- Firestore rules allow every client read/write the app performs; the `users` update rule matches the exact key set `completeOnboarding` writes.
- Composite indexes exist for both Library queries (`userId+createdAt`, `userId+type+createdAt`).
- Router guard: pure `guardFor` covered by tests; onboarding resumes at the first outstanding step.
- iOS `Info.plist` and `AndroidManifest.xml` both register `com.knowra.knowra` for the OAuth callback; the reversed Google client id is registered on iOS.
- `dev.json` / `prod.json` carry `GOOGLE_SERVER_CLIENT_ID`; Sentry DSN empty (logs local only) as documented.
- Code field: digits only, capped at 6, auto-submit, controller resyncs after a wrong code.
- Email validator, typo suggestion, name validator behave as the tests describe.
