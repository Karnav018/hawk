import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/presentation/widgets/result_file.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

/// What a v3 result is allowed to say.
///
/// The design's rule is short and easy to erode one row at a time: the short
/// answer, the file, and where the file lives. These pin the two lines that
/// carry the second and third of those, because the pressure is always to add
/// a fourth.
void main() {
  ResultFile file({
    MemoryType type = MemoryType.pdf,
    String? locator,
    String? storagePath,
    String? url,
  }) => (
    memoryId: 'm1',
    title: 'Pricing schedule v4',
    type: type,
    locator: locator,
    url: url,
    storagePath: storagePath,
  );

  group('the file line', () {
    test('names the kind and where inside it', () {
      expect(fileLine(file(locator: 'page 2')), 'PDF · page 2');
    });

    test('a file with no locator still says what it is', () {
      expect(fileLine(file(type: MemoryType.audio)), 'Audio');
    });

    test('carries no score', () {
      // v2 printed a relevance number on every row. It described the search,
      // not the file, and v3 deletes it — a result that has to argue for
      // itself is not a result.
      expect(fileLine(file(locator: 'page 2')), isNot(contains('9')));
    });
  });

  group('where it lives', () {
    test('reads as a breadcrumb from the phone down', () {
      expect(
        whereItLives(file(storagePath: 'users/u1/documents/board/plan.pdf')),
        'Phone › documents › board',
      );
    });

    test('drops the addressing nobody recognises', () {
      // `users/<uid>` is how Storage finds the file, not where a person
      // thinks it is.
      final where = whereItLives(
        file(storagePath: 'users/abc123/captures/plan.pdf'),
      );
      expect(where, isNot(contains('abc123')));
      expect(where, 'Phone › captures');
    });

    test('a file at the root of the vault is still on the phone', () {
      expect(whereItLives(file(storagePath: 'users/u1/plan.pdf')), 'Phone');
    });

    test('a link lives at its host', () {
      expect(
        whereItLives(file(url: 'https://drive.google.com/file/d/1/view')),
        'drive.google.com',
      );
    });

    test('nothing known is null, not a guess', () {
      // The row then shows the file line alone. An invented location is
      // worse than none: it is the line people navigate by.
      expect(whereItLives(file()), isNull);
    });
  });

  group('which files a result shows', () {
    const match = Match(memoryId: 'm', chunkId: 'c', title: 'from search');
    const citation = Citation(
      memoryId: 'm',
      index: 1,
      title: 'from the answer',
    );

    test('citations win once the answer exists', () {
      // The rows under an answer should be the files it was written from,
      // not everything retrieval considered.
      final files = resultFilesFor(citations: const [citation], answered: true);
      expect(files.single.title, 'from the answer');
    });

    test('an answer that cites nothing shows nothing — not the matches', () {
      // "hi" retrieves an invoice, because retrieval always returns its
      // nearest passages. The reply is a greeting written from nothing, and
      // the thread was putting two files under it as if they were sources.
      final files = resultFilesFor(citations: const [], answered: true);
      expect(files, isEmpty);
      expect(match.title, 'from search', reason: 'the match exists, unshown');
    });

    test('nothing shows while the answer is being read', () {
      // Search lands seconds before the answer, and its matches were shown
      // in the gap. People read them as the last thing they uploaded or
      // searched for, so "Reading your files…" now stands alone.
      expect(resultFilesFor(citations: const [], answered: false), isEmpty);
      expect(
        resultFilesFor(citations: const [citation], answered: false),
        isEmpty,
        reason: 'not even citations, before the answer exists',
      );
    });
  });

  group('one row per file, not per passage', () {
    Match passage(String memoryId, int part, {String? title}) => Match(
      memoryId: memoryId,
      chunkId: '${memoryId}_$part',
      title: title ?? '$memoryId.pdf',
      type: MemoryType.pdf,
      locator: 'part $part',
    );

    test('eight passages from one PDF are one file, not "8 files"', () {
      final files = distinctFiles([
        for (final part in [2, 5, 1, 7, 3, 8, 4, 6])
          resultFileFromMatch(
            passage('icc', part, title: 'ICC_MID1 MARKS.pdf'),
          ),
      ]);
      expect(files, hasLength(1));
      expect(files.single.title, 'ICC_MID1 MARKS.pdf');
      expect(files.single.locator, 'parts 1, 2, 3 +5');
    });

    test('files keep the rank of their best passage', () {
      final files = distinctFiles([
        for (final m in [
          passage('lease', 4),
          passage('pricing', 1),
          passage('lease', 2),
          passage('invoice', 9),
          passage('pricing', 3),
        ])
          resultFileFromMatch(m),
      ]);
      expect(
        [for (final f in files) f.memoryId],
        ['lease', 'pricing', 'invoice'],
      );
      expect(
        [for (final f in files) f.locator],
        ['parts 2, 4', 'parts 1, 3', 'part 9'],
      );
    });

    test('citations into one file are one file too', () {
      final files = resultFilesFor(
        citations: const [
          Citation(
            memoryId: 'icc',
            index: 1,
            title: 'ICC.pdf',
            locator: 'part 2',
          ),
          Citation(
            memoryId: 'icc',
            index: 2,
            title: 'ICC.pdf',
            locator: 'part 5',
          ),
        ],
        answered: true,
      );
      expect(files, hasLength(1));
      expect(files.single.locator, 'parts 2, 5');
    });

    test('a locator in another scheme is not mixed into a list', () {
      expect(mergedLocator(['page 3', 'part 2']), 'page 3');
      expect(mergedLocator(const []), isNull);
      expect(mergedLocator(['part 4']), 'part 4');
    });
  });
}
