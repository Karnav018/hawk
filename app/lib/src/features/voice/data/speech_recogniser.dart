import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/logging/app_logger.dart';

/// What a live dictation is doing.
enum SpeechStatus {
  /// The device cannot do it at all, or permission was refused.
  unavailable,
  idle,
  listening,

  /// Speech ended and the final transcript is in.
  done,
}

/// The microphone level, 0-1, whichever platform reported it.
///
/// The plugin does not normalise: Android forwards `SpeechRecognizer`'s
/// `onRmsChanged`, which is roughly -2..10 dB, while iOS reports 0..1
/// already. The old code divided by 10 unconditionally, and its own comment
/// named both ranges — so on iOS the level could never exceed 0.1 and
/// anything driven by it (the orb's squash, the waveform bars) would sit
/// almost still no matter how loudly anyone spoke.
///
/// Exposed and tested rather than inlined, because it is a platform
/// behaviour that cannot be checked by looking at the screen on one device:
/// getting it wrong on iOS looked exactly like getting it right on Android.
@visibleForTesting
double normaliseLevel(double level, {TargetPlatform? platform}) {
  final target = platform ?? defaultTargetPlatform;
  final scaled = switch (target) {
    // Already 0-1. The floor is silence, so nothing to offset.
    TargetPlatform.iOS || TargetPlatform.macOS => level,
    // -2..10. Negative values are quieter than the nominal floor, and clamp
    // to silence; dividing rather than mapping the full range keeps the
    // scale the Android build was tuned against.
    _ => level / 10,
  };
  return scaled.clamp(0.0, 1.0);
}

/// One update from the recogniser.
typedef SpeechUpdate = ({
  SpeechStatus status,
  String transcript,

  /// False while the engine is still revising what it heard. The UI shows
  /// partials so the orb feels live, but must not *submit* one — a question
  /// sent mid-utterance is a question nobody asked.
  bool isFinal,

  /// 0–1, for the waveform bars. The engine's own level, not our guess.
  double level,
});

/// On-device speech recognition — architecture §48.
///
/// On the device, not on a server, for three reasons that all point the same
/// way: it is free, it works without a round trip so the transcript appears
/// as you speak, and the audio never leaves the phone — which matters more
/// here than in most products, since the whole pitch is that the vault is
/// yours.
///
/// The trade is accuracy on proper nouns, which is exactly what a knowledge
/// vault is full of. That is a real limitation, and the typed field on screen
/// 2C is not a fallback for missing speech support — it is the repair path
/// for when dictation mishears a name.
abstract interface class SpeechRecogniser {
  /// True when this device can transcribe and has permission.
  ///
  /// Asks for the microphone permission as a side effect, so it is called
  /// when the user first reaches for dictation rather than at startup —
  /// a permission prompt on launch, before the product has explained itself,
  /// is the fastest way to be denied.
  Future<bool> prepare();

  Stream<SpeechUpdate> listen();

  /// A long, continuous dictation — screen 2F's voice note.
  ///
  /// [listen] is shaped for a question: it ends at a three-second pause or
  /// thirty seconds, which is right when the end of speech *is* the end of
  /// the request. A note is longer than either limit, and people stop to
  /// think in the middle of one. So this restarts the engine after every
  /// segment and stitches the segments together, and only ends when [stop]
  /// or [cancel] is called. Each update carries the whole transcript so far,
  /// never just the latest segment.
  Stream<SpeechUpdate> dictate();

  Future<void> stop();

  Future<void> cancel();
}

@LazySingleton(as: SpeechRecogniser)
class DeviceSpeechRecogniser implements SpeechRecogniser {
  DeviceSpeechRecogniser(this._logger);

  final AppLogger _logger;
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _ready = false;
  StreamController<SpeechUpdate>? _updates;

  /// The engine reports transcripts and sound levels on separate callbacks,
  /// so the most recent level is held here and attached to every update. The
  /// waveform would otherwise drop to zero on every partial result.
  double _level = 0;

