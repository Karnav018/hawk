import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/data/recent_finds.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/entities/seeded_question.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/chat/presentation/bloc/answer_cubit.dart';

import '../../support/memory_cache.dart';

class _Answers implements AnswerRepository {
  var searches = 0;
  var asks = 0;

  @override
  Future<MatchResults> search(String query) async {
    searches++;
    return (matches: const <Match>[], signals: const QuerySignals());
  }

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async {
    asks++;
    return Answer(
      id: 'a',
      question: question,
      blocks: const [
        AnswerBlock(text: 'Team is \$29 [1].', citations: [1]),
      ],
      citations: const [
        Citation(memoryId: 'm1', index: 1, title: 'pricing.pdf'),
      ],
    );
  }
}

/// A question released with its files already found asks only for the
/// answer — the second search a fresh cubit would have made is the one the
/// voice face already did while the user was speaking.
void main() {
  test('starts with the files and never searches again', () async {
    final answers = _Answers();
    final cubit = AnswerCubit.seeded(
      answers,
      RecentFinds(MemoryCacheStore()),
      const SeededQuestion(
        question: 'what did we agree on pricing',
        matches: [Match(memoryId: 'm1', chunkId: 'c1', title: 'pricing.pdf')],
        signals: QuerySignals(type: 'document'),
      ),
    );
    addTearDown(cubit.close);

    // Before any round trip: the rows are already there.
    expect(cubit.state.matches.single.title, 'pricing.pdf');
    expect(cubit.state.signals.type, 'document');
    expect(cubit.state.isSearching, isFalse);
    expect(cubit.state.isAsking, isTrue);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(answers.searches, 0);
    expect(answers.asks, 1);
    expect(cubit.state.answer?.citations.single.title, 'pricing.pdf');
    expect(cubit.state.isBusy, isFalse);
  });
}
