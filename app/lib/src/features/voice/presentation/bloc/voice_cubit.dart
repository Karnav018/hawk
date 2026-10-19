import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../chat/domain/entities/answer.dart';
import '../../../chat/domain/entities/seeded_question.dart';
import '../../../chat/domain/repositories/answer_repository.dart';
import '../../data/speech_recogniser.dart';

part 'voice_cubit.freezed.dart';

/// The orb's four states, straight from the design's own state table.
///
/// Not a boolean "listening": each state drives a different swirl speed, glow,
/// breathe period and ring timing, and the whole point of the home screen is
/// that you can tell what it is doing from across a room.
enum VoicePhase {
  /// Idle. Slow swirl, low glow, long breathe.
  ready,

  /// Capturing speech. Fast, bright, waveform bars visible.
  listening,

  /// Searching. Fastest — the one phase where speed reads as effort.
  retrieving,

  /// Done, settling. Matches on screen.
  answered;

  bool get showsBars => this == listening;
  bool get showsMatches => this != ready;

  /// Seconds per full swirl rotation.
  double get swirlSeconds => switch (this) {
    ready => 38,
    listening => 9,
    retrieving => 4,
    answered => 24,
  };

  double get breatheSeconds => switch (this) {
    ready => 9,
    listening => 2.6,
    retrieving => 1.5,
    answered => 6.4,
  };

  /// Seconds per revolution of the counter-rotating glow.
  ///
  /// The design runs two swirls at once and in opposite directions —
  /// `@keyframes swirl` clockwise, `@keyframes swirl2` at
  /// `rotate(-360deg)` — on deliberately unrelated periods. That is what
  /// stops the orb reading as one rigid object spinning: two layers turning
  /// against each other at 38s and 54s never line up, so the surface keeps
  /// producing new overlaps instead of repeating.
  double get glowSpinSeconds => switch (this) {
    ready => 54,
    listening => 13,
    retrieving => 7,
    answered => 34,
  };

  /// Seconds per emitted ring.
  ///
  /// `@keyframes pulseRing`: opacity .55 to 0 while scaling .94 to 1.22,
  /// held at zero for the last 30% so there is a gap between rings rather
  /// than a continuous halo. Its speed is the clearest phase readout on the
  /// screen — one ring every 5s at rest, one every 1.1s while retrieving.
  double get ringSeconds => switch (this) {
    ready => 5,
    listening => 1.7,
    retrieving => 1.1,
    answered => 4,
  };

  double get glow => switch (this) {
    ready => 0.34,
    listening => 0.72,
    retrieving => 0.6,
    answered => 0.5,
  };

  String get label => name.toUpperCase();

  String get hint => switch (this) {
    ready => 'Tap the orb, or hold to speak',
    listening => 'Listening — release when you are done',
    retrieving => 'Searching your vault',
    answered => 'Tap a match to open it',
  };
}

@freezed
abstract class VoiceState with _$VoiceState {
  const factory VoiceState({
    @Default(VoicePhase.ready) VoicePhase phase,

    /// What has been heard so far. Empty in [VoicePhase.ready].
    @Default('') String transcript,

    /// Seconds elapsed in the current utterance, for the "00:07" readout.
    @Default(0) int elapsedSeconds,

    /// 0–1 from the microphone, driving the waveform bars.
    @Default(0) double level,

    /// Set when the device cannot transcribe, or the microphone was refused.
    /// The typed path still works, so this is a note rather than an error.
    String? speechNote,

    /// Files found for the current question. The design's match rows.
    @Default(<Match>[]) List<Match> matches,

    /// How the question was read — §24's filters, so a narrowed search that
    /// finds nothing can say which filter narrowed it.
    @Default(QuerySignals()) QuerySignals signals,
    @Default(false) bool isSearching,

    /// The question the visible matches belong to, so a stale result from a
    /// slower earlier search cannot overwrite a newer one.
    @Default('') String searchedFor,
    AppException? searchError,

    /// A finished utterance, waiting to be handed to the answer screen.
    ///
    /// A one-shot signal rather than a flag: the screen navigates when this
    /// appears and calls [VoiceCubit.handedOff] to clear it, so a rebuild —
    /// a theme change, a keyboard opening — cannot push screen 3B a second
    /// time for a question already asked.
    String? finished,
  }) = _VoiceState;

  const VoiceState._();

