import 'package:audio_session/audio_session.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';

/// Playback of one local recording — screen 2H.
///
/// An interface over `just_audio` for one reason: the cubit's decisions
/// (what to do with a Drive link, how far a skip goes, where a seek lands)
/// are testable without a real audio engine, and `AudioPlayer` cannot be
/// constructed in a unit test at all.
abstract interface class AudioPlayback {
  /// Loads a file and returns its length, or null if the file has none the
  /// decoder can read.
  Future<Duration?> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get position;
  Stream<bool> get playing;
  Future<void> dispose();
}

@Injectable(as: AudioPlayback)
class JustAudioPlayback implements AudioPlayback {
  final _player = AudioPlayer();
  bool _sessionReady = false;

  @override
  Future<Duration?> open(String path) async {
    // Configured on first use, not at launch. The speech recogniser sets its
    // own record session while the orb is listening; claiming a playback
    // session app-wide at startup would fight it. `speech()` is the
    // podcast-style category: it plays with the ringer switch on silent,
    // which the default ambient session does not — a board call you tapped
    // play on should not be muted by a switch.
    if (!_sessionReady) {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _sessionReady = true;
    }
    return _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Future<void> dispose() => _player.dispose();
}
