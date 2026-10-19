// flutter_driver is a dev dependency on purpose: this entrypoint is never
// part of a release build.
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

import 'bootstrap.dart';

/// QA entrypoint. Not used by any release build.
///
/// Exists so an automated harness can drive the UI: `main.dart` is untouched,
/// and `flutter_driver` is a dev dependency, so nothing here reaches a store
/// build. Run with:
///
///     flutter run -t lib/main_qa.dart --dart-define-from-file=config/dev.json
///
/// The extension is enabled *before* `bootstrap()` so the driver can attach
/// during startup rather than racing the first frame — the splash screen owns
/// the screen for its whole animation, and a harness that attached afterwards
/// would miss it.
void main() {
  enableFlutterDriverExtension();
  bootstrap();
}