  String get timer {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Blank in ready: a timer reading 00:00 next to an idle orb suggests
  /// something is being recorded when nothing is.
  String get timerText => phase == VoicePhase.ready ? '' : timer;

  bool get canAsk => transcript.trim().isNotEmpty;

  bool get hasMatches => matches.isNotEmpty;

  /// True once a search has run for the current text and found nothing.
  bool get foundNothing =>
      !isSearching &&
      matches.isEmpty &&
      searchedFor.isNotEmpty &&
      searchedFor == transcript.trim();
}

/// Screen 2C — HOME, voice-first.
///
/// Owns the state machine the orb animates from, and the two ways in.
///
/// Dictation is on-device, so the transcript arrives as partials while the
/// user is still speaking — which is what makes the orb feel like it is
/// listening rather than processing. Partials are shown but never submitted:
/// a question sent mid-utterance is a question nobody asked.
@injectable
class VoiceCubit extends Cubit<VoiceState> with SafeEmit<VoiceState> {
  VoiceCubit(this._speech, this._answers) : super(const VoiceState());

  final SpeechRecogniser _speech;
  final AnswerRepository _answers;
  StreamSubscription<SpeechUpdate>? _dictation;
  Timer? _tick;
  Timer? _debounce;

  /// The query the screen currently cares about.
  ///
  /// Set both by [find] when a search starts *and* by [transcriptChanged] as
  /// the user types — which is the subtle half. Typing invalidates an
  /// in-flight search straight away rather than when the debounce eventually
  /// fires, so a slow answer to a phrase the user has already moved past
  /// cannot land on the screen 700ms later.
  ///
  /// This, not the transcript, is the comparison. Comparing against the
  /// transcript looked equivalent and was not: a search for text that is not
  /// the transcript — a retry, a suggestion, a finished utterance the field
  /// has not caught up with — would find its own result "stale" the instant
  /// it arrived and throw it away.
  String _latest = '';

  /// The words heard by the session now running, and by the one before it.
  ///
  /// Kept to catch one specific leftover. The speech plugin has a single
  /// result callback and swaps it on every listen, so a final result the
  /// platform delivers late, after the user has already started the next
  /// question, arrives through the *new* session. The screen took it as a
  /// finished question and opened the result screen for what the user had
  /// said before. See [isLeftover].
  String _heard = '';
  String _heardBefore = '';

  /// Whether this session has heard anything of its own yet. Once it has,
  /// nothing is filtered.
  bool _heardThisSession = false;

  /// Running while a leftover from the previous session can still arrive.
  Timer? _fresh;

  /// How long after the last keystroke a search fires.
  ///
  /// Long enough that typing a sentence is one search rather than thirty.
  /// Dictation does not wait for this — a final transcript is a finished
  /// thought, so it searches immediately.
  static const _settle = Duration(milliseconds: 700);

  /// Find files for the current text.
  ///
  /// Search does not spend a question from the daily allowance — only `ask`
  /// does — which is what makes searching-as-you-think affordable at all.
  Future<void> find({String? text}) async {
    final query = (text ?? state.transcript).trim();
    _debounce?.cancel();

    if (query.length < 3) {
      // Two characters match half the vault; the result would be noise
      // dressed up as an answer.
      _latest = '';
      emit(
        state.copyWith(matches: const [], searchedFor: '', isSearching: false),
      );
      return;
    }
    if (query == state.searchedFor && state.matches.isNotEmpty) return;

    _latest = query;
    emit(state.copyWith(isSearching: true, searchError: null));
    try {
      final result = await _answers.search(query);
      // Dropped if a newer search has started. Without this a slow answer
      // for an earlier phrase lands on top of a newer, correct result —
      // results for a question the user is no longer asking.
      if (isClosed || query != _latest) return;
      emit(
        state.copyWith(
          matches: result.matches,
          signals: result.signals,
          searchedFor: query,
          isSearching: false,
          // Zeroed only when this search *ends* a dictation. A prefetch
          // lands while the microphone is still open, and the level is its
          // reading — zeroing it mid-sentence would squash the eye for a
          // frame every time a search returned.
          level: state.phase == VoicePhase.retrieving ? 0 : state.level,
          // A dictated search ends in `answered`, not `retrieving`: the orb
          // spins fastest while searching, and leaving it there after the
          // results have landed would say the work is still going on. Typing
          // keeps `listening`, because the user is still composing.
          phase: state.phase == VoicePhase.retrieving
              ? VoicePhase.answered
              : state.phase,
        ),
      );
    } catch (error, stackTrace) {
      if (isClosed || query != _latest) return;
      emit(
        state.copyWith(
          isSearching: false,
          searchError: ErrorMapper.map(error, stackTrace),
          phase: state.phase == VoicePhase.retrieving
              ? VoicePhase.answered
              : state.phase,
        ),
      );
    }
  }

