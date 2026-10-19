import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../memory/domain/entities/memory_enums.dart';
import 'local_query.dart';
import 'ranking.dart';

/// One chunk as the phone's index knows it: the cloud's text and metadata,
/// plus — once this device has embedded it — its vector.
class LocalChunk {
  const LocalChunk({
    required this.id,
    required this.memoryId,
    required this.memoryTitle,
    required this.memoryType,
    required this.text,
    required this.chunkIndex,
    required this.active,
    this.capturedAt,
  });

  final String id;
  final String memoryId;
  final String memoryTitle;
  final MemoryType memoryType;
  final String text;
  final int chunkIndex;

  /// `recallState == active`. A dormant chunk keeps its vector — an upgrade
  /// revives it — but never answers.
  final bool active;
  final DateTime? capturedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'memoryId': memoryId,
    'memoryTitle': memoryTitle,
    'memoryType': memoryType.wireName,
    'text': text,
    'chunkIndex': chunkIndex,
    'active': active,
    'capturedAt': capturedAt?.toIso8601String(),
  };

  factory LocalChunk.fromJson(Map<String, dynamic> j) => LocalChunk(
    id: j['id'] as String,
    memoryId: j['memoryId'] as String? ?? '',
    memoryTitle: j['memoryTitle'] as String? ?? 'Untitled',
    memoryType: MemoryType.parse(j['memoryType'] as String?),
    text: j['text'] as String? ?? '',
    chunkIndex: (j['chunkIndex'] as num?)?.toInt() ?? 0,
    active: j['active'] as bool? ?? true,
    capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? ''),
  );
}

/// A nearest-neighbour hit: the chunk and its cosine distance.
typedef Nearest = ({LocalChunk chunk, double distance});

/// The vectors, on this phone and nowhere else.
///
/// The cloud stores each chunk's text; this store holds the same chunks with
/// the vectors this device made for them, and answers the question the
/// server's Firestore index used to answer: which passages are nearest to a
/// query. Everything a search needs is here, so a search touches the network
/// only to embed the question.
///
/// **Files, not a database.** Two files per user under application support:
/// `chunks.json` (the chunk metadata, in vector-row order) and `vectors.bin`
/// (the rows, `Float32`, back to back). A personal vault is thousands of
/// chunks, not millions; loading all of it into memory once and scanning it
/// is a few milliseconds, and writing both files whole after a change is
/// simpler and more auditable than a schema. Written to a temp name and
/// renamed, so a crash mid-write leaves the previous index, never half of
/// one.
///
/// Sign-out wipes the files: another person's vectors must not survive on a
/// shared phone.
@lazySingleton
class LocalIndex {
  LocalIndex();

  /// Points the store at a temporary directory, for tests.
  @visibleForTesting
  LocalIndex.at(this._rootOverride);

  Directory? _rootOverride;
  String? _uid;

  final _chunks = <String, LocalChunk>{};
  final _vectors = <String, Float32List>{};
  int _dims = 0;

  /// The newest server `updatedAt` this index has applied — where the next
  /// delta sync starts. Null until a full sync has landed.
  DateTime? syncedAt;

  /// When the last full reconcile landed. Delta sync is trusted for
  /// `IndexSync.reconcileEvery` after it, then the whole set is read again.
  DateTime? reconciledAt;

  /// Whether [load] has run for the current user.
  bool get isLoaded => _uid != null;

  int get size => _chunks.length;
  Iterable<String> get ids => _chunks.keys;
  int get embedded => _vectors.length;

  /// Chunks with text but no vector yet, oldest first.
  ///
  /// A chunk with no text has nothing to embed. It is skipped here as it is
  /// in [nearest] — otherwise it would sit in this list forever, the server
  /// would refuse every batch it travelled in, and the index would never be
  /// ready.
  List<LocalChunk> get pending => [
    for (final c in _chunks.values)
      if (c.text.trim().isNotEmpty && !_vectors.containsKey(c.id)) c,
  ];

  /// Whether a search here is worth doing: something is indexed and nothing
  /// is waiting. While chunks are still being embedded a local search would
  /// silently miss them, so the caller falls back until this is true.
  bool get isReady => isLoaded && _chunks.isNotEmpty && pending.isEmpty;

  LocalChunk? operator [](String id) => _chunks[id];

  Future<Directory> _dir(String uid) async {
    final base = _rootOverride ?? await getApplicationSupportDirectory();
    // The id is a Firebase uid — alphanumeric — but a path segment is not
    // the place to trust that.
    final safe = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return Directory(p.join(base.path, 'index', safe));
  }

