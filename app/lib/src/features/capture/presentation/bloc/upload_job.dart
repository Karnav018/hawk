import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../data/file_capture.dart';
import 'capture_cubit.dart';

part 'upload_job.freezed.dart';

/// Where one file is on its way into the Library, before the pipeline takes
/// over.
enum UploadPhase {
  /// Chosen, not started — behind another upload, or with no network (E5).
  waiting,

  /// Bytes are moving, or paused because the connection went.
  uploading,

  /// In Storage; the memory document is being written.
  saving,

  /// The upload or the save gave up. [UploadJob.problem] says how (E6).
  stopped,

  /// The memory exists. From here [UploadJob.memory]'s status is the truth.
  saved,
}

/// One file the user chose through Upload, followed from the picker to
/// "Ready to ask".
@freezed
abstract class UploadJob with _$UploadJob {
  const factory UploadJob({
    required String id,

    /// Everything chosen in one pick shares a batch. The Indexing screen
    /// shows a batch: one file as F1·4, several as F3·4.
    required String batchId,
    required CaptureKind kind,
    required PickedFile file,
    required DateTime addedAt,

    /// For E4 next time. Null when fingerprinting failed, which only costs
    /// a later duplicate check.
    String? contentHash,
    @Default(UploadPhase.waiting) UploadPhase phase,

    /// Bytes in Storage so far.
    @Default(0) int sent,

    /// Set once the bytes are up, so a retry after a failed *save* does not
    /// upload the file a second time.
    UploadedFile? uploaded,

    /// What went wrong, in the words the step shows — "Connection dropped at
    /// 1.0 MB".
    String? problem,

    /// The memory, live from Firestore once it exists.
    Memory? memory,

    /// Followed for its row only — a saved link or a spoken note. Those skip
    /// the Indexing screen and say "Saved — reading it now" once (F4·4,
    /// F7·4), so they never drive the progress island.
    @Default(false) bool quiet,
  }) = _UploadJob;

  const UploadJob._();

  String get name => file.name;

  MemoryType get memoryType => kind.memoryTypeFor(file.name);

  JobOutcome get outcome => outcomeOf(this);

  /// Nothing more will happen without the user.
  bool get isSettled => outcome != JobOutcome.working;
}

/// How a job ended, or that it has not.
enum JobOutcome {
  working,

  /// Searchable, all of it.
  ready,

  /// Searchable, but something could not be read — "Mostly ready" (E7).
  partial,

  /// Kept, not searchable: a type with no reading route, a blank scan, a
  /// full index. The pipeline's `extracted` with a note. Nothing broke.
  held,

  /// The pipeline broke.
  failed,

  /// The upload or the save broke — nothing reached the pipeline (E6).
  stopped,
}

JobOutcome outcomeOf(UploadJob job) {
  if (job.phase == UploadPhase.stopped) return JobOutcome.stopped;
  final memory = job.memory;
  if (job.phase != UploadPhase.saved || memory == null) {
    return JobOutcome.working;
  }
  return memoryOutcome(memory);
}

/// The same question about a memory with no job behind it.
JobOutcome memoryOutcome(Memory memory) => switch (memory.status) {
  ProcessingStatus.failed => JobOutcome.failed,
  // `indexed` is already searchable; enrichment after it only improves
  // ranking, and "Ready to ask" is the promise.
  ProcessingStatus.indexed || ProcessingStatus.ready =>
    memory.indexNote != null ? JobOutcome.partial : JobOutcome.ready,
  // `extracted` with a note is the pipeline's "held" — it will not move
  // again on its own, so it has to count as finished.
  ProcessingStatus.extracted when memory.indexNote != null => JobOutcome.held,
  _ => JobOutcome.working,
};

