import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/memory/domain/entities/library_filter.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/library_filter_row.dart';

/// The kinds under "Recent".
void main() {
  test('every kind of memory belongs to exactly one group', () {
    final seen = <MemoryType, LibraryFilter>{};
    for (final filter in LibraryFilter.values) {
      for (final type in filter.types) {
        expect(seen, isNot(contains(type)), reason: '$type in two groups');
        seen[type] = filter;
      }
    }
    expect(seen.keys.toSet(), MemoryType.values.toSet());
    expect(LibraryFilter.all.isAll, isTrue);
    expect(LibraryFilter.images.types, {
      MemoryType.photo,
      MemoryType.screenshot,
    });
    expect(LibraryFilter.audio.types, {MemoryType.audio, MemoryType.voiceNote});
  });

  testWidgets('tapping a kind reports it, and the chosen one reads selected', (
    tester,
  ) async {
    LibraryFilter? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: LibraryFilterRow(
            selected: LibraryFilter.docs,
            onChanged: (filter) => picked = filter,
          ),
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    await tester.tap(find.text('Images'));
    expect(picked, LibraryFilter.images);

    bool selectedChip(Widget w, String label) =>
        w is Semantics &&
        w.properties.label == label &&
        w.properties.selected == true;
    expect(
      find.byWidgetPredicate((w) => selectedChip(w, 'Docs')),
      findsOneWidget,
    );
    expect(find.byWidgetPredicate((w) => selectedChip(w, 'All')), findsNothing);
  });
}
