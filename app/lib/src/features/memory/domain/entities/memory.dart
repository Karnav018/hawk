import 'package:freezed_annotation/freezed_annotation.dart';

import 'memory_enums.dart';

part 'memory.freezed.dart';

/// Where a memory came from.
///
/// Kept separate from [Memory] for the reason architecture §10 gives: the
/// original can be moved, renamed or un-shared, and the memory has to survive
/// that. A null [Source] means the original is gone, not that the memory is.
@freezed
abstract class Source with _$Source {
  const factory Source({
    required String id,
    required StorageProvider provider,
    String? url,
    String? filename,
    String? mimeType,
    int? sizeBytes,
    DateTime? capturedAt,
  }) = _Source;
}

@freezed
abstract class Topic with _$Topic {
  const factory Topic({
    required String id,
    required String name,
    required String slug,
    @Default(0) int memoryCount,
  }) = _Topic;
}

@freezed
abstract class NamedEntity with _$NamedEntity {
  const factory NamedEntity({
    required String id,
    required String name,
    required String slug,
    @Default('thing') String kind,
    @Default(0) int memoryCount,
  }) = _NamedEntity;
}

/// A unit of recallable knowledge.
@freezed
abstract class Memory with _$Memory {
  const factory Memory({
    required String id,
    required MemoryType type,
    required ProcessingStatus status,
    required DateTime createdAt,
    String? title,
    String? description,
    String? text,
    String? language,

    /// Where the kept file lives in the vault, when one was kept. Null for a
    /// note, a link, or a capture that crossed the plan's file allowance.
    String? storagePath,

    /// Why this memory cannot answer questions, or can only partly.
    ///
    /// Three distinct outcomes share the `extracted`/`ready` statuses, and
    /// only this tells them apart: a type with no extraction route, a capture
    /// with nothing readable in it, and one indexed only as far as the plan's
    /// budget allowed. A user seeing "indexed the first 400 of 900 parts"
    /// knows why an answer missed something; one seeing nothing does not.
    String? indexNote,

    /// What broke, when [status] is `failed`. The pipeline's own message, cut
    /// to 500 characters server-side; shown on screen 2G under the file name.
    String? failure,

    /// Whether another attempt could succeed. Written by the pipeline —
    /// true for a rate limit or a missing key, false for a file it could not
    /// read at all — and it is what decides whether 2G offers Retry. Offering
    /// Retry on a password-protected PDF would just fail again, slower.
    @Default(false) bool retryable,

    /// The plan's index allowance cut this memory short: nothing indexed
    /// (`extracted`) or only the first parts (`ready`). Distinct from the
    /// fixed per-file ceiling, which no upgrade raises. Drives 1X's
    /// library-row lock — "OVER QUOTA" with an Unlock.
    @Default(false) bool overQuota,
    @Default(0.0) double importance,
    Source? source,
    @Default(<Topic>[]) List<Topic> topics,
    @Default(<NamedEntity>[]) List<NamedEntity> entities,
  }) = _Memory;

  const Memory._();

  /// Best available one-liner for a list row.
  ///
  /// Falls through to the url because a link saved with no note has nothing
  /// else — and "Untitled" is the one label that tells the user nothing about
  /// what they saved. Fixed here rather than at capture so it also covers
  /// links already stored, and links a connector indexed.
  String get displayTitle {
    for (final value in [title, description, text]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return _clip(trimmed);
    }

    final filename = source?.filename?.trim();
    if (filename != null && filename.isNotEmpty) return _clip(filename);

    final link = source?.url?.trim();
    if (link != null && link.isNotEmpty) return _clip(_readableUrl(link));

    return 'Untitled';
  }

  static String _clip(String value) =>
      value.length > 120 ? '${value.substring(0, 117)}…' : value;

  /// `https://example.com/a/b?c=1` → `example.com/a/b`.
  ///
  /// The host alone is too coarse — three saved articles from one site would
  /// be three identical rows — and the raw url is mostly scheme and query
  /// noise. Host plus path is what a person would read out.
  static String _readableUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw;

    final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
    final path = uri.path == '/' ? '' : uri.path;
    return '$host$path';
  }

  /// Only ready memories are answerable; the rest are still being understood.
  bool get isRecallable => status == ProcessingStatus.ready;

  /// The third element of a library row's metadata — what the plan promises
  /// about how long this memory stays answerable.
  ///
  /// Retention is a property of the *pair* (memory, plan), not of either one,
  /// so it is a method taking the window rather than a field on the memory:
  /// the same document is kept forever on Premium and has eleven days left on
  /// Free, and nothing about the document changes when the subscription does.
  ///
  /// [windowDays] is `Subscription.memoryWindowDays`; null means no ceiling.
  ///
  /// Past the window the answer is "DORMANT", not "EXPIRED" or "DELETED" —
  /// §36 demotes rather than deletes, so the memory is genuinely still here
  /// and an upgrade genuinely brings it back. A label that said otherwise
  /// would be describing a data loss that did not happen.
  /// Days until this memory falls outside the plan's window, or null when
  /// the plan has no ceiling or it has already fallen out.
  ///
  /// Shared by the library's "Expiring soon" section and by its label, so the
  /// list and the countdown on each row cannot disagree about which memories
  /// are nearly out of time.
  int? daysUntilDormant({int? windowDays, DateTime? now}) {
    if (windowDays == null) return null;
    final elapsed = (now ?? DateTime.now())
        .difference(createdAt.toLocal())
        .inDays;
    final left = windowDays - elapsed;
    return left > 0 ? left : null;
  }

  /// "GOES DORMANT IN 2 DAYS".
  ///
  /// **Not the design's "DELETED IN 2 DAYS".** §36 demotes rather than
  /// deletes: the file is still here, still on the user's own storage, and an
  /// upgrade brings it back into the index intact. Promising a deletion the
  /// product does not perform would be frightening people into paying for
  /// something that was never at risk.
  String? dormancyLabel({int? windowDays, DateTime? now}) {
    final left = daysUntilDormant(windowDays: windowDays, now: now);
    if (left == null) return null;
    return left == 1 ? 'GOES DORMANT TOMORROW' : 'GOES DORMANT IN $left DAYS';
  }

  String retentionLabel({int? windowDays, DateTime? now}) {
    if (windowDays == null) return 'KEPT FOREVER';

    final elapsed = (now ?? DateTime.now())
        .difference(createdAt.toLocal())
        .inDays;
    final left = windowDays - elapsed;

    if (left <= 0) return 'DORMANT';
    if (left == 1) return '1 DAY LEFT';
    return '$left DAYS LEFT';
  }
}
