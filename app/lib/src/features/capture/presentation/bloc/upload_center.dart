import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/files/local_originals.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../memory/domain/entities/memory.dart';
import '../../../memory/domain/repositories/memory_repository.dart';
import '../../data/file_capture.dart';
import '../../data/network_status.dart';
import 'capture_cubit.dart';
import 'upload_job.dart';

export 'upload_job.dart';

part 'upload_center.freezed.dart';

@freezed
abstract class UploadCenterState with _$UploadCenterState {
  const factory UploadCenterState({
    /// Newest first — the order the Library draws them in.
    @Default(<UploadJob>[]) List<UploadJob> jobs,
    @Default(true) bool online,
  }) = _UploadCenterState;

  const UploadCenterState._();

  List<UploadJob> batch(String batchId) => [
    for (final j in jobs)
      if (j.batchId == batchId) j,
  ].reversed.toList();

  UploadJob? jobForMemory(String memoryId) {
    for (final job in jobs) {
      if (job.memory?.id == memoryId) return job;
    }
    return null;
  }

  /// Files still on their way up — the Upload button's "Uploading 2 files…".
  int get uploading => jobs
      .where(
        (j) =>
            j.phase == UploadPhase.waiting ||
            j.phase == UploadPhase.uploading ||
            j.phase == UploadPhase.saving,
      )
      .length;
}

/// Where the island's actions go. An interface so the center can be tested
/// without a router, and so it never holds a `BuildContext`.
abstract interface class UploadNavigator {
  /// The Indexing screen for one batch.
  void openBatch(String batchId);

  /// Somewhere to ask — "Ask about it".
  void ask();
}

