import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

/// The countdown on 1V's "Expiring soon" rows.
///
/// The design writes "DELETED IN 2 DAYS". §36 demotes rather than deletes —
/// the file stays on the user's own storage and an upgrade brings it back
/// into the index intact. A deletion countdown would frighten somebody into
/// paying for a loss that does not happen, so the wording is the product's
/// and only the urgency is the design's.
void main() {
  final now = DateTime(2026, 9, 22, 12);

  Memory aged(int days) => Memory(
    id: 'm',
    type: MemoryType.pdf,
    status: ProcessingStatus.ready,
    createdAt: now.subtract(Duration(days: days)),
  );

  group('wording', () {
    test('never promises a deletion', () {
      final label = aged(28).dormancyLabel(windowDays: 30, now: now)!;
      expect(label, isNot(contains('DELET')));
      expect(label, contains('DORMANT'));
    });

    test('counts the days left', () {
      expect(
        aged(28).dormancyLabel(windowDays: 30, now: now),
        'GOES DORMANT IN 2 DAYS',
      );
    });

    test('the last day reads as a day, not as "1 DAYS"', () {
      expect(
        aged(29).dormancyLabel(windowDays: 30, now: now),
        'GOES DORMANT TOMORROW',
      );
    });

    test('a plan with no window counts down to nothing', () {
      expect(aged(400).dormancyLabel(windowDays: null, now: now), isNull);
      expect(aged(400).daysUntilDormant(windowDays: null, now: now), isNull);
    });

    test('already dormant has no countdown left to show', () {
      expect(aged(31).dormancyLabel(windowDays: 30, now: now), isNull);
      // retentionLabel still speaks for that row, and still says DORMANT.
      expect(aged(31).retentionLabel(windowDays: 30, now: now), 'DORMANT');
    });
  });

  group('the section and the row agree', () {
    // Both read `daysUntilDormant`, so a memory can never be listed as
    // expiring while its own row refuses to say when.
    test('anything inside the horizon has a label', () {
      for (var d = 23; d <= 29; d++) {
        final m = aged(d);
        final left = m.daysUntilDormant(windowDays: 30, now: now);
        expect(left, isNotNull, reason: 'aged $d');
        expect(left! <= 7, isTrue);
        expect(m.dormancyLabel(windowDays: 30, now: now), isNotNull);
      }
    });

    test('anything outside it is not listed', () {
      expect(aged(10).daysUntilDormant(windowDays: 30, now: now), 20);
    });
  });
}