  /// Searches for what has been heard so far, once it settles.
  ///
  /// The face never shows these results; they are for the moment of
  /// release. The result screen used to start from nothing — search and
  /// ask, both from scratch — although the words had been on screen for
  /// seconds. Now the files for the sentence-so-far are usually already in
  /// [VoiceState.matches] by the time the finger lifts, and [seedFor] hands
  /// them over, so the rows appear the instant the screen does.
  ///
  /// Search is unmetered (`usage.counts_as_ask` charges answers), so an
  /// utterance that is never released costs nothing but the call.
  void _prefetch(String heard) {
    final text = heard.trim();
    if (text.length < 3 || text == _latest) return;
    _debounce?.cancel();
    _debounce = Timer(_settle, () => unawaited(find(text: text)));
  }

  /// The files already found for [question], if the prefetch got there —
  /// or null, and the result screen searches for itself.
  ///
  /// Only an exact match for the released words counts: files for "what did
  /// we agree" are not the files for "what did we agree on the lease", and
  /// a search still in flight is not an answer yet.
  SeededQuestion? seedFor(String question) {
    final released = question.trim();
    if (released.isEmpty ||
        state.isSearching ||
        state.searchedFor != released ||
        state.matches.isEmpty) {
      return null;
    }
    return SeededQuestion(
      question: released,
      matches: state.matches,
      signals: state.signals,
    );
  }

  void transcriptChanged(String value) {
    // Invalidate anything in flight before emitting: whatever is being
    // searched for is no longer what is on screen.
    _latest = value.trim().length < 3 ? '' : value.trim();

    emit(
      state.copyWith(
        transcript: value,
        // Typing is a form of asking, so the orb should look engaged rather
        // than idle while it happens.
        phase: value.trim().isEmpty ? VoicePhase.ready : VoicePhase.listening,
        // Zero, and this is the one that mattered. Typing puts the orb into
        // `listening` — the one phase whose squash reads the level — while
        // no microphone is running, so a level left over from an earlier
        // utterance would squash the orb and then stay squashed, because no
        // further level tick is ever coming to correct it.
        level: 0,
      ),
    );

    _debounce?.cancel();
    if (value.trim().length < 3) {
      emit(state.copyWith(matches: const [], searchedFor: ''));
      return;
    }
    _debounce = Timer(_settle, find);
  }

  /// Called when the question has been handed to the answer screen.
  ///
  /// Zeroes the level with it. `level` is a *microphone* reading, and the
  /// only thing entitled to set it is the dictation stream — so every
  /// transition that is not a dictation update has to clear it, or the last
  /// value heard sits in the state with nothing left to correct it.
  void submitted() =>
      emit(state.copyWith(phase: VoicePhase.retrieving, level: 0));

  /// Clears the hand-off signal once the answer screen has the question —
  /// **and puts the orb back to rest.**
  ///
  /// [release] leaves the phase at [VoicePhase.retrieving], which is right
  /// for the moment between letting go and the result screen appearing. It
  /// stopped being right the instant that screen took the question: from
  /// there the search is the result screen's business, and this one has
  /// nothing left to search for. Without the reset the phase stayed
  /// `retrieving` for the rest of the session, so popping back to home showed
  /// an orb squinting up and to the right under the words "Hold to ask".
  ///
  /// It survived because v2's orb said "retrieving" by swirling slightly
  /// faster, which is invisible next to its resting swirl. The eye says it
  /// with a squint, a raised brow and a held gaze — the same wrong state,
  /// finally legible.
  void handedOff() =>
      emit(state.copyWith(finished: null, phase: VoicePhase.ready, level: 0));

