import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/cache/cache_store.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import 'embedder.dart';
import 'local_index.dart';

/// One change to the cloud's chunks: a chunk as it now is, or one that is
/// gone. What [ChunkFeed] delivers and [IndexSync] applies.
typedef ChunkChange = ({String id, LocalChunk? chunk});

/// One delivery from the cloud: the changes since the last one and, on a
/// full sync, every id that exists.
///
/// A listener only reports the removals it witnesses. A memory deleted while
/// this device was closed never arrives as a `removed` change — it arrives
/// as an absence, and the only way to see an absence is to be handed the
/// whole set once. [everyId] is that set, on the first delivery of a full
/// sync that comes from the server rather than the local cache.
class ChunkBatch {
  const ChunkBatch(this.changes, {this.everyId, this.latest});

  final List<ChunkChange> changes;
  final Set<String>? everyId;

  /// The newest server `updatedAt` among these changes, if any carried one.
  final DateTime? latest;
}

/// The cloud's chunks for a user, as a stream of deliveries.
///
/// An interface over the Firestore listener so [IndexSync] can be driven in
/// a test without a Firestore.
abstract interface class ChunkFeed {
  /// Every chunk when [since] is null; otherwise only chunks changed after
  /// it — including the ones marked deleted (`chunk_store`), which arrive as
  /// removals.
  Stream<ChunkBatch> watch(String uid, {DateTime? since});
}

@LazySingleton(as: ChunkFeed)
class FirestoreChunkFeed implements ChunkFeed {
  FirestoreChunkFeed(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<ChunkBatch> watch(String uid, {DateTime? since}) {
    var complete = false;
    Query<Map<String, dynamic>> query = _firestore
        .collection('chunks')
        .where('userId', isEqualTo: uid);
    // A delta: only what changed. Every listener start used to read the
    // whole collection — Firestore bills a fresh query in full once a
    // listener has been gone for thirty minutes, so each cold start cost a
    // read per chunk the user had ever indexed.
    if (since != null) {
      query = query.where(
        'updatedAt',
        isGreaterThan: Timestamp.fromDate(since),
      );
    }
    return query.snapshots().map((snapshot) {
      // The whole set travels once, only on a full sync, and only from the
      // server: a cached first snapshot can be partial, and reconciling
      // against it would drop chunks that merely had not been fetched yet.
      final whole =
          since == null && !complete && !snapshot.metadata.isFromCache;
      if (whole) complete = true;
      final changes = <ChunkChange>[];
      DateTime? latest;
      for (final change in snapshot.docChanges) {
        final data = change.doc.data() ?? const <String, dynamic>{};
        changes.add(
          changeFrom(
            change.doc.id,
            data,
            removed: change.type == DocumentChangeType.removed,
          ),
        );
        final at = updatedAtOf(data);
        if (at != null && (latest == null || at.isAfter(latest))) latest = at;
      }
      return ChunkBatch(
        changes,
        everyId: whole ? {for (final doc in snapshot.docs) doc.id} : null,
        latest: latest,
      );
    });
  }

  /// One change: a removal when the listener saw the document go or the
  /// cloud marked it deleted, the chunk as it now is otherwise.
  @visibleForTesting
  static ChunkChange changeFrom(
    String id,
    Map<String, dynamic> data, {
    bool removed = false,
  }) => (
    id: id,
    chunk: removed || data['deleted'] == true ? null : chunkFrom(id, data),
  );

  /// The server's commit time on a chunk, when it has one — chunks written
  /// before delta sync existed do not.
  @visibleForTesting
  static DateTime? updatedAtOf(Map<String, dynamic> data) =>
      switch (data['updatedAt']) {
        final Timestamp at => at.toDate().toUtc(),
        _ => null,
      };

  /// A chunk document as the cloud writes it (`ingestion._write_chunks`).
  @visibleForTesting
  static LocalChunk chunkFrom(String id, Map<String, dynamic> data) {
    final captured = data['capturedAt'];
    return LocalChunk(
      id: id,
      memoryId: data['memoryId'] as String? ?? '',
      memoryTitle: data['memoryTitle'] as String? ?? 'Untitled',
      memoryType: MemoryType.parse(data['memoryType'] as String?),
      text: data['text'] as String? ?? '',
      chunkIndex: (data['chunkIndex'] as num?)?.toInt() ?? 0,
      active: (data['recallState'] as String? ?? 'active') == 'active',
      capturedAt: switch (captured) {
        Timestamp() => captured.toDate(),
        String() => DateTime.tryParse(captured),
        _ => null,
      },
    );
  }
}

/// Keeps the phone's index in step with the cloud's chunks.
///
/// The cloud is the source of *text*: every memory's chunks live in the
/// `chunks` collection, written by ingestion and the Drive sync. This
/// follows that collection for the signed-in user and mirrors it into
/// [LocalIndex] — new chunks embedded here (through [Embedder]), changed
/// text re-embedded, dormant ones marked, deleted ones dropped. When every
/// chunk has a vector the device asks the cloud to delete the vectors it
/// used to hold ([CloudIndex.purge]), once, and from then on the only copy
/// of the searchable index is this phone's.
///
/// Bound to the auth state: signing out wipes the local files, and a
/// different account starts from an empty index.
@lazySingleton
class IndexSync extends ChangeNotifier {
  IndexSync(
    this._auth,
    this._feed,
    this._embedder,
    this._cloud,
    this._index,
    this._cache,
    this._snacks,
    this._logger,
  );

