import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/splash/presentation/pages/splash_page.dart';

import '../../support/load_app_fonts.dart';

const _designSize = Size(402, 874);

/// Fractions of the run to capture. Chosen to land on the moments that carry
/// the animation: full bleed, mid-contraction, nearly settled, and the
/// wordmark's arrival.

void main() {
  setUpAll(loadAppFonts);

  testWidgets('splash matches the design frame', (tester) async {
    // One frame, not a filmstrip. v2 captured the animation at six
    // checkpoints because the animation *was* the screen; v3's splash is a
    // static composition with a progress bar over it, so the thing worth
    // pinning is the composition.
    tester.view
      ..physicalSize = _designSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await precacheAppImages(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const SplashPage(),
      ),
    );

    await tester.pump();
    await tester.pump(SplashPage.duration ~/ 2);

    await expectLater(
      find.byType(SplashPage),
      matchesGoldenFile('goldens/splash.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
