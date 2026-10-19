import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/widgets/voice_orb.dart';

/// The glow behind the orb must be round, measured on rendered pixels.
///
/// A structural test can say a ClipOval is present; it cannot say the result
/// is round — a clip in the wrong place, or a blur outside it, still passes.
/// So this renders the orb and compares brightness at the same distance from
/// the centre along the diagonal and along the axis. A round glow depends
/// only on distance, so the two agree. A square one reaches further on the
/// diagonal — its corners — and is visibly brighter there.
void main() {
  testWidgets('the background glow is round, not square', (tester) async {
    const canvas = 640.0;
    const size = 168.0;
    final key = GlobalKey();

    await tester.binding.setSurfaceSize(const Size(canvas, canvas));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox.square(
                dimension: canvas,
                child: Center(
                  child: VoiceOrb(phase: VoicePhase.ready, size: size),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Decode the emission map, or the glow is an empty box and every
    // sample reads zero — which would pass for the wrong reason.
    final element = tester.element(find.byType(VoiceOrb));
    await tester.runAsync(
      () => precacheImage(const AssetImage(OrbListening.emission), element),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;

    double luminance(double x, double y) {
      final i = (y.round() * image.width + x.round()) * 4;
      return (bytes.getUint8(i) +
              bytes.getUint8(i + 1) +
              bytes.getUint8(i + 2)) /
          3;
    }

    // The glow's square box, if it were square, has half-width
    // 168 * 1.36 * 1.6 / 2 ~= 183. A distance between that and its
    // half-diagonal (~258) is inside a square's corner but outside it on
    // the axis — the one place a square and a circle disagree.
    const d = 215.0;
    const c = canvas / 2;
    final diag = d / math.sqrt2;

    final onAxis =
        [
          luminance(c + d, c),
          luminance(c - d, c),
          luminance(c, c + d),
          luminance(c, c - d),
        ].reduce((a, b) => a + b) /
        4;
    final onDiagonal =
        [
          luminance(c + diag, c + diag),
          luminance(c - diag, c + diag),
          luminance(c + diag, c - diag),
          luminance(c - diag, c - diag),
        ].reduce((a, b) => a + b) /
        4;

    // Sanity: the glow was actually drawn, so the comparison means something.
    expect(
      luminance(c + 120, c),
      greaterThan(1),
      reason: 'the glow did not render; the shape check would be vacuous',
    );

    // Round: the diagonal is no brighter than the axis at the same distance.
    // A square glow's corners make the diagonal several times brighter.
    expect(
      onDiagonal,
      lessThanOrEqualTo(onAxis * 1.5 + 2),
      reason:
          'diagonal $onDiagonal vs axis $onAxis at ${d}px — '
          'the glow has corners',
    );
  });
}
