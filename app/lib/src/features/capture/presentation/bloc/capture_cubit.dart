import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/files/local_originals.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/validation/validators.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../data/file_capture.dart';

part 'capture_cubit.freezed.dart';

/// One of the six tiles on the Library's type sheet — "What are you adding?".
///
/// **The tiles moved off the screen.** v3's first cut put all six above the
/// Library's list, which made the Library read as a set of filters rather
/// than a list of your things. The redesign replaces them with one Upload
/// button under the tabs; the six live on the sheet it opens (F1·2).
///
/// The order and the wording are the design's, left to right and top to
/// bottom in a two-column grid: Files, Images, Link, Scan, Audio, Speak.
/// Declared in that order so the sheet can render `values` and cannot
/// disagree with the design about which tile goes where.
///
/// **There is no "note".** v2 offered a text box for writing something down.
/// The product spec drops it: Hawk is for things you already have. The
/// backend still accepts text memories — a link's fetched title and a
/// recording's transcript are both text — so only the offer is gone.
enum CaptureKind {
  files,
  images,
  links,
  scan,
  audio,
  speak;

  String get label => switch (this) {
    files => 'Files',
    images => 'Images',
    links => 'Link',
    scan => 'Scan',
    audio => 'Audio',
    speak => 'Speak',
  };

  /// Whether this path works today — every one of them, now.
  ///
  /// Kept as a getter so the next path that is not ready has somewhere to
  /// say so rather than shipping a tile that fails when pressed.
  bool get isAvailable => true;

  /// Which system picker to open. Null for the paths that are not a file.
  FilePickKind? get pick => switch (this) {
    files => FilePickKind.documents,
    images => FilePickKind.photos,
    audio => FilePickKind.audio,
    links || scan || speak => null,
  };

  /// Whether this tile ends on the Indexing screen.
  ///
  /// Links and Speak do not: a link is read in seconds, and a spoken note is
  /// already text by the time it is saved — "Links skip the indexing page;
  /// they're fast" (F4·4). They land as a row with the island's
  /// confirmation instead.
  bool get uploads => pick != null || this == scan;

  /// What the memory will be recorded as.
  ///
  /// [speak] is a voice note, not audio: the recorder keeps the on-device
  /// transcript and no recording, and a memory typed as audio would promise
  /// the player something to play.
  MemoryType get memoryType => switch (this) {
    files => MemoryType.document,
    images => MemoryType.photo,
    // A scan is bound into one PDF, so it is recorded as the document it is
    // rather than as a photograph of one.
    scan => MemoryType.pdf,
    audio => MemoryType.audio,
    speak => MemoryType.voiceNote,
    links => MemoryType.link,
  };

  /// What one picked file becomes.
  ///
  /// The Files picker is opened wide (see `DeviceFileCapture._typeFor`), so a
  /// photo or a recording can arrive through it — and should be filed as
  /// what it is, or the viewer shows a photo as "nothing readable in this
  /// file".
  MemoryType memoryTypeFor(String filename) {
    if (this != files) return memoryType;
    final ext = p.extension(filename).toLowerCase();
    return switch (ext) {
      '.pdf' => MemoryType.pdf,
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.heic' ||
      '.heif' ||
      '.webp' ||
      '.gif' => MemoryType.photo,
      '.mp3' ||
      '.m4a' ||
      '.aac' ||
      '.wav' ||
      '.ogg' ||
      '.opus' => MemoryType.audio,
      _ => MemoryType.document,
    };
  }
}

@freezed
abstract class CaptureState with _$CaptureState {
  const factory CaptureState({
    @Default('') String url,
    @Default(false) bool isSubmitting,
    @Default(false) bool urlTouched,

    /// Set on success so the sheet can close and the library can refresh.
    Memory? captured,

    /// Why the last save did not happen. Shown *inside* the sheet (E8), not
    /// as an island: the url is still there to fix.
    AppException? exception,
  }) = _CaptureState;

  const CaptureState._();

  ValidationResult get urlValidation => Validators.captureUrl(url);

  String? get urlError => urlTouched && url.isNotEmpty && !urlValidation.isValid
      ? urlValidation.message
      : null;

  bool get canSaveLink =>
      !isSubmitting && url.trim().isNotEmpty && urlValidation.isValid;
}

/// Turns uploaded files into memories, keeping each original on the phone.
///
/// Used by the home screen's camera, which uploads and captures in one go.
/// The Library's Upload flow does the same two steps through `UploadCenter`,
/// one file at a time with progress, so it can show the steps as they
/// happen.
///
/// Keeping the original is best-effort. By the time it is attempted the
/// memory exists and is being indexed; losing the local copy only means the
/// file cannot be opened from Hawk, and the user still has it wherever it
/// came from.
Future<List<Memory>> captureUploads(
  List<UploadedFile> uploaded, {
  required MemoryType type,
  required MemoryRepository memories,
  required LocalOriginals originals,
  required AppLogger logger,
}) async {
  final made = <Memory>[];
  for (final one in uploaded) {
    final memory = await memories.capture(
      type: type,
      title: one.filename,
      storagePath: one.storagePath,
      mimeType: one.mimeType,
      sizeBytes: one.bytes,
    );
    made.add(memory);
    try {
      await originals.keep(
        memoryId: memory.id,
        sourcePath: one.localPath,
        filename: one.filename,
      );
    } on Object catch (error) {
      logger.warning(
        'Could not keep the original',
        name: 'capture',
        data: {'error': error.toString()},
      );
    }
  }
  return made;
}

/// The link sheet (F4·3) — the one tile with somewhere to type.
///
/// Writing a `memories` document fires the `on_memory_created` trigger, so a
/// saved link really does enter the pipeline and appear in the list under
/// the sheet within a second. Nothing here is stubbed.
@injectable
class CaptureCubit extends Cubit<CaptureState> with SafeEmit<CaptureState> {
  CaptureCubit(this._memories) : super(const CaptureState());

  final MemoryRepository _memories;

  void urlChanged(String value) =>
      emit(state.copyWith(url: value, urlTouched: false, exception: null));

  /// A url that arrived from the clipboard rather than the keyboard. Marked
  /// touched at once, so a clipboard that held something url-shaped but
  /// invalid says so immediately instead of on blur.
  void urlPasted(String value) =>
      emit(state.copyWith(url: value, urlTouched: true, exception: null));

  void urlBlurred() => emit(state.copyWith(urlTouched: true));

  /// Saves a link with no title of its own.
  ///
  /// The fetcher reads the page's own `<title>` seconds later, which is both
  /// more accurate and one fewer thing to type. Until it lands,
  /// `Memory.displayTitle` falls back to a readable form of the url rather
  /// than to "Untitled".
  Future<void> saveLink() async {
    if (!state.canSaveLink) {
      emit(state.copyWith(urlTouched: true));
      return;
    }
    emit(state.copyWith(isSubmitting: true, exception: null));
    try {
      final memory = await _memories.capture(
        type: MemoryType.link,
        url: Validators.normalizeUrl(state.url),
      );
      emit(state.copyWith(isSubmitting: false, captured: memory));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isSubmitting: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void acknowledge() =>
      emit(state.copyWith(captured: null, url: '', urlTouched: false));

  void dismissError() => emit(state.copyWith(exception: null));
}
