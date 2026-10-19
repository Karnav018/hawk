part of 'memory_list_bloc.dart';

@freezed
sealed class MemoryListEvent with _$MemoryListEvent {
  /// First load, or a pull-to-refresh.
  const factory MemoryListEvent.started({@Default(false) bool refresh}) =
      MemoryListStarted;

  /// Load the next page. Ignored while a page is already in flight.
  const factory MemoryListEvent.nextPageRequested() =
      MemoryListNextPageRequested;

  /// Narrow the library to one group of kinds; [LibraryFilter.all] clears it.
  const factory MemoryListEvent.filterChanged(LibraryFilter filter) =
      MemoryListFilterChanged;

  const factory MemoryListEvent.retried() = MemoryListRetried;
}
