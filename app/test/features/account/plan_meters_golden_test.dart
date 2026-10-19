import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/account/presentation/widgets/profile_pieces.dart';

import '../../support/load_app_fonts.dart';

Widget _card() => MaterialApp(
  theme: AppTheme.dark,
  debugShowCheckedModeBanner: false,
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.fromLTRB(16, 40, 16, 0),
      child: HawkCard(
        tone: CardTone.paper,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A Premium account that has barely started: the case that
            // drew two blank bars.
            PaperMeter(
              label: 'Storage',
              value: '41 KB / 256 GB',
              fraction: 41 * 1024 / (256 * 1024 * 1024 * 1024),
            ),
            SizedBox(height: 16),
            PaperMeter(label: 'Asks today', value: '0 / 1000', fraction: 0),
            SizedBox(height: 16),
            PaperMeter(label: 'Asks today', value: '42 / 100', fraction: 0.42),
          ],
        ),
      ),
    ),
  ),
);

/// The plan card's meters must read on white: a visible track, and any use
/// at all visible as use.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('plan meters on paper', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 320)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_card());

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/plan_meters.png'),
    );
  });

  testWidgets('a sliver of use is a dot, and no use is no fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(
              width: 300,
              child: ProgressTrack(value: 0.0000001, height: 10),
            ),
            SizedBox(width: 300, child: ProgressTrack(value: 0, height: 10)),
          ],
        ),
      ),
    );
    final fills = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(ProgressTrack),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.constraints?.maxWidth)
        .toList();
    expect(fills, [10, 0]);
  });
}
