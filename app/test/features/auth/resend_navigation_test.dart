import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/auth/presentation/bloc/email_sign_in_cubit.dart';

import '../../support/fake_auth.dart';

/// QA-001. Screen 3H navigates on the `codeSent` false -> true edge.
///
/// `codeSent` was only ever raised, never lowered — so going 3H -> 3I -> back
/// -> "Send code" re-sent the code and left the user on the address screen,
/// with no error and nothing to retry. The edge has to be re-armed.
void main() {
  test('a second send re-arms the navigation edge', () async {
    final auth = FakeAuthRepository();
    final cubit = EmailSignInCubit(auth);

    cubit.emailChanged('sam@northwind.co');
    await cubit.sendCode();
    expect(cubit.state.codeSent, isTrue, reason: 'first send navigates');

    // Coming back from 3I. The page is rebuilt; the cubit survives in the
    // shell, still latched.
    final transitions = <bool>[];
    final sub = cubit.stream.listen((s) => transitions.add(s.codeSent));

    await cubit.sendCode();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // The false is what 3H's listenWhen needs to see before the true.
    expect(
      transitions,
      containsAllInOrder([false, true]),
      reason: 'without the lowered edge the page never navigates again',
    );
    expect(cubit.state.codeSent, isTrue);
  });
}
