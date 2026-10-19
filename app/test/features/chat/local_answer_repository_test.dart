import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/firebase/firebase_answer_repository.dart';
import 'package:knowra/src/features/chat/data/local/index_sync.dart';
import 'package:knowra/src/features/chat/data/local/local_answer_repository.dart';
import 'package:knowra/src/features/chat/data/local/local_index.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

class _Remote extends Mock implements FirebaseAnswerRepository {}

class _Sync extends Mock implements IndexSync {}

class _Memories extends Fake implements MemoryRepository {
  @override
  Stream<List<Memory>> watchMemories(List<String> ids) => Stream.value([
    for (final id in ids)
      Memory(
        id: id,
        type: MemoryType.pdf,
        status: ProcessingStatus.ready,
        title: '$id.pdf',
        storagePath: 'users/u1/originals/$id/$id.pdf',
        createdAt: DateTime(2026, 9, 1),
      ),
  ]);
}

Float32List _v(double x, double y) => Float32List.fromList([x, y, 0]);

LocalChunk _chunk(String id, String memoryId, String text, int part) =>
    LocalChunk(
      id: id,
      memoryId: memoryId,
      memoryTitle: '$memoryId.pdf',
      memoryType: MemoryType.pdf,
      text: text,
      chunkIndex: part,
      active: true,
    );

const _answer = Answer(
  id: 'a',
  question: 'q',
  blocks: [
    AnswerBlock(text: 'Team is \$29 [1].', citations: [1]),
  ],
  citations: [Citation(memoryId: 'pricing', index: 1, title: 'pricing.pdf')],
);

/// Retrieval on the phone; the server answers from what the phone chose.
void main() {
  late Directory root;
  late LocalIndex index;
  late _Remote remote;
  late _Sync sync;

  setUpAll(() {
    registerFallbackValue(<({String chunkId, double distance})>[]);
    registerFallbackValue(const QuerySignals());
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('hawk-repo-');
    index = LocalIndex.at(root);
    await index.load('u1');
    index
      ..upsert(_chunk('c1', 'pricing', 'Team is \$29 per seat.', 3))
      ..upsert(_chunk('c2', 'lease', 'Rent is due on the first.', 0))
      ..upsert(_chunk('c3', 'pricing', 'Solo is \$12.', 1))
      ..setVectors({'c1': _v(1, 0), 'c2': _v(0, 1), 'c3': _v(0.9, 0.1)});
    remote = _Remote();
    sync = _Sync();
    when(() => sync.isReady).thenReturn(true);
    when(() => sync.embedQuery(any())).thenAnswer((_) async => _v(1, 0));
  });
  tearDown(() => root.deleteSync(recursive: true));

  LocalAnswerRepository build() =>
      LocalAnswerRepository(remote, sync, index, _Memories());

  test(
    'search runs on the phone and never calls the server\'s search',
    () async {
      final found = await build().search('team price per seat');

      verifyNever(() => remote.search(any()));
      expect(found.matches.first.memoryId, 'pricing');
      expect(found.matches.first.title, 'pricing.pdf');
      expect(found.matches.first.locator, 'part 4');
      expect(found.matches.first.excerpt, 'Team is \$29 per seat.');
      // Somewhere to open, from the memory itself.
      expect(found.matches.first.storagePath, contains('pricing'));
      expect(found.matches.map((m) => m.chunkId), containsAll(['c1', 'c3']));
    },
  );

  test('ask sends the chosen passage ids, never their text', () async {
    when(
      () => remote.askWithPassages(
        any(),
        any(),
        conversationId: any(named: 'conversationId'),
        signals: any(named: 'signals'),
      ),
    ).thenAnswer((_) async => _answer);

    final answer = await build().ask(
      'what about the team price?',
      conversationId: 'conv-1',
      earlier: ['pricing tiers we agreed'],
    );

    expect(answer, _answer);
    final captured = verify(
      () => remote.askWithPassages(
        captureAny(),
        captureAny(),
        conversationId: captureAny(named: 'conversationId'),
        signals: any(named: 'signals'),
      ),
    ).captured;
    expect(captured[0], 'what about the team price?');
    final passages = captured[1] as List<({String chunkId, double distance})>;
    expect(passages.first.chunkId, 'c1');
    expect(passages.every((p) => p.distance >= 0 && p.distance <= 2), isTrue);
    expect(captured[2], 'conv-1');
    // The follow-up was embedded with its earlier question folded in.
    // …with its own filler trimmed, the way the server trimmed it.
    final embedded =
        verify(() => sync.embedQuery(captureAny())).captured.single as String;
    expect(embedded, startsWith('pricing tiers we agreed'));
    expect(embedded, endsWith('team price'));
    verifyNever(
      () => remote.ask(any(), conversationId: any(named: 'conversationId')),
    );
  });

  test('until the local index is ready, both calls go to the server', () async {
    when(() => sync.isReady).thenReturn(false);
    when(() => remote.search(any())).thenAnswer(
      (_) async => (matches: const <Match>[], signals: const QuerySignals()),
    );
    when(
      () => remote.ask(
        any(),
        conversationId: any(named: 'conversationId'),
        earlier: any(named: 'earlier'),
      ),
    ).thenAnswer((_) async => _answer);

    final repo = build();
    await repo.search('lease');
    await repo.ask('lease');

    verify(() => remote.search('lease')).called(1);
    verify(
      () => remote.ask(
        'lease',
        conversationId: any(named: 'conversationId'),
        earlier: any(named: 'earlier'),
      ),
    ).called(1);
    verifyNever(() => sync.embedQuery(any()));
  });

  test('a type word narrows the local search before ranking', () async {
    index
      ..upsert(
        LocalChunk(
          id: 'p1',
          memoryId: 'whiteboard',
          memoryTitle: 'whiteboard.jpg',
          memoryType: MemoryType.photo,
          text: 'TIERS solo team scale',
          chunkIndex: 0,
          active: true,
        ),
      )
      ..setVectors({'p1': _v(1, 0)});

    final found = await build().search('the photo of the tiers');
    expect(found.matches.map((m) => m.memoryId), ['whiteboard']);
    expect(found.signals.type, 'image');
  });

  test('an excerpt is cut on a word', () {
    expect(excerpt('short'), 'short');
    final long = List.filled(60, 'word').join(' ');
    final cut = excerpt(long);
    expect(cut.endsWith('…'), isTrue);
    expect(cut.length, lessThanOrEqualTo(221));
    expect(cut.contains('wor…'), isFalse);
  });
}