/// How far one job has come, 0..1 — the file card's bar and the island's
/// ring.
///
/// Two halves, weighted. The upload is measured in bytes and is honest to
/// the byte; the pipeline reports a *stage*, and
/// [ProcessingStatus.indexFraction] is the one place that stage is turned
/// into an estimate. The split gives the upload the first 40%, which is
/// roughly its share of the wall-clock on a phone for a typical PDF: long
/// enough that "42%" while uploading means something, short enough that the
/// bar does not sit near full while the pipeline does the real work.
double progressOf(UploadJob job) {
  switch (job.phase) {
    case UploadPhase.waiting:
      return 0;
    case UploadPhase.uploading || UploadPhase.stopped when job.uploaded == null:
      final total = job.file.bytes;
      return total == 0 ? 0 : _uploadShare * (job.sent / total).clamp(0, 1);
    case UploadPhase.uploading || UploadPhase.stopped || UploadPhase.saving:
      return _uploadShare;
    case UploadPhase.saved:
      final memory = job.memory;
      return memory == null ? _uploadShare : memoryProgress(memory);
  }
}

/// The same estimate for a memory already past its upload — a row in the
/// list that no job is following, after a restart.
double memoryProgress(Memory memory) {
  // A failure is drawn where it stopped, not at 100%: a full red bar reads
  // as "done, badly", which is not what happened.
  if (memory.status == ProcessingStatus.failed) {
    return _uploadShare +
        (1 - _uploadShare) * ProcessingStatus.processing.indexFraction;
  }
  return _uploadShare + (1 - _uploadShare) * memory.status.indexFraction;
}

const _uploadShare = 0.4;

/// One of the four steps on the Indexing screen.
enum IndexStepState { done, active, waiting, failed, pending }

typedef IndexStep = ({String label, IndexStepState state, String? note});

/// The four steps, named in plain words (F1·4).
///
/// "Reading what's inside" is the pipeline's extraction; "Making it
/// searchable" is chunking, enrichment and embedding. The design writes
/// "Page 9 of 12" and "Transcribing · 8 of 24 min" under the reading step.
/// The pipeline does not report pages or minutes — only its stage — so the
/// note says what kind of reading it is, which is true, rather than a count
/// that would have to be made up.
List<IndexStep> stepsOf(UploadJob job, {required bool online}) {
  final memory = job.memory;
  final reading = _readingNote(job.memoryType);

  IndexStep step(String label, IndexStepState state, [String? note]) =>
      (label: label, state: state, note: note);

  const upload = 'Uploading to your vault';
  const read = 'Reading what’s inside';
  const index = 'Making it searchable';
  const ready = 'Ready to ask';

  switch (job.phase) {
    case UploadPhase.waiting || UploadPhase.uploading when !online:
      return [
        step(upload, IndexStepState.waiting, 'Waiting for a connection'),
        step(read, IndexStepState.pending),
        step(index, IndexStepState.pending),
        step(ready, IndexStepState.pending),
      ];
    case UploadPhase.waiting:
      return [
        step(upload, IndexStepState.active, 'Waiting its turn'),
        step(read, IndexStepState.pending),
        step(index, IndexStepState.pending),
        step(ready, IndexStepState.pending),
      ];
    case UploadPhase.uploading:
      return [
        step(
          upload,
          IndexStepState.active,
          '${megabytes(job.sent)} of ${megabytes(job.file.bytes)}',
        ),
        step(read, IndexStepState.pending),
        step(index, IndexStepState.pending),
        step(ready, IndexStepState.pending),
      ];
    case UploadPhase.stopped:
      final uploaded = job.uploaded != null;
      return [
        step(
          upload,
          uploaded ? IndexStepState.done : IndexStepState.failed,
          uploaded ? null : job.problem,
        ),
        step(
          read,
          uploaded ? IndexStepState.failed : IndexStepState.pending,
          uploaded ? job.problem : null,
        ),
        step(index, IndexStepState.pending),
        step(ready, IndexStepState.pending),
      ];
    case UploadPhase.saving:
      return [
        step(upload, IndexStepState.done),
        step(read, IndexStepState.active, reading),
        step(index, IndexStepState.pending),
        step(ready, IndexStepState.pending),
      ];
    case UploadPhase.saved:
      if (memory == null) {
        return [
          step(upload, IndexStepState.done),
          step(read, IndexStepState.active, reading),
          step(index, IndexStepState.pending),
          step(ready, IndexStepState.pending),
        ];
      }
      final note = memory.indexNote;
      return switch (memoryOutcome(memory)) {
        JobOutcome.ready => [
          step(upload, IndexStepState.done),
          step(read, IndexStepState.done),
          step(index, IndexStepState.done),
          step(ready, IndexStepState.done),
        ],
        // E7: the reading step is the one that fell short, and says by how
        // much; the rest completed on what could be read.
        JobOutcome.partial => [
          step(upload, IndexStepState.done),
          step(read, IndexStepState.failed, note),
          step(index, IndexStepState.done),
          step(ready, IndexStepState.done),
        ],
        JobOutcome.held => [
          step(upload, IndexStepState.done),
          step(read, IndexStepState.failed, note),
          step(index, IndexStepState.pending),
          step(ready, IndexStepState.pending),
        ],
        JobOutcome.failed => [
          step(upload, IndexStepState.done),
          step(
            read,
            IndexStepState.failed,
            memory.failure ?? 'Hawk could not read it',
          ),
          step(index, IndexStepState.pending),
          step(ready, IndexStepState.pending),
        ],
        _ => switch (memory.status) {
          ProcessingStatus.uploaded || ProcessingStatus.processing => [
            step(upload, IndexStepState.done),
            step(read, IndexStepState.active, reading),
            step(index, IndexStepState.pending),
            step(ready, IndexStepState.pending),
          ],
          _ => [
            step(upload, IndexStepState.done),
            step(read, IndexStepState.done),
            step(index, IndexStepState.active),
            step(ready, IndexStepState.pending),
          ],
        },
      };
  }
}

