import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/memory/domain/entities/library_filter.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/memory/domain/usecases/memory_usecases.dart';
import 'package:knowra/src/features/memory/presentation/bloc/memory_list_bloc.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fake_logger.dart';

class _MockFetchMemories extends Mock implements FetchMemories {}

Memory _memory(String id) => Memory(
  id: id,
  type: MemoryType.note,
  status: ProcessingStatus.ready,
  createdAt: DateTime.utc(2026, 8, 26),
  title: 'Memory $id',
);

/// A page as the repository now reports it: what it fetched, plus whether
/// another page exists. There is no total — see [MemoryPage].
MemoryPage _page(List<Memory> items, {bool hasMore = false, int offset = 0}) =>
    (items: items, hasMore: hasMore, offset: offset);

void main() {
  late _MockFetchMemories fetchMemories;
  late FakeLogger logger;

  setUpAll(() {
    registerFallbackValue(
      (limit: 20, offset: 0, types: const <MemoryType>{}, status: null)
          as FetchMemoriesParams,
    );
  });

  setUp(() {
    fetchMemories = _MockFetchMemories();
    logger = FakeLogger();
  });

  MemoryListBloc build() => MemoryListBloc(fetchMemories, logger);

  blocTest<MemoryListBloc, MemoryListState>(
    'emits [loading, loaded] with hasMore when more pages exist',
    build: () {
      when(() => fetchMemories.call(any())).thenAnswer(
        (_) async => _page([_memory('a'), _memory('b')], hasMore: true),
      );
      return build();
    },
    act: (bloc) => bloc.add(const MemoryListEvent.started()),
    expect: () => [
      const MemoryListState.loading(),
      isA<MemoryListLoaded>()
          .having((s) => s.memories.length, 'rows', 2)
          .having((s) => s.total, 'loaded so far', 2)
          .having((s) => s.hasMore, 'hasMore', isTrue)
          .having((s) => s.hasMore, 'hasMore', true),
    ],
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'an empty first page is its own state, not a loaded list of zero rows',
    build: () {
      when(
        () => fetchMemories.call(any()),
      ).thenAnswer((_) async => _page(const []));
      return build();
    },
    act: (bloc) => bloc.add(const MemoryListEvent.started()),
    expect: () => [const MemoryListState.loading(), isA<MemoryListEmpty>()],
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'surfaces the AppException type on failure',
    build: () {
      when(
        () => fetchMemories.call(any()),
      ).thenThrow(const AppException.network());
      return build();
    },
    act: (bloc) => bloc.add(const MemoryListEvent.started()),
    expect: () => [
      const MemoryListState.loading(),
      const MemoryListState.failure(AppException.network()),
    ],
    verify: (_) => expect(logger.errors, isNotEmpty),
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'appends the next page onto the rows already on screen',
    build: () {
      var call = 0;
      when(() => fetchMemories.call(any())).thenAnswer((_) async {
        call++;
        return call == 1
            ? _page([_memory('a')], hasMore: true)
            : _page([_memory('b')], offset: 1);
      });
      return build();
    },
    act: (bloc) async {
      bloc.add(const MemoryListEvent.started());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MemoryListEvent.nextPageRequested());
    },
    skip: 2,
    expect: () => [
      isA<MemoryListLoaded>().having((s) => s.isAppending, 'isAppending', true),
      isA<MemoryListLoaded>()
          .having((s) => s.memories.map((m) => m.id).toList(), 'ids', [
            'a',
            'b',
          ])
          .having((s) => s.hasMore, 'hasMore', false),
    ],
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'a failed append keeps the rows already on screen',
    build: () {
      var call = 0;
      when(() => fetchMemories.call(any())).thenAnswer((_) async {
        call++;
        if (call == 1) return _page([_memory('a')], hasMore: true);
        throw const AppException.timeout();
      });
      return build();
    },
    act: (bloc) async {
      bloc.add(const MemoryListEvent.started());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MemoryListEvent.nextPageRequested());
    },
    skip: 3,
    expect: () => [
      isA<MemoryListLoaded>()
          .having((s) => s.memories.length, 'rows kept', 1)
          .having((s) => s.isAppending, 'isAppending', false),
    ],
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'paging past the end is a no-op',
    build: () {
      when(
        () => fetchMemories.call(any()),
      ).thenAnswer((_) async => _page([_memory('a')]));
      return build();
    },
    act: (bloc) async {
      bloc.add(const MemoryListEvent.started());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MemoryListEvent.nextPageRequested());
    },
    skip: 2,
    expect: () => const <MemoryListState>[],
    verify: (_) => verify(() => fetchMemories.call(any())).called(1),
  );

  blocTest<MemoryListBloc, MemoryListState>(
    'changing the filter restarts the list and is passed through',
    build: () {
      when(
        () => fetchMemories.call(any()),
      ).thenAnswer((_) async => _page([_memory('a')]));
      return build();
    },
    act: (bloc) =>
        bloc.add(const MemoryListEvent.filterChanged(LibraryFilter.images)),
    expect: () => [
      // The loading state carries the filter too, so the row of kinds never
      // snaps back to All while the narrowed list is on its way.
      const MemoryListState.loading(filter: LibraryFilter.images),
      isA<MemoryListLoaded>().having(
        (s) => s.filter,
        'filter',
        LibraryFilter.images,
      ),
    ],
    verify: (_) {
      final captured =
          verify(() => fetchMemories.call(captureAny())).captured.single
              as FetchMemoriesParams;
      expect(captured.types, {MemoryType.photo, MemoryType.screenshot});
      expect(captured.offset, 0);
    },
  );

  group('cached rows first', () {
    blocTest<MemoryListBloc, MemoryListState>(
      "the phone's copy shows at once, then the server's replaces it",
      build: () {
        when(
          () => fetchMemories.cached(any()),
        ).thenAnswer((_) async => _page([_memory('old')]));
        when(
          () => fetchMemories.call(any()),
        ).thenAnswer((_) async => _page([_memory('new'), _memory('old')]));
        return build();
      },
      act: (bloc) => bloc.add(const MemoryListEvent.started()),
      expect: () => [
        // No spinner: the cached list is the first thing drawn.
        isA<MemoryListLoaded>().having((s) => s.memories.length, 'cached', 1),
        isA<MemoryListLoaded>().having((s) => s.memories.length, 'fresh', 2),
      ],
    );

    blocTest<MemoryListBloc, MemoryListState>(
      'a failed refresh leaves the cached rows, not an error over them',
      build: () {
        when(
          () => fetchMemories.cached(any()),
        ).thenAnswer((_) async => _page([_memory('old')]));
        when(
          () => fetchMemories.call(any()),
        ).thenThrow(const AppException.network());
        return build();
      },
      act: (bloc) => bloc.add(const MemoryListEvent.started()),
      expect: () => [
        isA<MemoryListLoaded>().having((s) => s.memories.length, 'cached', 1),
      ],
    );

    blocTest<MemoryListBloc, MemoryListState>(
      'with nothing cached it is the spinner, as before',
      build: () {
        when(() => fetchMemories.cached(any())).thenAnswer((_) async => null);
        when(
          () => fetchMemories.call(any()),
        ).thenAnswer((_) async => _page([_memory('a')]));
        return build();
      },
      act: (bloc) => bloc.add(const MemoryListEvent.started()),
      expect: () => [const MemoryListState.loading(), isA<MemoryListLoaded>()],
    );
  });
}
