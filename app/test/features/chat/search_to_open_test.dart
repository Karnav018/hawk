import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/di/injector.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/files/original_access.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/chat/data/firebase/firebase_answer_repository.dart';
import 'package:knowra/src/features/chat/data/recent_finds.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/chat/presentation/bloc/answer_cubit.dart';
import 'package:knowra/src/features/chat/presentation/widgets/chat_thread.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/memory/domain/usecases/memory_usecases.dart';
import 'package:knowra/src/features/memory/presentation/bloc/file_viewer_cubit.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

import '../../support/memory_cache.dart';

// ---------------------------------------------------------------------------
// The three things a question depends on — finding the file, getting it, and
// opening it — each tested against the real app code, with only the platform
// at the edge faked: Cloud Functions, Firebase Storage, the OS file opener.
//
// The payloads below are copied from what `firebase/functions/api.py`
// returns, key for key. A rename on either side fails here rather than
// showing up as a result row that silently cannot open.
// ---------------------------------------------------------------------------

const _kept = 'users/u1/originals/m1/pricing-schedule-v4.pdf';

/// `api.search`'s response, as the callable delivers it.
final _searchPayload = <Object?, Object?>{
  'query': 'what is the team price',
  'signals': {'type': 'pdf', 'rewritten': false},
  'matches': [
    {
      'memoryId': 'm1',
      'chunkId': 'm1_3',
      'title': 'pricing-schedule-v4.pdf',
      'type': 'pdf',
      'excerpt': 'Team is \$29 per seat, billed monthly.',
      'score': 91.6,
      'locator': 'part 4',
      'url': null,
      'storagePath': _kept,
    },
    {
      'memoryId': 'm2',
      'chunkId': 'm2_0',
      'title': 'Pricing thread',
      'type': 'link',
      'excerpt': 'We agreed on per-seat.',
      'score': 64,
      'locator': 'part 1',
      'url': 'https://mail.example.com/thread/9',
      'storagePath': null,
    },
  ],
  'allowance': {'limit': 4, 'used': 1, 'remaining': 3},
};

/// `api.ask`'s response.
final _askPayload = <Object?, Object?>{
  'id': 'u1-1758600000000',
  'question': 'what is the team price',
  'answered': true,
  'confidence': 'high',
  'blocks': [
    {
      'text': 'Team is \$29 per seat, billed monthly [1].',
      'citations': [1],
    },
  ],
  'citations': [
    {
      'index': 1,
      'memoryId': 'm1',
      'title': 'pricing-schedule-v4.pdf',
      'type': 'pdf',
      'url': null,
      'storagePath': _kept,
      'locator': 'part 4',
      'score': 91,
    },
  ],
  'answeredAt': '2026-09-23T10:00:00+00:00',
  'latencyMs': 1840,
  'conversationId': 'c1',
  'signals': {'type': 'pdf'},
  'retrieved': 8,
};

class _Functions extends Mock implements FirebaseFunctions {}

class _Callable extends Mock implements HttpsCallable {}

class _Result extends Mock implements HttpsCallableResult<Object?> {}

class _Logger implements AppLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}

FirebaseAnswerRepository _repository({
  Object? search,
  Object? ask,
  FirebaseFunctionsException? error,
}) {
  final functions = _Functions();
  for (final (name, payload) in [('search', search), ('ask', ask)]) {
    final callable = _Callable();
    final result = _Result();
    when(() => result.data).thenReturn(payload);
    when(() => functions.httpsCallable(name)).thenReturn(callable);
    when(() => callable.call<Object?>(any())).thenAnswer((_) async {
      if (error != null) throw error;
      return result;
    });
  }
  return FirebaseAnswerRepository(functions, _Logger());
}

// --- Storage -----------------------------------------------------------------

class _Storage extends Mock implements FirebaseStorage {}

class _Ref extends Mock implements Reference {}

class _Snapshot extends Fake implements TaskSnapshot {}

/// A download that is a plain future underneath — `DownloadTask` is a
/// `Future<TaskSnapshot>`, and `await` only needs `then`.
class _Download extends Fake implements DownloadTask {
  _Download(this._future);

  final Future<TaskSnapshot> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => _future.catchError(onError, test: test);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

class _Cache implements LocalOriginals {
  final requested = <String>[];

  @override
  Future<File?> find(String memoryId) async => null;

  @override
  Future<File> destination({
    required String memoryId,
    required String filename,
  }) async {
    requested.add('$memoryId/$filename');
    return File('${Directory.systemTemp.path}/hawk-test/$memoryId/$filename');
  }

