import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_orb.dart';
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/widgets/voice_orb.dart';

/// The LISTENING transform — design/blender/HANDOFF_listening_orb.md.
///
/// Acceptance items LO-1..6 are mostly on-device judgements (does it look
/// right, does it hold 60fps). What is testable here is the structure those
/// judgements depend on: that the squash is outside the rotation, that the
/// resting phases are untransformed, that the strip frames exist and are
/// registered, and that the level normaliser is right on both platforms —
/// the last being the one bug that looked identical to working code on the
/// only device we have.
void main() {
  Widget host(VoicePhase phase, {double level = 0, bool hasMatches = false}) =>
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: VoiceOrb(
              phase: phase,
              size: 168,
              level: level,
              hasMatches: hasMatches,
            ),
          ),
        ),
      );

  /// Advance the clock the way a device does: one frame at a time.
  ///
  /// A single `pump(Duration(milliseconds: 200))` delivers *one* frame with a
  /// 200ms delta, and the ticker clamps `dt` to 1/30s so that a resume from
  /// the background cannot fling the animation forward. The smoothing
  /// therefore advances one 33ms step and the level lands well short of its
  /// target — a property of the test, not of the orb.
  Future<void> frames(WidgetTester tester, int milliseconds) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The squash transform: the outermost scale wrapping the orb's stack.
  Matrix4? squash(WidgetTester tester) {
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(VoiceOrb),
        matching: find.byType(Transform),
      ),
    );
    return transforms.isEmpty ? null : transforms.first.transform;
  }

  group('level normaliser (LO-6)', () {
    test('Android divides the -2..10 range', () {
      expect(
        normaliseLevel(10, platform: TargetPlatform.android),
        closeTo(1.0, 0.001),
      );
      expect(
        normaliseLevel(5, platform: TargetPlatform.android),
        closeTo(0.5, 0.001),
      );
      // Below the nominal floor is still silence, not a negative squash.
      expect(normaliseLevel(-2, platform: TargetPlatform.android), 0);
    });

    test('iOS passes 0..1 through', () {
      // The bug: /10 on a 0..1 input capped the orb at level 0.1, so it
      // barely moved however loudly anyone spoke.
      expect(normaliseLevel(1, platform: TargetPlatform.iOS), 1.0);
      expect(
        normaliseLevel(0.7, platform: TargetPlatform.iOS),
        closeTo(0.7, 0.001),
      );
      expect(
        normaliseLevel(0.6, platform: TargetPlatform.iOS),
        greaterThan(0.5),
        reason: 'LO-6: normal speech must pass 0.5 on iOS',
      );
    });

    test('never leaves 0..1 on either platform', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final raw in [-100.0, -2.0, 0.0, 0.5, 10.0, 999.0]) {
          final value = normaliseLevel(raw, platform: platform);
          expect(value, inInclusiveRange(0.0, 1.0), reason: '$platform $raw');
        }
      }
    });
  });

  group('assets', () {
    testWidgets('all five strip frames load', (tester) async {
      // A directory entry in pubspec does not cover subdirectories, so
      // `assets/images/` alone would ship none of these and the orb would
      // render an error box mid-utterance.
      for (var i = 0; i < OrbListening.frames; i++) {
        final data = await tester.runAsync(
          () => rootBundle.load(OrbListening.frame(i)),
        );
        expect(data, isNotNull, reason: OrbListening.frame(i));
        expect(data!.lengthInBytes, greaterThan(1000));
      }
    });
  });

  group('resting phases are untransformed (LO-4)', () {
    for (final phase in [
      VoicePhase.ready,
      VoicePhase.retrieving,
      VoicePhase.answered,
    ]) {
      testWidgets('$phase renders at 1:1 and shows the resting sphere', (
        tester,
      ) async {
        await tester.pumpWidget(host(phase));
        await tester.pump(const Duration(milliseconds: 400));

        // The cubit zeroes the level outside listening, so the squash must
        // resolve to identity — anything else means the resting phases moved.
        final matrix = squash(tester);
        expect(matrix, isNotNull);
        expect(matrix!.getMaxScaleOnAxis(), closeTo(1.0, 0.0001));

        expect(find.byType(HawkOrb), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      });
    }
  });

  group('the design\'s four motion layers', () {
    // The design runs four animations at once on the orb: `swirl`
    // (clockwise), `swirl2` (anticlockwise, its own period), `pulseRing`
    // (expand and fade), and `breathe`. The app had two of them, so the orb
    // moved but did not move like the design.
    test('every phase declares all four periods, and they differ', () {
      for (final phase in VoicePhase.values) {
        expect(phase.swirlSeconds, greaterThan(0), reason: '$phase swirl');
        expect(phase.glowSpinSeconds, greaterThan(0), reason: '$phase glow');
        expect(phase.ringSeconds, greaterThan(0), reason: '$phase ring');
        expect(phase.breatheSeconds, greaterThan(0), reason: '$phase breathe');

        // The counter-rotation is only worth its cost if it never comes back
        // into phase with the swirl. Equal periods would make the two layers
        // one rigid object.
        expect(
          phase.glowSpinSeconds,
          isNot(phase.swirlSeconds),
          reason: '$phase: the two swirls must not share a period',
        );
      }
    });

    test('faster phases move every layer faster', () {
      // A phase that hurried the swirl but not the ring would read as the
      // orb disagreeing with itself about how urgent it is.
      expect(
        VoicePhase.retrieving.swirlSeconds,
        lessThan(VoicePhase.ready.swirlSeconds),
      );
      expect(
        VoicePhase.retrieving.glowSpinSeconds,
        lessThan(VoicePhase.ready.glowSpinSeconds),
      );
      expect(
        VoicePhase.retrieving.ringSeconds,
        lessThan(VoicePhase.ready.ringSeconds),
      );
    });

    /// How many ring outlines are drawn right now.
    int rings(WidgetTester tester) =>
        tester.widgetList<Container>(find.byType(Container)).where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.border != null;
        }).length;

    testWidgets('no ring without matches', (tester) async {
      // `<sc-if value="{{ v2HasMatches }}">`: the ring reports a find. An
      // orb pulsing before anything was found would be claiming a result.
      await tester.pumpWidget(host(VoicePhase.retrieving));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(rings(tester), 0, reason: 'a ring appeared with no matches');
      }
    });

    testWidgets('the pulse ring appears and clears within one period', (
      tester,
    ) async {
      await tester.pumpWidget(host(VoicePhase.retrieving, hasMatches: true));

      // `pulseRing` holds at zero for the last 30% of its period, which is
      // what makes it a pulse rather than a permanent halo. So across one
      // period there must be frames with the ring and frames without.
      var withRing = 0;
      var withoutRing = 0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        if (rings(tester) > 0) {
          withRing++;
        } else {
          withoutRing++;
        }
      }
      expect(withRing, greaterThan(0), reason: 'the ring never appeared');
      expect(
        withoutRing,
        greaterThan(0),
        reason: 'the ring never cleared — it is a halo, not a pulse',
      );
    });

    testWidgets('the inside of the sphere moves', (tester) async {
      // The complaint this layer answers: "the orb is not moving". The
      // sphere is a static render, and everything that animated sat around
      // it — so the ball itself stood still. The swirl must be *inside* the
      // clip, and its transform must change between frames.
      await tester.pumpWidget(host(VoicePhase.listening));
      await tester.pump(const Duration(milliseconds: 16));

      Matrix4 inner() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(ClipOval),
              matching: find.byType(Transform),
            ),
          )
          .first
          .transform;

      final before = inner().clone();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        inner(),
        isNot(equals(before)),
        reason: 'nothing inside the sphere changed across half a second',
      );
    });

    testWidgets('the sphere breathes, not just its glow', (tester) async {
      await tester.pumpWidget(host(VoicePhase.retrieving));

      // The resting sphere specifically. There are other circles in the
      // orb now — the glow is clipped round too, under a 1.6x scale — so a
      // bare `find.byType(ClipOval)` would measure the glow's scale and
      // report the sphere as growing 60%.
      final sphere = find.byType(HawkOrb);

      final scales = <double>{};
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        final t = tester
            .widgetList<Transform>(
              find.ancestor(of: sphere, matching: find.byType(Transform)),
            )
            .map((t) => t.transform.getMaxScaleOnAxis())
            .where((v) => v > 1.0001);
        scales.addAll(t.map((v) => (v * 1000).round() / 1000));
      }
      expect(scales, isNotEmpty, reason: 'the sphere never grew');
      expect(
        scales.reduce(math.max),
        lessThanOrEqualTo(1 + OrbListening.breatheScale + 0.001),
        reason: 'breathe is scale(1) -> scale(1.05), no further',
      );
    });

    testWidgets('the rotating glow is round, not a square', (tester) async {
      // A blurred image drawn into a square box and rotated shows its
      // corners sweeping round behind the orb. It must be clipped to a
      // circle, and the clip must sit inside the blur so the edge is soft.
      await tester.pumpWidget(host(VoicePhase.retrieving));
      await tester.pump(const Duration(milliseconds: 16));

      final glow = find.byWidgetPredicate((w) => w is ImageFiltered);
      expect(glow, findsWidgets);
      expect(
        find.descendant(of: glow.first, matching: find.byType(ClipOval)),
        findsOneWidget,
        reason: 'the glow is not clipped round inside its blur',
      );
    });

    testWidgets('the glow counter-rotates', (tester) async {
      await tester.pumpWidget(host(VoicePhase.retrieving));
      await tester.pump(const Duration(milliseconds: 16));

      // Two rotations in the tree turning opposite ways: the arc clockwise,
      // the glow anticlockwise.
      final angles = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(VoiceOrb),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.getRow(0)[1])
          .where((v) => v.abs() > 1e-9)
          .toList();

      expect(
        angles.any((v) => v > 0) && angles.any((v) => v < 0),
        isTrue,
        reason: 'expected opposing rotations, got $angles',
      );
    });
  });

  group('listening (LO-1, LO-2)', () {
    testWidgets('a loud level widens and shortens the orb', (tester) async {
      await tester.pumpWidget(host(VoicePhase.listening, level: 1));
      // Past the 40ms attack.
      await frames(tester, 200);

      final matrix = squash(tester)!;
      final sx = matrix.getColumn(0).x;
      final sy = matrix.getColumn(1).y;

      expect(
        sx,
        greaterThan(1.05),
        reason: 'LO-1: loud speech must widen the orb by 6-8%',
      );
      expect(sy, lessThan(1.0));
      // Volume-preserving: sy is the reciprocal, not 2 - sx.
      expect(sx * sy, closeTo(1.0, 0.001));
    });

    testWidgets('silence while listening stays at rest', (tester) async {
      await tester.pumpWidget(host(VoicePhase.listening));
      await frames(tester, 400);

      expect(squash(tester)!.getMaxScaleOnAxis(), closeTo(1.0, 0.001));
    });

    testWidgets('the level springs back when speech stops', (tester) async {
      await tester.pumpWidget(host(VoicePhase.listening, level: 1));
      await frames(tester, 200);
      expect(squash(tester)!.getColumn(0).x, greaterThan(1.05));

      // Silence. Around 250ms later it must be most of the way back.
      await tester.pumpWidget(host(VoicePhase.listening));
      await frames(tester, 600);
      expect(squash(tester)!.getColumn(0).x, lessThan(1.01));
    });

    testWidgets('attack is faster than release', (tester) async {
      // Both directions using one time constant would either miss the onset
      // of a word or flicker in the gaps between syllables.
      await tester.pumpWidget(host(VoicePhase.listening));
      await frames(tester, 400);

      await tester.pumpWidget(host(VoicePhase.listening, level: 1));
      await frames(tester, 64);
      final afterAttack = squash(tester)!.getColumn(0).x - 1;
      final peak = afterAttack;

      await tester.pumpWidget(host(VoicePhase.listening));
      await frames(tester, 64);
      final afterRelease = squash(tester)!.getColumn(0).x - 1;

      // Rose most of the way in 64ms; fell only part of the way in 64ms.
      expect(afterAttack, greaterThan(0.5 * OrbListening.squashMax));
      expect(afterRelease, greaterThan(0.3 * peak));

      expect(
        afterAttack,
        greaterThan(afterRelease),
        reason: 'rose further in 60ms than it fell in 60ms',
      );
    });

    testWidgets('the squash is outside the swirl rotation (LO-3)', (
      tester,
    ) async {
      await tester.pumpWidget(host(VoicePhase.listening, level: 1));
      await frames(tester, 200);

      // A non-uniform scale *inside* a rotation is sheared by it, so the orb
      // would squash along whatever axis the swirl points at. The outermost
      // transform under VoiceOrb must therefore be the scale: pure, with no
      // rotation mixed into it.
      final matrix = squash(tester)!;
      expect(matrix.getColumn(0).y, closeTo(0, 0.0001));
      expect(matrix.getColumn(1).x, closeTo(0, 0.0001));
    });

    testWidgets('the strip is never rotated (revision 2)', (tester) async {
      await tester.pumpWidget(host(VoicePhase.listening, level: 0.6));
      await frames(tester, 400);

      // The strip frames are the images drawn through a ResizeImage.
      final strip = find.byWidgetPredicate(
        (w) => w is Image && w.image is ResizeImage,
      );
      expect(strip, findsWidgets);

      // Every Transform between a strip frame and the root must be a pure
      // scale — the squash and nothing else. The sphere's highlight and
      // off-centre core are lighting, and lighting does not turn with the
      // object: a rotated strip reads as a spinning marble, and it would
      // also have to dissolve between orientations on enter and leave.
      final ancestors = tester.widgetList<Transform>(
        find.ancestor(of: strip.first, matching: find.byType(Transform)),
      );
      for (final t in ancestors) {
        expect(
          t.transform.getColumn(0).y.abs(),
          lessThan(0.0001),
          reason: 'a rotating ancestor: ${t.transform}',
        );
        expect(t.transform.getColumn(1).x.abs(), lessThan(0.0001));
      }
    });

    testWidgets('the squash wraps the ring as well as the sphere', (
      tester,
    ) async {
      await tester.pumpWidget(host(VoicePhase.listening, level: 1));
      await frames(tester, 200);

      // The ring has to stretch with the orb it circles. Left outside the
      // squash it would stay a perfect circle around a squashed sphere,
      // which reads as the sphere having come loose from it.
      expect(
        find.descendant(
          of: find.byType(Transform).first,
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('entering listening does not restart the swirl', (
      tester,
    ) async {
      // The accumulators live in the state and must survive a phase change:
      // a visible jump back to the start of the swirl on every phase change
      // is the bug the ticker exists to prevent.
      await tester.pumpWidget(host(VoicePhase.ready));
      await tester.pump(const Duration(seconds: 2));
      final before = tester.state(find.byType(VoiceOrb));

      await tester.pumpWidget(host(VoicePhase.listening, level: 0.5));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.state(find.byType(VoiceOrb)),
        same(before),
        reason: 'the State was recreated, so the accumulators reset',
      );
    });
  });
}
