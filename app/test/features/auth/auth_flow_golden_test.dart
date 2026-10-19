import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/auth/presentation/bloc/email_sign_in_cubit.dart';
import 'package:knowra/src/features/auth/presentation/bloc/onboarding_cubit.dart';
import 'package:knowra/src/features/auth/presentation/bloc/session_cubit.dart';
import 'package:knowra/src/features/auth/presentation/pages/email_address_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/how_you_ask_page.dart';
import 'package:knowra/src/features/auth/presentation/pages/verify_code_page.dart';

import '../../support/fake_auth.dart';
import '../../support/load_app_fonts.dart';

const _designSize = Size(402, 874);

Future<void> _pumpAt(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = _designSize
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await precacheAppImages(tester);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: child,
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository());
  tearDown(() => repository.dispose());

  testWidgets('1D — enter address', (tester) async {
    final cubit = EmailSignInCubit(repository)
      ..emailChanged('sam@northwind.co');
    addTearDown(cubit.close);

    await _pumpAt(
      tester,
      BlocProvider.value(value: cubit, child: const EmailAddressPage()),
    );

    expect(find.text('Send code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EmailAddressPage),
      matchesGoldenFile('goldens/auth_1d_email.png'),
    );
  });

  testWidgets('1E — verify code, part typed', (tester) async {
    final cubit = EmailSignInCubit(repository);

    cubit.emailChanged('sam@northwind.co');
    await cubit.sendCode();
    cubit.codeChanged('419');

    await _pumpAt(
      tester,
      BlocProvider.value(value: cubit, child: const VerifyCodePage()),
    );

    // v3 puts the address on a "Sent to … · Change" line, so the address
    // is a span inside a richer paragraph rather than its own Text.
    expect(find.textContaining('sam@northwind.co'), findsWidgets);
    expect(find.text('RESEND CODE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(VerifyCodePage),
      matchesGoldenFile('goldens/auth_1e_verify.png'),
    );

    // Closed inside the body, not in a tearDown: the resend countdown is a
    // periodic timer, and flutter_test fails the test for pending timers
    // before tearDowns get a chance to run.
    await cubit.close();
  });

  testWidgets('1F — how you will ask', (tester) async {
    final cubit = OnboardingCubit(repository)..nameChanged('Sam Kaur');
    addTearDown(cubit.close);
    final session = SessionCubit(repository);
    addTearDown(session.close);

    await _pumpAt(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          // The greeting reads the session for the name, so the screen cannot
          // be rendered without one.
          BlocProvider.value(value: session),
        ],
        child: const HowYouAskPage(),
      ),
    );

    expect(find.text('Speak'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(HowYouAskPage),
      matchesGoldenFile('goldens/auth_1f_ask.png'),
    );
  });
}
