import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The phone's own copy of each captured file, keyed by memory id.
///
/// Exists because indexing a file used to lose it. The upload is transport,
/// not storage — the server deletes it the moment extraction succeeds — and
/// the path the picker hands back points into the app's *cache*, which the
/// OS clears whenever it likes. So once a file was indexed, nothing in the
/// app could open it again or share it, even though it was captured on this
/// very phone.
///
/// Keeping it costs no new space. `file_picker` already copies the chosen
/// file into the app's sandbox before handing over a path; this moves that
/// copy out of the evictable cache into support storage, on the same volume,
/// so the move is a rename rather than a second copy of the bytes.
///
/// Stored as `originals/<memoryId>/<original filename>`. The filename is kept
/// because it is what the user sees in a viewer's title bar and what the
/// recipient of a share receives — "Pricing v4.pdf", not "a8Fk2.pdf".
abstract interface class LocalOriginals {
  /// The kept file for [memoryId], or null if this phone never had it — a
  /// memory captured on another device, before this existed, or from a
  /// connector rather than the picker.
  Future<File?> find(String memoryId);

  /// Takes ownership of the file at [sourcePath]. Moves it; falls back to a
  /// copy only if the two paths are on different volumes.
  Future<File> keep({
    required String memoryId,
    required String sourcePath,
    required String filename,
  });

  /// Deletes the kept copy. A no-op when there is none.
  Future<void> forget(String memoryId);

  /// Where a download should write, with the directory ready.
  ///
  /// Downloading straight into this cache means a file fetched from the
  /// vault is kept for next time, so opening it twice costs one download.
  Future<File> destination({
    required String memoryId,
    required String filename,
  });
}

@LazySingleton(as: LocalOriginals)
class SandboxOriginals implements LocalOriginals {
  SandboxOriginals();

  /// Overridable so tests can point it at a temporary directory.
  @visibleForTesting
  SandboxOriginals.at(this._rootOverride);

  Directory? _rootOverride;

  /// Application *support*, not documents, on purpose. On iOS, Documents is
  /// surfaced in the Files app when file sharing is enabled; these are
  /// Hawk's working copies, not something the user filed there.
  Future<Directory> _root() async {
    final base = _rootOverride ?? await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'originals'));
  }

  Future<Directory> _dirFor(String memoryId) async =>
      Directory(p.join((await _root()).path, _safe(memoryId)));

  @override
  Future<File?> find(String memoryId) async {
    final dir = await _dirFor(memoryId);
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().toList();
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<File> keep({
    required String memoryId,
    required String sourcePath,
    required String filename,
  }) async {
    final dir = await _dirFor(memoryId);
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, _safeName(filename)));
    final source = File(sourcePath);

    try {
      return await source.rename(target.path);
    } on FileSystemException {
      // Different volumes. Rare on a phone, where the cache and support
      // directories share a volume, but a rename across volumes fails
      // outright rather than falling back on its own.
      final copied = await source.copy(target.path);
      try {
        await source.delete();
      } on FileSystemException {
        // The cache copy lingering is harmless; the OS clears it.
      }
      return copied;
    }
  }

  @override
  Future<File> destination({
    required String memoryId,
    required String filename,
  }) async {
    final dir = await _dirFor(memoryId);
    await dir.create(recursive: true);
    return File(p.join(dir.path, _safeName(filename)));
  }

  @override
  Future<void> forget(String memoryId) async {
    final dir = await _dirFor(memoryId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// A memory id is a Firestore document id, which is already path-safe —
  /// but it arrives as data, and a path built from data is sanitised.
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Keeps the name readable while removing separators and control
  /// characters, which would otherwise let a filename escape its directory.
  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_').trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'original'
        : cleaned;
  }
}
