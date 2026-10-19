import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/memory_row.dart';

/// `14 AUG · INDEXED · KEPT FOREVER` — the one line under a library row.
///
/// Three separate claims joined by a separator, and the third is the one that
/// is easy to get quietly wrong: retention is a property of the memory *and*
/// the plan, so nothing about a document changes when a subscription lapses,
/// but everything about what this line should say does.
void main() {
  final now = DateTime(2026, 8, 26, 21, 4);

  Memory memory({
    DateTime? createdAt,
    ProcessingStatus status = ProcessingStatus.ready,
  }) => Memory(
    id: 'm',
    type: MemoryType.pdf,
    status: status,
    createdAt: createdAt ?? DateTime(2026, 8, 14),
    title: 'pricing-schedule-v4.pdf',
  );

  group('the meta line', () {
    test('is date, state, then retention', () {
      expect(
        MemoryRow.metaLine(memory(), now: now),
        '14 AUG · INDEXED · KEPT FOREVER',
      );
    });

    test('counts a plan window down in days', () {
      expect(
        MemoryRow.metaLine(
          memory(createdAt: DateTime(2026, 8, 25)),
          windowDays: 42,
          now: now,
        ),
        '25 AUG · INDEXED · 41 DAYS LEFT',
      );
    });

    test('says nothing about retention until it can be asked (F2·2)', () {
      expect(
        MemoryRow.metaLine(
          memory(
            createdAt: DateTime(2026, 8, 25),
            status: ProcessingStatus.embedding,
          ),
          windowDays: 42,
          now: now,
        ),
        '25 AUG · INDEXING',
      );
    });

    test('a file saved a moment ago is JUST NOW', () {
      expect(
        MemoryRow.metaLine(
          memory(
            createdAt: now.subtract(const Duration(seconds: 40)),
            status: ProcessingStatus.processing,
          ),
          now: now,
        ),
        'JUST NOW · READING',
      );
      expect(
        MemoryRow.dateLabel(now.subtract(const Duration(minutes: 3)), now: now),
        '26 AUG',
      );
    });

    test('a single day is not "1 DAYS LEFT"', () {
      expect(
        memory(
          createdAt: DateTime(2026, 7, 28),
        ).retentionLabel(windowDays: 30, now: now),
        '1 DAY LEFT',
      );
    });

    test('past the window reads DORMANT, never EXPIRED or DELETED', () {
      // §36 demotes rather than deletes. The memory is genuinely still here
      // and upgrading genuinely brings it back, so the word has to say that.
      expect(
        memory(
          createdAt: DateTime(2026, 1, 1),
        ).retentionLabel(windowDays: 30, now: now),
        'DORMANT',
      );
    });

    test('no window means kept forever, not an empty third field', () {
      expect(memory().retentionLabel(now: now), 'KEPT FOREVER');
    });
  });

  group('the index badge', () {
    test('never moves backwards through the pipeline', () {
      // The badge is drawn from the stage, so a stage that scored lower than
      // the one before it would make a row count down while it worked.
      const order = [
        ProcessingStatus.uploaded,
        ProcessingStatus.processing,
        ProcessingStatus.extracted,
        ProcessingStatus.enriching,
        ProcessingStatus.embedding,
        ProcessingStatus.indexed,
        ProcessingStatus.ready,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i].indexFraction,
          greaterThan(order[i - 1].indexFraction),
          reason: '${order[i].name} after ${order[i - 1].name}',
        );
      }
    });

    test('is only drawn while there is work left', () {
      // `isWorking` is what the row switches on. A finished memory gets the
      // chevron back, because there is finally something behind it.
      expect(ProcessingStatus.ready.isWorking, isFalse);
      expect(ProcessingStatus.failed.isWorking, isFalse);
      expect(ProcessingStatus.embedding.isWorking, isTrue);
    });

    test('stays inside 0 and 1', () {
      for (final status in ProcessingStatus.values) {
        expect(
          status.indexFraction,
          inInclusiveRange(0, 1),
          reason: status.name,
        );
      }
    });
  });
}
