import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../data/recent_finds.dart';
import '../../domain/entities/answer.dart';
import '../../domain/entities/recent_find.dart';
import '../../domain/entities/seeded_question.dart';
import '../../domain/repositories/answer_repository.dart';

part 'answer_cubit.freezed.dart';

/// One exchange in a thread.
///
/// Kept as a list rather than one current answer because a follow-up is only
/// intelligible next to what it followed: "who pushed back?" is not a
/// question on its own, and a screen that replaced the previous answer with
/// its own follow-up would leave the reader holding half a conversation.
@freezed
abstract class Turn with _$Turn {
  const factory Turn({required String question, Answer? answer}) = _Turn;
}

@freezed
abstract class AnswerState with _$AnswerState {
  const factory AnswerState({
    required String question,
    Answer? answer,

    /// The files retrieval found, shown before the answer exists.
    @Default(<Match>[]) List<Match> matches,
    @Default(QuerySignals()) QuerySignals signals,

    /// Earlier exchanges in this thread, oldest first.
    @Default(<Turn>[]) List<Turn> turns,
    String? conversationId,
    @Default(true) bool isAsking,
    @Default(true) bool isSearching,
    AppException? exception,
  }) = _AnswerState;

  const AnswerState._();

  bool get hasAnswer => answer != null;

  /// Whether there is anything at all on screen yet.
  ///
  /// Sources arriving first is the point: retrieval takes about a second and
  /// generation several, so a screen that waits for prose shows a spinner
  /// for the entire time it already knows the answer's sources.
  bool get hasSources => matches.isNotEmpty;

  bool get isBusy => isAsking || isSearching;
}

/// Screen 3B — ANSWER.
///
/// Runs retrieval and generation **concurrently**, and renders whichever
/// finishes first. They are two calls to two endpoints over the same
/// question: `search` costs one embedding and a vector read, `ask` costs
/// that plus a model writing prose. Waiting for the second to show the
/// first is the difference between a screen that responds in a second and
/// one that responds in five.
///
/// It does mean the question is embedded twice, once per call. That is a
/// real cost — about half a second of server time, no user-visible latency
/// because they overlap — and it buys the screen filling immediately.
/// Threading one embedding through both would mean `ask` taking a vector
/// from the client, which is a retrieval the server no longer controls.
@injectable
class AnswerCubit extends Cubit<AnswerState> with SafeEmit<AnswerState> {
  AnswerCubit(this._repository, this._recent, @factoryParam String question)
    : super(AnswerState(question: question)) {
    // An empty question means the thread starts idle, which is how the chat
    // face on home creates one: the screen exists before anybody has asked
    // anything. A cubit that ran on construction could only ever serve a
    // route that already had a question in hand.
    if (question.trim().isEmpty) {
      emit(state.copyWith(isAsking: false, isSearching: false));
      return;
    }
    _run();
  }

  /// Reopens a question that already found something — LAST FOUND on the
  /// voice face — exactly as it was answered.
  ///
  /// **Nothing is sent.** The answer and its files come from this phone, so
  /// reopening one spends no ask; it is the same screen the user saw a
  /// minute ago, not a new question. Retry and follow-up still ask for real,
  /// because those are.
  AnswerCubit.replay(this._repository, this._recent, RecentFind find)
    : super(
        AnswerState(
          question: find.question,
          answer: find.answer,
          matches: find.matches,
          conversationId: find.answer.conversationId,
          isAsking: false,
          isSearching: false,
        ),
      );

  /// Starts from files a live search already found, and asks only for the
  /// answer.
  ///
  /// The voice face searches while the user is still speaking, so on
  /// release the files for the sentence are usually already known. A fresh
  /// cubit would search for the same words again and show nothing until it
  /// returned; this one shows them at once and spends the wait on the
  /// answer alone.
  AnswerCubit.seeded(this._repository, this._recent, SeededQuestion seed)
    : super(
        AnswerState(
          question: seed.question,
          matches: seed.matches,
          signals: seed.signals,
          isSearching: false,
        ),
      ) {
    unawaited(_ask(seed.question));
  }

  /// Nothing has been asked yet — the chat face's empty state.
  bool get isIdle => state.question.trim().isEmpty && state.turns.isEmpty;

  final AnswerRepository _repository;

  /// Where a question that found something is kept, for LAST FOUND.
  final RecentFinds _recent;

  /// Re-asks the current question from scratch. The retry path.
  Future<void> ask() => _run();

  /// Asks a follow-up in the same thread.
  ///
  /// The previous exchange moves into [AnswerState.turns] and the new
  /// question becomes current, carrying [AnswerState.conversationId] so the
  /// server retrieves with the earlier turns folded in — a follow-up is
  /// *retrieved* in context but *answered* as asked.
  Future<void> followUp(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.isBusy) return;

    // The first question on an idle thread is not a follow-up to anything.
    // Archiving here would push a blank turn above it, and the thread would
    // open with an empty bubble nobody sent.
    if (isIdle) {
      emit(state.copyWith(question: text, exception: null));
      await _run();
      return;
    }

    emit(
      state.copyWith(
        turns: [
          ...state.turns,
          Turn(question: state.question, answer: state.answer),
        ],
        question: text,
        answer: null,
        matches: const [],
        signals: const QuerySignals(),
        exception: null,
      ),
    );
    await _run();
  }

  Future<void> _run() async {
    emit(state.copyWith(isAsking: true, isSearching: true, exception: null));
    final question = state.question;

    // Not awaited in sequence: both are started, then each lands when it
    // lands. `Future.wait` would have been the obvious way to write this and
    // would have thrown away the whole point — it completes when the slower
    // one does.
    unawaited(_search(question));
    unawaited(_ask(question));
  }

  Future<void> _search(String question) async {
    try {
      final result = await _repository.search(question);
      if (isClosed || question != state.question) return;
      emit(
        state.copyWith(
          matches: result.matches,
          signals: result.signals,
          isSearching: false,
        ),
      );
    } catch (_) {
      if (isClosed || question != state.question) return;
      // Swallowed deliberately. Retrieval failing is not worth an error on
      // this screen while generation may still succeed — and if generation
      // fails too, *its* error is the one that explains the screen.
      emit(state.copyWith(isSearching: false));
    }
  }

  Future<void> _ask(String question) async {
    try {
      final answer = await _repository.ask(
        question,
        conversationId: state.conversationId,
        // For retrieval on the phone: a follow-up's nouns are in the
        // earlier turns. The server still answers the question as asked.
        earlier: [for (final t in state.turns) t.question],
      );
      if (isClosed || question != state.question) return;
      emit(
        state.copyWith(
          answer: answer,
          // Whatever the server called this thread is what the next
          // follow-up must quote. Held from the first answer onwards.
          conversationId: answer.conversationId ?? state.conversationId,
          isAsking: false,
        ),
      );
      // Kept only if it found something — the same test the server uses to
      // decide whether the question spent an ask. "Nothing matches" is not
      // a find worth reopening.
      if (answer.answered && answer.citations.isNotEmpty) {
        unawaited(
          _recent.record(
            RecentFind(
              question: question,
              answer: answer,
              matches: state.matches,
              foundAt: DateTime.now(),
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      if (isClosed || question != state.question) return;
      emit(
        state.copyWith(
          isAsking: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }
}
