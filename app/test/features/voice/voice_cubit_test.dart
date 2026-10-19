import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';

import 'dictation_test.dart' show FakeAnswers, FakeRecogniser;

void main() {
  group('VoiceState', () {
    test('the timer is blank at rest', () {
      // "00:00" beside an idle orb suggests something is being recorded.
      const state = VoiceState();
      expect(state.timerText, isEmpty);
      expect(state.timer, '00:00');
    });

    test('the timer pads both fields', () {
      const state = VoiceState(phase: VoicePhase.listening, elapsedSeconds: 7);
      expect(state.timerText, '00:07');
      expect(
        const VoiceState(
          phase: VoicePhase.listening,
          elapsedSeconds: 605,
        ).timerText,
        '10:05',
      );
    });
  });

  group('VoiceCubit', () {
    test('typing wakes the orb, clearing settles it', () {
      final cubit = VoiceCubit(FakeRecogniser(), FakeAnswers());
      expect(cubit.state.phase, VoicePhase.ready);

      cubit.transcriptChanged('what did we agree on pricing');
      expect(cubit.state.phase, VoicePhase.listening);
      expect(cubit.state.canAsk, isTrue);

      cubit.transcriptChanged('   ');
      expect(cubit.state.phase, VoicePhase.ready);
      expect(cubit.state.canAsk, isFalse);
    });

    test('submitting moves to retrieving', () {
      final cubit = VoiceCubit(FakeRecogniser(), FakeAnswers())
        ..transcriptChanged('q');
      cubit.submitted();
      expect(cubit.state.phase, VoicePhase.retrieving);
    });
  });

  _searchBehaviour();

  group('phase motion', () {
    test('faster swirl means more work, monotonically', () {
      // The whole point of the home screen is that you can tell what it is
      // doing from across a room, so the ordering has to hold.
      expect(
        VoicePhase.retrieving.swirlSeconds,
        lessThan(VoicePhase.listening.swirlSeconds),
      );
      expect(
        VoicePhase.listening.swirlSeconds,
        lessThan(VoicePhase.answered.swirlSeconds),
      );
      expect(
        VoicePhase.answered.swirlSeconds,
        lessThan(VoicePhase.ready.swirlSeconds),
      );
    });

    test('bars only while listening', () {
      for (final phase in VoicePhase.values) {
        expect(
          phase.showsBars,
          phase == VoicePhase.listening,
          reason: phase.name,
        );
      }
    });

    test('every phase has a hint, because the orb alone is ambiguous', () {
      for (final phase in VoicePhase.values) {
        expect(phase.hint, isNotEmpty, reason: phase.name);
      }
    });
  });
}

void _searchBehaviour() {
  group('finding files', () {
    test('a query under three characters searches nothing', () async {
      final answers = FakeAnswers();
      final cubit = VoiceCubit(FakeRecogniser(), answers);

      await cubit.find(text: 'pd');

      // Two characters match half the vault; the result would be noise
      // dressed up as an answer.
      expect(answers.searched, isEmpty);
      expect(cubit.state.matches, isEmpty);
      await cubit.close();
    });

    test('matches and signals land on the state', () async {
      final answers = FakeAnswers(
        matches: const [
          Match(memoryId: 'm1', chunkId: 'c1', title: 'Pricing v4', score: 94),
        ],
        signals: const QuerySignals(type: 'document'),
      );
      final cubit = VoiceCubit(FakeRecogniser(), answers);

      await cubit.find(text: 'pricing schedule');

      expect(cubit.state.matches.single.score, 94);
      expect(cubit.state.signals.type, 'document');
      expect(cubit.state.searchedFor, 'pricing schedule');
      expect(cubit.state.isSearching, isFalse);
      await cubit.close();
    });

    test('the same query twice searches once', () async {
      final answers = FakeAnswers(
        matches: const [Match(memoryId: 'm1', chunkId: 'c1', title: 'A')],
      );
      final cubit = VoiceCubit(FakeRecogniser(), answers);

      await cubit.find(text: 'pricing schedule');
      await cubit.find(text: 'pricing schedule');

      expect(answers.searched, hasLength(1));
      await cubit.close();
    });

    test('a stale result cannot overwrite a newer one', () async {
      final answers = FakeAnswers(
        matches: const [Match(memoryId: 'old', chunkId: 'c1', title: 'Old')],
      );
      final gate = Completer<void>();
      answers.gate = gate;
      final cubit = VoiceCubit(FakeRecogniser(), answers);

      // A search for the old phrase is in flight when the user types on.
      final inFlight = cubit.find(text: 'pricing');
      cubit.transcriptChanged('pricing schedule for the flat');
      gate.complete();
      await inFlight;

      // Without the guard, the slow answer to "pricing" would land on top of
      // a screen that has moved on — results for a question the user is no
      // longer asking, which reads as the app finding the wrong thing.
      expect(cubit.state.matches, isEmpty);
      await cubit.close();
    });

    test('a failure is reported and the orb stops spinning', () async {
      final answers = FakeAnswers()..error = const AppException.network();
      final cubit = VoiceCubit(FakeRecogniser(), answers);
      cubit.submitted();

      await cubit.find(text: 'pricing schedule');

      expect(cubit.state.searchError, isNotNull);
      expect(cubit.state.isSearching, isFalse);
      expect(
        cubit.state.phase,
        VoicePhase.answered,
        reason: 'leaving it retrieving would say the search is still going',
      );
      await cubit.close();
    });
  });
}
