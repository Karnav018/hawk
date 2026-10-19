# Knowra — Flutter app

## Stack

| Concern            | Choice                              |
| ------------------ | ----------------------------------- |
| State management   | BLoC (`bloc` / `flutter_bloc`)      |
| Dependency injection | `get_it` + `injectable` (codegen) |
| Backend            | Firebase (Auth, Firestore, Functions, Storage) |
| Models / unions    | `freezed` + `json_serializable`     |
| Crash + logs       | `sentry_flutter`                    |
| Routing            | `go_router`                         |
| Provider OAuth     | `flutter_web_auth_2` (PKCE, exchanged server-side) |
| Caching            | Firestore offline persistence + a TTL store for callables |

## Run

Configuration is compile-time, never read from a bundled file at runtime:

```bash
flutter run --dart-define-from-file=config/dev.json
flutter build apk --release --dart-define-from-file=config/prod.json
flutter build ipa --release --dart-define-from-file=config/prod.json
```

Set `SENTRY_DSN` in `config/prod.json` (or pass `--dart-define=SENTRY_DSN=...`
from CI). With an empty DSN, Sentry stays uninitialised and errors are only
logged locally — nothing crashes.

## Code generation

Any change to a `@freezed`, `@injectable`, `@module` or `@JsonSerializable`
annotation needs a regen:

```bash
dart run build_runner build      # once
dart run build_runner watch      # while developing
```

## Layout

```
lib/
  main.dart              entry point → bootstrap()
  bootstrap.dart         composition root: DI, Sentry, BlocObserver, runApp
  src/
    app/                 shell: MaterialApp, router, theme, BlocObserver
    core/                cross-cutting: config, di, network, error, logging, storage
    features/<name>/
      data/              DTOs, data sources, repository implementations
      domain/            entities, repository contracts, use cases
      presentation/      BLoC, pages, widgets
```

`features/memory` is the reference vertical slice, wired end to end against
Firestore (query → DTO → repository → use case → BLoC → page). Copy its shape
for the remaining features.

The repository boundary is what made the FastAPI → Firebase move cheap: only
the seven files under `*/data/firebase/` know Firebase exists. Domain,
presentation and the router were untouched, and their tests never changed.

## Design system

The design lives in `../design/mobile-application-design-planning/` (a Claude
Design HTML handoff for **Vault** — 13 dark screens, 3 light). Its tokens are
ported, not approximated:

| File | Holds |
| --- | --- |
| `src/app/theme/app_palette.dart` | Semantic colours as a `ThemeExtension`; identical names in both themes |
| `src/app/theme/app_typography.dart` | The three type roles — Instrument Serif for questions/headlines, Archivo for interface copy and tracked-caps labels, Martian Mono strictly for numerals |
| `src/app/theme/app_spacing.dart` | The single 4px scale, radii and control heights |
| `src/app/theme/app_theme.dart` | Assembles `ThemeData` from those tokens |

Reach for tokens through `context.palette`, never a raw `Color`.

