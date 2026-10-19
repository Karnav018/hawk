import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/capture/presentation/bloc/capture_cubit.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

/// The six tiles on the Library's type sheet — "What are you adding?" (F1·2).
///
/// The sheet renders `CaptureKind.values` directly into a two-column grid, so
/// the enum's declaration order *is* the layout. That makes the order a
/// design decision living in a bloc file, which is exactly the kind of thing
/// that gets tidied alphabetically by somebody being helpful. These pin it.
void main() {
  group('CaptureKind', () {
    test('is the design\'s six, in the design\'s order', () {
      expect(CaptureKind.values.map((k) => k.label).toList(), [
        'Files',
        'Images',
        'Link',
        'Scan',
        'Audio',
        'Speak',
      ]);
    });

    test('Files is first — top left, where the eye lands', () {
      expect(CaptureKind.values.first, CaptureKind.files);
    });

    test('Link and Speak skip the Indexing screen; the rest end on it', () {
      // "Links skip the indexing page; they're fast" (F4·4).
      expect(CaptureKind.values.where((k) => k.uploads), [
        CaptureKind.files,
        CaptureKind.images,
        CaptureKind.scan,
        CaptureKind.audio,
      ]);
    });

    test('no tile offers writing a note', () {
      // The product spec drops the note capture path from the UI. The
      // backend still accepts text memories — a link's fetched title and a
      // transcript are both text — so this guards the *offer*, not the type.
      expect(
        CaptureKind.values.map((k) => k.memoryType),
        isNot(contains(MemoryType.note)),
      );
      expect(
        CaptureKind.values.map((k) => k.memoryType),
        isNot(contains(MemoryType.text)),
      );
    });

    test('every tile maps to a real MemoryType', () {
      for (final kind in CaptureKind.values) {
        expect(
          MemoryType.values.contains(kind.memoryType),
          isTrue,
          reason: kind.name,
        );
      }
    });

    test('links map to link, not to a file type', () {
      // The repository overrides `type` to link whenever a url is present, so
      // a mismatch here would be a silent disagreement between two layers.
      expect(CaptureKind.links.memoryType, MemoryType.link);
    });

    test('speak is filed as a voice note, not audio', () {
      // The recorder (2F) keeps the transcript and no recording. Typed as
      // audio, it would promise the player (2H) something to play.
      expect(CaptureKind.speak.memoryType, MemoryType.voiceNote);
    });

    test('a scan is filed as the PDF it becomes', () {
      // Pages are bound into one PDF (2E) — one memory per document, not a
      // photograph per page.
      expect(CaptureKind.scan.memoryType, MemoryType.pdf);
    });

    test('every capture path is live now', () {
      // Scan was the last "not yet": the platforms' own document scanners
      // do the edge detection and de-skew that made it a refusal.
      expect(CaptureKind.values.every((k) => k.isAvailable), isTrue);
    });

    test('the three file paths name a picker, and nothing else does', () {
      // Links has a sheet, Speak its recorder, Scan the platform scanner. A
      // file picker for any of them would open a browser for something that
      // is not yet a file.
      expect(CaptureKind.files.pick, isNotNull);
      expect(CaptureKind.images.pick, isNotNull);
      expect(CaptureKind.audio.pick, isNotNull);
      expect(CaptureKind.links.pick, isNull);
      expect(CaptureKind.scan.pick, isNull);
      expect(CaptureKind.speak.pick, isNull);
    });
  });

  group('CaptureState', () {
    test('a link cannot be saved until it is a url', () {
      expect(const CaptureState().canSaveLink, isFalse);
      expect(const CaptureState(url: 'not a url').canSaveLink, isFalse);
      expect(const CaptureState(url: 'example.com').canSaveLink, isTrue);
    });

    test('an error only shows once the field has been left', () {
      // Validating as somebody types "h" tells them "h" is not a url, which
      // they know.
      expect(const CaptureState(url: 'h').urlError, isNull);
      expect(
        const CaptureState(url: 'h', urlTouched: true).urlError,
        isNotNull,
      );
    });
  });
}