  /// Reads [uid]'s index from disk, replacing whatever is in memory.
  Future<void> load(String uid) async {
    _chunks.clear();
    _vectors.clear();
    _dims = 0;
    syncedAt = null;
    reconciledAt = null;
    _uid = uid;
    final dir = await _dir(uid);
    final meta = File(p.join(dir.path, 'chunks.json'));
    final bin = File(p.join(dir.path, 'vectors.bin'));
    if (!meta.existsSync()) return;
    try {
      final json =
          jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final dims = (json['dims'] as num?)?.toInt() ?? 0;
      syncedAt = DateTime.tryParse(json['syncedAt'] as String? ?? '');
      reconciledAt = DateTime.tryParse(json['reconciledAt'] as String? ?? '');
      final rows = (json['rows'] as List? ?? const []).cast<String>();
      for (final raw in (json['chunks'] as List? ?? const [])) {
        final c = LocalChunk.fromJson(Map<String, dynamic>.from(raw as Map));
        _chunks[c.id] = c;
      }
      if (dims > 0 && rows.isNotEmpty && bin.existsSync()) {
        final bytes = await bin.readAsBytes();
        final all = bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ 4,
        );
        if (all.length == rows.length * dims) {
          _dims = dims;
          for (final (i, id) in rows.indexed) {
            if (_chunks.containsKey(id)) {
              _vectors[id] = Float32List.fromList(
                all.sublist(i * dims, (i + 1) * dims),
              );
            }
          }
        }
      }
    } on Object {
      // A corrupt index is an empty one: every chunk re-syncs from the
      // cloud and re-embeds. Slow once, never wrong.
      _chunks.clear();
      _vectors.clear();
      _dims = 0;
      syncedAt = null;
      reconciledAt = null;
    }
  }

  /// Writes the index whole, atomically.
  Future<void> persist() async {
    final uid = _uid;
    if (uid == null) return;
    final dir = await _dir(uid);
    await dir.create(recursive: true);
    final rows = _vectors.keys.toList();
    final meta = {
      'dims': _dims,
      'rows': rows,
      'syncedAt': syncedAt?.toUtc().toIso8601String(),
      'reconciledAt': reconciledAt?.toUtc().toIso8601String(),
      'chunks': [for (final c in _chunks.values) c.toJson()],
    };
    final bin = Float32List(rows.length * _dims);
    for (final (i, id) in rows.indexed) {
      bin.setRange(i * _dims, (i + 1) * _dims, _vectors[id]!);
    }
    final metaFile = File(p.join(dir.path, 'chunks.json'));
    final binFile = File(p.join(dir.path, 'vectors.bin'));
    final metaTmp = File('${metaFile.path}.tmp');
    final binTmp = File('${binFile.path}.tmp');
    await binTmp.writeAsBytes(bin.buffer.asUint8List(), flush: true);
    await metaTmp.writeAsString(jsonEncode(meta), flush: true);
    await binTmp.rename(binFile.path);
    await metaTmp.rename(metaFile.path);
  }

  /// Forgets everything in memory and on disk for the current user.
  Future<void> wipe() async {
    final uid = _uid;
    _chunks.clear();
    _vectors.clear();
    _dims = 0;
    syncedAt = null;
    reconciledAt = null;
    _uid = null;
    if (uid == null) return;
    final dir = await _dir(uid);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// A chunk arrived or changed. Changed *text* drops the vector, because
  /// the vector was of the old text.
  void upsert(LocalChunk chunk) {
    final before = _chunks[chunk.id];
    _chunks[chunk.id] = chunk;
    if (before != null && before.text != chunk.text) _vectors.remove(chunk.id);
  }

  void remove(String id) {
    _chunks.remove(id);
    _vectors.remove(id);
  }

  void setVectors(Map<String, Float32List> vectors) {
    for (final MapEntry(key: id, value: v) in vectors.entries) {
      if (!_chunks.containsKey(id)) continue;
      if (_dims == 0) _dims = v.length;
      // A vector of another size is from another model or another build of
      // the store. Refuse it rather than corrupt every distance.
      if (v.length != _dims) continue;
      _vectors[id] = v;
    }
  }

  /// The [candidates] nearest chunks to [query], active only, narrowed by
  /// the parsed filters — what Firestore's `find_nearest` plus the server's
  /// post-filters returned.
  List<Nearest> nearest(
    Float32List query,
    LocalQuery parsed, {
    int limit = candidates,
  }) {
    if (_dims == 0 || query.length != _dims) return const [];
    final hits = <Nearest>[];
    for (final MapEntry(key: id, value: v) in _vectors.entries) {
      final chunk = _chunks[id];
      if (chunk == null || !chunk.active || chunk.text.isEmpty) continue;
      if (parsed.memoryTypes.isNotEmpty &&
          !parsed.memoryTypes.contains(chunk.memoryType)) {
        continue;
      }
      if (!parsed.withinDates(chunk.capturedAt)) continue;
      hits.add((chunk: chunk, distance: cosineDistance(query, v)));
    }
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }
}
