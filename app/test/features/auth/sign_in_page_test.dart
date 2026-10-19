import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/config/legal_links.dart';
import 'package:knowra/src/core/widgets/hawk_mark.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/bloc/sign_in_cubit.dart';
import 'package:knowra/src/features/auth/presentation/pages/sign_in_page.dart';

import '../../support/fake_auth.dart';

Widget _host({FakeSocialGateway? gateway}) => MaterialApp(
  theme: AppTheme.dark,
  home: BlocProvider(
    create: (_) =>
        SignInCubit(FakeAuthRepository(), gateway ?? FakeSocialGateway()),
    child: const SignInPage(),
  ),
);

void main() {
  testWidgets('renders the headline, both ways in, and the legal line', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.textContaining('keep, askable'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(
      find.text(
        'Drive files stay in your Drive. No ads, no selling, and you can '
        'delete it all.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('By continuing you accept the Terms and Privacy Policy.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out on a small phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    expect(tester.takeException(), isNull);
  });

  group('provider availability', () {
    testWidgets('an unconfigured provider is shown, not hidden', (
      tester,
    ) async {
      // A missing button reads as a design decision. A release built without
      // credentials would ship that way unnoticed; a dimmed one that names
      // what is missing is louder and still safe.
      await tester.pumpWidget(
        _host(
          gateway: FakeSocialGateway(configured: const {SocialProvider.apple}),
        ),
      );

      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('v3 offers two ways in, and Apple is not one of them', (
      tester,
    ) async {
      // The design draws Google and email. Apple is still implemented in the
      // repository — this asserts the *screen* does not offer it, so putting
      // it back is a deliberate edit here rather than a regression nobody
      // notices.
      await tester.pumpWidget(
        _host(
          gateway: FakeSocialGateway(
            available: const {SocialProvider.google, SocialProvider.apple},
          ),
        ),
      );

      expect(find.text('Continue with Apple'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
    });

    testWidgets('the mark is the brand, not a wordmark', (tester) async {
      // v3 leads with the mark alone: the user has just tapped an icon that
      // says Hawk and is about to reach a home screen that says it again.
      await tester.pumpWidget(_host());

      expect(find.byType(HawkMark), findsOneWidget);
      expect(find.text('Hawk'), findsNothing);
      expect(find.text('Vault'), findsNothing);
    });
  });

  group('the legal line links to the landing pages', () {
    final opened = <Uri>[];
    setUp(() {
      opened.clear();
      LegalLinks.opener = (page) async {
        opened.add(page);
        return true;
      };
    });

    /// Fires the recognizer on the span reading [label] in the consent line.
    void tapSpan(WidgetTester tester, String label) {
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().startsWith('By continuing'),
        ),
      );
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == label) {
          (span.recognizer! as TapGestureRecognizer).onTap!();
          return false;
        }
        return true;
      });
    }

    testWidgets('Terms opens /terms, Privacy Policy opens /privacy', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      tapSpan(tester, 'Terms');
      tapSpan(tester, 'Privacy Policy');
      expect(opened, [LegalLinks.terms, LegalLinks.privacy]);
    });

    test('they are the landing site\'s own pages', () {
      expect(LegalLinks.privacy.toString(), 'https://hawkapp.in/privacy');
      expect(LegalLinks.terms.toString(), 'https://hawkapp.in/terms');
    });
  });
}
