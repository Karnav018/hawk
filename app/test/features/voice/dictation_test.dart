import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';

/// An answer repository under test control.
///
/// Records what it was asked, so a test can assert that dictation searched
/// for the *final* transcript rather than a partial one — which is the whole
/// contract between the recogniser and retrieval.
class FakeAnswers implements AnswerRepository {
  FakeAnswers({this.matches = const [], this.signals = const QuerySignals()});

  List<Match> matches;
  QuerySignals signals;
  final List<String> searched = [];
  Object? error;

  /// Completes only when released, for testing the in-flight state.
  Completer<void>? gate;

  @override
  Future<MatchResults> search(String query) async {
    searched.add(query);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return (matches: matches, signals: signals);
  }

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async => throw UnimplementedError();
}

/// A recogniser under test control.
class FakeRecogniser implements SpeechRecogniser {
  FakeRecogniser({this.available = true});

  final bool available;
  final _controller = StreamController<SpeechUpdate>.broadcast();
  int stops = 0;
  int cancels = 0;

  void emit(
    SpeechStatus status,
    String transcript, {
    bool isFinal = false,
    double level = 0,
  }) => _controller.add((
    status: status,
    transcript: transcript,
    isFinal: isFinal,
    level: level,
  ));

  void fail() => _controller.addError(StateError('engine died'));

  @override
  Future<bool> prepare() async => available;

  @override
  Stream<SpeechUpdate> listen() => _controller.stream;