  /// Start dictating. Idempotent — a second tap while listening stops.
  Future<void> toggleDictation() async {
    if (state.phase == VoicePhase.listening && _dictation != null) {
      await stopDictation();
      return;
    }

    // A session the recogniser ended itself, at a pause or its time cap, was
    // never cancelled. Let go of it before the next one starts.
    await _dictation?.cancel();
    _dictation = null;
    _debounce?.cancel();

    _latest = '';
    _heardBefore = _heard;
    _heard = '';
    _heardThisSession = false;
    _fresh?.cancel();
    _fresh = Timer(leftoverWindow, () => _fresh = null);

    emit(
      state.copyWith(
        speechNote: null,
        transcript: '',
        elapsedSeconds: 0,
        // A new question starts with no files. Results left from the last
        // one could otherwise seed its result screen (see [seedFor]).
        matches: const [],
        signals: const QuerySignals(),
        searchedFor: '',
        isSearching: false,
        searchError: null,
      ),
    );

    final ready = await _speech.prepare();
    if (!ready) {
      emit(
        state.copyWith(
          phase: VoicePhase.ready,
          speechNote: 'Dictation is unavailable — type instead.',
        ),
      );
      return;
    }

    emit(state.copyWith(phase: VoicePhase.listening));
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => emit(state.copyWith(elapsedSeconds: state.elapsedSeconds + 1)),
    );

    _dictation = _speech.listen().listen(
      (update) {
        if (isClosed) return;

        final words = update.transcript.trim();
        if (words.isNotEmpty && !_heardThisSession) {
          if (_fresh != null && isLeftover(words, _heardBefore)) return;
          _heardThisSession = true;
        }
        if (words.isNotEmpty) _heard = words;

        switch (update.status) {
          case SpeechStatus.unavailable:
            emit(
              state.copyWith(
                phase: VoicePhase.ready,
                speechNote: 'Dictation is unavailable — type instead.',
              ),
            );
          case SpeechStatus.listening:
            emit(
              state.copyWith(
                phase: VoicePhase.listening,
                level: update.level,
                // A level tick carries no words; keeping the existing
                // transcript stops the field flickering empty between them.
                transcript: update.transcript.isEmpty
                    ? state.transcript
                    : update.transcript,
              ),
            );
            if (update.transcript.isNotEmpty) _prefetch(update.transcript);
          case SpeechStatus.done:
            _stopTimer();
            // The sentence is finished; a prefetch still waiting to fire
            // would search for a version of it the user has moved past.
            _debounce?.cancel();
            final spoken = update.transcript.isEmpty
                ? state.transcript
                : update.transcript;
            // A finished utterance goes to the answer screen rather than
            // searching in place.
            //
            // The design's own copy for the listening state is "RELEASE TO
            // ASK", and screen 3B is where an asked question is answered —
            // so stopping here to fill a list at the bottom of home would
            // leave the user looking at the preview of a question they had
            // already finished asking. 3B runs its own retrieval, so
            // nothing is searched twice.
            emit(
              state.copyWith(
                phase: VoicePhase.retrieving,
                level: 0,
                transcript: spoken,
                finished: spoken.trim().isEmpty ? null : spoken.trim(),
              ),
            );
            // The recogniser ended this session itself. Let go of it, so a
            // finger lifting after a hold cannot hand the same words off a
            // second time through [release].
            final ended = _dictation;
            _dictation = null;
            unawaited(ended?.cancel());
          case SpeechStatus.idle:
            break;
        }
      },
      onError: (Object _) {
        if (isClosed) return;
        _stopTimer();
        emit(
          state.copyWith(
            phase: VoicePhase.ready,
            level: 0,
            speechNote: 'Dictation stopped. Type instead.',
          ),
        );
      },
    );
  }

  /// Stop the microphone. Safe to call when it is not running.
  ///
  /// The early return is not just an optimisation. Screen 2C now calls this
  /// before every typed submit — it has to, or dictation left running would
  /// later hand off a phrase the user abandoned — and most typed submits
  /// happen with no microphone at all. Without the guard each one would make
  /// a pointless platform call and emit `ready`, which would undo the
  /// `listening` phase that *typing* had set moments earlier. Typing is not
  /// dictation, and stopping dictation must not reach into it.
  Future<void> stopDictation() async {
    if (_dictation == null) return;

    _stopTimer();
    await _dictation?.cancel();
    _dictation = null;
    await _speech.stop();
    if (!isClosed) {
      emit(state.copyWith(phase: VoicePhase.ready, level: 0));
    }
  }

