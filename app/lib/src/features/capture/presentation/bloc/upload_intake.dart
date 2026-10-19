import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../data/file_capture.dart';
import 'capture_cubit.dart';

/// What came back from a picker, and what the Library should do about it.
///
/// Sealed, because each answer is a different screen: a list to upload, a
/// sheet that has to be decided (E2, E4), an island (E3), or nothing at all
/// (E1). The Library switches on it; nothing here knows about widgets.
sealed class Intake {
  const Intake();
}

/// Backed out of the picker. Nothing happens — the type sheet is still
/// there (E1·2).
final class IntakeCancelled extends Intake {
  const IntakeCancelled();
}

/// Ready to upload.
final class IntakeReady extends Intake {
  const IntakeReady({
    required this.kind,
    required this.files,
    this.hashes = const {},
    this.skipped = 0,
  });

  final CaptureKind kind;
  final List<PickedFile> files;

  /// Path → SHA-256, for the ones that could be fingerprinted.
  final Map<String, String> hashes;

  /// From a batch: files dropped for being too big, unreadable or already
  /// kept. A batch is not stopped for one bad file — the rest go up, and
  /// the island says how many were left out.
  final int skipped;
}

/// One file, over the limit (E2). Caught before a byte is sent.
final class IntakeTooLarge extends Intake {
  const IntakeTooLarge({required this.kind, required this.file});

  final CaptureKind kind;
  final PickedFile file;
}

/// One file of a type Hawk cannot read (E3).
final class IntakeUnsupported extends Intake {
  const IntakeUnsupported({required this.extension});

  /// `.pages`, lower-cased, with the dot. Empty when the file has none.
  final String extension;
}

/// One file, already in the Library byte for byte (E4).
final class IntakeDuplicate extends Intake {
  const IntakeDuplicate({
    required this.kind,
    required this.file,
    required this.hash,
    required this.existing,
  });

  final CaptureKind kind;
  final PickedFile file;
  final String hash;
  final Memory existing;
}

/// Everything in a batch was left out.
final class IntakeNothing extends Intake {
  const IntakeNothing({required this.skipped});

  final int skipped;
}

/// The camera is off (E9's shape, for Scan).
final class IntakeCameraDenied extends Intake {
  const IntakeCameraDenied();
}

final class IntakeFailed extends Intake {
  const IntakeFailed(this.exception, {this.kind});

  final AppException exception;

  /// Which tile it came from, so the island can name what failed —
  /// "Could not add those images".
  final CaptureKind? kind;
}

/// From "pick" to "ready to upload" — every check that happens before a byte
/// leaves the phone.
///
/// **Size, then type, then sameness**, in that order, because that is the
/// order of what is cheapest to say no to. A 1.2 GB video is refused on its
/// size (E2's example) without anybody hashing 1.2 GB to find out it was
/// also a duplicate.
///
/// **One file gets a decision; a batch gets on with it.** A single pick that
/// is too big or already kept is exactly the moment to ask. Four photos with
/// one duplicate among them is not: the three new ones go up and the island
/// says one was left out, rather than stopping on a sheet about the fourth.
@injectable
class UploadIntake {
  UploadIntake(this._files, this._memories, this._logger);

  final FileCapture _files;
  final MemoryRepository _memories;
  final AppLogger _logger;

  /// What each picker is allowed to hand back. Anything else is E3.
  ///
  /// Files is opened on every type (see `DeviceFileCapture._typeFor`) so the
  /// refusal can come with a reason; photos and recordings picked through it
  /// are fine, and filed as what they are.
  static const readable = {
    '.pdf',
    '.txt',
    '.md',
    '.markdown',
    '.csv',
    '.rtf',
    ..._images,
    ..._audio,
  };

  static const _images = {
    '.png',
    '.jpg',
    '.jpeg',
    '.heic',
    '.heif',
    '.webp',
    '.gif',
  };

  static const _audio = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus'};

