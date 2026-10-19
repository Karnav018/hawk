import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/capture/data/file_capture.dart';
import 'package:knowra/src/features/capture/presentation/bloc/capture_cubit.dart';
import 'package:knowra/src/features/capture/presentation/bloc/upload_intake.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:mocktail/mocktail.dart';

class _Files extends Fake implements FileCapture {
  List<PickedFile> picked = const [];
  PickedFile? scanned;
  Object? scanError;
  final hashed = <String>[];

  @override
  Future<List<PickedFile>> pick(FilePickKind kind) async => picked;

  @override
  Future<List<PickedFile>> pickImages() async => picked;

  @override
  Future<PickedFile?> scanDocument() async {
    if (scanError != null) throw scanError!;
    return scanned;
  }

  /// The hash is the file's name, so a test can make two files "the same".
  @override
  Future<String> fingerprint(String path) async {
    hashed.add(path);
    return 'sha:${path.split('/').last.replaceAll(RegExp(r' \(\d\)'), '')}';
  }
}

class _Memories extends Mock implements MemoryRepository {}

class _Logger extends Mock implements AppLogger {}

PickedFile _file(String name, {int bytes = 1024}) =>
    (path: '/cache/$name', name: name, bytes: bytes);

/// Everything between the picker closing and a byte being sent — E1 to E4.
void main() {
  late _Files files;
  late _Memories memories;
  late UploadIntake intake;

  final kept = Memory(
    id: 'tax',
    type: MemoryType.pdf,
    status: ProcessingStatus.ready,
    createdAt: DateTime(2026, 8, 2),
    title: 'Tax_Return_2023.pdf',
  );

  setUp(() {
    files = _Files();
    memories = _Memories();
    intake = UploadIntake(files, memories, _Logger());
    when(() => memories.findByContentHash(any())).thenAnswer((_) async => null);
  });

  test('backing out of the picker is nothing at all (E1)', () async {
    expect(await intake.pick(CaptureKind.files), isA<IntakeCancelled>());
  });

  test('one file, fine: ready, with its fingerprint', () async {
    files.picked = [_file('Lease agreement 2026.pdf')];
    final result = await intake.pick(CaptureKind.files);
    expect(result, isA<IntakeReady>());
    final ready = result as IntakeReady;
    expect(ready.files.single.name, 'Lease agreement 2026.pdf');
    expect(ready.hashes['/cache/Lease agreement 2026.pdf'], isNotNull);
  });

  test('too big is caught before anything is hashed or sent (E2)', () async {
    files.picked = [
      _file('Board_recording.mov', bytes: FileCapture.maxBytes + 1),
    ];
    final result = await intake.pick(CaptureKind.files);
    expect(result, isA<IntakeTooLarge>());
    expect(files.hashed, isEmpty, reason: 'nobody hashes 1.2 GB to refuse it');
  });

  test('a type Hawk cannot read is named, with its extension (E3)', () async {
    files.picked = [_file('Pitch notes.pages')];
    final result = await intake.pick(CaptureKind.files);
    expect(result, isA<IntakeUnsupported>());
    expect((result as IntakeUnsupported).extension, '.pages');
  });

  test('Word files are refused — the pipeline has no route for them', () async {
    files.picked = [_file('Wedding speech draft.docx')];
    expect(await intake.pick(CaptureKind.files), isA<IntakeUnsupported>());
  });

  test('a photo picked through Files is fine, and filed as a photo', () async {
    files.picked = [_file('Parking level P3.heic')];
    expect(await intake.pick(CaptureKind.files), isA<IntakeReady>());
    expect(
      CaptureKind.files.memoryTypeFor('Parking level P3.heic'),
      MemoryType.photo,
    );
  });

  test('the same bytes already kept is a decision (E4)', () async {
    when(
      () => memories.findByContentHash('sha:Tax_Return_2023.pdf'),
    ).thenAnswer((_) async => kept);
    files.picked = [_file('Tax_Return_2023.pdf')];

    final result = await intake.pick(CaptureKind.files);
    expect(result, isA<IntakeDuplicate>());
    final duplicate = result as IntakeDuplicate;
    expect(duplicate.existing.id, 'tax');

    // "Keep both" goes ahead with the same file and the same hash.
    final both = UploadIntake.keepBoth(duplicate);
    expect(both.files.single.name, 'Tax_Return_2023.pdf');
    expect(both.hashes.values.single, 'sha:Tax_Return_2023.pdf');
  });

  test('a lookup that fails does not stop the save', () async {
    when(() => memories.findByContentHash(any())).thenThrow(Exception('rules'));
    files.picked = [_file('a.pdf')];
    expect(await intake.pick(CaptureKind.files), isA<IntakeReady>());
  });

  test('a batch drops the bad ones and goes on with the rest', () async {
    when(
      () => memories.findByContentHash('sha:IMG_5102.heic'),
    ).thenAnswer((_) async => kept);
    files.picked = [
      _file('IMG_5102.heic'), // already kept
      _file('IMG_5103.heic'),
      _file('IMG_5103 (2).heic'), // same bytes twice in one pick
      _file('IMG_5104.heic', bytes: FileCapture.maxBytes + 1), // too big
      _file('IMG_5105.heic'),
    ];

    final result = await intake.pick(CaptureKind.images);
    expect(result, isA<IntakeReady>());
    final ready = result as IntakeReady;
    expect(ready.files.map((f) => f.name), ['IMG_5103.heic', 'IMG_5105.heic']);
    expect(ready.skipped, 3);
  });

  test('a batch with nothing left says so', () async {
    files.picked = [_file('a.pages'), _file('b.numbers')];
    final result = await intake.pick(CaptureKind.files);
    expect(result, isA<IntakeNothing>());
    expect((result as IntakeNothing).skipped, 2);
  });

  test('a scan with the camera off asks for the camera', () async {
    files.scanError = const CameraDeniedException();
    expect(await intake.pick(CaptureKind.scan), isA<IntakeCameraDenied>());
  });

  test('backing out of the scanner is nothing at all', () async {
    expect(await intake.pick(CaptureKind.scan), isA<IntakeCancelled>());
  });
}