  @override
  Stream<SpeechUpdate> dictate() => const Stream<SpeechUpdate>.empty();

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  _prefetch();
  group('dictation', () {
    test('a partial updates the transcript and keeps listening', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());

      await cubit.toggleDictation();
      expect(cubit.state.phase, VoicePhase.listening);

      fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.6);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.transcript, 'what did we agree');
      expect(cubit.state.level, 0.6);
      expect(cubit.state.phase, VoicePhase.listening);
      await cubit.close();
    });

    test('abandoning stops the microphone and forgets the words', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();
      fake.emit(SpeechStatus.listening, 'what did we agree');
      await Future<void>.delayed(Duration.zero);

      await cubit.abandonDictation();

      expect(fake.stops, 1);
      expect(cubit.state.phase, VoicePhase.ready);
      expect(cubit.state.transcript, '');
      expect(cubit.state.finished, isNull, reason: 'nothing is asked');
      await cubit.close();
    });

    test('abandoning when nothing is listening does nothing', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.abandonDictation();
      expect(fake.stops, 0);
      expect(cubit.state.phase, VoicePhase.ready);
      await cubit.close();
    });

    test('a level tick does not blank the transcript', () async {
      // The engine reports words and sound levels on separate callbacks. An
      // empty transcript on a level tick used to clear the field mid-sentence.
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      fake.emit(SpeechStatus.listening, 'on pricing');
      await Future<void>.delayed(Duration.zero);
      fake.emit(SpeechStatus.listening, '', level: 0.9);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.transcript, 'on pricing');
      expect(cubit.state.level, 0.9);
      await cubit.close();
    });

    test('a final result settles the orb but keeps the words', () async {
      final fake = FakeRecogniser();
      final answers = FakeAnswers();
      final cubit = VoiceCubit(fake, answers);
      await cubit.toggleDictation();

      fake.emit(
        SpeechStatus.done,
        'what did we agree on pricing',
        isFinal: true,
      );
      await Future<void>.delayed(Duration.zero);

      // `retrieving`, and a hand-off waiting to be collected: a finished
      // utterance is an asked question, and asked questions are answered on
      // screen 3B.
      expect(cubit.state.phase, VoicePhase.retrieving);
      expect(cubit.state.finished, 'what did we agree on pricing');
      expect(cubit.state.level, 0);
      expect(cubit.state.transcript, 'what did we agree on pricing');
      expect(
        cubit.state.canAsk,
        isTrue,
        reason: 'the question must survive for the user to submit',
      );
      expect(
        answers.searched,
        isEmpty,
        reason: 'the answer screen retrieves; searching here duplicates it',
      );

      // One-shot. A rebuild must not be able to push 3B twice for one
      // question, so the screen clears the signal as it navigates.
      cubit.handedOff();
      expect(cubit.state.finished, isNull);
      await cubit.close();
    });

    test('a partial utterance navigates nowhere', () async {
      final fake = FakeRecogniser();
      final answers = FakeAnswers();
      final cubit = VoiceCubit(fake, answers);
      await cubit.toggleDictation();

      // Partials arrive while the user is mid-sentence. Acting on one would
      // hand the answer screen a question nobody finished asking. (It *is*
      // searched for, quietly, once it settles — see the prefetch group.)
      fake.emit(SpeechStatus.listening, 'what did');
      fake.emit(SpeechStatus.listening, 'what did we agree');
      await Future<void>.delayed(Duration.zero);
      expect(answers.searched, isEmpty, reason: 'not before it settles');
      expect(cubit.state.finished, isNull);

      fake.emit(SpeechStatus.done, 'what did we agree on', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.finished, 'what did we agree on');
      await cubit.close();
    });

    test('the level is zero in every phase that is not listening', () async {
      // LO-4: the squash reads the level, and the level is a *microphone*
      // reading. Any phase reached without the microphone running must carry
      // zero, or the last value heard sits in the state with nothing left to
      // correct it — there are no more level ticks coming.
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      fake.emit(SpeechStatus.listening, 'pricing', level: 0.9);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.level, 0.9);

      // Submitting mid-utterance is the reachable route: tapping the field
      // and typing does not stop the orb.
      cubit.submitted();
      expect(cubit.state.phase, VoicePhase.retrieving);
      expect(cubit.state.level, 0);
      await cubit.close();
    });

    test('typing after dictation cannot leave a residual squash', () async {
      // The bad one. Typing puts the orb into `listening` — the only phase
      // whose squash reads the level — while no microphone is running. A
      // level left over from an earlier utterance would squash the orb and
      // then stay squashed for ever.
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      fake.emit(SpeechStatus.listening, 'pricing', level: 0.8);
      await Future<void>.delayed(Duration.zero);
      cubit.submitted();

      cubit.transcriptChanged('pricing schedule');
      expect(cubit.state.phase, VoicePhase.listening);
      expect(
        cubit.state.level,
        0,
        reason: 'typing has no microphone behind it',
      );
      await cubit.close();
    });

    test('stopping dictation clears the level', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      fake.emit(SpeechStatus.listening, 'pricing', level: 0.7);
      await Future<void>.delayed(Duration.zero);
      await cubit.stopDictation();

      expect(cubit.state.level, 0);
      expect(cubit.state.phase, VoicePhase.ready);
      expect(fake.stops, 1, reason: 'the recogniser must actually be stopped');
      await cubit.close();
    });

    test('stopping when nothing is listening changes nothing', () async {
      // 2C calls this before every typed submit, and most typed submits
      // happen with no microphone at all. It must not reach into the
      // `listening` phase that *typing* set, and must not call the plugin.
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      cubit.transcriptChanged('pricing schedule');
      expect(cubit.state.phase, VoicePhase.listening);

      await cubit.stopDictation();

      expect(cubit.state.phase, VoicePhase.listening);
      expect(fake.stops, 0, reason: 'no microphone was running');
      await cubit.close();
    });

    test('an empty utterance hands nothing off', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      // Tapping the orb and saying nothing must not open an answer screen
      // for an empty question — which would spend a question from the daily
      // allowance on silence.
      fake.emit(SpeechStatus.done, '   ', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.finished, isNull);
      await cubit.close();
    });

    test('an unavailable engine says so and leaves typing working', () async {
      final cubit = VoiceCubit(FakeRecogniser(available: false), FakeAnswers());
      await cubit.toggleDictation();

      expect(cubit.state.phase, VoicePhase.ready);
      expect(cubit.state.speechNote, isNotNull);
      // The typed path is the repair, not a consolation — it must still work.
      cubit.transcriptChanged('typed instead');
      expect(cubit.state.canAsk, isTrue);
      await cubit.close();
    });

    test('an engine error is recoverable, not fatal', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();

      fake.fail();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, VoicePhase.ready);
      expect(cubit.state.speechNote, isNotNull);
      await cubit.close();
    });

    test('a second tap stops listening', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());

      await cubit.toggleDictation();
      expect(cubit.state.phase, VoicePhase.listening);

      await cubit.toggleDictation();
      expect(cubit.state.phase, VoicePhase.ready);
      expect(fake.stops, 1);
      await cubit.close();
    });

    test('closing releases the microphone', () async {
      // A cubit disposed while listening leaves the mic hot — the OS shows a
      // recording indicator for an app that is no longer on screen.
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();
      await cubit.close();
      expect(fake.cancels, greaterThanOrEqualTo(1));
    });

    test('emits nothing after close', () async {
      final fake = FakeRecogniser();
      final cubit = VoiceCubit(fake, FakeAnswers());
      await cubit.toggleDictation();
      await cubit.close();

      // A late partial arriving after the router disposed the cubit must not
      // throw an emit-after-close.
      fake.emit(SpeechStatus.listening, 'too late');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.isClosed, isTrue);
    });
  });
}