  @override
  Future<bool> prepare() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (error) => _logger.warning(
          'Speech error',
          name: 'voice',
          data: {'error': error.errorMsg, 'permanent': error.permanent},
        ),
        // Deliberately no onStatus handler here: status is reported through
        // the stream below, and having two paths emit it meant the orb could
        // be told it had stopped while a partial was still arriving.
      );
    } catch (error) {
      _logger.warning('Speech unavailable', name: 'voice');
      _ready = false;
    }
    return _ready;
  }

  @override
  Stream<SpeechUpdate> listen() {
    final controller = StreamController<SpeechUpdate>(onCancel: cancel);
    _updates = controller;

    Future<void> start() async {
      if (!await prepare()) {
        controller.add((
          status: SpeechStatus.unavailable,
          transcript: '',
          isFinal: true,
          level: 0,
        ));
        await controller.close();
        return;
      }

      await _speech.listen(
        onResult: (result) {
          if (controller.isClosed) return;
          controller.add((
            status: result.finalResult
                ? SpeechStatus.done
                : SpeechStatus.listening,
            transcript: result.recognizedWords,
            isFinal: result.finalResult,
            level: _level,
          ));
        },
        onSoundLevelChange: (level) {
          if (controller.isClosed) return;
          _level = normaliseLevel(level);
          controller.add((
            status: SpeechStatus.listening,
            // Empty, not the last transcript: a level tick is not new speech,
            // and echoing the transcript would make the cubit think it was.
            transcript: '',
            isFinal: false,
            level: _level,
          ));
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // Generous: people pause mid-question, and cutting them off at the
          // first silence makes the product feel like it is not listening.
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
        ),
      );
    }

    start();
    return controller.stream;
  }

  @override
  Stream<SpeechUpdate> dictate() {
    final controller = StreamController<SpeechUpdate>(onCancel: cancel);
    _updates = controller;

    // Finished segments. The engine restarts its own transcript at every
    // session, so what it has already committed is kept here.
    var committed = '';

    String joined(String words) =>
        [committed, words].where((part) => part.trim().isNotEmpty).join(' ');

    Future<void> segment() async {
      if (controller.isClosed) return;
      try {
        await _speech.listen(
          onResult: (result) {
            if (controller.isClosed) return;
            final text = joined(result.recognizedWords);
            controller.add((
              status: SpeechStatus.listening,
              transcript: text,
              isFinal: false,
              level: _level,
            ));
            if (!result.finalResult) return;

            // The engine ended this session at a pause or its time cap. A
            // note outlives both, so the next segment starts straight away.
            // A short delay first: the plugin reports the final result a
            // moment before it has actually released the microphone, and a
            // listen() in that window is silently ignored.
            committed = text;
            Future<void>.delayed(const Duration(milliseconds: 250), segment);
          },
          onSoundLevelChange: (level) {
            if (controller.isClosed) return;
            _level = normaliseLevel(level);
            controller.add((
              status: SpeechStatus.listening,
              transcript: joined(''),
              isFinal: false,
              level: _level,
            ));
          },
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: stt.ListenMode.dictation,
            // Longer than a question's pause: thinking mid-note is normal,
            // and every cut is a seam in the transcript.
            pauseFor: const Duration(seconds: 8),
            listenFor: const Duration(minutes: 1),
          ),
        );
      } on Object catch (error) {
        // A restart that fails ends the note where it is. What was already
        // heard is still in `committed` and still gets saved.
        _logger.warning(
          'Dictation segment failed',
          name: 'voice',
          data: {'error': error.toString()},
        );
      }
    }

    () async {
      if (!await prepare()) {
        controller.add((
          status: SpeechStatus.unavailable,
          transcript: '',
          isFinal: true,
          level: 0,
        ));
        await controller.close();
        return;
      }
      await segment();
    }();

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    await _updates?.close();
    _updates = null;
  }

  @override
  Future<void> cancel() async {
    await _speech.cancel();
    await _updates?.close();
    _updates = null;
  }
}
