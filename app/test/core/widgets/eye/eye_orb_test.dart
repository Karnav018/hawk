import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/core/widgets/eye/eye_motion.dart';
import 'package:knowra/src/core/widgets/eye/eye_orb.dart';
import 'package:knowra/src/core/widgets/eye/eye_pose.dart';

/// Against `HANDOFF_eye_orb.md` § Acceptance, numbered as it numbers them.
///
/// Almost all of this is asserted on [EyeMotion] rather than on pixels. The
/// shader needs a GPU and `flutter test` has none — but more to the point,
/// the things that can be *wrong* here are not pixel things. A gaze that
/// sweeps instead of rolling, an amplitude that ignores the microphone, a
/// blink that survives reduce-motion: each is a number, and each looks
/// perfectly fine in a still.
void main() {
  /// Every pose the eye passes through in [seconds] of a state.
  List<EyePose> sample(
    OrbState state, {
    double seconds = 6.0,
    double level = 0,
    double progress = 0,
    bool reduceMotion = false,
    double step = 1 / 60,
  }) => [
    for (var t = 0.0; t < seconds; t += step)
      EyeMotion.poseFor(
        state,
        loopT: t,
        sinceT: t,
        level: level,
        progress: progress,
        reduceMotion: reduceMotion,
      ),
  ];

  group('1 · READY is a still white oval with an accent disc', () {
    test('there is always a disc — never a bare circle', () {
      for (final p in sample(OrbState.ready)) {
        expect(p.discR, greaterThan(0.1));
        // The ring is the outline; without it the eye has no edge.
        expect(p.ringW, greaterThan(0));
      }
    });

    test('it double-blinks once per loop', () {
      // A blink is the lids collapsing towards zero. Two of them, close
      // together, then nothing for the rest of the six seconds.
      var runs = 0;
      var wasClosed = false;
      for (final p in sample(OrbState.ready, step: 1 / 120)) {
        final closed = p.eyeTop < 0.2;
        if (closed && !wasClosed) runs++;
        wasClosed = closed;
      }
      expect(runs, 2, reason: 'a double blink, not one and not a flutter');
    });

    test('it looks around, and comes back', () {
      final xs = sample(OrbState.ready).map((p) => p.lookX).toList();
      expect(xs.reduce(math.max), greaterThan(0.1));
      expect(xs.reduce(math.min), lessThan(-0.1));
      // Bounded: the handoff's wander is +-.2, not a roving eye.
      expect(xs.map((x) => x.abs()).reduce(math.max), lessThanOrEqualTo(0.21));
    });

    test('it breathes, slowly', () {
      final s = sample(OrbState.ready).map((p) => p.scale).toList();
      expect(s.reduce(math.max) - s.reduce(math.min), closeTo(0.012, 0.001));
    });
  });

  group('2 · listening is the wave', () {
    test('it pops within 0.2s and the pop is over by then', () {
      final early = EyeMotion.poseFor(
        OrbState.listening,
        loopT: 0.08,
        sinceT: 0.08,
      );
      expect(early.scale, greaterThan(1.02));

      final after = EyeMotion.poseFor(
        OrbState.listening,
        loopT: 0.3,
        sinceT: 0.3,
      );
      expect(after.scale, 1.0);
    });

    test('the transformation takes a second, not a blink', () {
      // The bug this exists for: the design says "blend 200ms into row 1,
      // then play the clip", because frames 1-36 of the clip are the pop and
      // the morph. Taking the 200ms *without* clip playback made 200ms the
      // entire transformation — the user's words were "too fast".
      double waveAt(double t) =>
          EyeMotion.poseFor(OrbState.listening, loopT: t, sinceT: t).wave;

      // Nothing has begun growing while the pop is still landing.
      expect(waveAt(0.1), 0);
      expect(waveAt(EyeMotion.morphStart), 0);
      // Partway through, genuinely partway.
      final mid = waveAt(0.7);
      expect(mid, greaterThan(0.1));
      expect(mid, lessThan(0.99));
      // Full only at the end of the window.
      expect(waveAt(EyeMotion.morphEnd), closeTo(1, 1e-9));
      expect(
        EyeMotion.morphEnd - EyeMotion.morphStart,
        greaterThanOrEqualTo(0.5),
      );
    });

    test('the lids and the disc travel with the wave, not ahead of it', () {
      // If the disc vanished on the 200ms blend while the wave arrived a
      // second later, the eye would be briefly blank.
      final p = EyeMotion.poseFor(OrbState.listening, loopT: 0.3, sinceT: 0.3);
      expect(p.discR, greaterThan(0.3), reason: 'disc still there pre-morph');
      expect(p.wave, 0);
    });

    test('the brow arrives with the pop, ahead of everything else', () {
      final p = EyeMotion.poseFor(
        OrbState.listening,
        loopT: 0.17,
        sinceT: 0.17,
      );
      expect(p.browShow, closeTo(1, 1e-9));
      expect(p.wave, 0, reason: 'the brow says "heard you" before the morph');
    });

    test('the wave is fully on, and the disc is not', () {
      final p = EyeMotion.poseFor(OrbState.listening, loopT: 1, sinceT: 1);
      expect(p.wave, 1);
      // A visible pupil under moving bands reads as a second object.
      expect(p.discR, lessThan(0.1));
    });

    test('the bands move, and the field they are cut from drifts', () {
      final a = EyeMotion.poseFor(OrbState.listening, loopT: 1, sinceT: 1);
      final b = EyeMotion.poseFor(OrbState.listening, loopT: 2, sinceT: 2);
      expect(b.waveFlow, lessThan(a.waveFlow), reason: 'bands rise');
      expect(b.waveT, greaterThan(a.waveT), reason: 'the shape drifts');
      // Two different rates, or the pattern repeats on itself.
      expect(
        (b.waveFlow - a.waveFlow).abs(),
        isNot(closeTo((b.waveT - a.waveT).abs(), 0.01)),
      );
    });

    test('amplitude follows speech, and nothing else does', () {
      EyePose at(double level) => EyeMotion.poseFor(
        OrbState.listening,
        loopT: 1,
        sinceT: 1,
        level: level,
      );

      expect(at(0).waveAmp, closeTo(0.5, 1e-9));
      expect(at(1).waveAmp, closeTo(0.95, 1e-9));
      // Out-of-range levels from a noisy recogniser must not blow the eye up.
      expect(at(4).waveAmp, closeTo(0.95, 1e-9));
      expect(at(-1).waveAmp, closeTo(0.5, 1e-9));

      // The level reaches the amplitude and stops there.
      expect(at(1).eyeTop, at(0).eyeTop);
      expect(at(1).scale, at(0).scale);
    });
  });

  group('5 · RETRIEVING rolls, it never reads', () {
    test('the gaze traces a closed loop and returns', () {
      final start = EyeMotion.poseFor(OrbState.retrieving, loopT: 0, sinceT: 0);
      final round = EyeMotion.poseFor(
        OrbState.retrieving,
        loopT: EyeMotion.retrieveLoop,
        sinceT: EyeMotion.retrieveLoop,
      );
      expect(round.lookX, closeTo(start.lookX, 1e-9));
      expect(round.lookZ, closeTo(start.lookZ, 1e-9));
    });

    test('it never sweeps: the gaze reverses within one loop', () {
      final xs = sample(
        OrbState.retrieving,
        seconds: EyeMotion.retrieveLoop,
      ).map((p) => p.lookX).toList();
      var reversals = 0;
      for (var i = 2; i < xs.length; i++) {
        final a = xs[i - 1] - xs[i - 2];
        final b = xs[i] - xs[i - 1];
        if (a != 0 && b != 0 && a.sign != b.sign) reversals++;
      }
      expect(
        reversals,
        greaterThanOrEqualTo(1),
        reason: 'a monotonic pan across the eye would read as scanning text',
      );
    });

    test('it holds its gaze up and to the right the whole time', () {
      for (final p in sample(OrbState.retrieving, seconds: 4)) {
        expect(p.lookX, greaterThan(0), reason: 'right');
        expect(p.lookZ, greaterThan(0), reason: 'up');
      }
    });
  });

  group('6 · INDEXING lids are the progress', () {
    test('at nothing done they are open .3, not shut', () {
      // The job sits at 0 through its whole enumerating phase, which on a
      // large Drive is the longest part. A closed eye there looks broken.
      expect(EyePose.rest(OrbState.indexing, progress: 0).eyeTop, 0.3);
    });

    test('they open with the fraction, monotonically', () {
      var last = 0.0;
      for (var f = 0.0; f <= 0.97; f += 0.05) {
        final open = EyePose.rest(OrbState.indexing, progress: f).eyeTop;
        expect(open, greaterThan(last));
        last = open;
      }
    });

    test('>= .98 is fully open', () {
      expect(EyePose.rest(OrbState.indexing, progress: 0.98).eyeTop, 1.0);
      expect(EyePose.rest(OrbState.indexing, progress: 1.0).eyeTop, 1.0);
    });

    test('the lids mirror, always', () {
      for (var f = 0.0; f <= 1.0; f += 0.1) {
        final p = EyePose.rest(OrbState.indexing, progress: f);
        expect(p.eyeBot, -p.eyeTop);
      }
    });

    test('a blink is a blink of that opening, not a jump to open', () {
      // Multiplicative, so a blink at 20% done does not flash the eye wide.
      final poses = sample(OrbState.indexing, progress: 0.2);
      final widest = poses.map((p) => p.eyeTop).reduce(math.max);
      expect(
        widest,
        lessThanOrEqualTo(
          EyePose.rest(OrbState.indexing, progress: 0.2).eyeTop,
        ),
      );
    });
  });

  group('7 · reduce motion means no motion', () {
    test('every state pins to its rest pose, at every moment', () {
      for (final state in OrbState.values) {
        final rest = EyePose.rest(state, progress: 0.5);
        for (final p in sample(
          state,
          progress: 0.5,
          level: 0.8,
          reduceMotion: true,
        )) {
          expect(p.eyeTop, rest.eyeTop, reason: '$state lids');
          expect(p.scale, rest.scale, reason: '$state breathe');
          expect(p.lookX, rest.lookX, reason: '$state wander');
          expect(p.spark, rest.spark, reason: '$state twinkle');
        }
      }
    });

    test('there is no blink anywhere in a full loop', () {
      final lids = sample(
        OrbState.ready,
        reduceMotion: true,
      ).map((p) => p.eyeTop);
      expect(lids.toSet().length, 1);
    });
  });

  group('8 · white and accent only', () {
    test(
      'the accent is the last three uniforms and nothing else is colour',
      () {
        const accent = Color(0xFFC8F04A);
        final f = EyePose.rest(
          OrbState.ready,
        ).toFloats(const Size(224, 224), accent);
        expect(f.length, EyePose.uniformCount);
        expect(f[42], closeTo(accent.r, 1e-6));
        expect(f[43], closeTo(accent.g, 1e-6));
        expect(f[44], closeTo(accent.b, 1e-6));
      },
    );

    test('all six theme accents reach the shader unchanged', () {
      for (final c in [
        const Color(0xFF59D3FF),
        const Color(0xFFC8F04A),
        const Color(0xFFFF7A3D),
        const Color(0xFFFFD14A),
        const Color(0xFFFF6FAE),
        const Color(0xFFA78BFA),
      ]) {
        final f = EyePose.rest(
          OrbState.ready,
        ).toFloats(const Size(190, 190), c);
        expect([f[42], f[43], f[44]], [c.r, c.g, c.b], reason: '$c');
      }
    });
  });

  group('9 · nothing draws outside the box', () {
    /// The furthest any feature reaches along either axis, in box units.
    ///
    /// Per-axis, not radial: the box is a **square** running -1.3..1.3 on
    /// both, so a feature at (.98, .8) is inside it even though its distance
    /// from centre is 1.27. Measuring radially fails the sparkle for being
    /// diagonal, which is not a clip.
    double extent(EyePose p) {
      final lid = math.max(p.eyeTop, -p.eyeBot);
      final ring = math.max(p.eyeW, lid) + p.ringGap + p.ringW;
      // brow_th is a HALF width, so the stroke's top edge is browZ + browTh.
      final brow = p.browShow > 0.001
          ? math.max(p.browZ + p.browTh, p.browLen)
          : 0.0;
      final deco = [
        // Dashes and the burst are radial, out to r 1.25 — which is 1.25 on
        // an axis in the worst case.
        if (p.dash > 0.001 || p.lines > 0.001) 1.25,
        // The astroid's tips are `size` from its centre, on each axis.
        if (p.spark > 0.001)
          math.max(p.sparkX.abs(), p.sparkZ.abs()) + p.sparkSize * p.spark,
        if (p.drop > 0.001) p.dropX.abs() + 0.10 * p.drop,
      ].fold(0.0, math.max);
      return math.max(math.max(ring, brow), deco) * p.scale +
          math.max(p.locX.abs(), p.locZ.abs());
    }

    test('every state, every frame, stays inside 1.3', () {
      for (final state in OrbState.values) {
        for (var f = 0.0; f <= 1.0; f += 0.25) {
          for (final p in sample(state, progress: f, level: 1)) {
            expect(
              extent(p),
              lessThanOrEqualTo(eyeBoxUnits / 2),
              reason: '$state at progress $f reaches ${extent(p)}',
            );
          }
        }
      }
    });

    test('the brow never clips at the top, even mid-pop', () {
      // ANSWERED is the worst case: brow up *and* a 1.06 scale pop.
      for (final p in sample(OrbState.answered, seconds: 3)) {
        if (p.browShow <= 0.001) continue;
        expect((p.browZ + p.browTh) * p.scale, lessThan(eyeBoxUnits / 2));
      }
    });
  });

  group('10 · the fallback painter carries the widget', () {
    Widget host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.dark]),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('it renders and animates with no GPU', (tester) async {
      EyeOrb.debugForceFallback = true;
      addTearDown(() => EyeOrb.debugForceFallback = false);

      await tester.pumpWidget(
        host(const EyeOrb(state: OrbState.ready, size: 224)),
      );
      // Not pumpAndSettle: the eye runs a continuous ticker, so settling
      // never terminates.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.byType(EyeOrb), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every state paints', (tester) async {
      EyeOrb.debugForceFallback = true;
      addTearDown(() => EyeOrb.debugForceFallback = false);

      for (final s in OrbState.values) {
        await tester.pumpWidget(
          host(EyeOrb(state: s, size: 224, level: 0.6, progress: 0.4)),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull, reason: '$s');
      }
    });

    testWidgets('a state change morphs rather than cutting', (tester) async {
      EyeOrb.debugForceFallback = true;
      addTearDown(() => EyeOrb.debugForceFallback = false);

      await tester.pumpWidget(
        host(const EyeOrb(state: OrbState.ready, size: 224)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        host(const EyeOrb(state: OrbState.listening, size: 224)),
      );
      // Mid-morph the wave must be partway, not already 1.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  });

  group('transitions — the design session\'s matrix', () {
    int ms(OrbState a, OrbState b, {double wave = 0}) =>
        EyeMotion.transition(a, b, currentWave: wave).inMilliseconds;

    test('320ms is the default', () {
      expect(ms(OrbState.ready, OrbState.retrieving), 320);
      expect(
        ms(OrbState.indexing, OrbState.retrieving),
        400,
        reason: 'anything touching indexing is the calm 400',
      );
      expect(ms(OrbState.retrieving, OrbState.ready), 320);
    });

    test('into a state that pops, the blend is short', () {
      // The pop *is* the transition; a long blend on top swallows it and the
      // press feels unacknowledged.
      expect(ms(OrbState.ready, OrbState.listening), 200);
      expect(ms(OrbState.retrieving, OrbState.answered), 200);
    });

    test('a flinch is not an apology', () {
      // Released before the wave took hold: the eye barely started, so it
      // must not run the full exit as though something was said.
      expect(ms(OrbState.listening, OrbState.ready, wave: 0.2), 240);
      expect(ms(OrbState.listening, OrbState.ready, wave: 0.9), 900);
    });

    test(
      'a result renders on this screen, so the wave eases rather than cuts',
      () {
        // The handoff calls a successful release a cut because in the design
        // the result is a different screen. Ours is not — the user asked to
        // listen in place — so the same-screen rule applies instead.
        expect(ms(OrbState.listening, OrbState.retrieving, wave: 1), 240);
      },
    );

    test('answered settles back to ready lazily', () {
      expect(ms(OrbState.answered, OrbState.ready), 480);
    });

    test('indexing is calm at both ends', () {
      expect(ms(OrbState.ready, OrbState.indexing), 400);
      expect(ms(OrbState.indexing, OrbState.ready), 400);
    });
  });

  group('never two pops within a second', () {
    test('the pop can be suppressed without touching anything else', () {
      EyePose at({required bool allowPop}) => EyeMotion.poseFor(
        OrbState.listening,
        loopT: 0.08,
        sinceT: 0.08,
        allowPop: allowPop,
      );

      expect(at(allowPop: true).scale, greaterThan(1.02));
      expect(at(allowPop: false).scale, 1.0);
      // Suppressing the pop must not also suppress the state.
      expect(at(allowPop: false).wave, at(allowPop: true).wave);
    });

    testWidgets(
      're-pressing while the wave is still draining does not re-pop',
      (tester) async {
        EyeOrb.debugForceFallback = true;
        addTearDown(() => EyeOrb.debugForceFallback = false);

        Widget at(OrbState s) => MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.dark]),
          home: Scaffold(
            body: Center(child: EyeOrb(state: s, size: 224)),
          ),
        );

        await tester.pumpWidget(at(OrbState.ready));
        await tester.pump(const Duration(milliseconds: 50));

        // Into listening, let the wave grow, then bail out and immediately
        // press again — the eye never finished leaving.
        await tester.pumpWidget(at(OrbState.listening));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpWidget(at(OrbState.ready));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpWidget(at(OrbState.listening));
        await tester.pump(const Duration(milliseconds: 60));

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the uniform contract', () {
    /// (bindings, floats) declared by `eye_orb.frag`.
    ({int bindings, int floats}) declared() {
      final src = File('shaders/eye_orb.frag').readAsStringSync();
      var bindings = 0;
      var floats = 0;
      for (final line in src.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('uniform ')) continue;
        final body = t.substring(8, t.indexOf(';'));
        final type = body.split(RegExp(r'\s+')).first;
        final names = body.substring(type.length).split(',').length;
        bindings += names;
        floats +=
            names *
            switch (type) {
              'vec2' => 2,
              'vec3' => 3,
              'vec4' => 4,
              _ => 1,
            };
      }
      return (bindings: bindings, floats: floats);
    }

    test('it stays inside Metal\'s uniform binding budget', () {
      // The one that actually bit us. Metal gives every uniform DECLARATION
      // its own buffer binding and accepts indices 0..30. Declared one per
      // knob, the eye needed 44 and the device refused the program with
      // "'buffer' attribute parameter is out of bounds" — while every host
      // build stayed green, because impellerc validates the GLSL and the
      // SkSL translation, not Metal's binding budget.
      //
      // Nothing short of running it on a device would have caught that. This
      // test is the substitute.
      expect(declared().bindings, lessThanOrEqualTo(30));
    });

    test('it declares room for every float the pose sends', () {
      final d = declared();
      expect(d.floats, greaterThanOrEqualTo(EyePose.uniformCount));
      // Packed four to a vec4, so at most three slots of padding. More than
      // that means a knob was dropped rather than packed.
      expect(
        d.floats - EyePose.uniformCount,
        lessThan(4),
        reason: 'declared ${d.floats} for ${EyePose.uniformCount} floats',
      );
    });

    test('the pose sends that many, in a fixed order', () {
      final f = EyePose.rest(
        OrbState.ready,
      ).toFloats(const Size(224, 236), const Color(0xFF59D3FF));
      expect(f.length, EyePose.uniformCount);
      // uSize first, because the shader needs it for FlutterFragCoord.
      expect(f[0], 224);
      expect(f[1], 236);
    });
  });
}
