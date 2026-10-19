import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/error/app_exception.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/capture/data/file_capture.dart';
import 'package:knowra/src/features/capture/data/network_status.dart';
import 'package:knowra/src/features/capture/presentation/bloc/capture_cubit.dart';
import 'package:knowra/src/features/capture/presentation/bloc/upload_center.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:mocktail/mocktail.dart';

/// An upload the test drives by hand: bytes, pauses, the finish.
class _Handle implements UploadHandle {
  _Handle(this.file);

  final PickedFile file;
  final _sent = StreamController<int>.broadcast();
  final _done = Completer<UploadedFile>();
  bool paused = false;
  bool cancelled = false;

  void send(int bytes) => _sent.add(bytes);

  void finish() => _done.complete((
    storagePath: 'users/u/captures/${file.name}',
    filename: file.name,
    mimeType: DeviceFileCapture.mimeTypeFor(file.name),
    bytes: file.bytes,
    localPath: file.path,
  ));

  void fail(AppException error) => _done.completeError(error);

  @override
  Stream<int> get sent => _sent.stream;

  @override
  Future<UploadedFile> get done => _done.future;

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(const AppException.cancelled());
  }
}

class _Files extends Fake implements FileCapture {
  final handles = <_Handle>[];

  @override
  UploadHandle upload(PickedFile file) {
    final handle = _Handle(file);
    handles.add(handle);
    return handle;
  }
}

class _Network implements NetworkStatus {
  bool online = true;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => _changes.stream;
}

class _Memories extends Mock implements MemoryRepository {}

class _Originals extends Mock implements LocalOriginals {}

class _Logger extends Mock implements AppLogger {}

class _Navigator implements UploadNavigator {
  final opened = <String>[];
  var asked = 0;

  @override
  void openBatch(String batchId) => opened.add(batchId);

  @override
  void ask() => asked++;
}

PickedFile _pick(String name, {int bytes = 2400000}) =>
    (path: '/cache/$name', name: name, bytes: bytes);

Memory _memory(
  String id, {
  ProcessingStatus status = ProcessingStatus.uploaded,
  String? indexNote,
  bool retryable = false,
}) => Memory(
  id: id,
  type: MemoryType.pdf,
  status: status,
  createdAt: DateTime(2026, 9, 26),
  title: 'Lease agreement 2026.pdf',
  indexNote: indexNote,
  retryable: retryable,
  storagePath: 'users/u/captures/lease.pdf',
);

