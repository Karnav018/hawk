import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/files/original_access.dart';
import 'package:knowra/src/features/memory/data/audio/audio_playback.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/bloc/audio_player_cubit.dart';
import 'package:knowra/src/features/memory/presentation/pages/file_viewer_page.dart';
import 'package:mocktail/mocktail.dart';

class _Originals extends Mock implements OriginalAccess {}

class _Playback implements AudioPlayback {
  final positions = StreamController<Duration>.broadcast();
  final playings = StreamController<bool>.broadcast();
  final seeks = <Duration>[];
  String? opened;
  int plays = 0;
  int pauses = 0;
  bool disposed = false;

  @override
  Future<Duration?> open(String path) async {
    opened = path;
    return const Duration(minutes: 41, seconds: 7);
  }

  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<bool> get playing => playings.stream;
  @override
  Future<void> dispose() async => disposed = true;
}

/// Screen 2H — the original recording above its transcript.
///
/// The player's real decisions are about *where the audio is*: on this
/// phone it plays; behind a Drive link it must say so rather than fail
/// silently; a dictated note from 2F never had a recording at all.
void main() {
  late _Originals originals;
  late _Playback playback;

  Memory rec({String? storagePath, String? url}) => Memory(
    id: 'r1',
    type: MemoryType.audio,
    status: ProcessingStatus.ready,
    createdAt: DateTime(2026, 8, 14),
    title: 'board-call-14-aug.m4a',
    storagePath: storagePath,
    source: url == null
        ? null
        : Source(id: 's', provider: StorageProvider.googleDrive, url: url),
  );

  void resolvesTo(OriginalHandle handle) => when(
    () => originals.resolve(
      memoryId: any(named: 'memoryId'),
      url: any(named: 'url'),
      storagePath: any(named: 'storagePath'),
      filename: any(named: 'filename'),
    ),
  ).thenAnswer((_) async => handle);

  setUp(() {
    originals = _Originals();
    playback = _Playback();
  });

  Future<AudioPlayerCubit> build(Memory m) async {
    final c = AudioPlayerCubit(playback, originals, m);
    addTearDown(c.close);
    await pumpEventQueue();
    return c;
  }

  group('where the audio is', () {
    test('on this phone, it plays', () async {
      resolvesTo(OriginalOnDevice(File('/kept/board.m4a')));
      final c = await build(rec(storagePath: 'users/u/originals/board.m4a'));
      expect(c.state.source, AudioSourceState.ready);
      expect(playback.opened, '/kept/board.m4a');
      expect(c.state.duration, const Duration(minutes: 41, seconds: 7));
    });

    test(
      'behind a Drive link, it says to open Drive — never streams it',
      () async {
        resolvesTo(
          OriginalAtUrl(Uri.parse('https://drive.google.com/file/d/x')),
        );
        final c = await build(rec(url: 'https://drive.google.com/file/d/x'));
        expect(c.state.source, AudioSourceState.unavailable);
        expect(c.state.reason, contains('Drive'));
        expect(playback.opened, isNull);
      },
    );

    test('a dictated note was only ever words', () async {
      resolvesTo(const OriginalUnavailable());
      final c = await build(rec());
      expect(c.state.source, AudioSourceState.unavailable);
      expect(c.state.reason, contains('transcript only'));
    });

    test(
      'a kept file this phone cannot reach says that, not "no audio"',
      () async {
        resolvesTo(const OriginalUnavailable());
        final c = await build(rec(storagePath: 'users/u/originals/board.m4a'));
        expect(c.state.reason, contains('not on this phone'));
      },
    );
  });

  group('controls', () {
    Future<AudioPlayerCubit> ready() async {
      resolvesTo(OriginalOnDevice(File('/kept/board.m4a')));
      return build(rec(storagePath: 'p'));
    }

    test('play, then pause', () async {
      final c = await ready();
      await c.toggle();
      expect(playback.plays, 1);
      playback.playings.add(true);
      await pumpEventQueue();
      await c.toggle();
      expect(playback.pauses, 1);
    });

    test('play at the very end starts again from the beginning', () async {
      final c = await ready();
      playback.positions.add(const Duration(minutes: 41, seconds: 7));
      await pumpEventQueue();
      await c.toggle();
      expect(playback.seeks.last, Duration.zero);
      expect(playback.plays, 1);
    });

    test('skips are fifteen seconds and never leave the recording', () async {
      final c = await ready();
      await c.back();
      expect(playback.seeks.last, Duration.zero, reason: 'not -15s');

      playback.positions.add(const Duration(minutes: 41));
      await pumpEventQueue();
      await c.forward();
      expect(playback.seeks.last, const Duration(minutes: 41, seconds: 7));

      playback.positions.add(const Duration(minutes: 10));
      await pumpEventQueue();
      await c.forward();
      expect(playback.seeks.last, const Duration(minutes: 10, seconds: 15));
    });

    test('a tap on the scrubber seeks to that fraction', () async {
      final c = await ready();
      await c.seekFraction(0.5);
      expect(
        playback.seeks.last.inMilliseconds,
        closeTo(const Duration(minutes: 20, seconds: 33).inMilliseconds, 600),
      );
    });

    test('nothing to play, nothing happens', () async {
      resolvesTo(const OriginalUnavailable());
      final c = await build(rec());
      await c.toggle();
      await c.forward();
      expect(playback.plays, 0);
      expect(playback.seeks, isEmpty);
    });

    test('leaving the screen releases the player', () async {
      final c = await ready();
      await c.close();
      expect(playback.disposed, isTrue);
    });
  });

  test('the clock reads as the design writes it', () {
    expect(clockOf(const Duration(minutes: 18, seconds: 20)), '18:20');
    expect(clockOf(const Duration(seconds: 5)), '00:05');
    expect(
      clockOf(const Duration(hours: 1, minutes: 4, seconds: 5)),
      '1:04:05',
    );
  });
}
