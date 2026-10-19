import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/memory_row.dart';

/// What a library row hands to open and share.
void main() {
  Memory memory({Source? source, String? text, String title = 'Doc'}) => Memory(
    id: 'm1',
    type: MemoryType.document,
    status: ProcessingStatus.ready,
    createdAt: DateTime(2026, 9, 17),
    title: title,
    text: text,
    source: source,
  );

  test('a Drive file gets a link from its id', () {
    // The sync stores the Drive file id and never a url, so without this a
    // Drive memory in the library had nothing to open.
    final ref = MemoryRow.originalOf(
      memory(
        source: const Source(id: '1AbC', provider: StorageProvider.googleDrive),
      ),
    );
    expect(ref.url, 'https://drive.google.com/open?id=1AbC');
  });

  test('a link keeps its own url', () {
    final ref = MemoryRow.originalOf(
      memory(
        source: const Source(
          id: 'https://example.com/a',
          provider: StorageProvider.internal,
          url: 'https://example.com/a',
        ),
      ),
    );
    expect(ref.url, 'https://example.com/a');
  });

  test('a note has no url, and shares its own text', () {
    // A typed note has no file anywhere, so sharing it means sharing what
    // was written.
    final ref = MemoryRow.originalOf(memory(text: 'call the architect'));
    expect(ref.url, isNull);
    expect(ref.fallback, 'call the architect');
    expect(ref.memoryId, 'm1');
  });

  test('a captured file with no Drive id invents no link', () {
    final ref = MemoryRow.originalOf(
      memory(
        source: const Source(
          id: 'm1',
          provider: StorageProvider.internal,
          filename: 'IMG_0111.jpeg',
        ),
      ),
    );
    // Opened from the kept copy on this phone, not from a url.
    expect(ref.url, isNull);
  });
}
