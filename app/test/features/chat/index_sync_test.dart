import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/chat/data/local/embedder.dart';
import 'package:knowra/src/features/chat/data/local/index_sync.dart';
import 'package:knowra/src/features/chat/data/local/local_index.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/memory_cache.dart';

class _Auth extends Mock implements fb.FirebaseAuth {}

class _User extends Mock implements fb.User {}

class _Feed implements ChunkFeed {
  final controller = StreamController<ChunkBatch>.broadcast();
  final watched = <String>[];

  /// Where each watch started: null for a full sync.
  final sinces = <DateTime?>[];

  /// Set to make a delta watch fail, as the server does before its index
  /// has been built.
  Object? failDeltaWith;

  @override
  Stream<ChunkBatch> watch(String uid, {DateTime? since}) {
    watched.add(uid);
    sinces.add(since);
    if (since != null && failDeltaWith != null) {
      return Stream.error(failDeltaWith!);
    }
    return controller.stream;
  }
}

class _Embedder implements Embedder {
  final calls = <List<String>>[];
  Object? failWith;

  @override
  Future<List<Float32List>> documents(List<String> texts) async {
    calls.add(texts);
    if (failWith != null) throw failWith!;
    return [
      for (final t in texts) Float32List.fromList([t.length.toDouble(), 1, 0]),
    ];
  }

  @override
  Future<Float32List> query(String text) async =>
      Float32List.fromList([1, 0, 0]);
}

class _Cloud implements CloudIndex {
  final purges = <String?>[];

  @override
  Future<String?> purge({String? after}) async {
    purges.add(after);
    // Two pages, then done.
    return after == null ? 'page-1' : null;
  }
}

class _Snacks extends SnackController {
  final shown = <Snack>[];
  var dismissed = 0;

  @override
  void show(Snack snack) => shown.add(snack);

  @override
  void dismiss() => dismissed++;
}

class _Logger implements AppLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}

LocalChunk _chunk(String id, {String text = 'text', bool active = true}) =>
    LocalChunk(
      id: id,
      memoryId: 'm-$id',
      memoryTitle: '$id.pdf',
      memoryType: MemoryType.pdf,
      text: text,
      chunkIndex: 0,
      active: active,
    );

