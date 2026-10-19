import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/router/tab_shell.dart';
import 'package:knowra/src/app/theme/app_spacing.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/app_screen.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';

import '../support/load_app_fonts.dart';

/// A tab screen the way Library and Profile are built: a list longer than the
/// screen, ending in [navClearance].
class _Scrolling extends StatelessWidget {
  const _Scrolling();

  @override
  Widget build(BuildContext context) => AppScreen(
    scrollable: false,
    padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
    child: ListView(
      padding: const EdgeInsets.only(bottom: navClearance),
      children: [
        const Headline('Library', size: 28),
        const SizedBox(height: AppSpacing.inset),
        for (var i = 0; i < 14; i++) ...[
          HawkRow(title: 'quarterly-report-$i.pdf', meta: 'PDF · 2.1 MB'),
          const SizedBox(height: AppSpacing.gap),
        ],
      ],
    ),
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/library',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => TabShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const AppScreen(child: SizedBox()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/library', builder: (_, _) => const _Scrolling()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const AppScreen(child: SizedBox()),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// The nav must look the same on every tab: the pill on plain ground, as the
/// design draws it on 1K, 1Q and 1Y alike — not a pill with rows showing
/// round it on the screens that scroll.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('nav over a scrolling tab', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tab_shell_scrolling.png'),
    );
  });

  testWidgets('the last row scrolls clear of the nav, not under it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final lastRow = tester.getRect(find.text('quarterly-report-13.pdf'));
    final bandTop = 874 - navBand;
    expect(lastRow.bottom, lessThanOrEqualTo(bandTop));
  });
}
