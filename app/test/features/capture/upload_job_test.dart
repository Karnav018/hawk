import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/capture/presentation/bloc/capture_cubit.dart';
import 'package:knowra/src/features/capture/presentation/bloc/upload_job.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';

const _mb = 1024 * 1024;

UploadJob _job({
  String name = 'Lease agreement 2026.pdf',
  CaptureKind kind = CaptureKind.files,
  UploadPhase phase = UploadPhase.waiting,
  int sent = 0,
  int bytes = (2.4 * _mb) ~/ 1,
  Memory? memory,
  String? problem,
}) => UploadJob(
  id: 'j',
  batchId: 'b',
  kind: kind,
  file: (path: '/cache/$name', name: name, bytes: bytes),
  addedAt: DateTime(2026, 9, 26, 9, 41),
  phase: phase,
  sent: sent,
  memory: memory,
  problem: problem,
);

Memory _memory(ProcessingStatus status, {String? note, MemoryType? type}) =>
    Memory(
      id: 'm',
      type: type ?? MemoryType.pdf,
      status: status,
      createdAt: DateTime(2026, 9, 26, 9, 41),
      indexNote: note,
    );

List<IndexStepState> _states(UploadJob job, {bool online = true}) =>
    stepsOf(job, online: online).map((s) => s.state).toList();

/// The Indexing screen's four steps (F1·4–F1·6) and the exceptions that end
/// on it (E5–E7), as data.
void main() {
  const done = IndexStepState.done;
  const active = IndexStepState.active;
  const pending = IndexStepState.pending;
  const failed = IndexStepState.failed;

  test('uploading: the first step counts the bytes', () {
    final job = _job(phase: UploadPhase.uploading, sent: _mb);
    expect(_states(job), [active, pending, pending, pending]);
    expect(stepsOf(job, online: true).first.note, '1.0 MB of 2.4 MB');
  });

  test('the upload is the first 40%, measured to the byte', () {
    final job = _job(phase: UploadPhase.uploading, sent: (1.2 * _mb) ~/ 1);
    expect(progressOf(job), closeTo(0.2, 0.001));
  });

  test('reading: upload done, reading active', () {
    final job = _job(
      phase: UploadPhase.saved,
      memory: _memory(ProcessingStatus.processing),
    );
    expect(_states(job), [done, active, pending, pending]);
    expect(stateWordOf(job, online: true), 'READING');
  });

  test('a recording is transcribed, not read (F6·4)', () {
    final job = _job(
      name: 'Interview — Sam.m4a',
      kind: CaptureKind.audio,
      phase: UploadPhase.saved,
      memory: _memory(ProcessingStatus.processing, type: MemoryType.audio),
    );
    expect(stepsOf(job, online: true)[1].note, 'Transcribing');
    expect(stateWordOf(job, online: true), 'TRANSCRIBING');
  });

  test('making it searchable once the text is out', () {
    final job = _job(
      phase: UploadPhase.saved,
      memory: _memory(ProcessingStatus.embedding),
    );
    expect(_states(job), [done, done, active, pending]);
  });

  test('ready: every step done', () {
    final job = _job(
      phase: UploadPhase.saved,
      memory: _memory(ProcessingStatus.ready),
    );
    expect(_states(job), [done, done, done, done]);
    expect(job.outcome, JobOutcome.ready);
    expect(progressOf(job), 1.0);
  });

  test('offline: waiting, not failing (E5)', () {
    final job = _job(phase: UploadPhase.uploading, sent: _mb);
    final steps = stepsOf(job, online: false);
    expect(steps.first.state, IndexStepState.waiting);
    expect(steps.first.note, 'Waiting for a connection');
    expect(job.isSettled, isFalse);
  });

  test('stopped: the upload step fails with its cause (E6)', () {
    final job = _job(
      phase: UploadPhase.stopped,
      sent: _mb,
      problem: 'Connection dropped at 1.0 MB',
    );
    final steps = stepsOf(job, online: true);
    expect(steps.first.state, failed);
    expect(steps.first.note, 'Connection dropped at 1.0 MB');
    expect(job.outcome, JobOutcome.stopped);
    // Drawn where it stopped, not reset to zero: the bar is red at the
    // byte the connection dropped at.
    expect(progressOf(job), closeTo(0.4 * _mb / (2.4 * _mb), 0.01));
  });

  test('mostly ready: reading fell short, the rest finished (E7)', () {
    final job = _job(
      phase: UploadPhase.saved,
      memory: _memory(
        ProcessingStatus.ready,
        note: '3 of 12 pages had no readable text',
      ),
    );
    expect(_states(job), [done, failed, done, done]);
    expect(stepsOf(job, online: true)[1].note, contains('3 of 12 pages'));
    expect(job.outcome, JobOutcome.partial);
  });

  test('a pipeline failure is drawn where it stopped, not at 100%', () {
    final job = _job(
      phase: UploadPhase.saved,
      memory: _memory(ProcessingStatus.failed),
    );
    expect(job.outcome, JobOutcome.failed);
    expect(progressOf(job), lessThan(1));
  });

  test('sizes read the way the design writes them', () {
    expect(megabytes((2.4 * _mb) ~/ 1), '2.4 MB');
    expect(megabytes(44 * _mb), '44 MB');
    expect(megabytes(820 * 1024), '820 KB');
    expect(megabytes((1.2 * 1024 * _mb) ~/ 1), '1.2 GB');
  });
}