  @override
  Future<File> keep({
    required String memoryId,
    required String sourcePath,
    required String filename,
  }) => throw UnimplementedError();

  @override
  Future<void> forget(String memoryId) async {}
}

// --- Opening -----------------------------------------------------------------

/// Records what the Open chip asked for, and answers as the phone would.
class _Opener implements OriginalAccess {
  _Opener({this.fetches = true});

  final bool fetches;
  final calls = <String>[];
  ({String memoryId, String? url, String? storagePath})? resolved;

  @override
  Future<OriginalHandle> resolve({
    required String memoryId,
    String? url,
    String? storagePath,
    String? filename,
  }) async {
    calls.add('resolve');
    resolved = (memoryId: memoryId, url: url, storagePath: storagePath);
    return OriginalInVault(storagePath: storagePath!, filename: filename!);
  }

  @override
  Future<OriginalHandle> materialise(
    OriginalHandle handle,
    String memoryId,
  ) async {
    calls.add('materialise');
    return fetches ? OriginalOnDevice(File('/tmp/$memoryId.pdf')) : handle;
  }

  @override
  Future<OpenOutcome> open(OriginalHandle handle) async {
    calls.add('open:${handle.runtimeType}');
    return handle is OriginalOnDevice
        ? OpenOutcome.opened
        : OpenOutcome.unreachable;
  }

  @override
  Future<bool> share(
    OriginalHandle handle, {
    required String title,
    String? fallback,
    Rect? origin,
  }) async => true;
}

class _Snacks extends SnackController {
  final shown = <Snack>[];

  @override
  void show(Snack snack) => shown.add(snack);

  List<String> get titles => [
    for (final s in shown)
      if (s case DetailSnack(:final title)) title,
  ];
}

class _Answers implements AnswerRepository {
  _Answers(this.source);

  final FirebaseAnswerRepository source;

  @override
  Future<MatchResults> search(String query) => source.search(query);

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) => source.ask(question, conversationId: conversationId);
}

// --- Library -------------------------------------------------------------------

class _Memories extends Fake implements MemoryRepository {
  _Memories(this.memories);

  final Map<String, Memory> memories;

