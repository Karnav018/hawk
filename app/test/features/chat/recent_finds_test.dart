import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/recent_finds.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/entities/recent_find.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/chat/presentation/bloc/answer_cubit.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

import '../../support/memory_cache.dart';

Answer _found(String question) => Answer(
  id: 'a-$question',
  question: question,
  blocks: const [
    AnswerBlock(text: 'Team is \$29 per seat [1].', citations: [1]),
  ],
  citations: const [
    Citation(
      memoryId: 'm1',
      index: 1,
      title: 'pricing.pdf',
      type: MemoryType.pdf,
      storagePath: 'users/u1/originals/m1/pricing.pdf',
    ),
  ],
  answeredAt: DateTime.utc(2026, 9, 26, 18),
);

RecentFind _find(String question) => RecentFind(
  question: question,
  answer: _found(question),
  foundAt: DateTime.utc(2026, 9, 26),
);

class _Answers implements AnswerRepository {
  _Answers(this.answer);
  final Answer answer;
  var asks = 0;

  @override
  Future<MatchResults> search(String query) async =>
      (matches: const <Match>[], signals: const QuerySignals());

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async {
    asks++;
    return answer;
  }
}

/// LAST FOUND — the row above the nav that reopens a find for free.
void main() {
  group('the store', () {
    test('keeps the newest two, newest first', () async {
      final finds = RecentFinds(MemoryCacheStore());
      await finds.record(_find('first'));
      await finds.record(_find('second'));
      await finds.record(_find('third'));
      expect([for (final f in finds.items) f.question], ['third', 'second']);
    });

    test(
      'asking the same thing again is one find, moved to the front',
      () async {
        final finds = RecentFinds(MemoryCacheStore());
        await finds.record(_find('pricing'));
        await finds.record(_find('lease'));
        await finds.record(_find('Pricing'));
        expect([for (final f in finds.items) f.question], ['Pricing', 'lease']);
      },
    );

    test('survives a restart, answer and files intact', () async {
      final cache = MemoryCacheStore();
      await RecentFinds(cache).record(_find('pricing'));

      final reopened = RecentFinds(cache);
      await reopened.load();
      final find = reopened.items.single;
      expect(find.answer.blocks.single.text, contains(r'$29 per seat'));
      expect(find.answer.citations.single.storagePath, contains('pricing.pdf'));
      expect(find.leadType, MemoryType.pdf);
    });
  });

  group('the cubit', () {
    test('a question that found something is kept', () async {
      final finds = RecentFinds(MemoryCacheStore());
      final cubit = AnswerCubit(_Answers(_found('pricing')), finds, 'pricing');
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(finds.items.single.question, 'pricing');
    });

    test('"nothing matches" is not kept', () async {
      final finds = RecentFinds(MemoryCacheStore());
      final cubit = AnswerCubit(
        _Answers(const Answer(id: 'x', question: 'uh', answered: false)),
        finds,
        'uh',
      );
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(finds.items, isEmpty);
    });

    test('reopening a find asks nothing — no ask is spent', () async {
      final answers = _Answers(_found('pricing'));
      final cubit = AnswerCubit.replay(
        answers,
        RecentFinds(MemoryCacheStore()),
        _find('pricing'),
      );
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);

      expect(answers.asks, 0);
      expect(cubit.state.answer?.citations.single.title, 'pricing.pdf');
      expect(cubit.state.isBusy, isFalse);
    });
  });
}
