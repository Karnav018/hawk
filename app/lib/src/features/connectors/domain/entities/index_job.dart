import 'package:freezed_annotation/freezed_annotation.dart';

part 'index_job.freezed.dart';

/// Where the first index has got to (§22's state machine, one level up).
enum IndexJobState {
  queued,
  enumerating,
  processing,
  complete,
  failed;

  static IndexJobState parse(String? raw) => switch (raw) {
    'enumerating' => enumerating,
    'processing' => processing,
    'complete' => complete,
    'failed' => failed,
    _ => queued,
  };

  bool get isTerminal => this == complete || this == failed;
}

/// One row of screen 3L's per-kind breakdown.
@freezed
abstract class IndexKindProgress with _$IndexKindProgress {
  const factory IndexKindProgress({
    required String kind,
    required int done,
    required int total,
  }) = _IndexKindProgress;

  const IndexKindProgress._();

  bool get isComplete => total > 0 && done >= total;

  String get label => switch (kind) {
    'document' => 'Documents',
    'image' => 'Images',
    'recording' => 'Recordings',
    _ => kind,
  };
}

/// Screen 3L, as a document the client streams.
///
/// No polling endpoint and no websocket: the worker writes progress to
/// `indexJobs/{id}` and the app listens. The same trick the rest of the app
/// uses for session state.
@freezed
abstract class IndexJob with _$IndexJob {
  const factory IndexJob({
    required String id,
    required IndexJobState state,
    @Default(0) int totalFiles,
    @Default(0) int totalBytes,
    @Default(0) int processed,
    @Default(0) int failed,

    /// "TRANSCRIBING AUDIO" — what the worker is doing right now.
    String? stage,
    @Default(<IndexKindProgress>[]) List<IndexKindProgress> byKind,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
  }) = _IndexJob;

  const IndexJob._();

  /// 0–1. Guards the empty case because a job that discovered nothing would
  /// otherwise divide by zero and render NaN.
  double get fraction =>
      totalFiles == 0 ? 0 : (processed / totalFiles).clamp(0.0, 1.0);

  /// The design's "02:41 LEFT".
  ///
  /// Extrapolated from actual throughput rather than a fixed per-file guess,
  /// and withheld until there is enough of a sample to be worth showing — an
  /// estimate that swings from 30 seconds to nine minutes is worse than none.
  Duration? estimateRemaining({DateTime? now}) {
    final started = startedAt;
    if (started == null || processed < 10 || state.isTerminal) return null;

    final elapsed = (now ?? DateTime.now()).difference(started);
    if (elapsed.inSeconds < 5) return null;

    final perFile = elapsed.inMilliseconds / processed;
    final remaining = totalFiles - processed;
    if (remaining <= 0) return null;
    return Duration(milliseconds: (perFile * remaining).round());
  }
}
