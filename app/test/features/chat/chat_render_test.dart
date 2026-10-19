import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/chat/data/recent_finds.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/chat/presentation/bloc/answer_cubit.dart';
import 'package:knowra/src/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:knowra/src/features/chat/presentation/widgets/chat_thread.dart';
import 'package:knowra/src/features/chat/presentation/widgets/result_file.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

import '../../support/memory_cache.dart';

/// Does the chat actually render?
///
/// The existing chat tests are about one bubble's corners. Nothing put a
/// whole thread on a phone-sized screen and looked for the failures that only
/// appear there: a RenderFlex overflow, an unbounded-height list, a long
/// unbroken token with nowhere to wrap. Those do not show up in a unit test
/// and they do not show up on a wide simulator either — they show up on the
/// narrowest device a user owns, which is what this pumps.
void main() {
  const narrow = Size(320, 568); // the smallest phone still in support

  // ChatTrouble offers a retry, so the thread needs the cubit even when the
  // test only cares about layout.
  late AnswerCubit cubit;
  setUp(
    () => cubit = AnswerCubit(_Answers(), RecentFinds(MemoryCacheStore()), ''),
  );
  tearDown(() => cubit.close());

  Widget host(AnswerState state, {Size size = narrow}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: AppTheme.dark,
      home: BlocProvider<AnswerCubit>.value(
        value: cubit,
        child: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: ChatThread(state: state, controller: ScrollController()),
          ),
        ),
      ),
    ),
  );

  Answer answerWith(List<String> paragraphs, {int citations = 0}) => Answer(
    id: 'a1',
    question: 'q',
    answered: true,
    confidence: AnswerConfidence.high,
    blocks: [
      for (final p in paragraphs) AnswerBlock(text: p, citations: const []),
    ],
    citations: [
      for (var i = 0; i < citations; i++)
        Citation(
          index: i + 1,
          memoryId: 'm$i',
          title: 'A document with a fairly long title number $i.pdf',
          type: MemoryType.pdf,
          locator: 'part ${i + 1}',
          score: 90 - i,
        ),
    ],
    answeredAt: DateTime(2026, 9, 22),
    latency: const Duration(milliseconds: 900),
  );

  testWidgets('a question with no answer yet holds the place', (tester) async {
    await tester.pumpWidget(host(const AnswerState(question: 'Where is it?')));
    await tester.pump();

    expect(find.text('Where is it?'), findsOneWidget);
    expect(find.text('Reading your files…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long answer with files does not overflow a small phone', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AnswerState(
          question: 'What did the board decide about the budget last quarter?',
          answer: answerWith([
            'The board approved the revised budget on the 14th, with the '
                'reduction to contractor spend carried over from the previous '
                'review and a new ceiling on travel.',
            'Two items were deferred: the office move and the tooling '
                'renewal, both to the next cycle.',
          ], citations: 3),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');

    // `ListView(children:)` is still lazy — off-screen rows are not in the
    // element tree at all, so they have to be scrolled into view before they
    // can be found, or the assertion passes vacuously.
    await tester.drag(find.byType(ChatThread), const Offset(0, -600));
    await tester.pump();
    expect(find.byType(FileRow), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'overflow after scrolling');
  });

  testWidgets('an unbreakable token wraps rather than overflowing', (
    tester,
  ) async {
    // A URL or a hash pasted into the thread. Text that cannot break is the
    // classic way a bubble blows out its parent's width.
    await tester.pumpWidget(
      host(
        AnswerState(
          question: 'https://example.com/${'a' * 200}',
          answer: answerWith(['x' * 300]),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final bubble in tester.widgetList<ChatBubble>(
      find.byType(ChatBubble),
    )) {
      final rect = tester.getRect(find.byWidget(bubble));
      expect(rect.width, lessThanOrEqualTo(narrow.width));
    }
  });

  testWidgets('a failed turn renders in place of the reply', (tester) async {
    await tester.pumpWidget(
      host(
        const AnswerState(
          question: 'Anything?',
          exception: AppException.network(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatTrouble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long history of turns still lays out', (tester) async {
    await tester.pumpWidget(
      host(
        AnswerState(
          turns: [
            for (var i = 0; i < 12; i++)
              Turn(
                question: 'Earlier question number $i, reasonably long.',
                answer: answerWith(['An earlier reply number $i.']),
              ),
          ],
          question: 'And now?',
          answer: answerWith(['The latest reply.'], citations: 2),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _Answers implements AnswerRepository {
  @override
  Future<MatchResults> search(String query) async =>
      (matches: const <Match>[], signals: const QuerySignals());

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async => throw UnimplementedError();
}
