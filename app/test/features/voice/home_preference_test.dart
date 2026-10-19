import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/voice/presentation/pages/home_page.dart';

import '../../support/fake_auth.dart';

/// The product's headline promise, and the one thing screen 1F exists to set:
///
/// > *"if user select voice for searching in the onboarding, home screen
/// > gets centre orb screen, if user select chat based than it shows chat
/// > screen to start."*
///
/// Asserted against [HomePage.faceFor] rather than by pumping the screen:
/// everything around the decision — the orb, the ask bar, the greeting's
/// memory count — needs half the injector to render, and none of it has any
/// bearing on which face is correct. Testing the widget would mostly be
/// testing the fakes.
AuthStatus _signedIn(InputPreference preference) =>
    AuthStatus.authenticated(testUser.copyWith(inputPreference: preference));

void main() {
  test('answering "Speak" on 1F opens the orb', () {
    expect(
      HomePage.faceFor(_signedIn(InputPreference.voice)),
      InputPreference.voice,
    );
  });

  test('answering "Type" on 1F opens the chat face', () {
    // v2 had no equivalent decision: home was the orb for everybody, so
    // somebody who answered "typing" got a voice screen with a text box.
    expect(
      HomePage.faceFor(_signedIn(InputPreference.typing)),
      InputPreference.typing,
    );
  });

  test('the preference survives the onboarding half of the session', () {
    // 1F completes while the session is still `AuthOnboarding`, and home is
    // reachable from there through the guard.
    expect(
      HomePage.faceFor(
        AuthStatus.onboarding(
          testUser.copyWith(inputPreference: InputPreference.typing),
        ),
      ),
      InputPreference.typing,
    );
  });

  test('a choice made on the screen outranks the stored preference', () {
    // The tabs are "how I want to ask right now"; 1F is "what home opens
    // to". Switching must not be undone by the next rebuild.
    expect(
      HomePage.faceFor(
        _signedIn(InputPreference.voice),
        InputPreference.typing,
      ),
      InputPreference.typing,
    );
  });

  test('an unresolved session falls through to voice without pinning it', () {
    // The distinction that matters: falling through is not the same as
    // *choosing*. A cold start shows the orb, and the moment the session
    // arrives with `typing` the face changes — which only works because the
    // fallback is computed each build rather than seeded once.
    expect(HomePage.faceFor(const AuthStatus.unknown()), InputPreference.voice);
    expect(
      HomePage.faceFor(const AuthStatus.unauthenticated()),
      InputPreference.voice,
    );
  });
}
