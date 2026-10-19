import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/files/original_access.dart';
import '../../data/audio/audio_playback.dart';
import '../../domain/entities/memory.dart';
import '../widgets/memory_row.dart';

part 'audio_player_cubit.freezed.dart';

enum AudioSourceState {
  /// Finding the original — on this phone, or fetching it from the vault.
  resolving,
  ready,

  /// Nothing to play *here*: a transcript-only voice note, a Drive link
  /// that needs its own app, or a file this phone cannot reach right now.
  unavailable,
}

@freezed
abstract class AudioPlayerState with _$AudioPlayerState {
  const factory AudioPlayerState({
    @Default(AudioSourceState.resolving) AudioSourceState source,
    @Default(Duration.zero) Duration position,
    Duration? duration,
    @Default(false) bool playing,

    /// Why there is nothing to play, when [source] is unavailable.
    String? reason,
  }) = _AudioPlayerState;

  const AudioPlayerState._();

  double get fraction {
    final d = duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Screen 2H — AUDIO PLAYER.
///
/// Plays the *original* recording, from the same resolution the "Open"
/// button uses: on this phone first, then the vault. What it never does is
/// stream a Drive link — Drive needs the user's own session, and a player
/// that silently failed on every Drive recording would be worse than one
/// that says "open it in Drive".
@injectable
class AudioPlayerCubit extends Cubit<AudioPlayerState>
    with SafeEmit<AudioPlayerState> {
  AudioPlayerCubit(this._playback, this._originals, @factoryParam this._memory)
    : super(const AudioPlayerState()) {
    unawaited(_resolve());
  }

  final AudioPlayback _playback;
  final OriginalAccess _originals;
  final Memory _memory;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The design's two skip buttons. Fifteen seconds is long enough to jump a
  /// sentence and short enough to find your place again.
  static const skip = Duration(seconds: 15);

  Future<void> _resolve() async {
    final ref = MemoryRow.originalOf(_memory);
    try {
      var handle = await _originals.resolve(
        memoryId: ref.memoryId,
        url: ref.url,
        storagePath: ref.storagePath,
        filename: ref.title,
      );
      if (handle is OriginalInVault) {
        handle = await _originals.materialise(handle, ref.memoryId);
      }

      switch (handle) {
        case OriginalOnDevice(:final file):
          final length = await _playback.open(file.path);
          _subscriptions
            ..add(
              _playback.position.listen(
                (p) => emit(state.copyWith(position: p)),
              ),
            )
            ..add(
              _playback.playing.listen(
                (on) => emit(state.copyWith(playing: on)),
              ),
            );
          emit(
            state.copyWith(source: AudioSourceState.ready, duration: length),
          );
        case OriginalAtUrl():
          _unavailable(
            'This recording lives in Drive. Open it there to play it.',
          );
        case OriginalInVault():
        case OriginalUnavailable():
          _unavailable(
            ref.storagePath == null && ref.url == null
                // A dictated note from 2F: it was only ever kept as words.
                ? 'Kept as a transcript only. There is no recording to play.'
                : 'The recording is not on this phone right now.',
          );
      }
    } on Object {
      _unavailable('This recording could not be opened.');
    }
  }

  void _unavailable(String reason) => emit(
    state.copyWith(source: AudioSourceState.unavailable, reason: reason),
  );

  Future<void> toggle() async {
    if (state.source != AudioSourceState.ready) return;
    if (state.playing) {
      await _playback.pause();
      return;
    }
    // At the end, play means from the start — not a silent no-op on a
    // finished track, which is what a bare play() does.
    final d = state.duration;
    if (d != null && state.position >= d) await _playback.seek(Duration.zero);
    await _playback.play();
  }

  Future<void> back() => seekTo(state.position - skip);

  Future<void> forward() => seekTo(state.position + skip);

  /// Clamped to the recording, so a skip near either end lands on it rather
  /// than asking the decoder for a moment that does not exist.
  Future<void> seekTo(Duration target) async {
    if (state.source != AudioSourceState.ready) return;
    final end = state.duration ?? target;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > end ? end : target);
    emit(state.copyWith(position: clamped));
    await _playback.seek(clamped);
  }

  /// A tap on the scrubber, as a fraction of its width.
  Future<void> seekFraction(double fraction) async {
    final d = state.duration;
    if (d == null) return;
    await seekTo(d * fraction.clamp(0.0, 1.0));
  }

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _playback.dispose();
    return super.close();
  }
}
