import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/voice/presentation/pages/result_stack_page.dart';

/// Screen 2A — the dead end.
///
/// The screen's whole argument is that "nothing matched" and "nothing matched
/// *in the tenth of your Drive you chose to index*" are different facts, and
/// only one of them is the user's to fix. That argument collapses if the
/// first row ever shows a number the app does not actually know.
void main() {
  Widget host(int unindexed) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: NoMatchRoutes(unindexed: unindexed)),
  );

  testWidgets('the Drive route appears only when there is something to index', (
    tester,
  ) async {
    await tester.pumpWidget(host(9570));
    expect(find.text('Index 9,570 more Drive files'), findsOneWidget);
    expect(find.text('Not searched yet'), findsOneWidget);
  });

  testWidgets('nothing unindexed means the row is gone, not zeroed', (
    tester,
  ) async {
    await tester.pumpWidget(host(0));
    // Not "Index 0 more Drive files" — a row offering to index nothing is
    // worse than two routes becoming one.
    expect(find.textContaining('Drive files'), findsNothing);
    expect(find.byType(HawkRow), findsNWidgets(1));
  });

  testWidgets('an unknown count is treated as nothing, never as a guess', (
    tester,
  ) async {
    // `totalCount - indexedCount` is negative for the first frame, before the
    // listing lands. It must not render as "Index -12 more Drive files".
    await tester.pumpWidget(host(-12));
    expect(find.textContaining('Drive files'), findsNothing);
  });

  testWidgets('the capture route is always offered, and no search is', (
    tester,
  ) async {
    for (final n in [0, 5]) {
      await tester.pumpWidget(host(n));
      expect(find.text('Add it now'), findsOneWidget, reason: '$n');
      expect(find.text('Scan, upload or paste a link'), findsOneWidget);
      // There is no filename search anywhere in the product. The row that
      // offered one only opened the Library, so it promised a feature that
      // does not exist — asking *is* the search.
      expect(find.text('Search filenames instead'), findsNothing);
    }
  });

  test('the count is grouped, so it does not read as a file size', () {
    expect(NoMatchRoutes.grouped(9570), '9,570');
    expect(NoMatchRoutes.grouped(999), '999');
    expect(NoMatchRoutes.grouped(1000), '1,000');
    expect(NoMatchRoutes.grouped(1234567), '1,234,567');
  });
}