  final fb.FirebaseAuth _auth;
  final ChunkFeed _feed;
  final Embedder _embedder;
  final CloudIndex _cloud;
  final LocalIndex _index;
  final CacheStore _cache;
  final SnackController _snacks;
  final AppLogger _logger;

  StreamSubscription<String?>? _users;
  StreamSubscription<ChunkBatch>? _chunks;
  String? _uid;
  bool _draining = false;
  bool _persistScheduled = false;
  var _failures = 0;
  Timer? _retry;

  /// Waits after a failed embedding call. Bounded: the next chunk change
  /// retries anyway.
  static const retries = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
  ];

  /// How long a burst of changes is collected before the index is written.
  static const persistAfter = Duration(milliseconds: 500);

  /// How long delta syncs are trusted before the whole set is read again —
  /// the safety net for anything a delta could miss (a phone whose clock
  /// was wrong, a tombstone swept before this phone saw it). Well inside
  /// `chunk_store.TOMBSTONE_DAYS`.
  static const reconcileEvery = Duration(days: 7);

  /// How far before the saved position a delta starts. Upserts are
  /// idempotent, so reading a few chunks twice is free; missing one is not.
  static const overlap = Duration(minutes: 10);

  /// The clock, for tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static const _purgedKey = 'index.cloudPurged';

  /// Whether a search should run on this phone rather than the server.
  bool get isReady => _index.isReady;

  /// Chunks still waiting for a vector on this device.
  int get pending => _index.pending.length;
  int get total => _index.size;

  /// Starts following the signed-in user. Idempotent.
  void start() {
    _users ??= _auth
        .authStateChanges()
        .map((u) => u?.uid)
        .distinct()
        .listen((uid) => unawaited(_bind(uid)));
  }

  Future<void> _bind(String? uid) async {
    await _chunks?.cancel();
    _chunks = null;
    _retry?.cancel();
    if (_uid != null && _uid != uid) await _index.wipe();
    _uid = uid;
    notifyListeners();
    if (uid == null) return;

    await _index.load(uid);
    if (_uid != uid) return;
    notifyListeners();

    _listen(uid, since: _deltaSince());
    // Whatever was waiting from last time.
    unawaited(_drain());
  }

  /// Where a delta sync would start, or null when the whole set should be
  /// read: no saved position yet, or the last full reconcile is too old.
  DateTime? _deltaSince() {
    final synced = _index.syncedAt;
    final reconciled = _index.reconciledAt;
    if (synced == null || reconciled == null) return null;
    if (clock().difference(reconciled) >= reconcileEvery) return null;
    return synced.subtract(overlap);
  }

  void _listen(String uid, {DateTime? since}) {
    _chunks = _feed
        .watch(uid, since: since)
        .listen(
          _apply,
          onError: (Object error) {
            _logger.warning(
              'Chunk sync failed',
              name: 'index',
              data: {'error': error.toString(), 'delta': since != null},
            );
            // A delta the server will not run — its index still building
            // after a deploy — falls back to the full sync that always works.
            if (since != null && _uid == uid) {
              unawaited(_chunks?.cancel());
              _listen(uid);
            }
          },
        );
  }

