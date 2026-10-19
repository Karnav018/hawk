import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/widgets/voice_orb.dart';

/// QA-024. The orb took the whole home screen down on first build.
///
/// `AnimationController(vsync: this)..repeat()` was cascaded in `initState`,
/// so `repeat()` ran before `_retime()` had set a duration — and `repeat()`
/// with neither a period nor a controller duration asserts. Every phase was
/// affected, so the home screen was a red error box for everyone.
///
/// The existing voice tests only exercised the state machine, which is pure
/// and was fine. Nothing built the widget with a real ticker, which is the
/// only way this surfaces.
///
/// Note: these `pump` a fixed duration rather than `pumpAndSettle`. The
/// controllers repeat forever, so `pumpAndSettle` would spin until it times
/// out — a settling animation is exactly what this widget does not have.
void main() {
  Widget host(VoicePhase phase) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(child: VoiceOrb(phase: phase, size: 120)),
    ),
  );

  for (final phase in VoicePhase.values) {
    testWidgets('builds and animates in ${phase.name}', (tester) async {
      await tester.pumpWidget(host(phase));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('survives a phase change mid-cycle', (tester) async {
    // `didUpdateWidget` retimes both controllers. Resetting a running
    // controller and repeating it again is where an ordering mistake would
    // resurface.
    await tester.pumpWidget(host(VoicePhase.ready));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.pumpWidget(host(VoicePhase.retrieving));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(VoicePhase.answered));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its controllers cleanly', (tester) async {
    await tester.pumpWidget(host(VoicePhase.listening));
    await tester.pump(const Duration(milliseconds: 80));
    // A controller still ticking at teardown throws on dispose.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bars build in both states', (tester) async {
    for (final active in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: VoiceBars(active: active, level: 0.5)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: 'active=$active');
    }
  });

  testWidgets('the orb is reachable to a screen reader', (tester) async {
    await tester.pumpWidget(host(VoicePhase.ready));
    // The orb is the primary control on the home screen; if it carries no
    // label it is an unlabelled tap target on the app's main screen.
    expect(find.bySemanticsLabel(RegExp('Ask Hawk')), findsOneWidget);
  });

  _continuity();
}

/// QA-025's follow-up. `_retime()` used to `reset()` both controllers, so
/// every phase change snapped the orb back to the start of its cycle — while
/// the comment above it claimed the opposite. Phase is now accumulated, so a
/// period change alters the rate and never the position.
void _continuity() {
  testWidgets('a phase change does not snap the animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(child: VoiceOrb(phase: VoicePhase.ready, size: 120)),
        ),
      ),
    );

    // Let it travel away from zero.
    await tester.pump(const Duration(milliseconds: 500));
    final before = _ringAngle(tester);
    expect(before, greaterThan(0), reason: 'the ring should have moved');

    // Change phase — this is the moment that used to reset.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: VoiceOrb(phase: VoicePhase.retrieving, size: 120),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final after = _ringAngle(tester);

    // It must have continued, not restarted. A reset would put it back near
    // zero; continuing leaves it at least where it was.
    expect(
      after,
      greaterThanOrEqualTo(before),
      reason: 'ring went from $before to $after — that is a snap',
    );
  });
}

/// The ring's current rotation, read out of the Transform in the tree.
double _ringAngle(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(find.byType(Transform));
  var best = 0.0;
  for (final t in transforms) {
    // Rotation about z shows up in the top-left 2x2 of the matrix.
    final m = t.transform;
    final angle = math.atan2(m.storage[1], m.storage[0]);
    best = math.max(best, angle.abs());
  }
  return best;
}
