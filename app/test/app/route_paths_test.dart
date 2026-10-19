import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/auth/presentation/pages/email_address_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/how_you_ask_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/sign_in_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/verify_code_page.dart';
import 'package:knowra/src/features/billing/presentation/pages/paywall_page.dart';
import 'package:knowra/src/features/capture/presentation/pages/capture_page.dart';
import 'package:knowra/src/features/chat/presentation/pages/answer_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/choose_folders_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/connect_storage_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/index_progress_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/permissions_page.dart';
import 'package:knowra/src/features/connectors/presentation/pages/vault_ready_page.dart';
import 'package:knowra/src/features/memory/presentation/pages/library_page.dart';
import 'package:knowra/src/features/splash/presentation/pages/splash_page.dart';
import 'package:knowra/src/features/voice/presentation/pages/voice_home_page.dart';

/// QA-023. The splash and the home screen both declared `/`.
///
/// go_router returns the first registered match, so `/` always rendered the
/// splash — and the guard's redirect from splash to home became a redirect to
/// the location it was already on, which go_router treats as a no-op. The home
/// screen was unreachable.
///
/// The guard was never wrong: `guardFor` correctly returned `/`. The bug was
/// in route *registration*, which no test looked at. This is that test.
void main() {
  const paths = <String, String>{
    'SplashPage': SplashPage.routePath,
    'SignInPage': SignInPage.routePath,
    'EmailAddressPage': EmailAddressPage.routePath,
    'VerifyCodePage': VerifyCodePage.routePath,
    'HowYouAskPage': HowYouAskPage.routePath,
    'ConnectStoragePage': ConnectStoragePage.routePath,
    'ConnectStoragePage.manage': ConnectStoragePage.manageRoutePath,
    'PermissionsPage': PermissionsPage.routePath,
    'ChooseFoldersPage': ChooseFoldersPage.routePath,
    'IndexProgressPage': IndexProgressPage.routePath,
    'VaultReadyPage': VaultReadyPage.routePath,
    'VoiceHomePage': VoiceHomePage.routePath,
    'LibraryPage': LibraryPage.routePath,
    'CapturePage': CapturePage.routePath,
    'AnswerPage': AnswerPage.routePath,
    'PaywallPage': PaywallPage.routePath,
  };

  test('no two screens claim the same path', () {
    final byPath = <String, List<String>>{};
    paths.forEach((name, path) {
      byPath.putIfAbsent(path, () => []).add(name);
    });

    final clashes = byPath.entries.where((e) => e.value.length > 1).toList();
    expect(
      clashes,
      isEmpty,
      reason: clashes
          .map((e) => '${e.key} claimed by ${e.value.join(" and ")}')
          .join('; '),
    );
  });

  test('the home screen owns the root', () {
    // Not the splash. `/` is where a cold launch and every `go('/')` land, and
    // it has to be the screen the user is meant to end up on.
    expect(VoiceHomePage.routePath, '/');
    expect(SplashPage.routePath, isNot('/'));
  });

  test('every path is absolute and has no trailing slash', () {
    paths.forEach((name, path) {
      expect(path, startsWith('/'), reason: name);
      expect(path == '/' || !path.endsWith('/'), isTrue, reason: name);
    });
  });

  test('onboarding paths sit under the prefix the guard matches', () {
    // The guard decides "is this person mid-onboarding" with
    // `location.startsWith('/welcome')`. A step outside that prefix would be
    // redirected away from itself on every build.
    for (final path in [
      HowYouAskPage.routePath,
      ConnectStoragePage.routePath,
      PermissionsPage.routePath,
      ChooseFoldersPage.routePath,
      IndexProgressPage.routePath,
      VaultReadyPage.routePath,
    ]) {
      expect(path, startsWith('/welcome'), reason: path);
    }

    // And the manage route must NOT, or a signed-in user tapping the dock
    // would be bounced straight back to the home screen.
    expect(ConnectStoragePage.manageRoutePath, isNot(startsWith('/welcome')));
  });
}
