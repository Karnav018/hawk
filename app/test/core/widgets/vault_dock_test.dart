import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/vault_dock.dart';
import 'package:knowra/src/features/capture/presentation/pages/capture_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/connect_storage_page.dart';
import 'package:knowra/src/features/memory/presentation/pages/library_page.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/pages/voice_home_page.dart';
import 'package:knowra/src/features/voice/presentation/widgets/voice_orb.dart';

/// The dock: layout, and where its buttons actually go.
///
/// Two bugs are pinned here. The layout one: its root was a `Center`, which
/// expands on BOTH axes under loose constraints — invisible inside the
/// library's `Column`, but as a `Scaffold.bottomNavigationBar` it was handed
/// the full screen height to centre within, so the pill floated mid-screen
/// with the mic on top of the orb.
///
/// The routing one: every screen passed its own three callbacks, and they
/// disagreed. The same microphone started dictation on home and navigated
/// home from the library, and tapping a button for the screen you were
/// already on pushed a second copy of it.
void main() {
  /// A router with the four locations the dock knows about.
  ///
  /// Each screen is just the dock plus a label, so a test can read where it
  /// ended up from the widget tree rather than from the router's internals.
  ({GoRouter router, Widget app}) host({
    String at = '/',
    VoidCallback? onVoice,
    bool listening = false,
    Widget body = const SizedBox.expand(),
  }) {
    Widget screen(String name, {VoidCallback? voice}) => Scaffold(
      extendBody: true,
      bottomNavigationBar: VaultDock(onVoice: voice, isListening: listening),
      body: Stack(
        children: [
          body,
          Center(child: Text('screen:$name')),
        ],
      ),
    );

    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Column(
            children: [
              Expanded(child: screen('home', voice: onVoice)),
              // Proves what arrived with the navigation, not just that it
              // happened: the mic must ask home to start listening.
              Text('extra:${state.extra is StartDictation}'),
            ],
          ),
        ),
        GoRoute(path: '/capture', builder: (_, _) => screen('capture')),
        GoRoute(path: '/storage', builder: (_, _) => screen('storage')),
        GoRoute(path: '/library', builder: (_, _) => screen('library')),
      ],
    );

    return (
      router: router,
      app: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
  }

  /// Where the user actually is.
  ///
  /// Not `currentConfiguration.uri`, which was the obvious choice and is
  /// wrong: an imperative `push` appends an `ImperativeRouteMatch` and
  /// leaves the top-level `uri` on the route that was pushed *from*. So a
  /// working push reads as "still on /" if you ask the uri. The last match
  /// is the screen on screen.
  String where(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  group('layout', () {
    testWidgets('sizes to its content as a bottom bar, not to the screen', (
      tester,
    ) async {
      await tester.pumpWidget(host().app);

      final size = tester.getSize(find.byType(VaultDock));
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;

      // The buttons are 60 tall plus 8 of padding each side; anything near
      // the screen height means it expanded.
      expect(size.height, lessThan(120), reason: 'dock height $size');
      expect(size.height, lessThan(screen / 3));
    });

    testWidgets('sits at the bottom, not the middle', (tester) async {
      await tester.pumpWidget(host().app);

      final rect = tester.getRect(find.byType(VaultDock));
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        rect.top,
        greaterThan(screen * 0.6),
        reason: 'dock top ${rect.top} of $screen — it is not near the bottom',
      );
    });

    testWidgets('centres the pill horizontally', (tester) async {
      await tester.pumpWidget(host().app);

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final pill = tester.getRect(find.byType(ClipRRect).last);
      expect(
        (pill.center.dx - width / 2).abs(),
        lessThan(2),
        reason: 'pill centre ${pill.center.dx} vs screen centre ${width / 2}',
      );
    });

    testWidgets('does not overlap the orb it shares the screen with', (
      tester,
    ) async {
      // The actual harm of the layout bug: with the dock screen-tall, the
      // mic button sat on top of the orb and swallowed its taps.
      await tester.pumpWidget(
        host(
          body: const Center(
            child: VoiceOrb(phase: VoicePhase.ready, size: 168),
          ),
        ).app,
      );
      await tester.pump(const Duration(milliseconds: 60));

      final orb = tester.getRect(find.byType(VoiceOrb));
      final pill = tester.getRect(find.byType(ClipRRect).last);
      expect(
        pill.top,
        greaterThan(orb.bottom),
        reason:
            'dock pill at ${pill.top} overlaps the orb ending at '
            '${orb.bottom}',
      );
    });
  });

  group('routing', () {
    testWidgets('capture and storage go to their screens', (tester) async {
      final h = host();
      await tester.pumpWidget(h.app);

      await tap(tester, 'Capture');
      expect(where(h.router), '/capture');
    });

    testWidgets('storage is reachable from home', (tester) async {
      final h = host();
      await tester.pumpWidget(h.app);

      await tap(tester, 'Storage');
      expect(where(h.router), '/storage');
    });

    testWidgets('home overrides the microphone instead of navigating', (
      tester,
    ) async {
      var dictated = 0;
      final h = host(onVoice: () => dictated++);
      await tester.pumpWidget(h.app);

      await tap(tester, 'Ask with voice');

      // Home *is* the voice screen, so the mic listens rather than moving.
      expect(dictated, 1);
      expect(where(h.router), '/');
    });

    testWidgets('the microphone elsewhere goes home and asks it to listen', (
      tester,
    ) async {
      final h = host(at: '/library');
      await tester.pumpWidget(h.app);
      expect(where(h.router), '/library');

      await tap(tester, 'Ask with voice');

      // Both halves matter. Landing on home is not enough — the icon says
      // microphone, so the user must not have to tap a second one.
      expect(where(h.router), '/');
      expect(find.text('extra:true'), findsOneWidget);
    });

    testWidgets('the button for the current screen does nothing', (
      tester,
    ) async {
      final h = host(at: '/capture');
      await tester.pumpWidget(h.app);

      await tap(tester, 'Capture');

      // `push` would have stacked a second capture screen on the first, and
      // the back button would then appear to do nothing.
      expect(where(h.router), '/capture');
      expect(find.text('screen:capture'), findsOneWidget);
    });

    /// The fill of each dock button, left to right.
    List<Color?> fills(WidgetTester tester) => tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(VaultDock),
            matching: find.byType(Material),
          ),
        )
        .map((m) => m.color)
        .toList();

    testWidgets('exactly one button is accent, and it is the current screen', (
      tester,
    ) async {
      // The design's selected state. Every dock in the handoff has one
      // accent button and it moves with the screen — this used to paint
      // storage accent everywhere, so storage always looked current.
      final accent = AppTheme.dark.extension<AppPalette>()!.accent;
      final white = AppTheme.dark.extension<AppPalette>()!.textPrimary;

      for (final (location, index) in [
        ('/capture', 0),
        ('/', 1),
        ('/storage', 2),
      ]) {
        await tester.pumpWidget(host(at: location).app);
        final painted = fills(tester);
        expect(painted, hasLength(3), reason: location);
        for (var i = 0; i < 3; i++) {
          expect(
            painted[i],
            i == index ? accent : white,
            reason: '$location button $i',
          );
        }
      }
    });

    testWidgets('the microphone takes the listening blue', (tester) async {
      // `v2MicBg: v.bars ? '#2f5fe0' : '#ffffff'` — a deeper blue than the
      // selected accent, so "listening" does not read as "you are here".
      await tester.pumpWidget(host(at: '/', listening: true).app);

      expect(fills(tester)[1], const Color(0xFF2F5FE0));
    });

    testWidgets('the microphone stays tappable on its own screen', (
      tester,
    ) async {
      // Unlike the other two, its job on home is to listen, not to move.
      var dictated = 0;
      await tester.pumpWidget(host(onVoice: () => dictated++).app);

      await tap(tester, 'Ask with voice');
      expect(dictated, 1);
    });

    testWidgets('leaving home replaces it rather than stacking', (
      tester,
    ) async {
      final h = host(at: '/library');
      await tester.pumpWidget(h.app);

      await tap(tester, 'Ask with voice');

      // `go`, not `push`: pushing home on top of the library would leave a
      // back button that goes *into* a list from the screen it belongs to.
      expect(h.router.routerDelegate.currentConfiguration.matches.length, 1);
    });
  });

  // The dock spells its destinations out as string literals because it lives
  // in `core/` and the screens live in `features/` — importing them would
  // point a shared widget at four feature packages. The cost of that choice
  // is that a renamed route path would silently stop matching, dimming the
  // wrong button or pushing a duplicate screen. This is the guard.
  group('paths agree with the screens they name', () {
    test('the dock leads where those screens actually live', () {
      expect(VoiceHomePage.routePath, '/');
      expect(CapturePage.routePath, '/capture');
      expect(ConnectStoragePage.manageRoutePath, '/storage');
      expect(LibraryPage.routePath, '/library');
    });
  });
}
