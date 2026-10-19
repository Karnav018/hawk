import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/local/local_index.dart';
import 'package:knowra/src/features/chat/data/local/local_query.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

LocalChunk _chunk(
  String id, {
  String text = 'text',
  MemoryType type = MemoryType.pdf,
  bool active = true,
  DateTime? captured,
}) => LocalChunk(
  id: id,
  memoryId: 'm-$id',
  memoryTitle: '$id.pdf',
  memoryType: type,
  text: text,
  chunkIndex: 0,
  active: active,
  capturedAt: captured,
);

Float32List _unit(List<double> v) {
  var norm = 0.0;
  for (final x in v) {
    norm += x * x;
  }
  final n = norm == 0 ? 1 : norm;
  return Float32List.fromList([for (final x in v) x / n]);
}

/// The vectors on this phone: kept, found, and forgotten on sign-out.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('hawk-index-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('survives a restart, vectors and all', () async {
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('a', text: 'lease terms'))
      ..upsert(_chunk('b', text: 'pricing tiers'))
      ..setVectors({
        'a': _unit([1, 0, 0]),
      });
    expect(index.pending.single.id, 'b');
    await index.persist();

    final again = LocalIndex.at(root);
    await again.load('u1');
    expect(again.size, 2);
    expect(again.embedded, 1);
    expect(again['a']?.text, 'lease terms');
    expect(again.pending.single.id, 'b');
    expect(again.isReady, isFalse);
  });

  test('finds the nearest, active only, narrowed by the filters', () async {
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('near', type: MemoryType.pdf))
      ..upsert(_chunk('far', type: MemoryType.pdf))
      ..upsert(_chunk('dormant', active: false))
      ..upsert(
        _chunk(
          'photo',
          type: MemoryType.photo,
          captured: DateTime.utc(2026, 1, 1),
        ),
      )
      ..setVectors({
        'near': _unit([1, 0, 0]),
        'far': _unit([0, 1, 0]),
        'dormant': _unit([1, 0, 0]),
        'photo': _unit([1, 0.1, 0]),
      });

    final all = index.nearest(_unit([1, 0, 0]), const LocalQuery(search: ''));
    expect([for (final n in all) n.chunk.id], ['near', 'photo', 'far']);
    expect(all.first.distance, closeTo(0, 1e-6));

    final pdfs = index.nearest(
      _unit([1, 0, 0]),
      const LocalQuery(search: '', memoryTypes: {MemoryType.pdf}),
    );
    expect([for (final n in pdfs) n.chunk.id], ['near', 'far']);

    final recent = index.nearest(
      _unit([1, 0, 0]),
      LocalQuery(search: '', after: DateTime.utc(2026, 2)),
    );
    // The dated photo is outside the window; undated chunks pass.
    expect([for (final n in recent) n.chunk.id], ['near', 'far']);
  });

  test('changed text drops the old vector; a changed state keeps it', () async {
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('a', text: 'one'))
      ..setVectors({
        'a': _unit([1, 0, 0]),
      });
    expect(index.pending, isEmpty);

    index.upsert(_chunk('a', text: 'one', active: false));
    expect(index.pending, isEmpty, reason: 'same text — same vector');

    index.upsert(_chunk('a', text: 'two'));
    expect(index.pending.single.id, 'a', reason: 'the vector was of "one"');
  });

  test(
    'a chunk with no text is never pending, so it cannot hold the index',
    () async {
      final index = LocalIndex.at(root);
      await index.load('u1');
      index
        ..upsert(_chunk('blank', text: '   '))
        ..upsert(_chunk('a', text: 'lease terms'))
        ..setVectors({
          'a': _unit([1, 0, 0]),
        });
      expect(index.pending, isEmpty);
      expect(index.isReady, isTrue);
      final found = index.nearest(
        _unit([1, 0, 0]),
        const LocalQuery(search: ''),
      );
      expect([for (final n in found) n.chunk.id], ['a']);
    },
  );

  test('a vector of another size is refused', () async {
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('a'))
      ..upsert(_chunk('b'))
      ..setVectors({
        'a': _unit([1, 0, 0]),
      })
      ..setVectors({
        'b': _unit([1, 0]),
      });
    expect(index.embedded, 1);
  });

  test('wiping forgets the files, so another account starts clean', () async {
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('a'))
      ..setVectors({
        'a': _unit([1, 0, 0]),
      });
    await index.persist();
    expect(root.listSync(recursive: true).whereType<File>(), isNotEmpty);

    await index.wipe();
    expect(index.isLoaded, isFalse);
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('the sync position survives a restart and goes with a wipe', () async {
    final synced = DateTime.utc(2026, 9, 27, 11, 58);
    final reconciled = DateTime.utc(2026, 9, 26, 12);
    final index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('a'))
      ..syncedAt = synced
      ..reconciledAt = reconciled;
    await index.persist();

    final again = LocalIndex.at(root);
    await again.load('u1');
    expect(again.syncedAt, synced);
    expect(again.reconciledAt, reconciled);

    await again.wipe();
    expect(again.syncedAt, isNull);
    expect(again.reconciledAt, isNull);
  });

  test('a corrupt index is an empty one, not a crash', () async {
    final dir = Directory('${root.path}/index/u1')..createSync(recursive: true);
    File('${dir.path}/chunks.json').writeAsStringSync('{not json');
    final index = LocalIndex.at(root);
    await index.load('u1');
    expect(index.size, 0);
  });
}
