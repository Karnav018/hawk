import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/auth/presentation/bloc/email_sign_in_cubit.dart';
import 'package:knowra/src/features/auth/presentation/pages/email_address_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/sign_in_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/verify_code_page.dart';

import '../../support/fake_auth.dart';

const signInKey = Key('sign-in-stub');

/// The two email screens under a real router, so `push` and `pop` behave the
/// way they do in the app.
Widget _host(EmailSignInCubit cubit) {
  final router = GoRouter(
    initialLocation: EmailAddressPage.routePath,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            BlocProvider.value(value: cubit, child: child),
        routes: [
          // The address screen's fallback target, so an empty back stack has
          // somewhere real to land.
          GoRoute(
            path: SignInPage.routePath,
            name: SignInPage.routeName,
            builder: (context, state) => const Scaffold(key: signInKey),
          ),
          GoRoute(
            path: EmailAddressPage.routePath,
            name: EmailAddressPage.routeName,
            builder: (context, state) => const EmailAddressPage(),
          ),
          GoRoute(
            path: VerifyCodePage.routePath,
            name: VerifyCodePage.routeName,
            builder: (context, state) => const VerifyCodePage(),
          ),
        ],
      ),
    ],
  );

  return MaterialApp.router(theme: AppTheme.dark, routerConfig: router);
}

void main() {
  late FakeAuthRepository repository;
  late EmailSignInCubit cubit;

  setUp(() {
    repository = FakeAuthRepository()
      // No cooldown: the resend countdown is a periodic timer, and
      // flutter_test fails a test for pending timers before tearDown runs.
      // Navigation is what is under test here.
      ..resendIn = Duration.zero;
    cubit = EmailSignInCubit(repository);
  });

  tearDown(() async {
    await cubit.close();
    await repository.dispose();
  });

  testWidgets('sending a code moves on to the verify screen', (tester) async {
    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAddressPage), findsOneWidget);

    cubit.emailChanged('sam@northwind.co');
    await cubit.sendCode();
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodePage), findsOneWidget);
  });

  testWidgets('back from verify returns to the address screen', (tester) async {
    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();

    cubit.emailChanged('sam@northwind.co');
    await cubit.sendCode();
    await tester.pumpAndSettle();

    // The bug this covers: navigating with `go` leaves nothing on the stack,
    // so the back button silently did nothing.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailAddressPage), findsOneWidget);
    expect(find.byType(VerifyCodePage), findsNothing);
  });

  testWidgets('back with an empty stack falls through to the fallback', (
    tester,
  ) async {
    // A screen reached by a guard redirect or a deep link has nothing to pop.
    // The button must still go somewhere rather than doing nothing.
    await tester.pumpWidget(_host(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.byKey(signInKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