  void _apply(ChunkBatch batch) {
    if (_uid == null) return;
    for (final change in batch.changes) {
      final chunk = change.chunk;
      if (chunk == null) {
        _index.remove(change.id);
      } else {
        _index.upsert(chunk);
      }
    }
    // What this device still holds but the cloud no longer lists was deleted
    // while the device was away — a removal the listener never saw.
    var reconciled = 0;
    if (batch.everyId case final every?) {
      for (final id in _index.ids.toList()) {
        if (every.contains(id)) continue;
        _index.remove(id);
        reconciled++;
      }
    }
    // Where the next delta starts. A full sync of chunks that predate
    // `updatedAt` carries none, so it starts an hour back on this phone's
    // clock — the weekly reconcile covers a clock that was wrong.
    var moved = false;
    final latest = batch.latest;
    final synced = _index.syncedAt;
    if (latest != null && (synced == null || latest.isAfter(synced))) {
      _index.syncedAt = latest;
      moved = true;
    }
    if (batch.everyId != null) {
      _index
        ..reconciledAt = clock().toUtc()
        ..syncedAt ??= clock().toUtc().subtract(const Duration(hours: 1));
      moved = true;
    }
    final changed = batch.changes.isNotEmpty || reconciled > 0;
    if (!changed && !moved) return;
    _schedulePersist();
    if (!changed) return;
    notifyListeners();
    unawaited(_drain());
  }

  /// Embeds whatever is waiting, a batch at a time, until nothing is.
  Future<void> _drain() async {
    if (_draining || _uid == null) return;
    _draining = true;
    final uid = _uid;
    final startedWith = _index.pending.length;
    final firstBuild = _index.embedded == 0 && startedWith > 0;
    try {
      while (_uid == uid) {
        final batch = _index.pending.take(Embedder.batch).toList();
        if (batch.isEmpty) break;
        final vectors = await _embedder.documents([
          for (final c in batch) _clamp(c.text),
        ]);
        if (_uid != uid) return;
        _index.setVectors({
          for (final (i, c) in batch.indexed) c.id: vectors[i],
        });
        _failures = 0;
        _schedulePersist();
        if (firstBuild) _progress(startedWith);
        notifyListeners();
      }
      if (_uid == uid && _index.isReady) {
        if (firstBuild) _snacks.dismiss();
        await _purgeCloud();
      }
    } on Object catch (error) {
      _logger.warning(
        'Embedding failed',
        name: 'index',
        data: {'error': error.toString(), 'pending': _index.pending.length},
      );
      if (_failures < retries.length) {
        _retry?.cancel();
        _retry = Timer(retries[_failures], () => unawaited(_drain()));
      }
      _failures++;
    } finally {
      _draining = false;
    }
  }

  /// See [Embedder.maxChars]: the server embeds the head of a giant chunk
  /// and cuts the rest, so the rest is not worth sending.
  static String _clamp(String text) => text.length <= Embedder.maxChars
      ? text
      : text.substring(0, Embedder.maxChars);

  void _progress(int total) {
    final done = total - _index.pending.length;
    _snacks.show(
      Snack.progress(
        message: 'Indexing on this phone',
        fraction: total == 0 ? 1 : (done / total).clamp(0.0, 1.0),
      ),
    );
  }

  /// Asks the cloud to delete the vectors it used to hold — once, and only
  /// after every chunk has a vector here.
  Future<void> _purgeCloud() async {
    try {
      final done = await _cache.read(_purgedKey);
      if (done?.value['done'] == true) return;
      String? after;
      var pages = 0;
      do {
        after = await _cloud.purge(after: after);
        pages++;
      } while (after != null && pages < 500);
      await _cache.write(_purgedKey, {'done': true});
      _logger.info(
        'Cloud vectors purged',
        name: 'index',
        data: {'pages': pages},
      );
    } on Object catch (error) {
      // Not urgent: the next completed drain tries again.
      _logger.warning(
        'Could not purge cloud vectors',
        name: 'index',
        data: {'error': error.toString()},
      );
    }
  }

  void _schedulePersist() {
    if (_persistScheduled) return;
    _persistScheduled = true;
    // One write per burst: a snapshot of forty new chunks, or a drain of
    // fifty vectors, is one file write rather than forty.
    Timer(persistAfter, () async {
      _persistScheduled = false;
      try {
        await _index.persist();
      } on Object catch (error) {
        _logger.warning(
          'Could not save the index',
          name: 'index',
          data: {'error': error.toString()},
        );
      }
    });
  }

  /// A vector for [text] as a question, from the same embedder as the
  /// chunks — the one rule an index like this has.
  Future<Float32List> embedQuery(String text) => _embedder.query(text);

  @override
  void dispose() {
    _retry?.cancel();
    unawaited(_chunks?.cancel());
    unawaited(_users?.cancel());
    super.dispose();
  }
}
