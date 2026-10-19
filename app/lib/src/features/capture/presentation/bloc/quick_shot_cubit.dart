import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/files/local_originals.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../data/file_capture.dart';
import 'capture_cubit.dart';

/// Where the home header's camera is: idle, busy, or with news to report.
class QuickShotState {
  const QuickShotState({this.busy = false, this.saved = 0, this.exception});

  /// Between the shutter and the memory existing.
  final bool busy;

  /// How many photos this home session has saved. Counts up, so a listener
  /// can tell a new save from a rebuild.
  final int saved;
  final AppException? exception;

  QuickShotState copyWith({
    bool? busy,
    int? saved,
    AppException? exception,
    bool clearException = false,
  }) => QuickShotState(
    busy: busy ?? this.busy,
    saved: saved ?? this.saved,
    exception: clearException ? null : (exception ?? this.exception),
  );
}

/// Shoot and index, in one tap — the camera in home's header.
///
/// No review step, on purpose. Screen 2C's grid is for choosing among
/// photos already taken; a photo taken *now* has been chosen by the act of
/// taking it, and a second confirmation would turn "click and index" into
/// "click, look, tap Index". The same pipeline as 2C — upload, keep the
/// original on this phone, create the memory — so the photo is indexed and
/// openable exactly as one captured from the library would be.
@injectable
class QuickShotCubit extends Cubit<QuickShotState>
    with SafeEmit<QuickShotState> {
  QuickShotCubit(this._files, this._memories, this._originals, this._logger)
    : super(const QuickShotState());

  final FileCapture _files;
  final MemoryRepository _memories;
  final LocalOriginals _originals;
  final AppLogger _logger;

  Future<void> shoot() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearException: true));
    try {
      final shot = await _files.takePhoto();
      if (shot == null) {
        // Backed out of the camera. A decision, not a failure.
        emit(state.copyWith(busy: false));
        return;
      }
      final uploaded = await _files.uploadPaths([shot]);
      if (uploaded.isEmpty) {
        throw const AppException.badRequest(
          message: 'That photo could not be uploaded.',
        );
      }
      await captureUploads(
        uploaded,
        type: MemoryType.photo,
        memories: _memories,
        originals: _originals,
        logger: _logger,
      );
      emit(state.copyWith(busy: false, saved: state.saved + 1));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          busy: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(clearException: true));
}
