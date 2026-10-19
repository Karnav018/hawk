import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/bloc/sign_in_cubit.dart';

import '../../support/fake_auth.dart';

void main() {
  late FakeAuthRepository repository;
  late FakeSocialGateway gateway;

  setUp(() {
    repository = FakeAuthRepository();
    gateway = FakeSocialGateway();
  });
  tearDown(() => repository.dispose());

  SignInCubit build() => SignInCubit(repository, gateway);

  blocTest<SignInCubit, SignInState>(
    'shows a spinner on the provider that is actually running',
    build: build,
    act: (cubit) => cubit.signInWith(SocialProvider.apple),
    expect: () => [
      const SignInState.submitting(SocialProvider.apple),
      const SignInState.idle(),
    ],
    verify: (_) => expect(repository.calls, contains('signInWith:apple')),
  );

  blocTest<SignInCubit, SignInState>(
    'backing out of the provider sheet is not an error',
    build: () {
      // The repository owns the exchange; the gateway is only consulted for
      // availability, so this is where a cancellation surfaces from.
      repository.failWith = const AppException.cancelled();
      return build();
    },
    act: (cubit) => cubit.signInWith(SocialProvider.google),
    expect: () => [
      const SignInState.submitting(SocialProvider.google),
      // Straight back to idle: no error message for a deliberate act.
      const SignInState.idle(),
    ],
  );

  blocTest<SignInCubit, SignInState>(
    'a real failure is surfaced',
    build: () {
      repository.failWith = const AppException.network();
      return build();
    },
    act: (cubit) => cubit.signInWith(SocialProvider.google),
    expect: () => [
      const SignInState.submitting(SocialProvider.google),
      const SignInState.failure(AppException.network()),
    ],
  );

  blocTest<SignInCubit, SignInState>(
    'a second tap while one is in flight is ignored',
    build: build,
    act: (cubit) async {
      final first = cubit.signInWith(SocialProvider.apple);
      await cubit.signInWith(SocialProvider.google);
      await first;
    },
    verify: (_) {
      expect(repository.calls, ['signInWith:apple']);
    },
  );

  test('providers the device cannot offer are reported unavailable', () {
    gateway = FakeSocialGateway(available: const {SocialProvider.google});
    final cubit = build();
    expect(cubit.isAvailable(SocialProvider.apple), isFalse);
    expect(cubit.isAvailable(SocialProvider.google), isTrue);
  });
}
