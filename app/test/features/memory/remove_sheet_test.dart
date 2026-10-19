import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/memory/presentation/widgets/remove_sheet.dart';

const _long =
    'College FeesForPRAJAPATI KARNAV KAMLESHKUMAR_order_SsihXiQXNYHBds.pdf';

/// The "Remove from your index?" sheet, at phone width.
void main() {
  testWidgets('both actions sit on one line, the quiet one narrower', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var kept = false;
    var removed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RemoveFromIndexSheet(
              title: _long,
              onKeep: () => kept = true,
              onRemove: () => removed = true,
            ),
          ),
        ),
      ),
    );

    // The bug: "Keep it" had a fifteenth of the row and broke after every
    // syllable. Now neither label is cut, and the quiet pill is a real
    // target — narrower than Remove, not vanishing.
    for (final label in ['Keep it', 'Remove']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
    }
    Rect pill(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    expect(pill('Keep it').width, greaterThan(100));
    expect(pill('Remove').width / pill('Keep it').width, closeTo(1.4, 0.1));

    // The long name is cut from the middle and keeps its end.
    expect(find.textContaining('…'), findsOneWidget);
    expect(find.textContaining('XNYHBds.pdf.'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    expect(kept, isTrue);
    await tester.tap(find.text('Remove'));
    expect(removed, isTrue);
  });

  test('a long file name is shortened from the middle, keeping its end', () {
    expect(shortTitle('lease.pdf'), 'lease.pdf');
    final short = shortTitle(_long);
    expect(short.length, lessThanOrEqualTo(40));
    expect(short, endsWith('XNYHBds.pdf'));
    expect(short, startsWith('College FeesFor'));
    expect(short, contains('…'));
  });
}
