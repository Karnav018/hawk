import 'package:injectable/injectable.dart';

import '../config/app_config.dart';

/// Third-party singletons that injectable cannot annotate, because we do not
/// own their source.
///
/// Much smaller than it was: the HTTP client, its interceptors and the secure
/// token store all went with the move to Firebase, whose SDK owns the
/// transport and the session. The Firebase singletons themselves live in
/// [FirebaseModule].
@module
abstract class RegisterModule {
  /// Compile-time configuration for the current flavour.
  @lazySingleton
  AppConfig get appConfig => AppConfig.fromEnvironment();
}
