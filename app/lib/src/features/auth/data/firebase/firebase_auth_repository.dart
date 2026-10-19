import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/cache/cache_store.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/social_auth_gateway.dart';

/// [AuthRepository] backed by Firebase.
///
/// Implements the same interface the REST version did, which is why the
/// domain, the cubits, the screens, the router guard and their tests did not
/// change: everything above this line only ever knew about `AuthRepository`.
///
/// Three things get simpler here, and one gets harder.
///
/// Simpler: tokens are the SDK's problem, so the secure token store and the
/// Dio refresh interceptor are gone entirely; the session
/// survives a restart without a `restore()` round trip; and tenancy is
/// enforced by security rules rather than by remembering a `where` clause.
///
/// Harder: the six-digit email code does not exist in Firebase Auth. It is
/// implemented as a callable function that mints a *custom token*, which the
/// client exchanges for an ordinary session — so the design survives, at the
/// cost of one function we own.
@LazySingleton(as: AuthRepository)
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._auth,
    this._firestore,
    this._functions,
    this._social,
    this._cache,
    this._logger,
  ) {
    _subscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final SocialAuthGateway _social;
  final CacheStore _cache;
  final AppLogger _logger;

  final _controller = StreamController<AuthStatus>.broadcast();
  late final StreamSubscription<fb.User?> _subscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profile;

  AuthStatus _current = const AuthStatus.unknown();

  @override
  AuthStatus get current => _current;

  @override
  Stream<AuthStatus> get status async* {
    yield _current;
    yield* _controller.stream;
  }

  void _emit(AuthStatus next) {
    if (next == _current) return;
    _current = next;
    _controller.add(next);
  }

  /// Firebase restores the session itself before the first auth event, so
  /// there is nothing to do here but wait for that event.
  ///
  /// Kept on the interface because the splash screen hands it to `readyWhen`
  /// — the brand moment is exactly the window this resolves in.
  @override
  Future<void> restore() async {
    if (_current is! AuthUnknown) return;
    await _auth.authStateChanges().first.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  Future<void> _onAuthStateChanged(fb.User? user) async {
    await _profile?.cancel();
    _profile = null;

    // The cache is keyed by user id, and this is the one place that knows who
    // that is. Binding here rather than at each call site means a repository
    // can never read a cache belonging to nobody — an unbound store misses
    // every read by construction.
    _cache.bindUser(user?.uid);

    if (user == null) {
      await _logger.setUser();
      _emit(const AuthStatus.unauthenticated());
      return;
    }

    await _logger.setUser(id: user.uid, email: user.email);

    // Watched rather than read once: the onboarding flag is written by screen
    // 3J and by a Cloud Function on account creation, and the guard has to
    // move the moment either lands.
    _profile = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            // No profile document means the server-side seed has not run.
            // On a project with Identity Platform the blocking
            // `beforeUserCreated` trigger has already made one and this branch
            // is never taken; without it, Firebase Auth silently never calls
            // that trigger, and somebody would sign in to an account with no
            // entitlements at all.
            //
            // Asking for it here rather than on every auth change means the
            // round trip is paid only when there is genuinely nothing, and the
            // listener then fires again on its own with the seeded document —
            // no second read, no explicit emit.
            if (!snapshot.exists) {
              unawaited(_ensureProfile(user.uid));
            }
            _emit(_statusFrom(user, snapshot.data()));
          },
          onError: (Object error) {
            _logger.warning('Profile stream failed', name: 'auth');

            // `permission-denied` on your *own* profile means the token was
            // refused, not that the rules are wrong — this document is
            // readable by its owner and by nobody else. Worth the round trip
            // to find out which, because the alternative is leaving somebody
            // inside an app that will reject every write they make.
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              unawaited(verifySession());
            }

            // Meanwhile, hold the session. Offline is not signed out, and if
            // the check above does find a dead session it emits on its own.
            _emit(AuthStatus.onboarding(_userFrom(user, null)));
          },
        );
  }

  /// Guards against re-asking while the first request is still in flight —
  /// the snapshot listener can fire more than once before the seed lands.
  final _seeding = <String>{};

  Future<void> _ensureProfile(String uid) async {
    if (!_seeding.add(uid)) return;
    try {
      await _functions.httpsCallable('ensure_profile').call<Object?>();
      _logger.breadcrumb('profile seeded', category: 'auth');
    } on FirebaseFunctionsException catch (error) {
      _seeding.remove(uid);
      if (error.code == 'unauthenticated') {
        // The server does not believe this caller. That is the same signal as
        // a refused Firestore read, arriving through a different door.
        unawaited(verifySession());
        return;
      }
      // Otherwise not fatal, and deliberately not surfaced: the app already
      // renders a missing profile as "needs onboarding", and screen 3J writes
      // the document itself — so this costs the entitlements row, not the
      // session.
      _logger.warning('Could not seed profile', name: 'auth');
    } catch (error) {
      _logger.warning('Could not seed profile', name: 'auth');
      _seeding.remove(uid);
    }
  }

  AuthStatus _statusFrom(fb.User user, Map<String, dynamic>? data) {
    final profile = _userFrom(user, data);
    return profile.needsOnboarding
        ? AuthStatus.onboarding(profile)
        : AuthStatus.authenticated(profile);
  }

  AuthUser _userFrom(fb.User user, Map<String, dynamic>? data) => AuthUser(
    id: user.uid,
    // Apple's Hide My Email means the Firebase email can be a relay address;
    // it is still the stable identifier we address people by.
    email: data?['email'] as String? ?? user.email ?? '',
    name: data?['name'] as String? ?? user.displayName,
    inputPreference: InputPreference.parse(data?['inputPreference'] as String?),
    onboardedAt: (data?['onboardedAt'] as Timestamp?)?.toDate(),
    storageSetupAt: (data?['storageSetupAt'] as Timestamp?)?.toDate(),
  );

  // ------------------------------------------------------------- email ----

  @override
  Future<EmailCodeChallenge> requestEmailCode(
    String email,
  ) => _guard('requestEmailCode', () async {
    final result = await _functions
        .httpsCallable('request_email_code')
        .call<Map<String, dynamic>>({'email': email.trim().toLowerCase()});

    final data = result.data;
    return (
      expiresIn: Duration(seconds: (data['expiresIn'] as num?)?.toInt() ?? 600),
      resendIn: Duration(seconds: (data['resendIn'] as num?)?.toInt() ?? 60),
    );
  });

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) => _guard('verifyEmailCode', () async {
    final result = await _functions
        .httpsCallable('verify_email_code')
        .call<Map<String, dynamic>>({
          'email': email.trim().toLowerCase(),
          'code': code,
        });

    // The custom token is what turns our own code check into a real Firebase
    // session — from here on the client holds an ordinary ID token.
    await _auth.signInWithCustomToken(result.data['token'] as String);
  });

  // ------------------------------------------------------------ social ----

  @override
  Future<void> signInWith(SocialProvider provider) =>
      _guard('signInWith:${provider.name}', () async {
        final credential = await _social.authenticate(provider);

        final firebaseCredential = switch (provider) {
          SocialProvider.google => fb.GoogleAuthProvider.credential(
            idToken: credential.identityToken,
          ),
          SocialProvider.apple => fb.OAuthProvider('apple.com').credential(
            idToken: credential.identityToken,
            // Firebase re-derives the hash and compares, so it needs the raw
            // nonce rather than the SHA-256 we handed Apple.
            rawNonce: credential.rawNonce,
          ),
        };

        final result = await _auth.signInWithCredential(firebaseCredential);

        // Apple returns a display name exactly once, on first authorisation,
        // and never again. If it is not persisted now it is gone for good.
        final name = credential.name;
        final isNew = result.additionalUserInfo?.isNewUser ?? false;
        if (isNew && name != null && name.isNotEmpty) {
          await _firestore.collection('users').doc(result.user!.uid).set({
            'name': name,
          }, SetOptions(merge: true));
        }
      });

  // -------------------------------------------------------- onboarding ----

  @override
  Future<void> setInputPreference(InputPreference preference) =>
      _guard('setInputPreference', () async {
        final user = _auth.currentUser;
        if (user == null) throw const AppException.unauthorized();

        // `set(merge:)` rather than `update()`: the profile document is
        // seeded by a Cloud Function on account creation, and on a project
        // without the blocking trigger that seed can still be in flight.
        // `update()` throws `not-found` on a document that does not exist
        // yet, turning a race into a failed setting; a merging set creates
        // it and the seed fills the rest in afterwards.
        //
        // A client write by design rather than by omission: `firestore.rules`
        // lets the owner write exactly `name`, `inputPreference`,
        // `onboardedAt` and `updatedAt`, and pins this field to `voice` or
        // `typing`. There is no server logic to run, so a callable would be a
        // round trip to set a string the rules already validate.
        await _firestore.collection('users').doc(user.uid).set({
          'inputPreference': preference.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // No explicit emit: the profile stream is watching this document, so
        // the change arrives as a consequence of the write rather than
        // alongside it.
      });

  @override
  Future<void> completeOnboarding({
    String? name,
    InputPreference? inputPreference,
  }) => _guard('completeOnboarding', () async {
    final user = _auth.currentUser;
    if (user == null) throw const AppException.unauthorized();

    await _firestore.collection('users').doc(user.uid).set({
      'name': ?name,
      'inputPreference': ?inputPreference?.name,
      'onboardedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // No explicit emit: the profile stream is watching this document, so the
    // status changes as a consequence of the write rather than alongside it.
  });

  /// Auth error codes that mean the session is genuinely finished.
  ///
  /// Everything else — `network-request-failed` above all — is a reason to
  /// keep the session, not to end it.
  static const _deadSession = {
    'user-token-expired',
    'user-disabled',
    'user-not-found',
    'invalid-user-token',
    'requires-recent-login',
  };

  @override
  Future<bool> verifySession() async {
    final user = _auth.currentUser;
    if (user == null) {
      _emit(const AuthStatus.unauthenticated());
      return false;
    }

    try {
      // force: true is the entire point — the cached token is exactly the
      // thing we do not trust. This round-trips to Google, which is why it is
      // called on a signal rather than on a timer.
      await user.getIdToken(true);
      return true;
    } on fb.FirebaseAuthException catch (error) {
      if (_deadSession.contains(error.code)) {
        _logger.info(
          'Session ended by the server',
          name: 'auth',
          data: {'code': error.code},
        );
        // signOut() rather than emitting directly: it clears the cache and the
        // social gateway too, and the auth stream then emits unauthenticated
        // on its own. One path out of a session, not two.
        await signOut();
        return false;
      }
      // A refusal we do not recognise is not proof of a dead session.
      _logger.warning(
        'Session check inconclusive',
        name: 'auth',
        data: {'code': error.code},
      );
      return true;
    } catch (_) {
      // Offline. The session is fine; we just cannot ask right now.
      return true;
    }
  }

  @override
  Future<void> signOut() async {
    // Cleared before the sign-out, while the store is still bound to this
    // user — afterwards `bindUser(null)` makes `clear()` a no-op and their
    // folder names would sit on disk until the next person happened to
    // overwrite them.
    await _cache.clear();
    await _social.signOut();
    await _auth.signOut();
  }

  Future<T> _guard<T>(String name, Future<T> Function() body) async {
    _logger.breadcrumb(name, category: 'auth');
    try {
      return await body();
    } on fb.FirebaseAuthException catch (error, stackTrace) {
      throw _mapAuthError(error, stackTrace);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _mapFunctionsError(error, stackTrace);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw AppException.unknown(cause: error, stackTrace: stackTrace);
    }
  }

  /// Firebase's codes are strings; the app speaks `AppException`.
  static AppException _mapAuthError(
    fb.FirebaseAuthException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'network-request-failed' => const AppException.network(),
    'too-many-requests' => const AppException.badRequest(
      message: 'Too many attempts. Try again in a few minutes.',
    ),
    'user-disabled' => const AppException.unauthorized(
      message: 'That account is no longer active.',
    ),
    'invalid-custom-token' ||
    'custom-token-mismatch' ||
    'invalid-credential' => const AppException.unauthorized(
      message: 'That sign-in could not be verified.',
    ),
    'account-exists-with-different-credential' => const AppException.badRequest(
      message: 'That email is already signed in with another provider.',
    ),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  static AppException _mapFunctionsError(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthenticated' => AppException.unauthorized(
      message: error.message ?? 'That code is not valid.',
    ),
    'invalid-argument' => AppException.badRequest(
      message: error.message ?? 'That request was not valid.',
    ),
    'resource-exhausted' => const AppException.badRequest(
      message: 'Too many attempts. Try again shortly.',
    ),
    'unavailable' || 'deadline-exceeded' => const AppException.network(),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  @visibleForTesting
  Future<void> dispose() async {
    await _subscription.cancel();
    await _profile?.cancel();
    await _controller.close();
  }
}