/// Searching while the user is still speaking, so the result screen can
/// open with the files already in hand.
void _prefetch() {
  group('prefetch', () {
    test('what has been heard is searched once it settles', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final answers = FakeAnswers(
          matches: const [
            Match(memoryId: 'm1', chunkId: 'c1', title: 'Pricing v4'),
          ],
        );
        final cubit = VoiceCubit(fake, answers);
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();

        fake.emit(SpeechStatus.listening, 'what did', level: 0.4);
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.4);
        async.flushMicrotasks();
        expect(answers.searched, isEmpty);

        async.elapse(const Duration(milliseconds: 700));
        async.flushMicrotasks();
        // Once, for the latest words — the earlier partial was superseded
        // before its timer fired.
        expect(answers.searched, ['what did we agree']);
        expect(cubit.state.matches.single.title, 'Pricing v4');
        // Still listening, still the microphone's level: a prefetch landing
        // must not squash the eye or move the phase.
        expect(cubit.state.phase, VoicePhase.listening);
        expect(cubit.state.level, 0.4);
        expect(cubit.state.finished, isNull);

        unawaited(cubit.close());
      });
    });

    test('a release of the same words is seeded; different words are not', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final answers = FakeAnswers(
          matches: const [
            Match(memoryId: 'm1', chunkId: 'c1', title: 'Pricing v4'),
          ],
        );
        final cubit = VoiceCubit(fake, answers);
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 700));
        async.flushMicrotasks();

        expect(cubit.seedFor('what did we agree')?.matches, hasLength(1));
        expect(
          cubit.seedFor('what did we agree on the lease'),
          isNull,
          reason: 'files for a shorter sentence are not files for a longer one',
        );

        unawaited(cubit.close());
      });
    });

    test('a search still in flight is not a seed', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final answers = FakeAnswers(
          matches: const [Match(memoryId: 'm1', chunkId: 'c1', title: 'A')],
        )..gate = Completer<void>();
        final cubit = VoiceCubit(fake, answers);
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 700));
        async.flushMicrotasks();

        expect(answers.searched, ['what did we agree']);
        expect(cubit.seedFor('what did we agree'), isNull);

        answers.gate!.complete();
        async.flushMicrotasks();
        expect(cubit.seedFor('what did we agree'), isNotNull);

        unawaited(cubit.close());
      });
    });

    test('releasing cancels a prefetch that has not fired', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final answers = FakeAnswers();
        final cubit = VoiceCubit(fake, answers);
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));

        fake.emit(SpeechStatus.done, 'what did we agree on', isFinal: true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        // The result screen searches for the finished sentence itself.
        expect(answers.searched, isEmpty);
        expect(cubit.state.finished, 'what did we agree on');

        unawaited(cubit.close());
      });
    });
  });

  group('between questions', () {
    /// Asks [words] as a whole question and collects the hand-off, as the
    /// home screen does when it opens the result screen.
    void ask(
      FakeAsync async,
      VoiceCubit cubit,
      FakeRecogniser fake,
      String words,
    ) {
      unawaited(cubit.toggleDictation());
      async.flushMicrotasks();
      async.elapse(leftoverWindow);
      fake.emit(SpeechStatus.listening, words, level: 0.4);
      fake.emit(SpeechStatus.done, words, isFinal: true);
      async.flushMicrotasks();
      expect(cubit.state.finished, words);
      cubit.handedOff();
    }

    test('the last question arriving late is not the next question', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final cubit = VoiceCubit(fake, FakeAnswers());
        ask(async, cubit, fake, 'what did we agree on pricing');

        // The user taps the eye again, and the platform's late final result
        // for the first question comes through the new session.
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(
          SpeechStatus.done,
          'What did we agree on pricing?',
          isFinal: true,
        );
        async.flushMicrotasks();

        expect(cubit.state.finished, isNull, reason: 'nothing was asked yet');
        expect(cubit.state.transcript, isEmpty);
        expect(cubit.state.phase, VoicePhase.listening);

        // The new question itself goes through untouched.
        fake.emit(SpeechStatus.listening, 'the lease', level: 0.4);
        fake.emit(SpeechStatus.done, 'the lease and pets', isFinal: true);
        async.flushMicrotasks();
        expect(cubit.state.finished, 'the lease and pets');

        unawaited(cubit.close());
      });
    });

    test('asking the same question again, after a moment, still works', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final cubit = VoiceCubit(fake, FakeAnswers());
        ask(async, cubit, fake, 'invoice');
        ask(async, cubit, fake, 'invoice');
        unawaited(cubit.close());
      });
    });

    test('a new question that starts the same way is kept', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final cubit = VoiceCubit(fake, FakeAnswers());
        ask(async, cubit, fake, 'what did we agree on pricing');

        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what', level: 0.4);
        fake.emit(SpeechStatus.listening, 'what is the wifi', level: 0.4);
        async.flushMicrotasks();
        expect(cubit.state.transcript, 'what is the wifi');

        unawaited(cubit.close());
      });
    });

    test('a question the recogniser finished cannot be sent twice', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final cubit = VoiceCubit(fake, FakeAnswers());
        ask(async, cubit, fake, 'what did we agree on pricing');

        // The finger lifting after a hold, once the pause already sent it.
        unawaited(cubit.release());
        async.flushMicrotasks();
        expect(cubit.state.finished, isNull);

        unawaited(cubit.close());
      });
    });

    test('a new question starts with none of the last one\'s files', () {
      fakeAsync((async) {
        final fake = FakeRecogniser();
        final answers = FakeAnswers(
          matches: const [
            Match(memoryId: 'm1', chunkId: 'c1', title: 'Pricing v4'),
          ],
        );
        final cubit = VoiceCubit(fake, answers);
        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        fake.emit(SpeechStatus.listening, 'what did we agree', level: 0.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 700));
        async.flushMicrotasks();
        expect(cubit.state.matches, hasLength(1));

        fake.emit(SpeechStatus.done, 'what did we agree', isFinal: true);
        async.flushMicrotasks();
        cubit.handedOff();

        unawaited(cubit.toggleDictation());
        async.flushMicrotasks();
        expect(cubit.state.matches, isEmpty);
        expect(cubit.state.searchedFor, isEmpty);
        expect(cubit.seedFor('what did we agree'), isNull);

        unawaited(cubit.close());
      });
    });
  });

  group('isLeftover', () {
    test('the same words, ignoring case and punctuation', () {
      expect(isLeftover('What did we agree?', 'what did we agree'), isTrue);
    });

    test('a refined or a shorter version of them', () {
      expect(
        isLeftover('what did we agree on pricing', 'what did we agree'),
        isTrue,
      );
      expect(isLeftover('what did we', 'what did we agree'), isTrue);
    });

    test('different words, or nothing to compare with', () {
      expect(isLeftover('the lease', 'what did we agree'), isFalse);
      expect(isLeftover('what is the wifi', 'what did we agree'), isFalse);
      expect(isLeftover('invoice', ''), isFalse);
      expect(isLeftover('', 'invoice'), isFalse);
    });
  });
}
