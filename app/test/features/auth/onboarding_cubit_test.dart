import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/bloc/onboarding_cubit.dart';

import '../../support/fake_auth.dart';

void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository());
  tearDown(() => repository.dispose());

  OnboardingCubit build() => OnboardingCubit(repository);

  test('voice is the default, per the design', () {
    expect(build().state.inputPreference, InputPreference.voice);
  });

  test('starts from the name the session already knows', () {
    // Apple hands back a display name on first authorisation; asking for it
    // again would look like the app was not paying attention.
    repository = FakeAuthRepository(
      initial: const AuthStatus.onboarding(testUser),
    );
    expect(build().state.name, 'Sam');
  });

  blocTest<OnboardingCubit, OnboardingState>(
    'submits the trimmed name and the chosen preference',
    build: build,
    act: (cubit) async {
      cubit.nameChanged('  Sam Kaur  ');
      cubit.preferenceChanged(InputPreference.typing);
      await cubit.submit();
    },
    verify: (_) {
      expect(repository.lastName, 'Sam Kaur');
      expect(repository.lastPreference, InputPreference.typing);
    },
  );

  blocTest<OnboardingCubit, OnboardingState>(
    'an empty name is sent as null rather than an empty string',
    build: build,
    act: (cubit) async {
      cubit.nameChanged('   ');
      await cubit.submit();
    },
    verify: (_) => expect(repository.lastName, isNull),
  );

  blocTest<OnboardingCubit, OnboardingState>(
    'a failure is surfaced and submission is released',
    build: build,
    act: (cubit) async {
      repository.failWith = const AppException.server();
      await cubit.submit();
    },
    verify: (cubit) {
      expect(cubit.state.exception, isA<ServerException>());
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.canSubmit, isTrue, reason: 'retry must be possible');
    },
  );
}