/// Every upload the Library starts, for as long as the app is open.
///
/// **App-wide, not the Library's.** "Indexing keeps going if you leave"
/// (F1·4) is a promise about leaving the *screen*, and the island that
/// follows you (F2) has to be fed by something that outlives it. So the
/// jobs live here, a singleton, and the Library and the Indexing screen are
/// two views of the same list.
///
/// **One upload at a time, the pipeline in parallel.** Four concurrent
/// `putFile`s share one radio and finish no sooner, while making a failure in
/// the middle much harder to report. But once a file is up, its reading and
/// indexing happen on the server and cost the phone nothing — so the next
/// upload starts the moment the last one's bytes land, which is why F3·4
/// shows one image uploading while the one before it is being read.
///
/// **Offline is waiting, not failing (E5).** With no network the queue
/// stops taking new uploads and pauses the one in flight; the rows say
/// QUEUED · OFFLINE. When the radio comes back the paused upload resumes
/// from the byte it stopped at, and the rest follow. Only an upload the SDK
/// itself gives up on is "stopped" (E6).
///
/// **The island.** While anything is working somewhere the user is not
/// looking, a progress island says so; when it lands, the island turns into
/// a confirmation with a way to ask about it (F2·3). The Indexing screen
/// tells the center when it is showing a batch, because an island repeating
/// the screen underneath it is noise.
@lazySingleton
class UploadCenter extends Cubit<UploadCenterState>
    with SafeEmit<UploadCenterState> {
  UploadCenter(
    this._files,
    this._memories,
    this._originals,
    this._network,
    this._snacks,
    this._navigator,
    this._logger,
  ) : super(const UploadCenterState()) {
    // A radio that cannot be read is treated as up: the upload then says
    // for itself whether it can get through.
    _networkChanges = _network.changes.listen(
      _onNetwork,
      onError: (Object _) {},
    );
    unawaited(_network.isOnline().then(_onNetwork, onError: (Object _) {}));
  }

  final FileCapture _files;
  final MemoryRepository _memories;
  final LocalOriginals _originals;
  final NetworkStatus _network;
  final SnackController _snacks;
  final UploadNavigator _navigator;
  final AppLogger _logger;

  late final StreamSubscription<bool> _networkChanges;
  final _handles = <String, UploadHandle>{};
  final _watches = <String, StreamSubscription<List<Memory>>>{};

  /// Batches on screen right now, counted — the same batch can be pushed
  /// twice, from the island and from its row.
  final _viewing = <String, int>{};

  /// Batches whose ending has been said, by the screen or by the island.
  final _announced = <String>{};

  /// The user closed the island. It stays closed until something new is
  /// uploaded: the work is still visible on the rows, and an island that
  /// came back after being dismissed would be arguing.
  bool _islandMuted = false;

  /// What the island last showed, to the percent. Null when it is not up.
  int? _islandPercent;

  var _sequence = 0;

  /// Old enough to let go of. Settled jobs are kept a while so the Library
  /// can mark a row as just indexed and the island can still open its batch.
  static const _keepSettled = 40;

  // ------------------------------------------------------------ commands --

  /// Queue [files] and return the batch they form.
  String enqueue(
    List<PickedFile> files, {
    required CaptureKind kind,
    Map<String, String> hashes = const {},
  }) {
    final now = DateTime.now();
    final batchId = 'b${now.microsecondsSinceEpoch}';
    final jobs = [
      for (final file in files)
        UploadJob(
          id: '$batchId-${_sequence++}',
          batchId: batchId,
          kind: kind,
          file: file,
          addedAt: now,
          contentHash: hashes[file.path],
        ),
    ];
    _islandMuted = false;
    // Counted as on screen from the start. The Indexing screen is pushed
    // straight after this returns and attaches a frame later; without the
    // placeholder, the first byte uploaded in that frame would flash an
    // island over a screen that is about to say the same thing.
    _viewing[batchId] = 0;
    // Newest first, and within a batch in reverse pick order, so the list
    // reads the pick top-down once reversed back by `batch`.
    emit(state.copyWith(jobs: _pruned([...jobs.reversed, ...state.jobs])));
    _pump();
    return batchId;
  }

  /// Follow a memory made without an upload — a link, a spoken note — so its
  /// row in the Library moves as the pipeline reads it.
  void follow(Memory memory, {required CaptureKind kind}) {
    final now = DateTime.now();
    final id = 'f${now.microsecondsSinceEpoch}-${_sequence++}';
    final job = UploadJob(
      id: id,
      batchId: id,
      kind: kind,
      file: (path: '', name: memory.displayTitle, bytes: 0),
      addedAt: now,
      phase: UploadPhase.saved,
      memory: memory,
      quiet: true,
    );
    emit(state.copyWith(jobs: _pruned([job, ...state.jobs])));
    _watch(id, memory.id);
  }

  /// Another attempt, for a stopped upload or a failure the pipeline marked
  /// retryable.
  Future<void> retry(String jobId) async {
    final job = _job(jobId);
    if (job == null) return;
    _announced.remove(job.batchId);
    _islandMuted = false;

    if (job.phase == UploadPhase.stopped) {
      _update(
        jobId,
        (j) => j.copyWith(phase: UploadPhase.waiting, problem: null),
      );
      _pump();
      return;
    }

    // Ingestion runs on document *creation*, so the only way to run it
    // again is a new document over the same stored file — which is still
    // there: the pipeline only discards the upload after a successful index.
    final memory = job.memory;
    if (memory == null || !memory.retryable) return;
    try {
      final again = await _memories.capture(
        type: memory.type,
        title: memory.title,
        storagePath: memory.storagePath,
        mimeType: memory.source?.mimeType,
        contentHash: job.contentHash,
      );
      await _memories.deleteMemory(memory.id);
      _update(jobId, (j) => j.copyWith(memory: again));
      _watch(jobId, again.id);
    } catch (error, stackTrace) {
      final mapped = ErrorMapper.map(error, stackTrace);
      _snacks.show(
        Snack.detail(
          title: 'Could not try again',
          subtitle: mapped.displayMessage,
          mark: SnackMark.failure,
        ),
      );
    }
  }

  /// Stop following a file, and undo what it made. Remove on E6.
  Future<void> remove(String jobId) async {
    final job = _job(jobId);
    if (job == null) return;
    await _handles.remove(jobId)?.cancel();
    await _watches.remove(jobId)?.cancel();
    emit(
      state.copyWith(
        jobs: [
          for (final j in state.jobs)
            if (j.id != jobId) j,
        ],
      ),
    );
    _syncIsland();
    final memory = job.memory;
    if (memory != null) {
      try {
        await _memories.deleteMemory(memory.id);
      } on Object catch (error) {
        _logger.warning(
          'Could not remove a failed upload',
          name: 'capture',
          data: {'error': error.toString()},
        );
      }
    }
    _pump();
  }

  /// The Indexing screen is showing [batchId].
  void attach(String batchId) {
    _viewing.update(batchId, (n) => n + 1, ifAbsent: () => 1);
    _syncIsland();
  }

  /// The Indexing screen for [batchId] went away.
  ///
  /// If it had already finished, the screen *was* the news — but leaving it
  /// still earns one line on the list underneath (F1·7), because the row
  /// that just appeared is easy to miss.
  void detach(String batchId) {
    final left = (_viewing[batchId] ?? 0) - 1;
    if (left > 0) {
      _viewing[batchId] = left;
      return;
    }
    _viewing.remove(batchId);

    final jobs = state.batch(batchId);
    final settled = jobs.isNotEmpty && jobs.every((j) => j.isSettled);
    if (settled &&
        _announced.add(batchId) &&
        jobs.every((j) => j.outcome == JobOutcome.ready)) {
      _snacks.show(
        Snack.confirmation(
          message: jobs.length == 1
              ? '${jobs.single.name} is ready'
              : '${jobs.length} files are ready',
        ),
      );
    }
    // The progress island takes over first, so the news below can interrupt
    // it and it comes back underneath.
    _syncIsland();
    // F3·5: several files left mid-way all land in the list at once, and
    // the island says they were all kept before it starts counting them.
    if (!settled && jobs.length > 1) {
      _snacks.show(
        Snack.confirmation(
          message: 'Saved ${jobs.length} files — reading them now',
        ),
      );
    }
  }

  // ------------------------------------------------------------- the run --

  /// Start the oldest waiting upload, if the radio is up and nothing else is
  /// using it.
  void _pump() {
    if (!state.online || isClosed) return;
    if (state.jobs.any((j) => j.phase == UploadPhase.uploading)) return;
    UploadJob? next;
    for (final job in state.jobs.reversed) {
      if (job.phase == UploadPhase.waiting) {
        next = job;
        break;
      }
    }
    if (next != null) unawaited(_run(next.id));
  }

  Future<void> _run(String jobId) async {
    final job = _job(jobId);
    if (job == null) return;

    if (job.uploaded == null) {
      _update(
        jobId,
        (j) => j.copyWith(phase: UploadPhase.uploading, sent: 0, problem: null),
      );
      final handle = _files.upload(job.file);
      _handles[jobId] = handle;
      final progress = handle.sent.listen(
        (sent) => _update(jobId, (j) => j.copyWith(sent: sent)),
      );
      // Started while the radio was going down: hold it where it is.
      if (!state.online) unawaited(handle.pause());
      try {
        final uploaded = await handle.done;
        _update(
          jobId,
          (j) => j.copyWith(
            phase: UploadPhase.saving,
            uploaded: uploaded,
            sent: j.file.bytes,
          ),
        );
      } on CancelledException {
        // Removed while uploading. The job is already gone.
        return;
      } on Object catch (error, stackTrace) {
        final mapped = error is AppException
            ? error
            : ErrorMapper.map(error, stackTrace);
        _update(
          jobId,
          (j) => j.copyWith(
            phase: UploadPhase.stopped,
            problem: mapped is NetworkException
                ? 'Connection dropped at ${megabytes(j.sent)}'
                : mapped.displayMessage,
          ),
        );
        return;
      } finally {
        await progress.cancel();
        _handles.remove(jobId);
        _pump();
      }
    } else {
      _update(jobId, (j) => j.copyWith(phase: UploadPhase.saving));
    }

    await _save(jobId);
  }

  /// Write the memory document — the moment the pipeline starts.
  ///
  /// After the upload, never before: the ingestion trigger fires on this
  /// write and reads the file at once, so writing first would race the
  /// bytes and read an empty object.
  Future<void> _save(String jobId) async {
    final job = _job(jobId);
    final uploaded = job?.uploaded;
    if (job == null || uploaded == null) return;
    try {
      final memory = await _memories.capture(
        type: job.memoryType,
        title: uploaded.filename,
        storagePath: uploaded.storagePath,
        mimeType: uploaded.mimeType,
        sizeBytes: uploaded.bytes,
        contentHash: job.contentHash,
      );
      if (_job(jobId) == null) {
        // Removed while saving: the memory was made for nobody.
        unawaited(_memories.deleteMemory(memory.id).catchError((Object _) {}));
        return;
      }
      _update(
        jobId,
        (j) => j.copyWith(phase: UploadPhase.saved, memory: memory),
      );
      _watch(jobId, memory.id);
      await _keepOriginal(memory, uploaded);
    } on Object catch (error, stackTrace) {
      final mapped = ErrorMapper.map(error, stackTrace);
      _update(
        jobId,
        (j) => j.copyWith(
          phase: UploadPhase.stopped,
          problem: mapped.displayMessage,
        ),
      );
    }
  }

  /// Keep the phone's copy, now that it has an id to be kept under.
  ///
  /// A failure is swallowed: the memory exists and is being indexed. What is
  /// lost is only opening the original from Hawk, and the user still has
  /// the file wherever they picked it from.
  Future<void> _keepOriginal(Memory memory, UploadedFile uploaded) async {
    try {
      await _originals.keep(
        memoryId: memory.id,
        sourcePath: uploaded.localPath,
        filename: uploaded.filename,
      );
    } on Object catch (error) {
      _logger.warning(
        'Could not keep the original',
        name: 'capture',
        data: {'error': error.toString()},
      );
    }
  }

  void _watch(String jobId, String memoryId) {
    unawaited(_watches.remove(jobId)?.cancel());
    _watches[jobId] = _memories.watchMemories([memoryId]).listen(
      (memories) {
        if (memories.isEmpty) return;
        final before = _job(jobId)?.outcome;
        _update(jobId, (j) => j.copyWith(memory: memories.first));
        final job = _job(jobId);
        if (job == null || job.isSettled) {
          unawaited(_watches.remove(jobId)?.cancel());
        }
        if (job != null && before != job.outcome) _settledQuietly(job);
      },
      // A dropped listener is not the file failing. The last state stays
      // on screen, and the Library's own list catches up on refresh.
      onError: (Object error) => _logger.warning(
        'Lost the pipeline stream',
        name: 'capture',
        data: {'error': error.toString()},
      ),
    );
  }

  void _onNetwork(bool online) {
    if (isClosed || online == state.online) return;
    emit(state.copyWith(online: online));

    if (online) {
      for (final handle in _handles.values) {
        unawaited(handle.resume());
      }
      _pump();
      return;
    }

    for (final handle in _handles.values) {
      unawaited(handle.pause());
    }
    // E5's island — once per drop, and only if something is waiting on it.
    if (state.uploading > 0) {
      _snacks.show(
        const Snack.detail(
          title: 'You’re offline',
          subtitle: 'We’ll upload it as soon as you’re back.',
          mark: SnackMark.offline,
        ),
      );
    }
  }

  // ------------------------------------------------------------ the island --

  void _syncIsland() {
    if (isClosed) return;
    final away = [
      for (final job in state.jobs)
        if (!job.quiet && !_viewing.containsKey(job.batchId)) job,
    ];

    final working = [
      for (final job in away)
        if (!job.isSettled) job,
    ];
    if (working.isNotEmpty && !_islandMuted) {
      final fraction =
          working.fold<double>(0, (sum, j) => sum + progressOf(j)) /
          working.length;
      final percent = (fraction * 100).floor();
      if (percent != _islandPercent) {
        _islandPercent = percent;
        _snacks.show(
          Snack.progress(
            message: _workingLine(working),
            fraction: fraction,
            onCancel: () {
              _islandMuted = true;
              _islandPercent = null;
            },
          ),
        );
      }
    } else if (_islandPercent != null) {
      _islandPercent = null;
      _snacks.dismissPersistent();
    }

    final batches = {for (final job in away) job.batchId};
    for (final batchId in batches) {
      if (_announced.contains(batchId)) continue;
      final jobs = state.batch(batchId);
      if (!jobs.every((j) => j.isSettled)) continue;
      _announced.add(batchId);
      _announce(batchId, jobs);
    }
  }

  /// A link or a note that failed after its sheet closed. They skip the
  /// Indexing screen, so the island is the only place left to say so — in
  /// the design's words for a link, with the pipeline's reason under them
  /// ("That page blocks readers. Save it as a PDF instead.").
  void _settledQuietly(UploadJob job) {
    if (!job.quiet || job.outcome != JobOutcome.failed) return;
    _snacks.show(
      Snack.detail(
        title: job.kind == CaptureKind.links
            ? 'Could not save that link'
            : 'Could not save',
        subtitle: job.memory?.failure ?? 'Hawk could not read it.',
        mark: SnackMark.failure,
      ),
    );
  }

  /// "Indexing 1 file", or "Transcribing 1 file" when every one of them is
  /// a recording (F6·5).
  static String _workingLine(List<UploadJob> jobs) {
    final verb = jobs.every((j) => readingWord(j.memoryType) == 'TRANSCRIBING')
        ? 'Transcribing'
        : 'Indexing';
    return '$verb ${jobs.length} file${jobs.length == 1 ? '' : 's'}';
  }

  /// What a batch that finished out of sight says. One line, and a way in.
  void _announce(String batchId, List<UploadJob> jobs) {
    final broken = [
      for (final j in jobs)
        if (j.outcome == JobOutcome.failed || j.outcome == JobOutcome.stopped)
          j,
    ];
    final partial = [
      for (final j in jobs)
        if (j.outcome == JobOutcome.partial || j.outcome == JobOutcome.held) j,
    ];

    if (broken.isNotEmpty) {
      _snacks.show(
        Snack.detail(
          title: broken.length == 1
              ? 'Couldn’t add ${broken.single.name}'
              : 'Couldn’t add ${broken.length} of ${jobs.length} files',
          subtitle:
              broken.first.problem ??
              broken.first.memory?.failure ??
              'Open it to try again.',
          mark: SnackMark.failure,
          action: SnackAction(
            label: 'Open',
            style: SnackActionStyle.text,
            onPressed: () => _navigator.openBatch(batchId),
          ),
        ),
      );
      return;
    }

    if (partial.isNotEmpty) {
      _snacks.show(
        Snack.detail(
          title: 'Saved — some pages unreadable',
          subtitle:
              partial.first.memory?.indexNote ??
              'Ask about it; Hawk will say what it couldn’t read.',
          mark: SnackMark.file,
        ),
      );
      return;
    }

    _snacks.show(
      Snack.confirmation(
        message: jobs.length == 1
            ? 'Ready to ask'
            : '${jobs.length} files ready to ask',
        // Accent text, as drawn (F2·3) — the soft way on, not a filled pill.
        action: SnackAction(
          label: 'Ask',
          style: SnackActionStyle.text,
          onPressed: _navigator.ask,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ plumbing --

  UploadJob? _job(String id) {
    for (final job in state.jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void _update(String id, UploadJob Function(UploadJob) change) {
    if (isClosed) return;
    final index = state.jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final jobs = [...state.jobs];
    jobs[index] = change(jobs[index]);
    emit(state.copyWith(jobs: jobs));
    _syncIsland();
  }

  /// Drop the oldest settled jobs past [_keepSettled]. Working ones are never
  /// dropped, however many there are.
  List<UploadJob> _pruned(List<UploadJob> jobs) {
    var settled = 0;
    return [
      for (final job in jobs)
        if (!job.isSettled || ++settled <= _keepSettled) job,
    ];
  }

  @override
  Future<void> close() async {
    await _networkChanges.cancel();
    for (final watch in _watches.values) {
      await watch.cancel();
    }
    for (final handle in _handles.values) {
      await handle.cancel();
    }
    return super.close();
  }
}
