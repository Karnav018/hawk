import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

void main() {
  group('Answer.meta', () {
    test('matches the design line', () {
      // "21:04 · 3 SOURCES · 0.9S"
      final answer = Answer(
        id: 'a',
        question: 'Q3 pricing tiers',
        citations: const [
          Citation(memoryId: '1', index: 1, title: 'a'),
          Citation(memoryId: '2', index: 2, title: 'b'),
          Citation(memoryId: '3', index: 3, title: 'c'),
        ],
        answeredAt: DateTime(2026, 8, 29, 21, 4),
        latency: const Duration(milliseconds: 900),
      );
      expect(answer.meta, '21:04 · 3 SOURCES · 0.9S');
    });

    test('sources are files — three markers into one PDF are one source', () {
      final answer = Answer(
        id: 'a',
        question: 'q',
        citations: const [
          Citation(memoryId: 'icc', index: 1, title: 'ICC.pdf'),
          Citation(memoryId: 'icc', index: 2, title: 'ICC.pdf'),
          Citation(memoryId: 'lease', index: 3, title: 'lease.pdf'),
        ],
        answeredAt: DateTime(2026, 9, 26, 18, 42),
      );
      expect(answer.meta, contains('2 SOURCES'));
    });

    test('singularises one source', () {
      final answer = Answer(
        id: 'a',
        question: 'q',
        citations: const [Citation(memoryId: '1', index: 1, title: 'a')],
        answeredAt: DateTime(2026, 8, 29, 9, 5),
      );
      expect(answer.meta, contains('1 SOURCE'));
      expect(answer.meta, isNot(contains('SOURCES')));
    });

    test('pads the clock so the numerals do not jump', () {
      // A fixed shape; an unpadded hour would shift the whole line.
      final answer = Answer(
        id: 'a',
        question: 'q',
        answeredAt: DateTime(2026, 8, 29, 9, 5),
      );
      expect(answer.meta, startsWith('09:05'));
    });
  });

  group('Citation', () {
    test('provenance names the kind and where inside it', () {
      const c = Citation(
        memoryId: '1',
        index: 1,
        title: 'Pricing schedule v4',
        type: MemoryType.pdf,
        locator: 'p2',
      );
      expect(c.provenance, 'PDF · p2');
    });

    test('a source with no locator still says what it is', () {
      const c = Citation(
        memoryId: '1',
        index: 1,
        title: 'Board call',
        type: MemoryType.audio,
      );
      expect(c.provenance, 'AUDIO');
    });
  });

  group('citation lookup', () {
    test('resolves a superscript to its source', () {
      const citations = [
        Citation(memoryId: 'm1', index: 1, title: 'first'),
        Citation(memoryId: 'm2', index: 2, title: 'second'),
      ];
      const answer = Answer(id: 'a', question: 'q', citations: citations);
      expect(answer.citation(2)?.title, 'second');
    });

    test('an unresolvable superscript is null, not a crash', () {
      // A model that cites [4] when three sources were retrieved must render
      // the number without taking the screen down.
      const answer = Answer(id: 'a', question: 'q');
      expect(answer.citation(4), isNull);
    });
  });

  group('AnswerConfidence', () {
    test('maps to bars, and low is never zero', () {
      // Zero filled bars reads as "no answer" rather than "weak answer".
      expect(AnswerConfidence.low.bars, greaterThan(0));
      expect(AnswerConfidence.high.bars, 4);
      expect(AnswerConfidence.medium.bars, lessThan(4));
    });

    test('an unknown level from a newer backend degrades to low', () {
      expect(AnswerConfidence.parse('extremely-high'), AnswerConfidence.low);
      expect(AnswerConfidence.parse(null), AnswerConfidence.low);
    });
  });
}
