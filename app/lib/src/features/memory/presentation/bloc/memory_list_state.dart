part of 'memory_list_bloc.dart';

@freezed
sealed class MemoryListState with _$MemoryListState {
  const factory MemoryListState.initial({
    @Default(LibraryFilter.all) LibraryFilter filter,
  }) = MemoryListInitial;

  const factory MemoryListState.loading({
    @Default(LibraryFilter.all) LibraryFilter filter,
  }) = MemoryListLoading;

  /// Loaded, possibly still appending. [isAppending] drives the footer spinner
  /// without discarding the rows already on screen.
  const factory MemoryListState.loaded({
    required List<Memory> memories,
    required int total,
    required bool hasMore,
    @Default(false) bool isAppending,
    @Default(LibraryFilter.all) LibraryFilter filter,
  }) = MemoryListLoaded;

  /// Nothing captured yet — a distinct state, because "empty" and "loaded with
  /// zero rows" want completely different screens.
  const factory MemoryListState.empty({
    @Default(LibraryFilter.all) LibraryFilter filter,
  }) = MemoryListEmpty;

  const factory MemoryListState.failure(
    AppException exception, {
    @Default(LibraryFilter.all) LibraryFilter filter,
  }) = MemoryListFailure;
}
