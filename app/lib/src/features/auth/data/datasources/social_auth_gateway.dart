import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';

/// Obtains an OIDC identity token from Apple or Google.
///
/// The token is only ever a claim until the server checks its signature
/// against the provider's JWKS — nothing here is trusted on the device.
abstract interface class SocialAuthGateway {
  /// Whether the provider's SDK exists on this platform at all.
  ///
  /// Separate from [isConfigured] on purpose: "this device cannot do Google
  /// sign-in" and "this build has no client id" are different problems, and
  /// conflating them hides a misconfiguration behind a missing button.
  bool isAvailable(SocialProvider provider);

  /// Whether credentials were supplied for this build.
  bool isConfigured(SocialProvider provider);

  /// Throws [CancelledException] if the person backs out — that is a normal
  /// outcome, not an error to report.
  Future<SocialCredential> authenticate(SocialProvider provider);

  Future<void> signOut();
}

@LazySingleton(as: SocialAuthGateway)
class SocialAuthGatewayImpl implements SocialAuthGateway {
  SocialAuthGatewayImpl(this._config, this._logger);

  final AppConfig _config;
  final AppLogger _logger;

  bool _googleInitialised = false;

  @override
  bool isAvailable(SocialProvider provider) => switch (provider) {
    // Apple's SDK is only present on Apple platforms. Offering the button
    // elsewhere would be a guaranteed dead end.
    SocialProvider.apple => !kIsWeb && (Platform.isIOS || Platform.isMacOS),
    SocialProvider.google => true,
  };

  @override
  bool isConfigured(SocialProvider provider) => switch (provider) {
    // Apple carries its credentials in the app's entitlements, not in a
    // dart-define, so there is nothing here to check.
    SocialProvider.apple => true,
    // Only the server client id is checkable from Dart. On iOS the *client*
    // id lives in GoogleService-Info.plist, which the SDK reads itself and
    // this code cannot see — so a build can pass this check and still fail at
    // sign-in if Google is not enabled in the Firebase console. The error
    // thrown from `authenticate` names that case.
    SocialProvider.google => _config.googleServerClientId.isNotEmpty,
  };

  @override
  Future<SocialCredential> authenticate(SocialProvider provider) async {
    if (!isAvailable(provider)) {
      throw AppException.badRequest(
        message: '${provider.name} sign-in is not available on this device.',
      );
    }
    if (!isConfigured(provider)) {
      // Names the actual remaining step. Firebase owns the client ids now, so
      // the fix is a console toggle followed by a regenerate — not a value to
      // paste into config.
      throw const AppException.badRequest(
        message:
            'Google sign-in is not set up for this project yet.\n\n'
            '1. Firebase console -> Authentication -> Sign-in method -> '
            'enable Google\n'
            '2. flutterfire configure --project=knowra-506719 '
            '--platforms=ios,android\n'
            '3. make ios-url-scheme\n'
            '4. flutter clean && flutter run\n\n'
            'Steps 3 and 4 are native changes; a hot restart will not pick '
            'them up.',
      );
    }
    return switch (provider) {
      SocialProvider.apple => _apple(),
      SocialProvider.google => _google(),
    };
  }

  Future<SocialCredential> _apple() async {
    // Apple embeds the nonce we hand it verbatim into the token's `nonce`
    // claim. Hashing the raw value first means the raw nonce never leaves the
    // device in the authorization request, while the server can still bind the
    // token to this one attempt.
    final raw = _rawNonce();
    final hashed = _sha256(raw);

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashed,
      );

      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw const AppException.unknown(
          message: 'Apple did not return a sign-in token.',
        );
      }

      return SocialCredential(
        provider: SocialProvider.apple,
        identityToken: token,
        nonce: hashed,
        rawNonce: raw,
        // Apple sends the name exactly once, on first authorisation, and never
        // again — if it is not forwarded now it is gone for good.
        name: _joinName(credential.givenName, credential.familyName),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AppException.cancelled();
      }
      _logger.warning(
        'Apple sign-in failed',
        name: 'auth',
        data: {'code': error.code.name},
      );
      throw AppException.unknown(cause: error);
    }
  }

  Future<SocialCredential> _google() async {
    final raw = _rawNonce();

    // Google puts the nonce in the token unhashed, and it is supplied at
    // initialisation rather than per call — so re-initialise for each attempt
    // to keep one nonce bound to one sign-in.
    await GoogleSignIn.instance.initialize(
      clientId: _config.googleClientId.isEmpty ? null : _config.googleClientId,
      serverClientId: _config.googleServerClientId.isEmpty
          ? null
          : _config.googleServerClientId,
      nonce: raw,
    );
    _googleInitialised = true;

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AppException.badRequest(
        message: 'Google sign-in is not supported on this platform.',
      );
    }

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const AppException.unknown(
          message: 'Google did not return a sign-in token.',
        );
      }

      return SocialCredential(
        provider: SocialProvider.google,
        identityToken: token,
        nonce: raw,
        // Google is handed the nonce un-hashed, so both forms are the same.
        rawNonce: raw,
        name: account.displayName,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AppException.cancelled();
      }
      _logger.warning(
        'Google sign-in failed',
        name: 'auth',
        data: {'code': error.code.name},
      );
      throw AppException.unknown(cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    if (!_googleInitialised) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (error) {
      // Signing out of our own session is what matters; a provider that will
      // not cooperate must not block it.
      _logger.warning('Provider sign-out failed', name: 'auth');
    }
  }

  /// 32 bytes of CSPRNG entropy, url-safe.
  static String _rawNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static String? _joinName(String? given, String? family) {
    final parts = [
      given,
      family,
    ].where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim());
    return parts.isEmpty ? null : parts.join(' ');
  }
}
