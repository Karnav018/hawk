import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled typefaces into the test font collection.
///
/// Widget tests otherwise render everything in a fallback font, which makes
/// goldens useless for judging type. Call once from `setUpAll`.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  const families = <String, List<String>>{
    'Archivo': ['assets/fonts/Archivo-Variable.ttf'],
    'Instrument Serif': [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ],
    'Poppins': [
      'assets/fonts/Poppins-Regular.ttf',
      'assets/fonts/Poppins-Medium.ttf',
      'assets/fonts/Poppins-SemiBold.ttf',
      'assets/fonts/Poppins-Bold.ttf',
    ],
  };

  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path).then((d) => d));
    }
    await loader.load();
  }
}

/// Decodes bundled images into the global image cache.
///
/// `pumpAndSettle` does not wait for asset decoding, so a golden captured
/// straight after pumping renders every `Image` as empty. Resolving the
/// provider inside `runAsync` puts the frame in the cache, after which the
/// widget resolves it synchronously.
Future<void> precacheAppImages(WidgetTester tester) async {
  const providers = <AssetImage>[
    AssetImage('assets/images/orb_sphere.png'),
    AssetImage('assets/images/orb_emission.png'),
  ];

  await tester.runAsync(() async {
    for (final provider in providers) {
      final completer = Completer<void>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (error, stack) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      await completer.future;
    }
  });
}
