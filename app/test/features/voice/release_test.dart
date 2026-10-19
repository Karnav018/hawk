import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';

/// `VoiceCubit.release` — the gesture v3's copy promises.
///
/// The home screen says "Hold to ask" and the listening screen says "Release
/// to search", so letting go has to submit. It could not before: `stop`
/// cancels the recogniser's subscription, so the platform's own `done` event
/// — the only thing that used to produce `finished` — never arrives, and a
/// held question was silently discarded.
///
/// These are the two halves of that contract: words are handed off, silence
/// is not.
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

class _Recogniser implements SpeechRecogniser {
  final _updates = StreamController<SpeechUpdate>.broadcast();
  int stops = 0;

  void hear(String transcript, {double level = 0.4}) => _updates.add((
    status: SpeechStatus.listening,
    transcript: transcript,
    isFinal: false,
    level: level,
  ));

  @override
  Future<bool> prepare() async => true;

  @override
  Stream<SpeechUpdate> listen() => _updates.stream;

  @override
  Stream<SpeechUpdate> dictate() => const Stream<SpeechUpdate>.empty();

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async {}
}

void main() {
  _restAfterHandoff();

  group('release', () {
    test('hands the words off and stops the microphone', () async {
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      speech.hear('what did we agree on pricing');
      await Future<void>.delayed(Duration.zero);

      await cubit.release();

      expect(cubit.state.finished, 'what did we agree on pricing');
      expect(cubit.state.phase, VoicePhase.retrieving);
      // The level is a microphone reading, and there is no microphone left to
      // correct it — so the release has to zero it or the orb stays squashed.
      expect(cubit.state.level, 0);
      expect(speech.stops, 1);

      await cubit.close();
    });

    test('a release that heard nothing asks nothing', () async {
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      await cubit.release();

      // Not an error and not a question: pressing the orb and thinking
      // better of it should cost nobody a screen.
      expect(cubit.state.finished, isNull);
      expect(cubit.state.phase, VoicePhase.ready);

      await cubit.close();
    });

    test('whitespace is not a question', () async {
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      speech.hear('   ');
      await Future<void>.delayed(Duration.zero);
      await cubit.release();

      expect(cubit.state.finished, isNull);
      expect(cubit.state.phase, VoicePhase.ready);

      await cubit.close();
    });

    test('a stray tap that caught "uh" asks nothing', () async {
      // The accidental touch on the eye: it latched, heard a scrap of
      // noise, and the next touch released it. That is not a question.
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      speech.hear('uh');
      await Future<void>.delayed(Duration.zero);
      await cubit.release();

      expect(cubit.state.finished, isNull);
      expect(cubit.state.phase, VoicePhase.ready);

      await cubit.close();
    });

    test('a one-word question still goes through', () async {
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      speech.hear('invoice');
      await Future<void>.delayed(Duration.zero);
      await cubit.release();

      expect(cubit.state.finished, 'invoice');

      await cubit.close();
    });

    test('askable is letters, in any script', () {
      expect(VoiceCubit.isAskable('uh'), isFalse);
      expect(VoiceCubit.isAskable('  ?! 12 '), isFalse);
      expect(VoiceCubit.isAskable('lease'), isTrue);
      expect(VoiceCubit.isAskable('बिल'), isTrue);
    });

    test('releasing twice cannot ask twice', () async {
      // The screen clears the signal with `handedOff`; this is the other
      // half — a second release with the microphone already closed must not
      // re-raise a question that has been dealt with.
      final speech = _Recogniser();
      final cubit = VoiceCubit(speech, _Answers());

      await cubit.toggleDictation();
      speech.hear('board call pricing');
      await Future<void>.delayed(Duration.zero);

      await cubit.release();
      cubit.handedOff();
      await cubit.release();

      expect(cubit.state.finished, isNull);

      await cubit.close();
    });
  });
}

/// The orb has to come back to rest.
///
/// `release` leaves the phase at `retrieving`, which is right for the moment
/// between letting go and the result screen appearing — and wrong from the
/// instant that screen takes the question. Nothing reset it, so the phase
/// stayed `retrieving` for the rest of the session and popping back to home
/// showed an orb squinting up and to the right under the words "Hold to ask".
///
/// It hid for a whole design generation because v2's orb expressed
/// "retrieving" as a slightly faster swirl. The eye expresses it as a squint,
/// a raised brow and a held gaze, which is how it finally got noticed.
void _restAfterHandoff() {
  test('handing the question off puts the orb back to rest', () {
    final cubit = VoiceCubit(_Recogniser(), _Answers());
    addTearDown(cubit.close);

    cubit.submitted();
    expect(cubit.state.phase, VoicePhase.retrieving);

    cubit.handedOff();
    expect(
      cubit.state.phase,
      VoicePhase.ready,
      reason: 'the result screen owns the search now; this one does not',
    );
    expect(cubit.state.finished, isNull);
    // `level` is a microphone reading and nothing is listening any more.
    expect(cubit.state.level, 0);
  });
}
