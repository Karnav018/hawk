import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth_user.dart';

part 'auth_session.freezed.dart';

/// A signed-in session: the tokens plus what the server said about the account.
@freezed
abstract class AuthSession with _$AuthSession {
  const factory AuthSession({
    required String accessToken,
    required String refreshToken,
    required Duration expiresIn,
    @Default(false) bool isNewUser,
    @Default(false) bool needsOnboarding,
  }) = _AuthSession;
}

/// Where the app is, from the session's point of view.
///
/// A sealed union rather than a nullable user: "we have not looked yet" and
/// "there is nobody" have to be distinguishable, or the router flashes the
/// sign-in screen at an already-signed-in user on every cold start.
@freezed
sealed class AuthStatus with _$AuthStatus {
  /// Storage has not been read yet.
  const factory AuthStatus.unknown() = AuthUnknown;

  const factory AuthStatus.unauthenticated() = AuthUnauthenticated;

  /// Signed in, but screen 3J is still outstanding.
  const factory AuthStatus.onboarding(AuthUser user) = AuthOnboarding;

  const factory AuthStatus.authenticated(AuthUser user) = AuthAuthenticated;
}

/// A credential obtained from Apple or Google, ready to exchange with the API.
@freezed
abstract class SocialCredential with _$SocialCredential {
  const factory SocialCredential({
    required SocialProvider provider,
    required String identityToken,

    /// Exactly the value handed to the provider, because that is what lands
    /// in the token's `nonce` claim: Apple gets a SHA-256 of the raw nonce,
    /// Google gets the raw one.
    ///
    /// A server that verifies the token itself compares against this.
    String? nonce,

    /// The un-hashed nonce.
    ///
    /// Firebase wants this one for Apple — it re-derives the hash and compares
    /// internally, so handing it the already-hashed value fails verification
    /// with a misleading `invalid-credential`. Both forms are carried because
    /// which one is correct depends on who is checking.
    String? rawNonce,

    /// Apple returns the display name once, on first authorisation, and never
    /// again — so it has to be forwarded on that first call or it is lost.
    String? name,
  }) = _SocialCredential;
}
