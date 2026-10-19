// Renders the eye's states to a contact sheet.
//
//   flutter test test/tools/preview_eye.dart
//
// Previews the FALLBACK painter — `flutter test` is headless, so the shader
// never resolves here. For the shader itself, run the app on a device.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/widgets/eye/eye_motion.dart';
import 'package:knowra/src/core/widgets/eye/eye_painter.dart';
import 'package:knowra/src/core/widgets/eye/eye_pose.dart';

const _cell = 224.0;
const _accent = Color(0xFF59D3FF);

void main() {
  testWidgets('preview the eye', (tester) async {
    // Each state at a moment that shows what it does: ready mid-wander,
    // listening with the wave up and a loud level, retrieving mid-roll,
    // answered at the twinkle, indexing at 40%.
    final frames = <String, EyePose>{
      'ready': EyeMotion.poseFor(OrbState.ready, loopT: 2.2, sinceT: 2.2),
      'listening': EyeMotion.poseFor(
        OrbState.listening,
        loopT: 1.4,
        sinceT: 1.4,
        level: 0.8,
      ),
      'retrieving': EyeMotion.poseFor(
        OrbState.retrieving,
        loopT: 0.6,
        sinceT: 0.6,
      ),
      'answered': EyeMotion.poseFor(OrbState.answered, loopT: 0.9, sinceT: 0.9),
      'indexing': EyeMotion.poseFor(
        OrbState.indexing,
        loopT: 1.0,
        sinceT: 1.0,
        progress: 0.4,
      ),
      'blink': EyeMotion.poseFor(OrbState.ready, loopT: 0.75, sinceT: 0.75),
    };

    // The listening enter, sampled across its full second.
    final enter = <String, EyePose>{
      for (final t in const [0.0, 0.1, 0.25, 0.5, 0.7, 0.85, 1.0])
        '${t}s': EyeMotion.poseFor(
          OrbState.listening,
          loopT: t,
          sinceT: t,
          level: 0.7,
        ),
    };

    final key = GlobalKey();
    tester.view
      ..physicalSize = const Size(_cell * 7 + 40, _cell * 2 + 40)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF0C0C0D),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in [frames.values, enter.values])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in row)
                          CustomPaint(
                            size: const Size.square(_cell),
                            painter: EyeFallbackPainter(
                              pose: p,
                              accent: _accent,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    await tester.runAsync(() async {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/eye_states.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('wrote build/eye_states.png');
    // ignore: avoid_print
    print('  row 1: ${frames.keys.join(", ")}');
    // ignore: avoid_print
    print('  row 2 (listening enter): ${enter.keys.join(", ")}');
  });
}
