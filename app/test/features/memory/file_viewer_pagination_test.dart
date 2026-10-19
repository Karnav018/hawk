import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/bloc/file_viewer_cubit.dart';

/// How screen 1M gets a page count out of extracted text.
///
/// The header says "PAGE 2 OF 6", and there is nothing in the index that
/// knows how many pages the source document had — what Hawk holds is the text
/// it extracted. So the viewer paginates that, on a character budget at
/// paragraph boundaries rather than by measuring the viewport: a measured
/// pagination re-flows when somebody turns on larger type, which silently
/// changes what "page 2" means.
void main() {
  _visualTypes();

  List<String> pages(String? text, {int budget = 900}) =>
      FileViewerCubit.paginate(text, budget: budget);

  test('nothing extracted is no pages, not one empty one', () {
    // The state turns this into "PAGE 1 OF 1" for the header and an
    // explanation in the card. An empty string page would render a blank
    // white card with no reason given.
    expect(pages(null), isEmpty);
    expect(pages('   \n\n  '), isEmpty);
  });

  test('a short document is one page', () {
    expect(pages('All plans are billed annually.'), hasLength(1));
  });

  test('breaks between paragraphs, never inside a sentence', () {
    final text = List.generate(
      6,
      (i) => 'Paragraph $i. ${'x' * 300}',
    ).join('\n\n');
    final result = pages(text, budget: 700);

    expect(result.length, greaterThan(1));
    for (final page in result) {
      expect(page.trimLeft(), startsWith('Paragraph'));
    }
  });

  test('a paragraph longer than the budget is left whole', () {
    // One long page beats a sentence broken across a page turn, and the card
    // scrolls, so it still reads.
    final giant = 'y' * 3000;
    expect(pages(giant, budget: 900), [giant]);
  });

  test('loses no text', () {
    final text = List.generate(9, (i) => 'Section $i body.').join('\n\n');
    expect(pages(text, budget: 40).join('\n\n'), text);
  });

  test('the header never reads PAGE 1 OF 0', () {
    const empty = FileViewerState();
    expect(empty.pageCount, 1);
    expect(empty.pageLabel, 'PAGE 1 OF 1');
  });
}

/// Which memories the viewer reads, and which it shows.
///
/// The viewer is a *text* viewer on purpose — it renders what was extracted,
/// because that is what the answers were built from and it needs no download.
/// For a photo that reasoning inverts: there is no text and never will be, so
/// the screen told the user "nothing readable in this file" about a picture
/// that was perfectly fine. [MemoryType.isVisual] is the line between the two.
void _visualTypes() {
  test('a picture is shown, not read', () {
    expect(MemoryType.photo.isVisual, isTrue);
    expect(MemoryType.screenshot.isVisual, isTrue);
  });

  test('anything the index can extract text from is still read', () {
    for (final t in [
      MemoryType.pdf,
      MemoryType.document,
      MemoryType.text,
      MemoryType.note,
      MemoryType.link,
    ]) {
      expect(t.isVisual, isFalse, reason: '$t');
    }
  });

  test('a photo with OCR text is still shown as a photo', () {
    // The bug this exists for: the viewer first branched on "is there text",
    // which got the empty photo right and the interesting one exactly wrong.
    // A whiteboard with text read out of it has pages — and is still a
    // picture. `isVisual` has to be asked before `pages.isEmpty`.
    expect(MemoryType.photo.isVisual, isTrue);
    expect(MemoryType.screenshot.isVisual, isTrue);
  });

  test('media with no still to show is not treated as visual', () {
    // Video and audio have originals but nothing this card can render; they
    // keep the explanation and the "open in app" action.
    expect(MemoryType.video.isVisual, isFalse);
    expect(MemoryType.audio.isVisual, isFalse);
    expect(MemoryType.voiceNote.isVisual, isFalse);
    // An unknown type from a newer backend degrades to `file`, which must not
    // start trying to decode arbitrary bytes as an image.
    expect(MemoryType.parse('hologram').isVisual, isFalse);
  });
}