  /// The eye went off screen while the microphone was open — another tab, a
  /// screen pushed over home, the app sent to the background, the face
  /// switched to typing. Stop listening and forget what was heard.
  ///
  /// Not [stopDictation], which keeps the words, and not [release], which
  /// asks them: nobody asked this, and a phrase handed off later from a
  /// screen the user had already left would be a question they abandoned.
  /// Safe to call when nothing is listening.
  Future<void> abandonDictation() async {
    if (_dictation == null) return;

    _stopTimer();
    _debounce?.cancel();
    await _dictation?.cancel();
    _dictation = null;
    await _speech.stop();
    if (!isClosed) {
      emit(
        state.copyWith(
          phase: VoicePhase.ready,
          level: 0,
          transcript: '',
          elapsedSeconds: 0,
          finished: null,
        ),
      );
    }
  }

  /// Release the orb: stop the microphone and ask what was heard.
  ///
  /// **New in v3, and the design demanded it.** The home screen's copy is
  /// "Hold to ask" and the listening screen's is "Release to search", so
  /// letting go *is* the submit. [stopDictation] cannot express that: it
  /// cancels the recogniser's subscription, which means the platform's own
  /// `done` event — the thing that used to produce [VoiceState.finished] —
  /// never arrives. A held-and-released question would have been thrown away
  /// and the orb returned to rest, which is precisely what the copy promises
  /// will not happen.
  ///
  /// So the release path emits the hand-off itself, from the transcript it
  /// already holds. Nothing else changes: the screen still clears the signal
  /// with [handedOff], so one release can only ever produce one result.
  ///
  /// A release that caught no words is not an error and not a question. It
  /// goes back to `ready` in silence rather than pushing an empty search —
  /// pressing the orb and thinking better of it should cost nobody a screen.
  Future<void> release() async {
    // Nothing to release. Guards the re-entrant case the gesture can produce
    // — a second `onLongPressEnd`, or the footer button pressed as the modal
    // is already closing — which would otherwise re-raise a question the
    // screen has already handed off and answered, from a transcript that is
    // still sitting in state.
    if (_dictation == null) return;

    final spoken = state.transcript.trim();

    _stopTimer();
    _debounce?.cancel();
    await _dictation?.cancel();
    _dictation = null;
    await _speech.stop();

    emit(
      isAskable(spoken)
          ? state.copyWith(
              phase: VoicePhase.retrieving,
              level: 0,
              finished: spoken,
            )
          // A stray tap on the eye — nothing said, or a scrap like "uh" —
          // goes back to rest instead of becoming a question. It used to be
          // sent whatever it was, and each one was a round trip to the
          // server for a question nobody asked.
          : state.copyWith(phase: VoicePhase.ready, level: 0),
    );
  }

  /// Whether a transcript is a question at all: at least three letters.
  ///
  /// Short enough that a one-word ask — "invoice", "lease" — goes through;
  /// long enough that "uh", "hm" and silence do not. The server adds the
  /// other half: a question is charged only if it found something in the
  /// user's files (`usage.counts_as_ask`).
  static bool isAskable(String spoken) =>
      RegExp(r'[\p{L}\p{M}]', unicode: true).allMatches(spoken).length >= 3;

  void _stopTimer() {
    _tick?.cancel();
    _tick = null;
  }

  void clear() {
    _debounce?.cancel();
    emit(const VoiceState());
  }

  void reset() => emit(const VoiceState());

  @override
  Future<void> close() {
    _stopTimer();
    _fresh?.cancel();
    _debounce?.cancel();
    _dictation?.cancel();
    _speech.cancel();
    return super.close();
  }
}

/// How long after a new question starts a late result from the previous one
/// can still turn up.
const leftoverWindow = Duration(milliseconds: 1500);

/// Whether [words], the first thing a new listening session hears, are the
/// previous session's [before] arriving late.
///
/// A leftover repeats the previous words, or is a refined version that
/// extends them ("what did we agree" → "What did we agree on pricing?"). The
/// comparison ignores case and punctuation for that reason. A genuine first
/// result can only look like this within [leftoverWindow] if the user starts
/// a new question with the same opening words. Then only its first partials
/// are dropped: the rest get through once the words differ from the last
/// question's or the window has passed.
bool isLeftover(String words, String before) {
  final now = _plainWords(words);
  final then = _plainWords(before);
  if (now.isEmpty || then.isEmpty) return false;
  return now == then || now.startsWith(then) || then.startsWith(now);
}

String _plainWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');
