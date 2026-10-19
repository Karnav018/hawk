import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/bloc/email_sign_in_cubit.dart';
import 'package:knowra/src/features/auth/presentation/bloc/onboarding_cubit.dart';

import '../../support/fake_auth.dart';

void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository()..resendIn = Duration.zero);
  tearDown(() => repository.dispose());

  group('when the message appears', () {
    test('nothing is shown while you are still typing', () {
      final cubit = EmailSignInCubit(repository);

      // Telling someone their address is invalid at the second character is
      // noise, not help.
      for (final partial in ['s', 'sa', 'sam', 'sam@', 'sam@north']) {
        cubit.emailChanged(partial);
        expect(cubit.state.emailError, isNull, reason: partial);
      }
    });

    test('the message appears once focus leaves the field', () {
      final cubit = EmailSignInCubit(repository)..emailChanged('sam@north');
      expect(cubit.state.emailError, isNull);

      cubit.emailBlurred();
      expect(cubit.state.emailError, isNotNull);
    });

    test('typing again clears the stale message', () {
      final cubit = EmailSignInCubit(repository)
        ..emailChanged('sam@north')
        ..emailBlurred();
      expect(cubit.state.emailError, isNotNull);

      cubit.emailChanged('sam@northwind.co');
      expect(cubit.state.emailError, isNull);
    });

    blocTest<EmailSignInCubit, EmailSignInState>(
      'submitting an invalid address surfaces the message instead of failing '
      'silently',
      build: () => EmailSignInCubit(repository),
      act: (cubit) async {
        cubit.emailChanged('sam@north');
        await cubit.sendCode();
      },
      verify: (cubit) {
        expect(cubit.state.emailError, isNotNull);
        expect(
          repository.calls,
          isNot(contains('requestEmailCode')),
          reason: 'nothing should reach the network',
        );
      },
    );
  });

  group('typo suggestion', () {
    test('offered for a valid address with a likely-wrong domain', () {
      final cubit = EmailSignInCubit(repository)..emailChanged('sam@gmial.com');

      // Valid, so no error — but almost certainly not what they meant.
      expect(cubit.state.emailError, isNull);
      expect(cubit.state.emailSuggestion, 'sam@gmail.com');
    });

    test('accepting it rewrites the field', () {
      final cubit = EmailSignInCubit(repository)
        ..emailChanged('sam@gmial.com')
        ..acceptEmailSuggestion();

      expect(cubit.state.email, 'sam@gmail.com');
      expect(cubit.state.emailSuggestion, isNull);
    });

    test('never blocks sending — it is advice, not a rule', () async {
      final cubit = EmailSignInCubit(repository)..emailChanged('sam@gmial.com');

      await cubit.sendCode();
      expect(repository.calls, contains('requestEmailCode'));
    });
  });

  group('code', () {
    blocTest<EmailSignInCubit, EmailSignInState>(
      'a short code never reaches the network',
      build: () => EmailSignInCubit(repository),
      act: (cubit) async {
        cubit.codeChanged('4193');
        await cubit.verify();
      },
      verify: (_) =>
          expect(repository.calls, isNot(contains('verifyEmailCode'))),
    );
  });

  group('display name', () {
    test('an empty name is fine and submits', () async {
      final cubit = OnboardingCubit(repository)..nameChanged('');
      expect(cubit.state.canSubmit, isTrue);

      await cubit.submit();
      expect(repository.calls, contains('completeOnboarding'));
    });

    test('a link is refused and never submitted', () async {
      final cubit = OnboardingCubit(repository)
        ..nameChanged('http://spam.example');

      expect(cubit.state.canSubmit, isFalse);
      await cubit.submit();

      expect(cubit.state.nameError, isNotNull);
      expect(repository.calls, isNot(contains('completeOnboarding')));
    });

    test('names that trip naive ASCII rules are accepted', () async {
      for (final name in ["O'Brien", '李雷', 'María José', 'Jean-Luc']) {
        final cubit = OnboardingCubit(repository)..nameChanged(name);
        expect(cubit.state.canSubmit, isTrue, reason: name);
      }
    });

    test('preference still defaults to voice', () {
      expect(
        OnboardingCubit(repository).state.inputPreference,
        InputPreference.voice,
      );
    });
  });
}