String? _readingNote(MemoryType type) => switch (type) {
  // The design's "Transcribing · 8 of 24 min", without the minutes.
  MemoryType.audio || MemoryType.voiceNote => 'Transcribing',
  // Described first, then the words in it — see `gemini._DESCRIBE_SYSTEM`.
  MemoryType.photo || MemoryType.screenshot => 'Looking at what’s in it',
  _ => null,
};

/// The one-word state a row or a batch card prints — `UPLOADING`, `READ`.
///
/// F3·4 uses the past tense for a file that is done ("READ") because in a
/// list of four the question is *which ones are finished*, and "INDEXED"
/// four times over does not answer it at a glance.
String stateWordOf(UploadJob job, {required bool online}) {
  switch (job.phase) {
    case UploadPhase.waiting || UploadPhase.uploading when !online:
      return 'QUEUED · OFFLINE';
    case UploadPhase.waiting:
      return 'QUEUED';
    case UploadPhase.uploading:
      return 'UPLOADING';
    case UploadPhase.saving:
      return readingWord(job.memoryType);
    case UploadPhase.stopped:
      return 'UPLOAD STOPPED';
    case UploadPhase.saved:
      final memory = job.memory;
      if (memory == null) return readingWord(job.memoryType);
      return switch (memoryOutcome(memory)) {
        JobOutcome.ready => 'READ',
        JobOutcome.partial => 'PARTIAL',
        JobOutcome.held => 'HELD',
        JobOutcome.failed || JobOutcome.stopped => 'FAILED',
        JobOutcome.working =>
          memory.status == ProcessingStatus.uploaded ||
                  memory.status == ProcessingStatus.processing
              ? readingWord(job.memoryType)
              : 'INDEXING',
      };
  }
}

/// "READING", or "TRANSCRIBING" for anything with a voice in it (F6·5).
String readingWord(MemoryType type) =>
    type == MemoryType.audio || type == MemoryType.voiceNote
    ? 'TRANSCRIBING'
    : 'READING';

/// `2.4 MB`, `820 KB`. One decimal under 10 MB, where the decimal is most of
/// the information; whole numbers above.
String megabytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= 10 * mb) return '${(bytes / mb).round()} MB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / kb).ceil()} KB';
}
