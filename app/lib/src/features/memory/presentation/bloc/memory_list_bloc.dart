import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/library_filter.dart';
import '../../domain/entities/memory.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../domain/usecases/memory_usecases.dart';

part 'memory_list_bloc.freezed.dart';
part 'memory_list_event.dart';
part 'memory_list_state.dart';

/// Drives the library screen.
///
/// Paging drops repeats rather than queueing them. `concurrent` would
/// interleave two appends and duplicate rows; `sequential` ran every queued
/// request, so one fling fetched pages the user never scrolled to. Filter
/// changes restart the list instead, since a filter invalidates the cursor.
///
/// Dropping is only safe because something re-asks once the fetch lands —
/// see `LibraryPage._maybeLoadMore`, which is re-checked after every state
/// change as well as on scroll.
@injectable
class MemoryListBloc extends Bloc<MemoryListEvent, MemoryListState> {
  MemoryListBloc(this._fetchMemories, this._logger)
    : super(const MemoryListState.initial()) {
    on<MemoryListStarted>(_onStarted);
    // droppable(), not sequential(). The scroll listener fires on every tick
    // within 400px of the bottom, so one fling enqueues a dozen requests;
    // sequential() ran them all, and each only re-checked `hasMore` and
    // `isAppending` — never the scroll position — so a flick fetched several
    // pages the user never scrolled to. Dropping while a fetch is in flight
    // is the correct read of a repeated "give me more".
    on<MemoryListNextPageRequested>(_onNextPage, transformer: droppable());
    on<MemoryListFilterChanged>(_onFilterChanged);
    on<MemoryListRetried>((_, emit) => _load(emit, offset: 0));
  }

  static const pageSize = 20;

  final FetchMemories _fetchMemories;
  final AppLogger _logger;

  LibraryFilter _filter = LibraryFilter.all;

  /// What the list is narrowed to right now, whatever state it is in.
  LibraryFilter get filter => _filter;

  Future<void> _onStarted(
    MemoryListStarted event,
    Emitter<MemoryListState> emit,
  ) => _load(emit, offset: 0, silent: event.refresh);

  Future<void> _onFilterChanged(
    MemoryListFilterChanged event,
    Emitter<MemoryListState> emit,
  ) {
    _filter = event.filter;
    return _load(emit, offset: 0);
  }

  Future<void> _onNextPage(
    MemoryListNextPageRequested event,
    Emitter<MemoryListState> emit,
  ) async {
    final current = state;
    if (current is! MemoryListLoaded ||
        !current.hasMore ||
        current.isAppending) {
      return;
    }

    emit(current.copyWith(isAppending: true));

    try {
      final page = await _fetchMemories((
        limit: pageSize,
        offset: current.memories.length,
        types: _filter.types,
        status: null,
      ));

      final merged = [...current.memories, ...page.items];
      emit(
        MemoryListState.loaded(
          memories: merged,
          total: merged.length,
          hasMore: page.hasMore,
          filter: _filter,
        ),
      );
    } catch (error, stackTrace) {
      // A failed *append* must not throw away the rows already on screen.
      _report('Failed to load the next page of memories', error, stackTrace);
      emit(current.copyWith(isAppending: false));
    }
  }

  Future<void> _load(
    Emitter<MemoryListState> emit, {
    required int offset,
    bool silent = false,
  }) async {
    final params = (
      limit: pageSize,
      offset: offset,
      types: _filter.types,
      status: null,
    );

    // The rows this phone already has, first — Firestore's local copy, no
    // network — so the library opens full instead of on a spinner. The
    // server's answer replaces them a moment later.
    MemoryPage? head;
    if (offset == 0) {
      try {
        head = await _fetchMemories.cached(params);
      } on Object {
        head = null;
      }
    }
    if (head != null && head.items.isNotEmpty) {
      emit(
        MemoryListState.loaded(
          memories: head.items,
          total: head.items.length,
          hasMore: head.hasMore,
          filter: _filter,
        ),
      );
    } else if (!silent) {
      emit(MemoryListState.loading(filter: _filter));
    }

    try {
      final page = await _fetchMemories(params);

      if (page.items.isEmpty) {
        emit(MemoryListState.empty(filter: _filter));
        return;
      }

      emit(
        MemoryListState.loaded(
          memories: page.items,
          total: page.items.length,
          hasMore: page.hasMore,
          filter: _filter,
        ),
      );
    } catch (error, stackTrace) {
      final exception = _report('Failed to load memories', error, stackTrace);
      // Rows from the cache stay on screen: an error over a list the user
      // can already read would be worse than a list that is a little old.
      if (head == null || head.items.isEmpty) {
        emit(MemoryListState.failure(exception, filter: _filter));
      }
    }
  }

  AppException _report(String message, Object error, StackTrace stackTrace) {
    final exception = ErrorMapper.map(error, stackTrace);
    _logger.error(
      message,
      error: exception,
      stackTrace: stackTrace,
      name: 'MemoryListBloc',
      report: exception.shouldReport,
    );
    return exception;
  }
}
