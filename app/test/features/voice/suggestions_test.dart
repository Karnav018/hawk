import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/voice/presentation/bloc/suggestions_cubit.dart';

/// Home's suggestions — screen 1Y's chips and 1Z's START WITH list.
///
/// The design fills these with "Pricing we agreed", "Lease PDF",
/// "Standup": sample topics that, shown to a real user, would be questions
/// about files they do not have. These pin that suggestions are built only
/// from the user's own searchable memories.
void main() {
  Memory m(
    String title,
    MemoryType type, {
    ProcessingStatus status = ProcessingStatus.ready,
  }) => Memory(
    id: title,
    type: type,
    status: status,
    createdAt: DateTime(2026, 9, 23),
    title: title,
  );

  test('phrased by what the memory is', () {
    final s = suggestionsFrom([
      m('board-pack-sep.pdf', MemoryType.pdf),
      m('standup-25-aug.m4a', MemoryType.audio),
      m('whiteboard-tiers.jpg', MemoryType.photo),
    ]);
    expect(
      [for (final x in s) x.question],
      [
        'Summarise board pack sep',
        'What was said in standup 25 aug?',
        'What does whiteboard tiers show?',
      ],
    );
  });

  test('never offers something still being indexed', () {
    final s = suggestionsFrom([
      m(
        'still-reading.pdf',
        MemoryType.pdf,
        status: ProcessingStatus.processing,
      ),
      m('failed.pdf', MemoryType.pdf, status: ProcessingStatus.failed),
      m('lease.pdf', MemoryType.pdf, status: ProcessingStatus.indexed),
    ]);
    expect(s, hasLength(1));
    expect(s.single.chip, 'Lease');
  });

  test('an empty library suggests nothing, rather than sample topics', () {
    expect(suggestionsFrom(const []), isEmpty);
  });

  test('three at most, and no repeats', () {
    final s = suggestionsFrom([
      for (final t in ['a.pdf', 'A.pdf', 'b.pdf', 'c.pdf', 'd.pdf'])
        m(t, MemoryType.pdf),
    ]);
    expect([for (final x in s) x.chip], ['A', 'B', 'C']);
  });

  test('chips are short enough for a pill', () {
    final s = suggestionsFrom([
      m('quarterly-review-deck-final-v7.pdf', MemoryType.pdf),
    ]);
    expect(s.single.chip.length, lessThanOrEqualTo(22));
    expect(s.single.chip.endsWith('…'), isTrue);
  });

  test('a title with a dot that is not an extension keeps it', () {
    final s = suggestionsFrom([m('Notes v2.0 draft', MemoryType.note)]);
    // "0 draft" is not an extension; cutting there would lose the title.
    expect(s.single.question, 'Summarise Notes v2.0 draft');
  });

  group('a name a device gave the file', () {
    test('is called what it is and when it arrived', () {
      final s = suggestionsFrom([
        m('1000047716.jpg', MemoryType.photo),
        m('Screenshot_20260920-101010.png', MemoryType.screenshot),
        m('Recording 2026-09-23 14.23.11.m4a', MemoryType.voiceNote),
      ]);
      expect(
        [for (final x in s) x.chip],
        ['Photo · 23 Sep', 'Screenshot · 23 Sep', 'Voice note · 23 Sep'],
      );
      expect(
        [for (final x in s) x.question],
        [
          'What does the photo from 23 Sep show?',
          'What does the screenshot from 23 Sep show?',
          'What was said in the voice note from 23 Sep?',
        ],
      );
    });

    test('camera, scanner and hash names are all recognised', () {
      for (final name in [
        'IMG_20260923_142311',
        'PXL_20260923_142311123',
        'scan_1758612345',
        'IMG-20260923-WA0001',
        '3f2a9c1e-77b0-4c1d-9e2f-0a1b2c3d4e5f',
        'image_picker_1758612345',
      ]) {
        expect(isMachineName(name), isTrue, reason: name);
      }
    });

    test('a person\'s name with numbers in it is left alone', () {
      for (final name in [
        'Q3 report 2026',
        'Chapter 12',
        'Notes v2.0',
        'lease',
      ]) {
        expect(isMachineName(name), isFalse, reason: name);
      }
    });

    test('a word among the numbers is kept, the timestamps dropped', () {
      final s = suggestionsFrom([
        m('Screenshot_20260920-101010_Chrome.png', MemoryType.screenshot),
      ]);
      expect(s.single.chip, 'Screenshot Chrome');
    });

    test('two unnamed photos from one day are one chip, not twins', () {
      final s = suggestionsFrom([
        m('1000047716.jpg', MemoryType.photo),
        m('1000047717.jpg', MemoryType.photo),
        m('lease.pdf', MemoryType.pdf),
      ]);
      expect([for (final x in s) x.chip], ['Photo · 23 Sep', 'Lease']);
    });

    test('a scan names the kind it was saved as', () {
      final s = suggestionsFrom([m('scan_1758612345.pdf', MemoryType.pdf)]);
      expect(s.single.chip, 'PDF · 23 Sep');
      expect(s.single.question, 'Summarise the PDF from 23 Sep');
      expect(s.single.type, MemoryType.pdf);
    });
  });
}
