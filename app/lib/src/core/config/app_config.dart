import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_config.freezed.dart';

/// Build flavours. Selected at compile time via `--dart-define-from-file`.
enum Flavor { dev, staging, prod }

/// Immutable, compile-time application configuration.
///
/// Values come from `--dart-define-from-file=config/<flavor>.json`, so nothing
/// secret ever lives in the repository and the values are tree-shaken into the
/// binary rather than read at runtime.
///
/// There is no API base url or HTTP timeout here: the Firebase SDKs own the
/// transport and are configured from `firebase_options.dart` instead. The only
/// host we still name is the emulator one.
@freezed
abstract class AppConfig with _$AppConfig {
  const factory AppConfig({
    required String appName,
    required Flavor flavor,
    required String googleClientId,
    required String googleServerClientId,
    required bool useFirebaseEmulator,
    required String emulatorHost,
    required String sentryDsn,
    required double sentryTracesSampleRate,
  }) = _AppConfig;

  const AppConfig._();

  /// The Firebase project's web OAuth client — what Google sign-in asks for
  /// an ID token *for*, so Firebase Auth can verify it.
  ///
  /// A default, not only a dart-define: a plain `flutter run` or a
  /// `flutter build appbundle` without `--dart-define-from-file` left it
  /// empty, and Google sign-in refused with "not set up for this project".
  /// It is a public identifier, not a secret — the same value ships in
  /// `google-services.json` inside every build. `config/*.json` still
  /// overrides it.
  static const knowraWebClientId =
      '326925575468-5j1321uu45hm08fvfit57b5s5uu9sj4o.apps.googleusercontent.com';

  /// Reads the configuration injected at build time.
  factory AppConfig.fromEnvironment() {
    const flavorName = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

    return AppConfig(
      appName: const String.fromEnvironment(
        'APP_NAME',
        defaultValue: 'Hawk (dev)',
      ),
      flavor: Flavor.values.firstWhere(
        (f) => f.name == flavorName,
        orElse: () => Flavor.dev,
      ),
      // OAuth client ids. Empty means the provider is simply not offered,
      // which is how a build without credentials degrades instead of crashing
      // at the moment somebody taps the button.
      googleClientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      googleServerClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
        defaultValue: knowraWebClientId,
      ),
      useFirebaseEmulator: const bool.fromEnvironment('USE_FIREBASE_EMULATOR'),
      // Android emulators reach the host machine as 10.0.2.2; iOS simulators
      // share the host's loopback and use localhost.
      emulatorHost: const String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: 'localhost',
      ),
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
      sentryTracesSampleRate:
          double.tryParse(
            const String.fromEnvironment(
              'SENTRY_TRACES_SAMPLE_RATE',
              defaultValue: '1.0',
            ),
          ) ??
          1.0,
    );
  }

  /// Sentry is only wired up when a DSN was supplied for this flavour.
  bool get isSentryEnabled => sentryDsn.isNotEmpty;

  bool get isProduction => flavor == Flavor.prod;
}
