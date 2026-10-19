import 'dart:async';

import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/auth/data/datasources/social_auth_gateway.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/domain/repositories/auth_repository.dart';

const testUser = AuthUser(id: 'u1', email: 'sam@northwind.co', name: 'Sam');

/// In-memory [AuthRepository] that records what it was asked to do.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthStatus initial = const AuthStatus.unauthenticated()})
    : _current = initial;

  final _controller = StreamController<AuthStatus>.broadcast();
  AuthStatus _current;

  /// Set to make the next call throw.
  AppException? failWith;

  final calls = <String>[];
  String? lastEmail;
  String? lastCode;
  String? lastName;
  InputPreference? lastPreference;
  Duration resendIn = const Duration(seconds: 60);

  /// What [verifySession] should report. Set false to simulate a session the
  /// server has refused.
  bool sessionIsValid = true;

  @override
  Future<bool> verifySession() async {
    calls.add('verifySession');
    if (!sessionIsValid) emit(const AuthStatus.unauthenticated());
    return sessionIsValid;
  }

  @override
  AuthStatus get current => _current;

  @override
  Stream<AuthStatus> get status async* {
    yield _current;
    yield* _controller.stream;
  }

  void emit(AuthStatus status) {
    _current = status;
    _controller.add(status);
  }

  void _record(String call) {
    calls.add(call);
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }

  @override
  Future<void> restore() async => _record('restore');

  @override
  Future<EmailCodeChallenge> requestEmailCode(String email) async {
    lastEmail = email;
    _record('requestEmailCode');
    return (expiresIn: const Duration(minutes: 10), resendIn: resendIn);
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    lastEmail = email;
    lastCode = code;
    _record('verifyEmailCode');
    emit(const AuthStatus.onboarding(testUser));
  }

  @override
  Future<void> signInWith(SocialProvider provider) async {
    _record('signInWith:${provider.name}');
    emit(const AuthStatus.authenticated(testUser));
  }

  @override
  Future<void> completeOnboarding({
    String? name,
    InputPreference? inputPreference,
  }) async {
    lastName = name;
    lastPreference = inputPreference;
    _record('completeOnboarding');
    emit(const AuthStatus.authenticated(testUser));
  }

  @override
  Future<void> setInputPreference(InputPreference preference) async {
    // Records without emitting: the real repository writes to Firestore and
    // lets its own snapshot listener deliver the change, so a fake that
    // emitted here would let a screen pass a test the product would fail.
    lastPreference = preference;
    _record('setInputPreference');
  }

  @override
  Future<void> signOut() async {
    _record('signOut');
    emit(const AuthStatus.unauthenticated());
  }

  Future<void> dispose() => _controller.close();
}

/// Gateway double: nothing touches a real provider SDK in tests.
class FakeSocialGateway implements SocialAuthGateway {
  FakeSocialGateway({
    this.available = const {SocialProvider.apple, SocialProvider.google},
    this.configured = const {SocialProvider.apple, SocialProvider.google},
  });

  final Set<SocialProvider> available;
  final Set<SocialProvider> configured;
  AppException? failWith;
  int signOutCount = 0;

  @override
  bool isAvailable(SocialProvider provider) => available.contains(provider);

  @override
  bool isConfigured(SocialProvider provider) => configured.contains(provider);

  @override
  Future<SocialCredential> authenticate(SocialProvider provider) async {
    final failure = failWith;
    if (failure != null) throw failure;
    return SocialCredential(
      provider: provider,
      identityToken: 'stub-token',
      nonce: 'stub-nonce',
    );
  }

  @override
  Future<void> signOut() async => signOutCount++;
}
