import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/provider_folder.dart';
import '../../domain/repositories/connector_repository.dart';

part 'folder_selection_cubit.freezed.dart';

@freezed
abstract class FolderSelectionState with _$FolderSelectionState {
  const factory FolderSelectionState({
    @Default(<ProviderFolder>[]) List<ProviderFolder> folders,
    @Default(<String>{}) Set<String> selected,
    @Default(true) bool isLoading,
    @Default(false) bool isStarting,
    String? jobId,
    AppException? exception,
  }) = _FolderSelectionState;

  const FolderSelectionState._();

  List<ProviderFolder> get chosen => [
    for (final f in folders)
      if (selected.contains(f.id)) f,
  ];

  /// The design's "SELECTED · 508 FILES · 49.2 GB" running total.
  int get selectedFiles => chosen.fold(0, (sum, f) => sum + f.fileCount);
  int get selectedBytes => chosen.fold(0, (sum, f) => sum + f.bytes);

  bool get canStart => selected.isNotEmpty && !isStarting && !isLoading;
}

/// Screen 3K — CHOOSE WHAT TO INDEX.
@injectable
class FolderSelectionCubit extends Cubit<FolderSelectionState>
    with SafeEmit<FolderSelectionState> {
  FolderSelectionCubit(this._repository, @factoryParam this._accountId)
    : super(const FolderSelectionState());

  final ConnectorRepository _repository;
  final String _accountId;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, exception: null));
    try {
      final result = await _repository.listFolders(_accountId);
      emit(
        state.copyWith(
          folders: result.folders,
          // Pre-ticked from what is already indexed, so returning to this
          // screen to add a folder does not silently propose dropping the
          // ones already chosen.
          selected: result.selected.isEmpty
              ? _default(result.folders)
              : result.selected,
          isLoading: false,
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  /// Nothing pre-selected on a first run.
  ///
  /// Tempting to tick everything — but the design's own example is a 92 GB
  /// "Photos backup" folder next to a 8 GB "Contracts" one, and defaulting to
  /// all of it opts people into hours of indexing they did not ask for.
  Set<String> _default(List<ProviderFolder> folders) => const {};

  void toggle(String folderId) {
    final next = Set<String>.from(state.selected);
    if (!next.remove(folderId)) next.add(folderId);
    emit(state.copyWith(selected: next, exception: null));
  }

  Future<void> start() async {
    if (!state.canStart) return;
    emit(state.copyWith(isStarting: true, exception: null));
    try {
      final jobId = await _repository.setIndexedFolders(
        _accountId,
        state.chosen,
      );
      emit(state.copyWith(isStarting: false, jobId: jobId));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isStarting: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }
}