  Future<Intake> pick(CaptureKind kind) async {
    try {
      final picked = switch (kind) {
        CaptureKind.images => await _files.pickImages(),
        CaptureKind.scan => [?await _files.scanDocument()],
        CaptureKind.files || CaptureKind.audio => await _files.pick(kind.pick!),
        CaptureKind.links || CaptureKind.speak => const <PickedFile>[],
      };
      if (picked.isEmpty) return const IntakeCancelled();
      return picked.length == 1
          ? await _one(kind, picked.single)
          : await _many(kind, picked);
    } on CameraDeniedException {
      return const IntakeCameraDenied();
    } catch (error, stackTrace) {
      return IntakeFailed(ErrorMapper.map(error, stackTrace), kind: kind);
    }
  }

  /// The same file, again, past the size and type checks — "Keep both".
  static IntakeReady keepBoth(IntakeDuplicate duplicate) => IntakeReady(
    kind: duplicate.kind,
    files: [duplicate.file],
    hashes: {duplicate.file.path: duplicate.hash},
  );

  Future<Intake> _one(CaptureKind kind, PickedFile file) async {
    if (file.bytes > FileCapture.maxBytes) {
      return IntakeTooLarge(kind: kind, file: file);
    }
    final ext = _extension(file.name);
    if (!_accepts(kind, ext)) return IntakeUnsupported(extension: ext);

    final hash = await _hash(file);
    if (hash != null) {
      final existing = await _existing(hash);
      if (existing != null) {
        return IntakeDuplicate(
          kind: kind,
          file: file,
          hash: hash,
          existing: existing,
        );
      }
    }
    return IntakeReady(kind: kind, files: [file], hashes: {file.path: ?hash});
  }

  Future<Intake> _many(CaptureKind kind, List<PickedFile> picked) async {
    final keep = <PickedFile>[];
    final hashes = <String, String>{};
    var skipped = 0;
    for (final file in picked) {
      if (file.bytes > FileCapture.maxBytes ||
          file.bytes == 0 ||
          !_accepts(kind, _extension(file.name))) {
        skipped++;
        continue;
      }
      final hash = await _hash(file);
      if (hash != null) {
        // Twice in one pick counts too — the photo picker lets you choose
        // the same picture from two albums.
        if (hashes.containsValue(hash) || await _existing(hash) != null) {
          skipped++;
          continue;
        }
        hashes[file.path] = hash;
      }
      keep.add(file);
    }
    if (keep.isEmpty) return IntakeNothing(skipped: skipped);
    return IntakeReady(
      kind: kind,
      files: keep,
      hashes: hashes,
      skipped: skipped,
    );
  }

  bool _accepts(CaptureKind kind, String ext) => switch (kind) {
    // The system photo picker and the scanner only ever hand back what they
    // were asked for; HEIC, a Live Photo's still, a scanner's PDF.
    CaptureKind.images || CaptureKind.scan => true,
    CaptureKind.audio => _audio.contains(ext) || ext.isEmpty,
    _ => readable.contains(ext),
  };

  static String _extension(String name) => p.extension(name).toLowerCase();

  /// Null if the file could not be read for hashing — which only costs the
  /// duplicate check. The upload will say for itself if the file is gone.
  Future<String?> _hash(PickedFile file) async {
    try {
      return await _files.fingerprint(file.path);
    } on Object catch (error) {
      _logger.warning(
        'Could not fingerprint a file',
        name: 'capture',
        data: {'error': error.toString()},
      );
      return null;
    }
  }

  /// Null when the lookup itself fails. A duplicate check that cannot run
  /// is not a reason to stop somebody saving a file.
  Future<Memory?> _existing(String hash) async {
    try {
      return await _memories.findByContentHash(hash);
    } on Object catch (error) {
      _logger.warning(
        'Could not check for a duplicate',
        name: 'capture',
        data: {'error': error.toString()},
      );
      return null;
    }
  }
}
