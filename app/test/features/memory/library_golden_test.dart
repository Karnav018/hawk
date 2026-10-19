import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/app/theme/app_typography.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/capture/presentation/widgets/upload_button.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/memory_row.dart';

import '../../support/load_app_fonts.dart';

const _designSize = Size(402, 874);

Memory _memory({
  required String id,
  required MemoryType type,
  required ProcessingStatus status,
  required String title,
  required DateTime createdAt,
}) => Memory(
  id: id,
  type: type,
  status: status,
  title: title,
  createdAt: createdAt,
);

/// Screen 1K's own composition — tabs, Upload, heading, rows — on the real
/// ground with the real fonts.
///
/// **One theme, so one golden.** v2 captured this in light and dark; v3 has a
/// single palette (`AppTheme.light` returns `AppTheme.dark`), so a second
/// capture would be the same pixels under a different filename.
///
/// The whole point is the *rhythm*: 14px around the Upload button, 9px
/// between rows, one accented button, one accented ring, and a mono line that has to fit in a
/// 402px row without eliding. None of that is assertable, which is why it is
/// a picture.
Widget _host() {
  final now = DateTime(2026, 8, 26, 21, 4);
  final rows = [
    _memory(
      id: '1',
      type: MemoryType.pdf,
      status: ProcessingStatus.ready,
      title: 'pricing-schedule-v4.pdf',
      createdAt: DateTime(2026, 8, 14),
    ),
    _memory(
      id: '2',
      type: MemoryType.audio,
      status: ProcessingStatus.enriching,
      title: 'standup-25-aug.m4a',
      createdAt: DateTime(2026, 8, 25),
    ),
    _memory(
      id: '3',
      type: MemoryType.photo,
      status: ProcessingStatus.ready,
      title: 'whiteboard-tiers.jpg',
      createdAt: DateTime(2026, 8, 24),
    ),
  ];

  return MaterialApp(
    theme: AppTheme.dark,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppPalette.dark.ground,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Headline('Library', size: 28)),
                CircleButton(
                  icon:
                      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" '
                      'stroke-width="2.2" stroke-linecap="round">'
                      '<circle cx="11" cy="11" r="6.5"/>'
                      '<path d="M16 16l4.5 4.5"/></svg>',
                  semanticLabel: 'Search',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedTabs(
              labels: const ['On device', 'Drive'],
              selected: 0,
              onChanged: (_) {},
              dotOn: 1,
            ),
            const SizedBox(height: 14),
            UploadButton(onPressed: () {}),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent',
                  style: AppTypography.titleLarge.copyWith(fontSize: 15),
                ),
                const MetaText('1,516 indexed'),
              ],
            ),
            const SizedBox(height: 10),
            for (final memory in rows) ...[
              MemoryRow(
                memory: memory,
                // Pinned, so "30 DAYS LEFT" stays that tomorrow.
                now: now,
                windowDays: memory.type == MemoryType.audio ? 55 : null,
                onTap: () {},
              ),
              if (memory != rows.last) const SizedBox(height: 9),
            ],
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('library — 1K', (tester) async {
    tester.view
      ..physicalSize = _designSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/library_1k.png'),
    );
  });
}
