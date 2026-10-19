import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../../voice/data/speech_recogniser.dart';
import 'capture_cubit.dart';

part 'speak_capture_cubit.freezed.dart';

enum SpeakPhase {
  /// Asking for the microphone.
  preparing,
  recording,

  /// Held mid-note. The words so far are kept, and resuming adds to them.
  paused,

  /// Stopped, transcript in hand, nothing decided yet.
  stopped,
  saving,
  saved,

  /// No recogniser on this device, or permission refused.
  unavailable,
}

@freezed
abstract class SpeakCaptureState with _$SpeakCaptureState {
  const factory SpeakCaptureState({
    @Default(SpeakPhase.preparing) SpeakPhase phase,
    @Default('') String transcript,
    @Default(0.0) double level,
    @Default(0) int elapsedSeconds,
    Memory? saved,
    AppException? exception,
  }) = _SpeakCaptureState;

  const SpeakCaptureState._();

  /// A note with no words in it is not a memory.
  bool get canSave =>
      transcript.trim().isNotEmpty &&
      (phase == SpeakPhase.recording ||
          phase == SpeakPhase.paused ||
          phase == SpeakPhase.stopped);

  String get clock {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Screen 2F — SPEAK, RECORDING. A voice note, kept as a memory.
///
/// **Not the orb.** The Speak tile used to hand off to the orb, on the stated
/// grounds that "dictation has always lived there". But the orb *asks*: what
/// you say becomes a question and is answered. 2F *keeps*: what you say
/// becomes a memory that later questions can find. Same microphone, opposite
/// direction of travel, and routing one to the other meant a thought spoken
/// into the capture grid was answered and then lost.
///
/// Transcribed on the device, as the screen promises, by the same recogniser
/// the orb uses — in its continuous mode, since a note outlives a question's
/// thirty seconds. What is kept is the transcript; the recogniser gives no
/// audio file, and inventing an "original" to open would be the screen
/// claiming something it does not hold.
@injectable
class SpeakCaptureCubit extends Cubit<SpeakCaptureState>
    with SafeEmit<SpeakCaptureState> {
  SpeakCaptureCubit(this._speech, this._memories)
    : super(const SpeakCaptureState());

  final SpeechRecogniser _speech;
  final MemoryRepository _memories;

  StreamSubscription<SpeechUpdate>? _dictation;
  Timer? _tick;

  /// What was said before the last pause. The recogniser starts a fresh
  /// transcript each time it listens, so the note is this plus whatever the
  /// current session has heard.
  String _before = '';

  Future<void> start() async {
    if (state.phase == SpeakPhase.recording) return;
    if (!await _speech.prepare()) {
      emit(state.copyWith(phase: SpeakPhase.unavailable));
      return;
    }
    _listen();
  }

  /// Hold the note. The microphone closes — a paused recorder that kept
  /// listening would be the phone lying about what it is doing.
  Future<void> pause() async {
    if (state.phase != SpeakPhase.recording) return;
    await _halt(keep: true);
    emit(state.copyWith(phase: SpeakPhase.paused, level: 0));
  }

  /// Carry on from a pause, adding to the same note.
  ///
  /// Stitched with a space. The seam is real — the recogniser heard two
  /// sessions — but a note is read for what it says, and a pause to think
  /// is not a new thought.
  Future<void> resume() async {
    if (state.phase != SpeakPhase.paused) return;
    _before = state.transcript.trim();
    _listen();
  }

  void _listen() {
    emit(state.copyWith(phase: SpeakPhase.recording, exception: null));
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => emit(state.copyWith(elapsedSeconds: state.elapsedSeconds + 1)),
    );
    _dictation = _speech.dictate().listen((update) {
      if (update.status == SpeechStatus.unavailable) {
        _halt();
        emit(state.copyWith(phase: SpeakPhase.unavailable, level: 0));
        return;
      }
      emit(
        state.copyWith(
          // A level tick carries the transcript so far unchanged, so taking
          // it every time cannot erase words already heard.
          transcript: update.transcript.isEmpty
              ? state.transcript
              : [
                  _before,
                  update.transcript,
                ].where((part) => part.isNotEmpty).join(' '),
          level: update.level,
        ),
      );
    });
  }

  /// The square button. Stops listening; the note waits for Save or Discard.
  Future<void> stop() async {
    if (state.phase != SpeakPhase.recording) return;
    await _halt(keep: true);
    emit(state.copyWith(phase: SpeakPhase.stopped, level: 0));
  }

  Future<void> save() async {
    if (!state.canSave) return;
    if (state.phase == SpeakPhase.recording) await _halt(keep: true);

    final text = state.transcript.trim();
    emit(state.copyWith(phase: SpeakPhase.saving, level: 0));
    try {
      final memory = await _memories.capture(
        type: CaptureKind.speak.memoryType,
        title: titleFor(text),
        text: text,
      );
      emit(state.copyWith(phase: SpeakPhase.saved, saved: memory));
    } catch (error, stackTrace) {
      // Back to stopped, words intact. A failed save must never throw away
      // a minute and a half of somebody talking.
      emit(
        state.copyWith(
          phase: SpeakPhase.stopped,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  Future<void> discard() async {
    await _halt();
    _before = '';
    emit(const SpeakCaptureState(phase: SpeakPhase.stopped));
  }

  void dismissError() => emit(state.copyWith(exception: null));

  /// Stop the timer and the microphone. [keep] stops cleanly so the final
  /// words land; without it the engine is cancelled and they are dropped.
  Future<void> _halt({bool keep = false}) async {
    _tick?.cancel();
    _tick = null;
    await _dictation?.cancel();
    _dictation = null;
    keep ? await _speech.stop() : await _speech.cancel();
  }

  /// "Note for the board pack" — the first few words, cut at a word.
  ///
  /// Library rows show a title, and "Voice note, 23 Sep" repeated forty
  /// times is a list nobody can scan. The opening words are usually what
  /// the note is about, because that is how people start talking.
  static String titleFor(String text) {
    final firstSentence = text.split(RegExp(r'[.!?\n]')).first.trim();
    const max = 48;
    if (firstSentence.length <= max) return firstSentence;
    final cut = firstSentence.substring(0, max);
    final space = cut.lastIndexOf(' ');
    return '${space > 20 ? cut.substring(0, space) : cut}…';
  }

  @override
  Future<void> close() async {
    await _halt();
    return super.close();
  }
}
