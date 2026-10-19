import 'dart:async';

// `Source` is hidden: cloud_firestore exports one (the cache-vs-server enum
// for reads) and so does the domain, where it means the original a memory
// points at. The domain one is what this file builds.
import 'package:cloud_firestore/cloud_firestore.dart' hide Source;
import 'package:cloud_firestore/cloud_firestore.dart' as firestore show Source;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/files/local_originals.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/memory.dart';
import '../../domain/entities/memory_enums.dart';
import '../../domain/repositories/memory_repository.dart';

/// [MemoryRepository] backed by Firestore.
///
/// Same interface as the REST version, so the BLoC, the Library screen and
/// their tests are untouched.
///
/// Two things differ from SQL in ways that shape the code:
///
/// **Tenancy is a `where` clause *and* a rule.** Every query filters by
/// `userId` because Firestore rules reject reads that could return another
/// user's documents — the filter is not defence in depth, it is what makes the
/// query legal at all.
///
/// **There is no `COUNT(*)`.** Firestore's aggregate `count()` is a separate
/// billed query, so paging uses a cursor and reports "is there more" rather
/// than a total. [MemoryPage] carries `hasMore` for exactly that reason — an
/// earlier version smuggled it in as `total + 1`, and the library header
/// printed the sentinel as a count.
@LazySingleton(as: MemoryRepository)
class FirestoreMemoryRepository implements MemoryRepository {
  FirestoreMemoryRepository(
    this._firestore,
    this._auth,
    this._logger,
    this._originals,
  );

  final FirebaseFirestore _firestore;
  final fb.FirebaseAuth _auth;
  final AppLogger _logger;
  final LocalOriginals _originals;

  static const _collection = 'memories';

  /// Cursor for the next page, keyed by the filter it belongs to.
  ///
  /// Held here rather than passed through the domain because an opaque
  /// Firestore cursor is a storage detail; leaking it into `MemoryRepository`
  /// would put a Firestore type in the domain layer.
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _cursorKey;

  String get _userId {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AppException.unauthorized();
    return uid;
  }