/// Following the cloud's chunks into the phone's index.
void main() {
  late Directory root;
  late _Auth auth;
  late StreamController<fb.User?> users;
  late _Feed feed;
  late _Embedder embedder;
  late _Cloud cloud;
  late _Snacks snacks;
  late LocalIndex index;
  late MemoryCacheStore cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hawk-sync-');
    auth = _Auth();
    users = StreamController<fb.User?>.broadcast();
    when(() => auth.authStateChanges()).thenAnswer((_) => users.stream);
    feed = _Feed();
    embedder = _Embedder();
    cloud = _Cloud();
    snacks = _Snacks();
    index = LocalIndex.at(root);
    cache = MemoryCacheStore();
  });
  tearDown(() => root.deleteSync(recursive: true));

  IndexSync build() =>
      IndexSync(auth, feed, embedder, cloud, index, cache, snacks, _Logger());

  fb.User user(String uid) {
    final u = _User();
    when(() => u.uid).thenReturn(uid);
    return u;
  }

  test(
    'new chunks are embedded here, in batches, then the cloud is purged',
    () {
      fakeAsync((async) {
        final sync = build()..start();
        users.add(user('u1'));
        async.flushMicrotasks();
        expect(feed.watched, ['u1']);

        feed.controller.add(
          ChunkBatch([
            for (var i = 0; i < 120; i++)
              (id: 'c$i', chunk: _chunk('c$i', text: 't$i')),
          ]),
        );
        async.flushMicrotasks();
        // 120 texts is three calls of at most fifty.
        expect(embedder.calls.map((c) => c.length), [50, 50, 20]);
        expect(sync.isReady, isTrue);
        expect(sync.pending, 0);
        // Once complete, the cloud's copies go — page by page, once.
        expect(cloud.purges, [null, 'page-1']);
        // The first build showed its progress, then cleared it.
        expect(snacks.shown.whereType<ProgressSnack>(), isNotEmpty);
        expect(snacks.dismissed, 1);

        // A later drain does not purge again.
        feed.controller.add(ChunkBatch([(id: 'c999', chunk: _chunk('c999'))]));
        async.flushMicrotasks();
        expect(cloud.purges, hasLength(2));

        async.elapse(IndexSync.persistAfter);
        async.flushMicrotasks();
        sync.dispose();
      });
    },
  );

  test(
    'an over-long chunk is sent cut to the bound; a blank one not at all',
    () {
      // The real case: one 4,193-character chunk in a batch of five, and the
      // server refusing the whole batch, every retry, so the index could
      // never be ready.
      fakeAsync((async) {
        final sync = build()..start();
        users.add(user('u1'));
        async.flushMicrotasks();

        feed.controller.add(
          ChunkBatch([
            (
              id: 'big',
              chunk: _chunk('big', text: 'x' * (Embedder.maxChars + 500)),
            ),
            (id: 'blank', chunk: _chunk('blank', text: '   ')),
            (id: 'ok', chunk: _chunk('ok', text: 'fine')),
          ]),
        );
        async.flushMicrotasks();

        expect(embedder.calls.single.map((t) => t.length), [
          Embedder.maxChars,
          4,
        ]);
        expect(sync.isReady, isTrue);
        expect(sync.pending, 0);

        async.elapse(IndexSync.persistAfter);
        async.flushMicrotasks();
        sync.dispose();
      });
    },
  );

  test(
    'chunks deleted while the phone was away go on the first delivery',
    () async {
      // The listener only reports removals it witnesses. A delete that
      // happened while this device was closed arrives as an absence: the
      // first server snapshot is the whole collection, and what the disk
      // knows that the cloud no longer lists is dropped.
      final earlier = LocalIndex.at(root);
      await earlier.load('u1');
      earlier
        ..upsert(_chunk('kept'))
        ..upsert(_chunk('deleted'))
        ..setVectors({
          'kept': Float32List.fromList([1, 0, 0]),
          'deleted': Float32List.fromList([0, 1, 0]),
        });
      await earlier.persist();

      final sync = build()..start();
      users.add(user('u1'));
      for (var i = 0; i < 100 && feed.watched.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(feed.watched, ['u1']);

      feed.controller.add(
        ChunkBatch([(id: 'kept', chunk: _chunk('kept'))], everyId: {'kept'}),
      );
      for (var i = 0; i < 100 && index['deleted'] != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(index['deleted'], isNull);
      expect(index['kept'], isNotNull);
      expect(sync.isReady, isTrue);
      expect(embedder.calls, isEmpty, reason: 'same text, same vector');
      sync.dispose();
    },
  );

  test('a removed chunk leaves; changed text is re-embedded', () {
    fakeAsync((async) {
      final sync = build()..start();
      users.add(user('u1'));
      async.flushMicrotasks();
      feed.controller.add(
        ChunkBatch([
          (id: 'a', chunk: _chunk('a', text: 'one')),
          (id: 'b', chunk: _chunk('b', text: 'two')),
        ]),
      );
      async.flushMicrotasks();
      expect(index.embedded, 2);

      feed.controller.add(
        ChunkBatch([
          (id: 'a', chunk: null),
          (id: 'b', chunk: _chunk('b', text: 'two, revised')),
        ]),
      );
      async.flushMicrotasks();
      expect(index.size, 1);
      expect(embedder.calls.last, ['two, revised']);
      expect(sync.isReady, isTrue);

      async.elapse(IndexSync.persistAfter);
      async.flushMicrotasks();
      sync.dispose();
    });
  });

  test(
    'a failed embedding call is retried, and the index is not ready meanwhile',
    () {
      fakeAsync((async) {
        final sync = build()..start();
        users.add(user('u1'));
        async.flushMicrotasks();
        embedder.failWith = StateError('offline');
        feed.controller.add(ChunkBatch([(id: 'a', chunk: _chunk('a'))]));
        async.flushMicrotasks();
        expect(sync.isReady, isFalse);
        expect(embedder.calls, hasLength(1));

        embedder.failWith = null;
        async.elapse(IndexSync.retries.first);
        async.flushMicrotasks();
        expect(embedder.calls, hasLength(2));
        expect(sync.isReady, isTrue);

        async.elapse(IndexSync.persistAfter);
        async.flushMicrotasks();
        sync.dispose();
      });
    },
  );

  test('signing out wipes the index; another account starts empty', () async {
    // Real time, not fakeAsync: wiping is file IO, which fake time cannot
    // drive to completion. Each step is awaited by polling for its effect
    // rather than by a fixed sleep, so a slow disk cannot make it flaky.
    final sync = build()..start();
    users.add(user('u1'));
    await _until(() => feed.watched.contains('u1'));
    feed.controller.add(ChunkBatch([(id: 'a', chunk: _chunk('a'))]));
    await _until(() => index.embedded == 1);
    await _until(() => _files(root).isNotEmpty, reason: 'persisted');

    users.add(null);
    await _until(() => !index.isLoaded, reason: 'wiped');
    await _until(() => _files(root).isEmpty, reason: 'files gone');

    users.add(user('u2'));
    await _until(() => feed.watched.length == 2);
    expect(feed.watched, ['u1', 'u2']);
    expect(index.size, 0);
    sync.dispose();
  });

  group('delta sync', () {
    final noon = DateTime.utc(2026, 9, 27, 12);
    setUp(() => IndexSync.clock = () => noon);
    tearDown(() => IndexSync.clock = DateTime.now);

    Future<void> saved({
      required DateTime synced,
      required DateTime reconciled,
    }) async {
      final earlier = LocalIndex.at(root);
      await earlier.load('u1');
      earlier
        ..upsert(_chunk('a'))
        ..setVectors({
          'a': Float32List.fromList([1, 0, 0]),
        })
        ..syncedAt = synced
        ..reconciledAt = reconciled;
      await earlier.persist();
    }

    test('a first sync is full, and records where the next one starts', () {
      fakeAsync((async) {
        build().start();
        users.add(user('u1'));
        async.flushMicrotasks();
        expect(feed.sinces, [null], reason: 'nothing saved: read everything');

        final stamp = DateTime.utc(2026, 9, 27, 11, 58);
        feed.controller.add(
          ChunkBatch(
            [(id: 'a', chunk: _chunk('a'))],
            everyId: {'a'},
            latest: stamp,
          ),
        );
        async.flushMicrotasks();
        expect(index.syncedAt, stamp);
        expect(index.reconciledAt, noon);
      });
    });

    test('a restart within a week asks only for what changed', () async {
      final synced = DateTime.utc(2026, 9, 26, 9);
      await saved(
        synced: synced,
        reconciled: noon.subtract(const Duration(days: 2)),
      );

      final sync = build()..start();
      users.add(user('u1'));
      await _until(() => feed.sinces.isNotEmpty);
      expect(feed.sinces.single, synced.subtract(IndexSync.overlap));
      expect(index.size, 1, reason: 'the saved chunks, without a download');
      sync.dispose();
    });

    test('after a week it reads the whole set again', () async {
      await saved(
        synced: DateTime.utc(2026, 9, 26, 9),
        reconciled: noon.subtract(IndexSync.reconcileEvery),
      );

      final sync = build()..start();
      users.add(user('u1'));
      await _until(() => feed.sinces.isNotEmpty);
      expect(feed.sinces.single, isNull);
      sync.dispose();
    });

    test('a delta the server refuses falls back to a full sync', () async {
      final synced = DateTime.utc(2026, 9, 26, 9);
      await saved(
        synced: synced,
        reconciled: noon.subtract(const Duration(days: 1)),
      );
      feed.failDeltaWith = Exception('FAILED_PRECONDITION: needs an index');

      final sync = build()..start();
      users.add(user('u1'));
      await _until(() => feed.sinces.length == 2);
      expect(feed.sinces, [synced.subtract(IndexSync.overlap), null]);
      sync.dispose();
    });

    test('a newer change moves the position; an older one does not', () {
      fakeAsync((async) {
        build().start();
        users.add(user('u1'));
        async.flushMicrotasks();
        final later = DateTime.utc(2026, 9, 27, 11);
        feed.controller.add(
          ChunkBatch([(id: 'a', chunk: _chunk('a'))], latest: later),
        );
        async.flushMicrotasks();
        feed.controller.add(
          ChunkBatch([
            (id: 'b', chunk: _chunk('b')),
          ], latest: later.subtract(const Duration(hours: 3))),
        );
        async.flushMicrotasks();
        expect(index.syncedAt, later);
      });
    });

    test('a chunk the cloud marked deleted arrives as a removal', () {
      final gone = FirestoreChunkFeed.changeFrom('c1', {
        'memoryId': 'm1',
        'text': '',
        'deleted': true,
      });
      expect(gone.chunk, isNull);
      expect(
        FirestoreChunkFeed.changeFrom('c2', {'text': 'x'}, removed: true).chunk,
        isNull,
      );
      expect(
        FirestoreChunkFeed.changeFrom('c3', {'text': 'lease'}).chunk?.text,
        'lease',
      );
    });

    test('the server commit time is read off the chunk', () {
      final at = DateTime.utc(2026, 9, 27, 10, 30);
      expect(
        FirestoreChunkFeed.updatedAtOf({'updatedAt': Timestamp.fromDate(at)}),
        at,
      );
      expect(FirestoreChunkFeed.updatedAtOf(const {}), isNull);
    });
  });

  test('a chunk document reads as the cloud writes it', () {
    final chunk = FirestoreChunkFeed.chunkFrom('c1', {
      'memoryId': 'm1',
      'memoryTitle': 'lease.pdf',
      'memoryType': 'pdf',
      'text': 'Rent is due on the first.',
      'chunkIndex': 3,
      'recallState': 'dormant',
      'capturedAt': '2026-09-01T10:00:00Z',
    });
    expect(chunk.memoryType, MemoryType.pdf);
    expect(chunk.active, isFalse);
    expect(chunk.chunkIndex, 3);
    expect(chunk.capturedAt, DateTime.utc(2026, 9, 1, 10));
  });
}

List<File> _files(Directory root) =>
    root.listSync(recursive: true).whereType<File>().toList();

/// Polls until [condition] holds, for up to three seconds of real time.
Future<void> _until(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting${reason == null ? '' : ' for $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
