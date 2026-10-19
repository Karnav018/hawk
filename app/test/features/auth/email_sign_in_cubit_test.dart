import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/auth/presentation/bloc/email_sign_in_cubit.dart';

import '../../support/fake_auth.dart';

void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository());
  tearDown(() => repository.dispose());

  EmailSignInCubit build() => EmailSignInCubit(repository);

  group('address', () {
    test('obvious rubbish cannot be sent', () {
      final cubit = build();
      for (final bad in ['', 'sam', 'sam@', 'sam@northwind', 'sam@co.']) {
        cubit.emailChanged(bad);
        expect(cubit.state.canSend, isFalse, reason: bad);
      }
      cubit.emailChanged('sam@northwind.co');
      expect(cubit.state.canSend, isTrue);
    });

    blocTest<EmailSignInCubit, EmailSignInState>(
      'sending normalises the address and opens the code step',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('  Sam@Northwind.CO ');
        await cubit.sendCode();
      },
      verify: (cubit) {
        expect(repository.calls, contains('requestEmailCode'));
        expect(
          repository.lastEmail,
          'sam@northwind.co',
          reason:
              'the server keys challenges by address; casing must not fork them',
        );
        expect(cubit.state.codeSent, isTrue);
        expect(cubit.state.resendIn, 60);
      },
    );

    blocTest<EmailSignInCubit, EmailSignInState>(
      'a failure surfaces and does not open the code step',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('sam@northwind.co');
        repository.failWith = const AppException.network();
        await cubit.sendCode();
      },
      verify: (cubit) {
        expect(cubit.state.exception, isA<NetworkException>());
        expect(cubit.state.codeSent, isFalse);
        expect(cubit.state.isSending, isFalse);
      },
    );
  });

  group('code', () {
    test('non-digits are dropped and the length is capped', () {
      final cubit = build();
      cubit.codeChanged('4a1-9 3 7 2 9');
      expect(cubit.state.code, '419372');
      expect(cubit.state.isCodeComplete, isTrue);
    });

    blocTest<EmailSignInCubit, EmailSignInState>(
      'a complete code is verified against the address that was sent',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('sam@northwind.co');
        await cubit.sendCode();
        cubit.codeChanged('419372');
        await cubit.verify();
      },
      verify: (cubit) {
        expect(repository.lastCode, '419372');
        expect(repository.lastEmail, 'sam@northwind.co');
      },
    );

    blocTest<EmailSignInCubit, EmailSignInState>(
      'an incomplete code is not sent',
      build: build,
      act: (cubit) async {
        cubit.codeChanged('4193');
        await cubit.verify();
      },
      verify: (cubit) =>
          expect(repository.calls, isNot(contains('verifyEmailCode'))),
    );

    blocTest<EmailSignInCubit, EmailSignInState>(
      'a rejected code clears the field so the retry starts clean',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('sam@northwind.co');
        cubit.codeChanged('000000');
        repository.failWith = const AppException.unauthorized();
        await cubit.verify();
      },
      verify: (cubit) {
        expect(cubit.state.code, isEmpty);
        expect(cubit.state.exception, isA<UnauthorizedException>());
      },
    );
  });

  group('resend', () {
    blocTest<EmailSignInCubit, EmailSignInState>(
      'is locked out until the countdown expires',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('sam@northwind.co');
        repository.resendIn = const Duration(seconds: 3);
        await cubit.sendCode();
      },
      // No wall-clock wait, and no assertion that the counter has ticked.
      //
      // It waited 1100ms for a 1-second tick and then asserted the number had
      // moved, which is a race the whole suite loses occasionally: under load
      // the isolate is starved and the tick lands late. The contract this
      // test is for is the *lockout* — you cannot resend while a countdown is
      // running — and that holds from the first frame, no timer required.
      // Whether the counter counts is the next test's job.
      verify: (cubit) {
        expect(cubit.state.canResend, isFalse);
        expect(cubit.state.resendIn, greaterThan(0));
      },
    );

    blocTest<EmailSignInCubit, EmailSignInState>(
      'unlocks once the countdown reaches zero',
      build: build,
      act: (cubit) async {
        cubit.emailChanged('sam@northwind.co');
        repository.resendIn = const Duration(seconds: 1);
        await cubit.sendCode();
      },
      wait: const Duration(milliseconds: 1400),
      verify: (cubit) {
        expect(cubit.state.resendIn, 0);
        expect(cubit.state.canResend, isTrue);
      },
    );
  });
}
