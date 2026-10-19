import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/presentation/widgets/session_watcher.dart';

import '../../support/fake_auth.dart';

void main() {
  group('SessionWatcher', () {
    Future<void> pump(WidgetTester tester, FakeAuthRepository auth) =>
        tester.pumpWidget(
          SessionWatcher(
            auth: auth,
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(),
            ),
          ),
        );

    testWidgets('checks the session when the app is resumed', (tester) async {
      final auth = FakeAuthRepository(
        initial: const AuthStatus.authenticated(testUser),
      );
      await pump(tester, auth);
      expect(auth.calls, isEmpty, reason: 'nothing to check on first build');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(auth.calls, contains('verifySession'));
    });

    testWidgets('ignores inactive, which fires far too often', (tester) async {
      // `inactive` arrives for a notification-shade pull and for the OAuth
      // sheet opening over the app. Checking there would mean a token round
      // trip every time somebody glanced at a notification.
      final auth = FakeAuthRepository(
        initial: const AuthStatus.authenticated(testUser),
      );
      await pump(tester, auth);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      expect(auth.calls, isEmpty);
    });

    testWidgets('a refused session ends up unauthenticated', (tester) async {
      final auth = FakeAuthRepository(
        initial: const AuthStatus.authenticated(testUser),
      )..sessionIsValid = false;
      await pump(tester, auth);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // The watcher never navigates. It changes the session; the router guard
      // moves them — the same rule every screen follows.
      expect(auth.current, isA<AuthUnauthenticated>());
    });

    testWidgets('a valid session is left alone', (tester) async {
      final auth = FakeAuthRepository(
        initial: const AuthStatus.authenticated(testUser),
      );
      await pump(tester, auth);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(auth.current, isA<AuthAuthenticated>());
    });

    testWidgets(
      'detaches its observer, so a rebuilt tree does not double-check',
      (tester) async {
        final auth = FakeAuthRepository(
          initial: const AuthStatus.authenticated(testUser),
        );
        await pump(tester, auth);
        await tester.pumpWidget(const SizedBox());

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(auth.calls, isEmpty);
      },
    );
  });

  group('the guard sends an ended session to sign-in', () {
    test('unauthenticated is redirected from anywhere in the app', () {
      // The whole point of routing session loss through `AuthStatus` rather
      // than through a Navigator call: it does not matter which screen the
      // user was on when the server refused them.
      final auth = FakeAuthRepository(
        initial: const AuthStatus.authenticated(testUser),
      )..sessionIsValid = false;

      expect(auth.current, isA<AuthAuthenticated>());
      auth.verifySession();
      expect(auth.current, isA<AuthUnauthenticated>());
    });
  });
}