/// Lets queued microtasks and stream events land.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Files files;
  late _Memories memories;
  late _Originals originals;
  late _Network network;
  late SnackController snacks;
  late _Navigator navigator;
  late Map<String, StreamController<List<Memory>>> watched;
  var made = 0;

  setUpAll(() {
    registerFallbackValue(MemoryType.note);
  });

  setUp(() {
    files = _Files();
    memories = _Memories();
    originals = _Originals();
    network = _Network();
    snacks = SnackController();
    navigator = _Navigator();
    watched = {};
    made = 0;

    when(
      () => memories.capture(
        type: any(named: 'type'),
        title: any(named: 'title'),
        storagePath: any(named: 'storagePath'),
        mimeType: any(named: 'mimeType'),
        sizeBytes: any(named: 'sizeBytes'),
        contentHash: any(named: 'contentHash'),
      ),
    ).thenAnswer((_) async => _memory('mem-${++made}'));
    when(() => memories.watchMemories(any())).thenAnswer((invocation) {
      final id = (invocation.positionalArguments.first as List<String>).single;
      return (watched[id] = StreamController<List<Memory>>.broadcast()).stream;
    });
    when(() => memories.deleteMemory(any())).thenAnswer((_) async {});
    when(
      () => originals.keep(
        memoryId: any(named: 'memoryId'),
        sourcePath: any(named: 'sourcePath'),
        filename: any(named: 'filename'),
      ),
    ).thenAnswer((_) async => File('/originals/kept'));
  });

  tearDown(() => snacks.dispose());

  UploadCenter center() => UploadCenter(
    files,
    memories,
    originals,
    network,
    snacks,
    navigator,
    _Logger(),
  );

  group('the run', () {
    test('uploads, then writes the memory, then keeps the original', () async {
      final c = center();
      final batch = c.enqueue(
        [_pick('Lease agreement 2026.pdf')],
        kind: CaptureKind.files,
        hashes: {'/cache/Lease agreement 2026.pdf': 'abc123'},
      );
      await _settle();

      final handle = files.handles.single;
      handle.send(1000000);
      await _settle();
      expect(c.state.batch(batch).single.phase, UploadPhase.uploading);
      expect(c.state.batch(batch).single.sent, 1000000);

      handle.finish();
      await _settle();

      verify(
        () => memories.capture(
          // Filed by its extension, not by the tile: a PDF from Files is a
          // PDF.
          type: MemoryType.pdf,
          title: 'Lease agreement 2026.pdf',
          storagePath: 'users/u/captures/Lease agreement 2026.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 2400000,
          contentHash: 'abc123',
        ),
      ).called(1);
      verify(
        () => originals.keep(
          memoryId: 'mem-1',
          sourcePath: '/cache/Lease agreement 2026.pdf',
          filename: 'Lease agreement 2026.pdf',
        ),
      ).called(1);
      final job = c.state.batch(batch).single;
      expect(job.phase, UploadPhase.saved);
      expect(job.memory?.id, 'mem-1');
      await c.close();
    });

    test('one upload at a time; the next starts when the bytes land', () async {
      final c = center();
      c.enqueue([
        _pick('IMG_5102.heic'),
        _pick('IMG_5103.heic'),
      ], kind: CaptureKind.images);
      await _settle();
      expect(files.handles, hasLength(1));
      expect(files.handles.single.file.name, 'IMG_5102.heic');

      files.handles.single.finish();
      await _settle();
      // The first is being read on the server while the second goes up —
      // F3·4's "READING 58%" above "UPLOADING 12%".
      expect(files.handles, hasLength(2));
      expect(files.handles.last.file.name, 'IMG_5103.heic');
      await c.close();
    });

    test('a failure the SDK gave up on stops, and says where', () async {
      final c = center();
      final batch = c.enqueue([
        _pick('Lease agreement 2026.pdf'),
      ], kind: CaptureKind.files);
      await _settle();
      files.handles.single
        ..send(1048576)
        ..fail(const AppException.network());
      await _settle();

      final job = c.state.batch(batch).single;
      expect(job.phase, UploadPhase.stopped);
      expect(job.problem, 'Connection dropped at 1.0 MB');
      expect(job.outcome, JobOutcome.stopped);

      await c.retry(job.id);
      await _settle();
      expect(files.handles, hasLength(2), reason: 'Try again uploads again');
      await c.close();
    });

    test('a failed save does not upload the file a second time', () async {
      var attempts = 0;
      when(
        () => memories.capture(
          type: any(named: 'type'),
          title: any(named: 'title'),
          storagePath: any(named: 'storagePath'),
          mimeType: any(named: 'mimeType'),
          sizeBytes: any(named: 'sizeBytes'),
          contentHash: any(named: 'contentHash'),
        ),
      ).thenAnswer((_) async {
        if (attempts++ == 0) throw const AppException.server();
        return _memory('mem-9');
      });

      final c = center();
      final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      await _settle();
      files.handles.single.finish();
      await _settle();
      final job = c.state.batch(batch).single;
      expect(job.phase, UploadPhase.stopped);

      await c.retry(job.id);
      await _settle();
      expect(files.handles, hasLength(1));
      expect(c.state.batch(batch).single.memory?.id, 'mem-9');
      await c.close();
    });

    test('Remove cancels the upload and forgets the job', () async {
      final c = center();
      final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      await _settle();
      final handle = files.handles.single;

      await c.remove(c.state.batch(batch).single.id);
      await _settle();
      expect(handle.cancelled, isTrue);
      expect(c.state.batch(batch), isEmpty);
      verifyNever(
        () => memories.capture(
          type: any(named: 'type'),
          title: any(named: 'title'),
          storagePath: any(named: 'storagePath'),
          mimeType: any(named: 'mimeType'),
          sizeBytes: any(named: 'sizeBytes'),
          contentHash: any(named: 'contentHash'),
        ),
      );
      await c.close();
    });

    test('follows the pipeline to ready', () async {
      final c = center();
      final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      await _settle();
      files.handles.single.finish();
      await _settle();

      watched['mem-1']!.add([
        _memory('mem-1', status: ProcessingStatus.embedding),
      ]);
      await _settle();
      expect(c.state.batch(batch).single.outcome, JobOutcome.working);

      watched['mem-1']!.add([_memory('mem-1', status: ProcessingStatus.ready)]);
      await _settle();
      expect(c.state.batch(batch).single.outcome, JobOutcome.ready);
      await c.close();
    });
  });

  group('offline (E5)', () {
    test(
      'waits instead of failing, then goes when the radio is back',
      () async {
        network.online = false;
        final c = center();
        await _settle();
        expect(c.state.online, isFalse);

        final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
        await _settle();
        expect(files.handles, isEmpty, reason: 'nothing starts with no radio');
        final job = c.state.batch(batch).single;
        expect(stateWordOf(job, online: false), 'QUEUED · OFFLINE');
        expect(stepsOf(job, online: false).first.state, IndexStepState.waiting);
        expect(
          stepsOf(job, online: false).first.note,
          'Waiting for a connection',
        );

        network.set(true);
        await _settle();
        expect(files.handles, hasLength(1));
        await c.close();
      },
    );

    test('pauses the upload in flight and resumes it, and says so', () async {
      final c = center();
      c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      await _settle();
      final handle = files.handles.single;

      network.set(false);
      await _settle();
      expect(handle.paused, isTrue);
      final island = snacks.current;
      expect(island, isA<DetailSnack>());
      expect((island! as DetailSnack).title, 'You’re offline');

      network.set(true);
      await _settle();
      expect(handle.paused, isFalse);
      await c.close();
    });
  });

  group('the island', () {
    test('stays away while the Indexing screen is showing the batch', () async {
      final c = center();
      final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      c.attach(batch);
      await _settle();
      files.handles.single.send(500000);
      await _settle();
      expect(snacks.current, isNull);
      await c.close();
    });

    test('follows the user out as progress (F2·2)', () async {
      final c = center();
      final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
      c.attach(batch);
      await _settle();
      c.detach(batch);
      files.handles.single.send(1200000);
      await _settle();

      final island = snacks.current;
      expect(island, isA<ProgressSnack>());
      expect((island! as ProgressSnack).message, 'Indexing 1 file');
      await c.close();
    });

    test(
      'turns into "Ready to ask" with Ask when it lands away (F2·3)',
      () async {
        final c = center();
        final batch = c.enqueue([_pick('a.pdf')], kind: CaptureKind.files);
        c.attach(batch);
        await _settle();
        c.detach(batch);
        files.handles.single.finish();
        await _settle();
        watched['mem-1']!.add([
          _memory('mem-1', status: ProcessingStatus.ready),
        ]);
        await _settle();

        final island = snacks.current;
        expect(island, isA<ConfirmationSnack>());
        final ready = island! as ConfirmationSnack;
        expect(ready.message, 'Ready to ask');
        ready.action!.onPressed();
        expect(navigator.asked, 1);
        await c.close();
      },
    );

    test(
      'says the file is ready when leaving a finished screen (F1·7)',
      () async {
        final c = center();
        final batch = c.enqueue([
          _pick('Lease agreement 2026.pdf'),
        ], kind: CaptureKind.files);
        c.attach(batch);
        await _settle();
        files.handles.single.finish();
        await _settle();
        watched['mem-1']!.add([
          _memory('mem-1', status: ProcessingStatus.ready),
        ]);
        await _settle();
        expect(snacks.current, isNull, reason: 'the screen is the news');

        c.detach(batch);
        expect(
          (snacks.current! as ConfirmationSnack).message,
          'Lease agreement 2026.pdf is ready',
        );
        await c.close();
      },
    );

    test('several files left mid-way say they were all kept (F3·5)', () async {
      final c = center();
      final batch = c.enqueue([
        _pick('IMG_5102.heic'),
        _pick('IMG_5103.heic'),
      ], kind: CaptureKind.images);
      c.attach(batch);
      await _settle();
      c.detach(batch);

      expect(
        (snacks.current! as ConfirmationSnack).message,
        'Saved 2 files — reading them now',
      );
      // The progress island is underneath, back when the news has gone.
      snacks.dismiss();
      expect(snacks.current, isA<ProgressSnack>());
      await c.close();
    });

    test('a link the page refused says so, in the design’s words', () async {
      final c = center();
      c.follow(_memory('link-1'), kind: CaptureKind.links);
      await _settle();
      watched['link-1']!.add([
        _memory('link-1', status: ProcessingStatus.failed).copyWith(
          failure: 'That page blocks readers. Save it as a PDF instead.',
        ),
      ]);
      await _settle();

      final island = snacks.current! as DetailSnack;
      expect(island.title, 'Could not save that link');
      expect(
        island.subtitle,
        'That page blocks readers. Save it as a PDF instead.',
      );
      expect(island.mark, SnackMark.failure);
      await c.close();
    });

    test('a link or a note never drives it', () async {
      final c = center();
      c.follow(_memory('link-1'), kind: CaptureKind.links);
      await _settle();
      watched['link-1']!.add([
        _memory('link-1', status: ProcessingStatus.processing),
      ]);
      await _settle();
      expect(snacks.current, isNull);
      expect(c.state.jobs.single.quiet, isTrue);
      await c.close();
    });
  });
}
