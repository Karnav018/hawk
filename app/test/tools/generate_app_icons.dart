// Renders the launcher icon artwork to PNG.
//
//   flutter test test/tools/generate_app_icons.dart
//
// Two constraints put this file exactly here. It lives under `test/` because
// `flutter test` only builds the asset bundle for files in that tree — from
// `tool/` the app's assets never load. And it is *not* named
// `*_test.dart`, so `flutter test` does not pick it up and rewrite the icons on
// every run.
//
// Re-run it whenever the mark changes, then `dart run flutter_launcher_icons`
// to cut the platform sizes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/widgets/app_icon_artwork.dart';

const _canvas = 1024.0;

Future<void> _render(WidgetTester tester, Widget artwork, String path) async {
  final key = GlobalKey();

  await tester.pumpWidget(
    MediaQuery(
      // Render at 1:1 so logical pixels are device pixels.
      data: const MediaQueryData(devicePixelRatio: 1),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: artwork),
        ),
      ),
    ),
  );
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // `toImage` resolves under the test binding's fake clock, so it must NOT be
  // wrapped in `runAsync` — doing so deadlocks, because the frame that would
  // complete it is never pumped.
  final ui.Image image = await boundary.toImage();

  // Everything after this point is *real* async work. Under `FakeAsync` the
  // event loop is never advanced, so an awaited PNG encode or file write
  // simply never completes and the run hangs with no output. `runAsync` steps
  // outside the fake clock for exactly that reason.
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });

  // ignore: avoid_print
  print('wrote $path (${image.width}x${image.height})');
}

void main() {
  testWidgets('generate launcher icon artwork', (tester) async {
    tester.view
      ..physicalSize = const Size(_canvas + 2, _canvas + 2)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _render(
      tester,
      const AppIconArtwork(size: _canvas),
      'assets/branding/app_icon.png',
    );

    await _render(
      tester,
      const AppIconArtwork(size: _canvas, variant: IconVariant.light),
      'assets/branding/app_icon_light.png',
    );

    // The two Android layers are drawn at the adaptive ratio, so the mark
    // survives whatever mask the launcher crops them with.
    await _render(
      tester,
      const AppIconArtwork(
        size: _canvas,
        variant: IconVariant.foreground,
        markRatio: AppIconArtwork.adaptiveMarkRatio,
      ),
      'assets/branding/app_icon_foreground.png',
    );

    await _render(
      tester,
      const AppIconArtwork(
        size: _canvas,
        variant: IconVariant.monochrome,
        markRatio: AppIconArtwork.adaptiveMarkRatio,
      ),
      'assets/branding/app_icon_monochrome.png',
    );

    expect(File('assets/branding/app_icon.png').existsSync(), isTrue);
    expect(
      File('assets/branding/app_icon_monochrome.png').existsSync(),
      isTrue,
    );
  });
}
