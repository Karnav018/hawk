import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/features/capture/presentation/bloc/speak_capture_cubit.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements MemoryRepository {}

class _Speech implements SpeechRecogniser {
  _Speech({this.ready = true});

  final bool ready;
  final _updates = StreamController<SpeechUpdate>.broadcast();
  int stops = 0;
  int cancels = 0;

  void hear(String words, {double level = 0.5}) => _updates.add((
    status: SpeechStatus.listening,
    transcript: words,
    isFinal: false,
    level: level,
  ));

  @override
  Future<bool> prepare() async => ready;
  @override
  Stream<SpeechUpdate> listen() => const Stream.empty();
  @override
  Stream<SpeechUpdate> dictate() => _updates.stream;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel() async => cancels++;
}

/// Screen 2F — a voice note, kept as a memory.
///
/// The Speak tile used to hand off to the orb, which *asks*: whatever was
/// said became a question, was answered, and was gone. These pin the other
/// direction — speaking into the capture grid keeps what was said.
void main() {
  setUpAll(() => registerFallbackValue(MemoryType.note));

  late _Repo repo;
  late _Speech speech;

  Memory saved() => Memory(
    id: 'n1',
    type: MemoryType.voiceNote,
    status: ProcessingStatus.uploaded,
    createdAt: DateTime(2026, 9, 23),
  );

  setUp(() {
    repo = _Repo();
    speech = _Speech();
    when(
      () => repo.capture(
        type: any(named: 'type'),
        title: any(named: 'title'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((_) async => saved());
  });

  test('saving keeps the words as a voice note, not a question', () async {
    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);

    await cubit.start();
    speech.hear('Note for the board pack. Entry holds at twelve');
    await pumpEventQueue();
    await cubit.save();

    verify(
      () => repo.capture(
        type: MemoryType.voiceNote,
        title: 'Note for the board pack',
        text: 'Note for the board pack. Entry holds at twelve',
      ),
    ).called(1);
    expect(cubit.state.phase, SpeakPhase.saved);
  });

  test('saving stops cleanly so the last words land', () async {
    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);
    await cubit.start();
    speech.hear('something');
    await pumpEventQueue();
    await cubit.save();
    // stop(), not cancel(): cancelling drops whatever the engine had not
    // committed yet, which is the end of the sentence.
    expect(speech.stops, greaterThanOrEqualTo(1));
  });

  test('a level tick never erases words already heard', () async {
    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);
    await cubit.start();
    speech.hear('keep these words');
    await pumpEventQueue();
    speech.hear('', level: 0.9);
    await pumpEventQueue();
    expect(cubit.state.transcript, 'keep these words');
    expect(cubit.state.level, 0.9);
  });

  test('nothing said, nothing saved', () async {
    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);
    await cubit.start();
    expect(cubit.state.canSave, isFalse);
    await cubit.save();
    verifyNever(
      () => repo.capture(
        type: any(named: 'type'),
        title: any(named: 'title'),
        text: any(named: 'text'),
      ),
    );
  });

  test('a failed save keeps the words', () async {
    when(
      () => repo.capture(
        type: any(named: 'type'),
        title: any(named: 'title'),
        text: any(named: 'text'),
      ),
    ).thenThrow(const AppException.network());

    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);
    await cubit.start();
    speech.hear('a minute and a half of talking');
    await pumpEventQueue();
    await cubit.save();

    // Back to stopped with the transcript intact, so Save can be pressed
    // again. Losing the note on a network blip would be unforgivable.
    expect(cubit.state.phase, SpeakPhase.stopped);
    expect(cubit.state.transcript, 'a minute and a half of talking');
    expect(cubit.state.canSave, isTrue);
  });

  test('no recogniser is a state the screen explains, not a crash', () async {
    final cubit = SpeakCaptureCubit(_Speech(ready: false), repo);
    addTearDown(cubit.close);
    await cubit.start();
    expect(cubit.state.phase, SpeakPhase.unavailable);
  });

  test('discarding cancels and clears', () async {
    final cubit = SpeakCaptureCubit(speech, repo);
    addTearDown(cubit.close);
    await cubit.start();
    speech.hear('never mind');
    await pumpEventQueue();
    await cubit.discard();
    expect(speech.cancels, greaterThanOrEqualTo(1));
    expect(cubit.state.transcript, isEmpty);
  });

  group('titles', () {
    test('the first sentence, when it is short', () {
      expect(
        SpeakCaptureCubit.titleFor('Call Mercer back. About the lease.'),
        'Call Mercer back',
      );
    });

    test('cut at a word, never mid-word', () {
      final t = SpeakCaptureCubit.titleFor(
        'the enterprise floor needs revisiting after the renewal lands in october',
      );
      expect(t.endsWith('…'), isTrue);
      expect(t.length, lessThanOrEqualTo(49));
      expect(t, isNot(contains('renew…')));
    });
  });
}