  Query<Map<String, dynamic>> _query({
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(_collection)
        .where('userId', isEqualTo: _userId);

    // One kind is an equality; a group is `in`, which Firestore runs on the
    // same (userId, type, createdAt) index as a merge of equalities.
    if (types.length == 1) {
      query = query.where('type', isEqualTo: types.single.wireName);
    } else if (types.isNotEmpty) {
      query = query.where('type', whereIn: _wire(types));
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }
    return query.orderBy('createdAt', descending: true);
  }

  /// Sorted, so the same group always names the same query and cursor key.
  static List<String> _wire(Set<MemoryType> types) =>
      [for (final t in types) t.wireName]..sort();

  @override
  Future<MemoryPage> fetchMemories({
    int limit = 20,
    int offset = 0,
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) => _guard('fetchMemories', () async {
    final key = '${_wire(types).join(',')}/${status?.name}';

    // offset 0 means "start over" — a filter change or a pull-to-refresh.
    // Firestore has no offset that is not a full scan, so the contract is
    // honoured with a cursor that resets here.
    if (offset == 0 || key != _cursorKey) {
      _cursor = null;
      _cursorKey = key;
    }

    var query = _query(types: types, status: status).limit(limit);
    if (offset > 0 && _cursor != null) {
      query = query.startAfterDocument(_cursor!);
    }

    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;

    final items = snapshot.docs.map(_toEntity).toList();

    // A full page probably means more; a short one certainly means the end.
    // Cheaper and honest, versus paying for an aggregate count on every page.
    return (items: items, hasMore: items.length == limit, offset: offset);
  });

  @override
  Future<MemoryPage?> cachedMemories({
    int limit = 20,
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) async {
    // `get()` on its default source waits for the server whenever the phone
    // is online, so the library showed a spinner on every open even though
    // Firestore had the same rows on disk from last time. Reading the local
    // copy first is what makes the list appear at once.
    try {
      final snapshot = await _query(
        types: types,
        status: status,
      ).limit(limit).get(const GetOptions(source: firestore.Source.cache));
      if (snapshot.docs.isEmpty) return null;
      return (
        items: snapshot.docs.map(_toEntity).toList(),
        hasMore: snapshot.docs.length == limit,
        offset: 0,
      );
    } on Object {
      // Nothing cached yet, or no persistence on this platform.
      return null;
    }
  }

  @override
  Stream<List<Memory>> watchMemories(List<String> ids) {
    if (ids.isEmpty) return Stream.value(const <Memory>[]);

    // One document stream per id, not a `whereIn` query. `whereIn` stops at
    // 30 values, a batch pick can be larger, and chunking it would mean
    // stitching several query streams back together anyway. A document
    // listen is also checked by the rules one document at a time, which is
    // exactly the ownership rule this screen needs.
    final latest = <String, Memory>{};
    final subscriptions = <StreamSubscription<Object?>>[];
    late final StreamController<List<Memory>> controller;

    void emit() => controller.add([for (final id in ids) ?latest[id]]);

    controller = StreamController<List<Memory>>(
      onListen: () {
        for (final id in ids) {
          subscriptions.add(
            _firestore.collection(_collection).doc(id).snapshots().listen((
              doc,
            ) {
              if (!doc.exists || doc.data()?['userId'] != _userId) {
                latest.remove(id);
              } else {
                latest[id] = _toEntity(doc);
              }
              emit();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Memory> fetchMemory(String id) => _guard('fetchMemory', () async {
    final doc = await _firestore.collection(_collection).doc(id).get();

    // Ownership checked here as well as in the rules: a denied read and a
    // missing document should look the same to the caller, and relying on the
    // rule alone would surface a `permission-denied` that says more than it
    // should.
    if (!doc.exists || doc.data()?['userId'] != _userId) {
      throw const AppException.notFound(message: 'That memory does not exist.');
    }

    unawaited(
      doc.reference.update({
        'accessCount': FieldValue.increment(1),
        'lastAccessedAt': FieldValue.serverTimestamp(),
      }),
    );

    return _toEntity(doc);
  });

  @override
  Future<Memory> capture({
    MemoryType type = MemoryType.note,
    String? title,
    String? text,
    String? url,
    String? storagePath,
    String? mimeType,
    int? sizeBytes,
    String? contentHash,
  }) => _guard('capture', () async {
    final now = FieldValue.serverTimestamp();

    final data = <String, dynamic>{
      'userId': _userId,
      'type': (url != null ? MemoryType.link : type).wireName,
      // Both are pipeline-owned and rule-pinned to these values on create: a
      // client that could write `ready` would make an un-embedded memory
      // answerable.
      'status': ProcessingStatus.uploaded.name,
      'recallState': 'active',
      'title': ?title,
      'text': ?text,
      'url': ?url,
      // Read by the ingestion trigger, which downloads the file and hands it
      // to the model. `mimeType` is what decides the extraction route, and
      // `storage.rules` already matched on it at upload time.
      'storagePath': ?storagePath,
      'mimeType': ?mimeType,
      'bytes': ?sizeBytes,
      'contentHash': ?contentHash,
      'importance': 0.0,
      'accessCount': 0,
      'createdAt': now,
      'updatedAt': now,
    };

    final ref = await _firestore.collection(_collection).add(data);
    final created = await ref.get();
    return _toEntity(created);
  });

  @override
  Future<Memory?> findByContentHash(String contentHash) =>
      _guard('findByContentHash', () async {
        // Two equality filters, which Firestore serves by merging its
        // automatic single-field indexes — no composite index to deploy.
        // `userId` is not optional: the rules only let a query through if it
        // can only ever return the caller's own documents.
        final snapshot = await _firestore
            .collection(_collection)
            .where('userId', isEqualTo: _userId)
            .where('contentHash', isEqualTo: contentHash)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) return null;
        return _toEntity(snapshot.docs.first);
      });

  @override
  Future<void> deleteMemory(String id) => _guard('deleteMemory', () async {
    final doc = await _firestore.collection(_collection).doc(id).get();
    if (!doc.exists || doc.data()?['userId'] != _userId) {
      throw const AppException.notFound(message: 'That memory does not exist.');
    }

    // Deletes the memory and Hawk's own working copy of its file.
    //
    // The user's original is never touched — removing what you remember
    // about a file and removing the file are different intents, and the
    // second lives behind an explicit confirmation. But the copy kept under
    // `originals/` is Hawk's, not theirs: left behind, it would be storage
    // on their phone spent on a memory that no longer exists, with no way
    // left in the app to find or remove it.
    await doc.reference.delete();
    try {
      await _originals.forget(id);
    } on Object catch (error) {
      _logger.warning(
        'Could not remove the kept original',
        name: 'memory',
        data: {'error': error.toString()},
      );
    }
  });

  Memory _toEntity(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};

    return Memory(
      id: doc.id,
      type: MemoryType.parse(data['type'] as String?),
      status: ProcessingStatus.parse(data['status'] as String?),
      // serverTimestamp resolves to null in the local write echo before the
      // server acknowledges it; falling back to now keeps a just-captured
      // memory sortable instead of throwing.
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      title: data['title'] as String?,
      description: data['description'] as String?,
      text: data['text'] as String?,
      language: data['language'] as String?,
      indexNote: data['indexNote'] as String?,
      failure: data['error'] as String?,
      retryable: data['errorRetryable'] as bool? ?? false,
      // The flag ingestion now writes; for memories indexed before it
      // existed, the budget's own fixed sentence for "nothing fitted". An
      // older *partially* indexed memory cannot be told apart from a
      // per-file ceiling and is left unflagged rather than guessed at.
      overQuota:
          data['overQuota'] as bool? ??
          ((data['indexNote'] as String?)?.startsWith(
                "Your plan's index is full",
              ) ??
              false),
      importance: (data['importance'] as num?)?.toDouble() ?? 0,
      source: _source(doc.id, data),
      // Present once ingestion has kept the file; null for a note, a link,
      // or a capture that crossed the plan's file allowance.
      storagePath: data['storagePath'] as String?,
    );
  }

  /// Where the memory came from — §10's pointer to the original.
  ///
  /// This was missing entirely, which was not just a lost field. A link
  /// captured with no note has its url as the only thing to show, so every
  /// such row read "Untitled"; and every Drive-indexed memory lost its
  /// provider, mime type and source reference, which is the pointer the
  /// whole BYOS model rests on.
  ///
  /// Null when there is genuinely no original: a note typed into the app is
  /// its own content, and a `Source` with every field empty would claim
  /// otherwise.
  Source? _source(String memoryId, Map<String, dynamic> data) {
    final url = data['url'] as String?;
    final ref = data['sourceRef'] as String?;
    final provider = data['provider'] as String?;
    final filename = data['sourceFilename'] as String?;

    if (url == null && ref == null && provider == null && filename == null) {
      return null;
    }

    return Source(
      // The provider's own id where there is one, so a re-index can match
      // this memory to the same file rather than creating a second.
      id: ref ?? url ?? memoryId,
      provider: StorageProvider.parse(provider),
      url: url,
      filename: filename,
      mimeType: data['mimeType'] as String?,
      sizeBytes: (data['bytes'] as num?)?.toInt(),
      capturedAt: (data['capturedAt'] as Timestamp?)?.toDate(),
    );
  }

  Future<T> _guard<T>(String name, Future<T> Function() body) async {
    _logger.breadcrumb(name, category: 'repository.memory');
    try {
      return await body();
    } on FirebaseException catch (error, stackTrace) {
      throw _map(error, stackTrace);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw AppException.unknown(cause: error, stackTrace: stackTrace);
    }
  }

  static AppException _map(FirebaseException error, StackTrace stackTrace) =>
      switch (error.code) {
        'unavailable' || 'deadline-exceeded' => const AppException.network(),
        'permission-denied' => const AppException.unauthorized(),
        'not-found' => const AppException.notFound(),
        // A composite index is missing or still building. In debug the message
        // carries a console link that creates it.
        'failed-precondition' => AppException.server(
          message: 'That view is not ready yet. ${error.message ?? ''}'.trim(),
        ),
        _ => AppException.unknown(cause: error, stackTrace: stackTrace),
      };
}
