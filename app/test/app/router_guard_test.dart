import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/router/app_router.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/pages/email_address_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/how_you_ask_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/sign_in_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/verify_code_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/connect_storage_page.dart';
import 'package:knowra/src/features/memory/presentation/pages/library_page.dart';
import 'package:knowra/src/features/splash/presentation/pages/splash_page.dart';
import 'package:knowra/src/features/voice/presentation/pages/voice_home_page.dart';

import '../support/fake_auth.dart';

/// The guard's decision table.
///
/// This calls `AppRouter.guardFor` rather than re-stating it. It used to hold
/// a copy of the policy, which passed cheerfully while the real guard grew a
/// second onboarding step — exactly the drift the test existed to catch.
String? guard({
  required AuthStatus status,
  required String location,
  required bool splashComplete,
}) => AppRouter.guardFor(
  status: status,
  location: location,
  splashComplete: splashComplete,
);

void main() {
  group('while the splash is running', () {
    test('nobody is moved, whatever the session turns out to be', () {
      for (final status in const [
        AuthStatus.unknown(),
        AuthStatus.unauthenticated(),
        AuthStatus.authenticated(testUser),
      ]) {
        expect(
          guard(
            status: status,
            location: SplashPage.routePath,
            splashComplete: false,
          ),
          isNull,
          reason: 'the launch animation must not be cut short',
        );
      }
    });
  });

  group('signed out', () {
    test('is sent to sign-in from anywhere else', () {
      expect(
        guard(
          status: const AuthStatus.unauthenticated(),
          location: LibraryPage.routePath,
          splashComplete: true,
        ),
        SignInPage.routePath,
      );
    });

    test('is left alone anywhere in the sign-in flow', () {
      for (final location in [
        SignInPage.routePath,
        EmailAddressPage.routePath,
        VerifyCodePage.routePath,
      ]) {
        expect(
          guard(
            status: const AuthStatus.unauthenticated(),
            location: location,
            splashComplete: true,
          ),
          isNull,
          reason: location,
        );
      }
    });
  });

  group('mid-onboarding', () {
    test('cannot skip ahead into the app', () {
      expect(
        guard(
          status: const AuthStatus.onboarding(testUser),
          location: LibraryPage.routePath,
          splashComplete: true,
        ),
        HowYouAskPage.routePath,
      );
    });

    test('cannot fall back into sign-in', () {
      expect(
        guard(
          status: const AuthStatus.onboarding(testUser),
          location: SignInPage.routePath,
          splashComplete: true,
        ),
        HowYouAskPage.routePath,
      );
    });
  });

  group('signed in', () {
    test('is bounced out of the sign-in flow and onboarding', () {
      for (final location in [
        SignInPage.routePath,
        VerifyCodePage.routePath,
        HowYouAskPage.routePath,
        SplashPage.routePath,
      ]) {
        expect(
          guard(
            status: const AuthStatus.authenticated(testUser),
            location: location,
            splashComplete: true,
          ),
          VoiceHomePage.routePath,
          reason: location,
        );
      }
    });

    test('is left alone inside the app', () {
      expect(
        guard(
          status: const AuthStatus.authenticated(testUser),
          location: LibraryPage.routePath,
          splashComplete: true,
        ),
        isNull,
      );
    });
  });

  test('an unresolved session parks on the splash', () {
    expect(
      guard(
        status: const AuthStatus.unknown(),
        location: LibraryPage.routePath,
        splashComplete: true,
      ),
      SplashPage.routePath,
    );
  });

  _onboardingRun();
}

/// Onboarding became a run of screens (3J → 3F → 3G → 3K → 3L → 3M) rather
/// than one, so the guard has to know which step is outstanding. These are the
/// transitions that used to be a single `if`.
void _onboardingRun() {
  const named = AuthUser(id: 'u', email: 'a@b.co', name: 'Sam');
  final namedAt = DateTime(2026, 8, 29);

  AuthStatus onboarding({DateTime? onboardedAt, DateTime? storageSetupAt}) =>
      AuthStatus.onboarding(
        named.copyWith(
          onboardedAt: onboardedAt,
          storageSetupAt: storageSetupAt,
        ),
      );

  group('the onboarding run', () {
    test('starts at the name screen', () {
      expect(
        guard(
          status: onboarding(),
          location: LibraryPage.routePath,
          splashComplete: true,
        ),
        HowYouAskPage.routePath,
      );
    });

    test('moves to storage the moment the name is recorded', () {
      // The handoff. 3J writes `onboardedAt`, the user document stream fires,
      // the guard re-evaluates, and the redirect that was holding them on the
      // name screen now pushes them forward instead.
      expect(
        guard(
          status: onboarding(onboardedAt: namedAt),
          location: HowYouAskPage.routePath,
          splashComplete: true,
        ),
        ConnectStoragePage.routePath,
      );
    });

    test('does not drag anyone back to a step they have finished', () {
      expect(
        guard(
          status: onboarding(onboardedAt: namedAt),
          location: '/welcome/folders/acct-1',
          splashComplete: true,
        ),
        isNull,
        reason: 'mid-run screens must be allowed to hold the screen',
      );
    });

    test(
      're-entering from outside lands on the outstanding step, not the first',
      () {
        expect(
          guard(
            status: onboarding(onboardedAt: namedAt),
            location: LibraryPage.routePath,
            splashComplete: true,
          ),
          ConnectStoragePage.routePath,
        );
      },
    );

    test('skipping storage ends the run as firmly as connecting does', () {
      // `complete_storage_setup` stamps `storageSetupAt` whether the user
      // connected or skipped, which is what stops a device-only user being
      // parked on 3F forever.
      final done = named.copyWith(
        onboardedAt: namedAt,
        storageSetupAt: namedAt,
      );
      expect(done.needsOnboarding, isFalse);
      expect(
        guard(
          status: AuthStatus.authenticated(done),
          location: ConnectStoragePage.routePath,
          splashComplete: true,
        ),
        VoiceHomePage.routePath,
      );
    });

    test('the manage route is not part of the run', () {
      // `/storage` is the same screen reached from the vault dock. It must
      // not be swept up by the `/welcome` prefix, or a signed-in user tapping
      // it would be bounced straight back to the library.
      final done = named.copyWith(
        onboardedAt: namedAt,
        storageSetupAt: namedAt,
      );
      expect(
        guard(
          status: AuthStatus.authenticated(done),
          location: ConnectStoragePage.manageRoutePath,
          splashComplete: true,
        ),
        isNull,
      );
    });
  });
}
