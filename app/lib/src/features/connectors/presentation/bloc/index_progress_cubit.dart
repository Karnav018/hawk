import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/index_job.dart';
import '../../domain/repositories/connector_repository.dart';

part 'index_progress_cubit.freezed.dart';

@freezed
abstract class IndexProgressState with _$IndexProgressState {
  const factory IndexProgressState({
    IndexJob? job,
    @Default(true) bool isLoading,
    AppException? exception,
  }) = _IndexProgressState;

  const IndexProgressState._();

  /// 3L's promise: "You can start asking as soon as the first ones land."
  ///
  /// True the moment anything has been discovered, not when the job finishes —
  /// which is the whole reason the screen has a way out that is not "wait".
  ///
  /// Also true whenever something has gone wrong, and once loading has
  /// settled with nothing to show. A screen whose only exit is progress that
  /// may never arrive is a dead end, and this one is reached by a
  /// `pushReplacement` so there is not even a back stack to escape into.
  bool get canLeave =>
      (job?.processed ?? 0) > 0 ||
      (job?.state.isTerminal ?? false) ||
      exception != null ||
      job == null && !isLoading;

  /// Something to show the user, whether it came from the job or the stream.
  String? get failure => exception?.displayMessage ?? job?.error;

  bool get hasFailed => failure != null || job?.state == IndexJobState.failed;
}

/// Screen 3L — FIRST INDEX, PROGRESS.
@injectable
class IndexProgressCubit extends Cubit<IndexProgressState>
    with SafeEmit<IndexProgressState> {
  IndexProgressCubit(this._repository, @factoryParam this._jobId)
    : super(const IndexProgressState()) {
    _subscription = _repository
        .watchIndexJob(_jobId)
        .listen(
          (job) => emit(state.copyWith(job: job, isLoading: false)),
          onError: (Object error, StackTrace stackTrace) => emit(
            state.copyWith(
              isLoading: false,
              exception: ErrorMapper.map(error, stackTrace),
            ),
          ),
          // The repository filters out non-existent documents, so a job that was
          // never written — or was deleted — closes the stream without ever
          // emitting. Left unhandled that leaves the screen loading forever.
          onDone: () => emit(state.copyWith(isLoading: false)),
        );
  }

  final ConnectorRepository _repository;
  final String _jobId;
  late final StreamSubscription<IndexJob> _subscription;

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
