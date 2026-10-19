import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_mark.dart';
import 'package:knowra/src/features/splash/presentation/pages/splash_page.dart';

const _screen = Size(402, 874);

Future<void> _pumpSplash(
  WidgetTester tester, {
  VoidCallback? onComplete,
  Future<void>? readyWhen,
  Duration maxWait = const Duration(seconds: 6),
}) async {
  tester.view
    ..physicalSize = _screen
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: SplashPage(
        onComplete: onComplete,
        readyWhen: readyWhen,
        maxWait: maxWait,
      ),
    ),
  );

  // A ticker's first frame only records its start time — it does not advance
  // the animation. Without this priming pump, a single `pump(duration)` leaves
  // the controller at 0 and nothing ever completes.
  await tester.pump();
}

/// Play the bar to the end and flush the continuations behind it.
Future<void> _playToEnd(WidgetTester tester) async {
  await tester.pump(SplashPage.duration ~/ 2);
  await tester.pump(SplashPage.duration);
  await tester.pump();
}

void main() {
  group('composition', () {
    testWidgets('draws the mark, the name and the line', (tester) async {
      await _pumpSplash(tester);

      expect(find.byType(HawkMark), findsOneWidget);
      expect(find.text('Hawk'), findsOneWidget);
      expect(find.text('Your second memory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bar reports real progress, not a fixed animation', (
      tester,
    ) async {
      await _pumpSplash(tester);

      double value() => tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;

      expect(value(), lessThan(0.2));
      await tester.pump(SplashPage.duration ~/ 2);
      final midway = value();
      expect(midway, greaterThan(0.2));

      await tester.pump(SplashPage.duration ~/ 2);
      expect(value(), greaterThan(midway));
    });
  });

  group('hand-off', () {
    testWidgets('does not fire mid-animation', (tester) async {
      var completed = 0;
      await _pumpSplash(tester, onComplete: () => completed++);

      await tester.pump(SplashPage.duration * 0.9);
      expect(completed, 0);

      await _playToEnd(tester);
      expect(completed, 1);
    });

    testWidgets('waits for start-up work that outlasts the animation', (
      tester,
    ) async {
      final ready = Completer<void>();
      var completed = 0;

      await _pumpSplash(
        tester,
        onComplete: () => completed++,
        readyWhen: ready.future,
      );

      await _playToEnd(tester);
      expect(completed, 0, reason: 'start-up work is still running');

      ready.complete();
      await tester.pump();
      await tester.pump();
      expect(completed, 1);
    });

    testWidgets('a hung dependency cannot strand the user', (tester) async {
      var completed = 0;
      await _pumpSplash(
        tester,
        onComplete: () => completed++,
        readyWhen: Completer<void>().future, // never resolves
        // Comfortably longer than the bar, so this asserts the *ceiling*
        // releasing the user rather than the animation happening to outlast
        // it.
        maxWait: const Duration(seconds: 4),
      );

      await _playToEnd(tester);
      expect(completed, 0, reason: 'still inside maxWait');

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(completed, 1, reason: 'maxWait must release the user');
    });

    testWidgets('a failed warm-up still hands off', (tester) async {
      var completed = 0;
      await _pumpSplash(
        tester,
        onComplete: () => completed++,
        // Fails *after* the page has adopted it, which is how a real session
        // check fails. Constructing an already-failed future here would blow
        // up in the test's own zone before the widget existed.
        readyWhen: Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => throw StateError('session check failed'),
        ),
      );

      await _playToEnd(tester);
      expect(completed, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never hands off twice', (tester) async {
      var completed = 0;
      await _pumpSplash(tester, onComplete: () => completed++);

      await _playToEnd(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(completed, 1);
    });
  });

  group('accessibility', () {
    testWidgets('reduce motion skips the bar entirely', (tester) async {
      // The one animation a user cannot avoid by looking away, so the setting
      // has to actually switch it off rather than shorten it.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      var completed = 0;
      await _pumpSplash(tester, onComplete: () => completed++);
      await tester.pump();

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1.0,
      );

      await tester.pump();
      expect(completed, 1, reason: 'nothing left to wait for');
    });

    testWidgets('the app introduces itself once', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpSplash(tester);
      await _playToEnd(tester);

      expect(
        find.bySemanticsLabel('Hawk. Your second memory.'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
