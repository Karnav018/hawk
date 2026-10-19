import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/memory_row.dart';

/// Four outcomes share two statuses, and only `indexNote` tells them apart.
///
/// The one that matters is `ready` *with* a note: searchable, but only partly
/// indexed because the plan's budget stopped the rest. Labelling that
/// "INDEXED" is how a user comes to believe an answer was complete when the
/// second half of the document was never embedded.
///
/// v3 renamed the healthy case from READY to INDEXED. READY described the
/// pipeline; INDEXED describes the file, and it is the word the Drive tab and
/// the indexing screen already used for the same condition.
void main() {
  Memory memory(ProcessingStatus status, {String? note}) => Memory(
    id: 'm',
    type: MemoryType.pdf,
    status: status,
    createdAt: DateTime(2026, 9, 11),
    indexNote: note,
  );

  String label(Memory m) => MemoryRow.debugStateLabel(m);

  test('fully indexed reads INDEXED', () {
    expect(label(memory(ProcessingStatus.ready)), 'INDEXED');
  });

  test('partly indexed reads PARTIAL, not INDEXED', () {
    expect(
      label(
        memory(
          ProcessingStatus.ready,
          note: 'Indexed the first 400 of 900 parts',
        ),
      ),
      'PARTIAL',
    );
  });

  test('held with a reason reads HELD, not FAILED', () {
    // A photo with no OCR route, a blank scan, a full index. Nothing went
    // wrong — calling it FAILED would blame the user for working software.
    expect(
      label(
        memory(
          ProcessingStatus.extracted,
          note: 'Nothing readable in this file.',
        ),
      ),
      'HELD',
    );
  });

  test('extracted with no reason is still in progress', () {
    expect(label(memory(ProcessingStatus.extracted)), 'INDEXING');
  });

  test('a real failure still reads FAILED', () {
    expect(label(memory(ProcessingStatus.failed)), 'FAILED');
  });

  test('before extraction the row says what is happening to it', () {
    // F4·4's "JUST NOW · READING" — the pipeline having it is not something
    // anybody asked. A recording is transcribed (F6·5).
    expect(label(memory(ProcessingStatus.uploaded)), 'READING');
    expect(label(memory(ProcessingStatus.processing)), 'READING');
  });

  test('indexed is answerable, so it says INDEXED', () {
    expect(label(memory(ProcessingStatus.indexed)), 'INDEXED');
  });
}