Shared primitives live in `src/core/widgets/`: `AppScreen` (screen chrome plus a
pinned `footer` slot), `AmbientBackground` (the blurred emission wash),
`GlassPanel`, `TrackedLabel` / `Numeral`, `HeaderIconButton`, and `AppIcon`
(the design's own SVG paths).

Fonts are bundled under `assets/fonts/` rather than fetched at runtime. Archivo
and Martian Mono are variable fonts, so weight is applied with `FontVariation`
alongside `fontWeight`.

### Brand

The mark is the product's own voice orb (`Knowra Logo.dc.html`, direction 1A).

Its material is a **path-traced render of `assets/voice_orb.glb`** — a glass
shell (`KHR_materials_transmission` + IOR) around an emissive plasma core —
baked offline to `assets/images/orb_sphere.png`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tool/render_orb.py -- --frames 1 --size 1024 --samples 320
```

Baking rather than rendering at run time is deliberate. Real refraction needs a
path tracer, and the Flutter-side options are a WebView running
`<model-viewer>` (heavy, slow to first paint, unusable on a splash) or
`flutter_scene` (no transmission support — the glass would render wrong).
Baking gives exact fidelity at zero runtime cost on every device. The trade-off
is a fixed viewing angle; `--frames N` renders a turntable if a screen needs
the orb to move.

The render is cropped to the sphere's exact bounds so the circular clip hugs
the silhouette and a full-bleed draw shows no transparent edge.

It exists once, as a widget:

| Piece | Where |
| --- | --- |
| `KnowraOrb` | `core/widgets/knowra_orb.dart` — the mark, sized by one parameter |
| `KnowraLockup` | orb + wordmark, for headers |
| `AppIconArtwork` | the launcher icon, composed from the same orb |
| `SplashPage` | the launch animation |

Launcher icons and the splash are **rendered from that widget**, not exported
by hand, so the icon on the home screen and the orb inside the app cannot
drift:

```bash
flutter test test/tools/generate_app_icons.dart   # widget -> assets/branding/*.png
dart run flutter_launcher_icons                   # -> iOS + Android sizes
dart run flutter_native_splash:create             # -> the pre-Flutter ground
```

The native splash is ground colour only. `SplashPage`'s first frame is the same
`#070B16`, and the emission fades up from it, so the handoff is invisible —
a static image there would jump the moment Flutter took over.

`SplashPage` is a two-layer cross-fade, not a morph: the full-bleed emission
dissolves while the circular mark resolves dead centre in its place, so the
transition never passes through an in-between shape. It also:

- respects the OS reduce-motion setting (lands on the final frame, hands off);
- accepts `readyWhen`, so session checks overlap the brand moment instead of
  becoming a spinner after it;
- caps that wait with `maxWait`, so a hung dependency cannot strand the user;
- adopts `readyWhen` in `initState` rather than at the point it is awaited —
  a future that fails in between would otherwise be an unhandled async error
  that takes the app down during its own launch animation.

### Goldens

`test/features/auth/sign_in_golden_test.dart` renders a screen at the design's
402×874 frame in both themes. Regenerate after an intentional visual change:

```bash
flutter test --update-goldens
```

Golden tests must call `loadAppFonts()` and `precacheAppImages(tester)` from
`test/support/` — without them the capture uses a fallback font and blank
images. Goldens are host-rendered; expect diffs across machines.

### Screens

Built: `3E SIGN IN`, `3D LIBRARY`. Remaining from the handoff: email address,
verify code, your name, connect storage (BYOS), permissions, choose what to
index, first index progress, ready/first ask, home (voice orb), answer,
capture.

## Product

This is the client for the Personal Knowledge Vault described in
`personal_knowledge_vault_complete_architecture.md`: capture anything, ask for
it later in your own words, and let the storage engine reason about what is
still worth keeping.

There is no endpoint table to mirror any more: the client reads Firestore
directly under `firebase/firestore.rules` and calls Cloud Functions only where
a client cannot be trusted with the work. Feature packages map onto §56:

| Feature | State |
| --- | --- |
| `auth` | Complete: Apple, Google and email-code sign-in, onboarding, session guard |
| `memory` | Full slice: list, paging, filters, type marks, Library screen |
| `connectors` | Screens 3F–3L: BYOS connect, permissions, folder scope, first index |
| `voice` | Screen 2C — the home screen. Orb state machine, typed ask path |
| `chat` | Screen 3B — answer with inline citations, confidence, sources |
| `capture` | Screen 3C — six tiles; link and note work end to end |
| `search` | Not started — hybrid retrieval UI (blocked on §25) |
| `storage_manager` | Not started — dashboard, review & delete |
| `settings` | Not started |

## Sign-in

Three ways in — Apple, Google, and a six-digit email code — all landing on the
same session.

```
 3E sign in ─┬─ Apple  ─┐
             ├─ Google ─┤ id token ──► signInWithCredential ─┐
             │          │                                    │
             └─ email ──► 3H address ──► 3I code ────────────┤
                          requestEmailCode / verifyEmailCode │
                          (callable mints a custom token)    │
                                                             ▼
                                                  FirebaseAuthRepository
                                                  (the only session authority)
                                                             │ status stream
                                          ┌──────────────────┴──────────────┐
                                          ▼                                 ▼
                                    router guard                      SessionCubit
                                    (where you may be)                (UI reads it)
```

Rules that hold:

- **Screens never navigate on sign-in.** They change the session; the guard
  moves them. A screen that routed itself would be a second opinion about which
  half of the app you are in.
- **One session authority.** `AuthRepository.status` is the only source. It
  combines two streams — `FirebaseAuth.authStateChanges` and a *snapshot
  listener* on the user document — so a profile written by the blocking
  `beforeUserCreated` function, or an onboarding flag flipped anywhere, reaches
  the guard without a refetch.
- **The user document decides onboarding**, not a flag on the credential.
- **Tokens are the SDK's problem.** There is no interceptor, no refresh queue
  and no secure store: `firebase_auth` refreshes silently and hands every
  Firestore and callable request its own token. That whole layer was deleted
  rather than ported.
- **Offline is not signed out.** Firebase keeps the session across a failed
  network restore, and the guard only reacts to an actual sign-out.
- **Platform support and configuration are different questions.** A provider
  the device cannot do is hidden; one this build has no credentials for is
  shown *dimmed*, and says what is missing when tapped. Hiding it would make a
  misconfigured release look intentional.

Credentials setup — Apple Developer, the Google clients, the Android SHA-1 and
the iOS reversed-client-ID URL scheme — is in
[`../docs/FIREBASE_SETUP.md`](../docs/FIREBASE_SETUP.md).

## Conventions

- Nothing above the data layer imports `firebase_*`. Repositories map provider
  error codes into a sealed `AppException`, so BLoCs and widgets `switch` over
  one known set of cases and the provider stays swappable — which is what kept
  the move off the old REST backend to a seven-file change.
- Log through `AppLogger`, never `Sentry` directly — the transport is swappable
  and no-ops cleanly in tests.
- BLoC events and states are sealed freezed unions; state handling in the UI is
  an exhaustive `switch`, so a new state is a compile error until it is handled.

## Test

```bash
flutter test
```