  @override
  Future<Memory> fetchMemory(String id) async =>
      memories[id] ??
      (throw const AppException.notFound(
        message: 'That memory does not exist.',
      ));
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(File(''));
  });

  group('1 · searching — the backend\'s answer, read by the app', () {
    test('every match keeps what it needs to be opened', () async {
      final found = await _repository(
        search: _searchPayload,
      ).search('what is the team price');

      expect(found.matches, hasLength(2));
      final pdf = found.matches.first;
      expect(pdf.memoryId, 'm1');
      expect(pdf.title, 'pricing-schedule-v4.pdf');
      expect(pdf.type, MemoryType.pdf);
      expect(pdf.locator, 'part 4');
      expect(pdf.score, 92);
      expect(
        pdf.storagePath,
        _kept,
        reason: 'without it a vault file cannot be fetched on this phone',
      );

      final link = found.matches.last;
      expect(link.type, MemoryType.link);
      expect(link.url, 'https://mail.example.com/thread/9');
      expect(link.storagePath, isNull);
    });

    test('an empty question never reaches the server', () async {
      final found = await _repository().search('   ');
      expect(found.matches, isEmpty);
    });

    test('the answer\'s citations point at the same files', () async {
      final answer = await _repository(
        ask: _askPayload,
      ).ask('what is the team price');

      expect(answer.answered, isTrue);
      expect(answer.blocks.single.text, contains(r'$29 per seat'));
      expect(answer.conversationId, 'c1');
      final source = answer.citations.single;
      expect(source.memoryId, 'm1');
      expect(source.storagePath, _kept);
      expect(source.type, MemoryType.pdf);
    });

    test('out of asks: the server\'s own words reach the user', () async {
      final repo = _repository(
        error: FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'That is all 4 questions for today.',
        ),
      );
      await expectLater(
        repo.search('anything'),
        throwsA(
          isA<AppException>().having(
            (e) => e.displayMessage,
            'message',
            'That is all 4 questions for today.',
          ),
        ),
      );
    });

    test('offline reads as a network problem, not a crash', () async {
      final repo = _repository(
        error: FirebaseFunctionsException(code: 'unavailable', message: ''),
      );
      await expectLater(repo.ask('anything'), throwsA(isA<NetworkException>()));
    });
  });

  group('2 · getting the file — the vault download', () {
    test('fetches exactly the kept path into the local cache', () async {
      final storage = _Storage();
      final ref = _Ref();
      final cache = _Cache();
      when(() => storage.ref(_kept)).thenReturn(ref);
      when(
        () => ref.writeToFile(any()),
      ).thenAnswer((_) => _Download(Future.value(_Snapshot())));

      final access = NativeOriginalAccess(cache, storage, _Logger());
      final handle = await access.resolve(
        memoryId: 'm1',
        storagePath: _kept,
        filename: 'pricing-schedule-v4.pdf',
      );
      expect(handle, isA<OriginalInVault>());

      final local = await access.materialise(handle, 'm1');

      verify(() => storage.ref(_kept)).called(1);
      expect(cache.requested, ['m1/pricing-schedule-v4.pdf']);
      expect(local, isA<OriginalOnDevice>());
      expect(
        (local as OriginalOnDevice).file.path,
        endsWith('m1/pricing-schedule-v4.pdf'),
        reason: 'downloaded into the cache, so the second open is offline',
      );
    });

    test('a failed download says so instead of opening nothing', () async {
      final storage = _Storage();
      final ref = _Ref();
      when(() => storage.ref(_kept)).thenReturn(ref);
      when(() => ref.writeToFile(any())).thenAnswer(
        (_) => _Download(
          Future.error(
            FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
          ),
        ),
      );

      final access = NativeOriginalAccess(_Cache(), storage, _Logger());
      final handle = await access.resolve(
        memoryId: 'm1',
        storagePath: _kept,
        filename: 'pricing-schedule-v4.pdf',
      );
      final after = await access.materialise(handle, 'm1');

      expect(after, isA<OriginalInVault>());
      expect(await access.open(after), OpenOutcome.unreachable);
    });
  });

  group('3 · opening — from the answer on screen', () {
    late _Snacks snacks;
    late RecentFinds recent;

    setUp(() {
      recent = RecentFinds(MemoryCacheStore());
      snacks = _Snacks();
      getIt.registerSingleton<SnackController>(snacks);
    });
    tearDown(() => getIt.reset(dispose: false));

    Future<void> ask(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(402, 874)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // The real cubit over the real repository — only the callable is fake.
      final cubit = AnswerCubit(
        _Answers(_repository(search: _searchPayload, ask: _askPayload)),
        recent,
        'what is the team price',
      );
      addTearDown(cubit.close);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: BlocBuilder<AnswerCubit, AnswerState>(
                builder: (context, state) =>
                    ChatThread(state: state, controller: scroll),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'the answer arrives with its file, and Open fetches then opens',
      (tester) async {
        final opener = _Opener();
        getIt.registerSingleton<OriginalAccess>(opener);
        await ask(tester);

        expect(find.textContaining(r'$29 per seat'), findsOneWidget);
        expect(find.text('pricing-schedule-v4.pdf'), findsWidgets);

        await tester.tap(find.text('Open').first);
        await tester.pump();

        expect(opener.resolved?.memoryId, 'm1');
        expect(opener.resolved?.storagePath, _kept);
        expect(opener.calls, [
          'resolve',
          'materialise',
          'open:OriginalOnDevice',
        ]);
        expect(snacks.titles, ['Fetching pricing-schedule-v4.pdf']);
      },
    );

    testWidgets('when the download fails, the user is told why', (
      tester,
    ) async {
      getIt.registerSingleton<OriginalAccess>(_Opener(fetches: false));
      await ask(tester);

      await tester.tap(find.text('Open').first);
      await tester.pump();

      expect(snacks.titles, [
        'Fetching pricing-schedule-v4.pdf',
        'Could not fetch it',
      ]);
    });
  });

  group('4 · opening — from the library, into the viewer', () {
    final memory = Memory(
      id: 'm1',
      type: MemoryType.pdf,
      status: ProcessingStatus.ready,
      title: 'pricing-schedule-v4.pdf',
      text: 'Team is \$29 per seat.\n\nEnterprise is priced on request.',
      createdAt: DateTime(2026, 9, 14),
    );

    test('the viewer loads the memory it was opened for', () async {
      final repo = _Memories({'m1': memory});
      final cubit = FileViewerCubit(GetMemory(repo), 'm1');
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.memory?.title, 'pricing-schedule-v4.pdf');
      expect(cubit.state.pages.join(), contains(r'$29 per seat'));
    });

    test('a memory that is gone is an error, not a blank page', () async {
      final repo = _Memories(const {});
      final cubit = FileViewerCubit(GetMemory(repo), 'x');
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.memory, isNull);
      expect(cubit.state.exception, isA<NotFoundException>());
    });
  });
}
