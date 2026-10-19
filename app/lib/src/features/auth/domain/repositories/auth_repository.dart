import '../entities/auth_session.dart';
import '../entities/auth_user.dart';

/// The session authority.
///
/// Everything that changes who is signed in goes through here, and [status] is
/// the single place the rest of the app watches. That is what keeps the router
/// guard, the API interceptor and the UI from each holding their own opinion
/// about whether there is a session.
abstract interface class AuthRepository {
  /// Emits on every session change. Replays the current value to new
  /// listeners, so a late subscriber is never left on [AuthUnknown].
  Stream<AuthStatus> get status;

  AuthStatus get current;

  /// Reads stored tokens and resolves the session. Safe to call before the
  /// first frame.
  Future<void> restore();

  /// Sends a six-digit code. Deliberately returns nothing useful about whether
  /// the address has an account — the server does not say, and neither do we.
  Future<EmailCodeChallenge> requestEmailCode(String email);

  Future<void> verifyEmailCode({required String email, required String code});

  Future<void> signInWith(SocialProvider provider);

  /// Changes how the user asks, and nothing else. Screen 1Q's row.
  ///
  /// Separate from [completeOnboarding], which writes this same field to this
  /// same document — because it *also* stamps `onboardedAt`. Reusing it from
  /// the profile would move "the date they finished onboarding" to "the date
  /// they last changed their mind about the microphone", quietly corrupting
  /// the one field the router's guard reads.
  ///
  /// No return value and no emit: this repository is already watching the
  /// document, so the new value reaches the screen through `SessionCubit` —
  /// the same path a change made on another device takes.
  Future<void> setInputPreference(InputPreference preference);

  /// Screen 1F.
  Future<void> completeOnboarding({
    String? name,
    InputPreference? inputPreference,
  });

  Future<void> signOut();

  /// Asks the server whether this session is still real, and ends it if not.
  ///
  /// Exists because a dead session is not self-announcing. Firebase refreshes
  /// its token roughly hourly, so a revoked or deleted account keeps working
  /// locally until that refresh happens to fall due — up to an hour of a user
  /// tapping through an app whose every write is being rejected.
  ///
  /// Call it wherever the server has just said "no": a `permission-denied`
  /// from Firestore, an `unauthenticated` from a callable, or on app resume,
  /// where a session may have been revoked while the phone was in a pocket.
  ///
  /// Distinguishes *refused* from *unreachable*. Offline is not signed out,
  /// and forcing a sign-out on a network blip is how you log people out on
  /// the underground.
  Future<bool> verifySession();
}

/// What the server will accept, and when.
typedef EmailCodeChallenge = ({Duration expiresIn, Duration resendIn});
