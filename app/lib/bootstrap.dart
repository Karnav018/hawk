import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'firebase_options.dart';
import 'src/app/app.dart';
import 'src/app/observer/app_bloc_observer.dart';
import 'src/app/theme/theme_cubit.dart';
import 'src/core/config/app_config.dart';
import 'src/core/di/injector.dart';
import 'src/core/logging/app_logger.dart';
import 'src/features/account/data/privacy_settings.dart';
import 'src/features/chat/data/local/index_sync.dart';

/// Single composition root.
///
/// Order matters: bindings → DI (so a logger exists) → error handlers →
/// `runApp`. Anything that can throw before `runApp` would otherwise crash
/// silently with no reporter attached.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();

  // Before DI: the Firebase singletons are registered from the locator, and
  // touching any of them before `initializeApp` throws.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (config.useFirebaseEmulator) {
    _connectEmulators(config);
  }

  await configureDependencies(
    environment: config.isProduction ? AppEnv.prod : AppEnv.dev,
  );

  final logger = getIt<AppLogger>();
  Bloc.observer = AppBlocObserver(logger);

  // The phone's search index follows the signed-in user from here on:
  // loads on sign-in, mirrors the cloud's chunks, wipes on sign-out.
  getIt<IndexSync>().start();

  // Restore the theme before the first frame so the app never flashes the
  // wrong ground colour.
  await getIt<ThemeCubit>().load();

  logger.info(
    'Booting ${config.appName}',
    name: 'bootstrap',
    data: {
      'flavor': config.flavor.name,
      'emulator': config.useFirebaseEmulator,
      'sentry': config.isSentryEnabled,
      'google_client_id': config.googleClientId.isEmpty ? 'MISSING' : 'set',
    },
  );

  // Loud in debug, because the usual cause is launching without
  // `--dart-define-from-file` — which looks identical to having no
  // credentials, and a hot restart will never fix it.
  if (kDebugMode && config.googleClientId.isEmpty) {
    logger.warning(
      'GOOGLE_CLIENT_ID is empty. Relaunch with '
      '--dart-define-from-file=config/${config.flavor.name}.json',
      name: 'bootstrap',
    );
  }

  if (!config.isSentryEnabled) {
    // No DSN for this flavour — still make sure nothing is swallowed.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      logger.error(
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        name: 'flutter',
        report: false,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      logger.error(
        'Uncaught platform error',
        error: error,
        stackTrace: stack,
        name: 'platform',
        report: false,
      );
      return true;
    };

    runApp(const HawkApp());
    return;
  }

  // SentryFlutter.init installs FlutterError.onError and
  // PlatformDispatcher.onError itself, and only runs `appRunner` once the SDK
  // is ready — so the very first frame is already covered.
  // Before Sentry, so the very first event already honours the switch.
  await PrivacySettings.load();

  await SentryFlutter.init((options) {
    options
      ..dsn = config.sentryDsn
      ..environment = config.flavor.name
      ..debug = kDebugMode
      ..tracesSampleRate = config.sentryTracesSampleRate
      ..enableAutoSessionTracking = true
      ..attachScreenshot = true
      ..maxBreadcrumbs = 150
      // Never ship PII by default; opt in per-event via the logger scope.
      ..sendDefaultPii = false
      ..beforeSend = _beforeSend;
  }, appRunner: () => runApp(SentryWidget(child: const HawkApp())));
}

/// Points every SDK at the local emulator suite.
///
/// Host, not `localhost`: an Android emulator reaches the developer machine as
/// `10.0.2.2`, and `localhost` there is the emulated device itself.
void _connectEmulators(AppConfig config) {
  final host = config.emulatorHost;

  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).useFunctionsEmulator(host, 5001);
}

/// Last chance to drop or scrub an event before it leaves the device.
FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
  // Debug builds stay local — otherwise every hot reload pollutes the issue
  // stream. Flip this if you need to verify the pipeline end to end.
  if (kDebugMode) return null;

  // Screen 2K's switch, enforced at the last possible moment.
  //
  // Dropping the event here rather than skipping `SentryFlutter.init` is
  // deliberate: the switch can be thrown at any point in the session, and an
  // SDK that was never initialised cannot be turned back on without a
  // restart. Read from a cached static because this runs on the error path
  // and cannot await a preference.
  if (!PrivacySettings.crashReportsEnabled) return null;

  return event;
}
