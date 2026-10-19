import '../entities/memory.dart';
import '../entities/memory_enums.dart';

/// A page of results plus enough to know whether to ask for more.
///
/// `hasMore`, not a total. Firestore's aggregate `count()` is a separately
/// billed query, so there is no cheap total to report — and the previous
/// shape encoded "there is more" as `total + 1`, which the library header
/// then printed as a count. A 20-item first page read "21 memories".
typedef MemoryPage = ({List<Memory> items, bool hasMore, int offset});

/// Domain-owned contract. Every method throws an `AppException` on failure.
abstract interface class MemoryRepository {
  /// [types] keeps only those kinds; empty keeps every kind.
  Future<MemoryPage> fetchMemories({
    int limit,
    int offset,
    Set<MemoryType> types,
    ProcessingStatus? status,
  });

  /// The first page as this device last saw it — Firestore's own offline
  /// copy — or null when it holds nothing. Instant, because it never touches
  /// the network; for drawing the list at once while [fetchMemories] asks
  /// the server. Never cursors: the next [fetchMemories] starts over.
  Future<MemoryPage?> cachedMemories({
    int limit,
    Set<MemoryType> types,
    ProcessingStatus? status,
  });

  Future<Memory> fetchMemory(String id);

  /// Live state of a known set of memories, in the order given.
  ///
  /// For screen 2G, which follows a batch the user just captured through the
  /// pipeline. Emits whenever any one of them changes status; a memory that
  /// does not exist or is not the caller's is left out rather than failing
  /// the whole stream, because one deleted file must not blank a queue of
  /// four.
  Stream<List<Memory>> watchMemories(List<String> ids);

  /// Captures text, a note, a link, or an uploaded file. Returns immediately
  /// — the memory comes back in `uploaded` and is enriched on the server's
  /// queue.
  ///
  /// [storagePath] points at a file already in Storage. The pipeline reads it
  /// from there, so the upload must complete *before* this is called: the
  /// ingestion trigger fires on the write, and a memory whose file is still
  /// uploading would be read as an empty one.
  Future<Memory> capture({
    MemoryType type,
    String? title,
    String? text,
    String? url,
    String? storagePath,
    String? mimeType,
    int? sizeBytes,

    /// SHA-256 of the file, so a later upload of the same bytes can be
    /// recognised (E4). Null for links and notes, which have no bytes.
    String? contentHash,
  });

  /// A memory already made from these exact bytes, or null.
  ///
  /// Only memories captured since fingerprints were recorded can match: an
  /// older upload has no hash, and is not guessed at by name, because two
  /// different files called `scan.pdf` are the common case, not the rare one.
  Future<Memory?> findByContentHash(String contentHash);

  /// Removes the memory only. The original file is never touched.
  Future<void> deleteMemory(String id);
}
