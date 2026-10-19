import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/auth/presentation/bloc/sign_in_cubit.dart';
import 'package:knowra/src/features/auth/presentation/pages/sign_in_page.dart';

import '../../support/fake_auth.dart';
import '../../support/load_app_fonts.dart';

/// The device frame the design is drawn in.
const _designSize = Size(402, 874);

Widget _host(ThemeData theme) => MaterialApp(
  theme: theme,
  debugShowCheckedModeBanner: false,
  home: BlocProvider(
    create: (_) => SignInCubit(FakeAuthRepository(), FakeSocialGateway()),
    child: const SignInPage(),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('sign in matches the design frame', (tester) async {
    tester.view
      ..physicalSize = _designSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await precacheAppImages(tester);

    await tester.pumpWidget(_host(AppTheme.dark));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SignInPage),
      matchesGoldenFile('goldens/sign_in_dark.png'),
    );
  });
}
