import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

/// QA-027. A link saved with no note rendered as "Untitled".
///
/// The reported cause was `displayTitle` not checking the url. The real cause
/// was one layer down: the Firestore mapper never built a `Source` at all, so
/// the entity had no url to check — and every Drive-indexed memory was also
/// silently losing its provider, mime type and source reference, which is the
/// pointer the whole bring-your-own-storage model rests on.
void main() {
  Memory memory({String? title, String? text, Source? source}) => Memory(
    id: 'm1',
    type: source?.url != null ? MemoryType.link : MemoryType.note,
    status: ProcessingStatus.ready,
    createdAt: DateTime(2026, 9, 10),
    title: title,
    text: text,
    source: source,
  );

  Source link(String url) =>
      Source(id: url, provider: StorageProvider.internal, url: url);

  group('displayTitle', () {
    test('a note title wins', () {
      expect(memory(title: 'Q3 pricing').displayTitle, 'Q3 pricing');
    });

    test('a link with no note reads as host and path, not "Untitled"', () {
      expect(
        memory(source: link('https://example.com/qa-link-1')).displayTitle,
        'example.com/qa-link-1',
      );
    });

    test('www is dropped', () {
      expect(
        memory(source: link('https://www.example.com/a')).displayTitle,
        'example.com/a',
      );
    });

    test('a bare host loses its trailing slash', () {
      expect(
        memory(source: link('https://example.com/')).displayTitle,
        'example.com',
      );
    });

    test('query strings are dropped as noise', () {
      expect(
        memory(
          source: link('https://example.com/a?utm_source=x&ref=y'),
        ).displayTitle,
        'example.com/a',
      );
    });

    test('the host alone would collapse distinct saves — path is kept', () {
      final a = memory(source: link('https://example.com/one')).displayTitle;
      final b = memory(source: link('https://example.com/two')).displayTitle;
      expect(a, isNot(b));
    });

    test('an unparseable url is shown verbatim rather than hidden', () {
      expect(memory(source: link('not a url')).displayTitle, 'not a url');
    });

    test('a filename beats a url', () {
      expect(
        memory(
          source: Source(
            id: 'f',
            provider: StorageProvider.googleDrive,
            filename: 'Pricing schedule v4.pdf',
            url: 'https://drive.google.com/file/d/abc',
          ),
        ).displayTitle,
        'Pricing schedule v4.pdf',
      );
    });

    test('a note with neither is the only real "Untitled"', () {
      expect(memory().displayTitle, 'Untitled');
    });

    test('long text is clipped, not wrapped', () {
      final long = 'x' * 400;
      final shown = memory(text: long).displayTitle;
      expect(shown.length, lessThanOrEqualTo(120));
      expect(shown, endsWith('…'));
    });
  });
}
