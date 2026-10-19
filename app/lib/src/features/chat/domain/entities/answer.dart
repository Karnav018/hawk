import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../memory/domain/entities/memory_enums.dart';

part 'answer.freezed.dart';

/// How much the system is willing to stand behind an answer (§26, §28).
///
/// Shown on screen 3B as four bars. Deliberately coarse: a percentage invites
/// the reader to treat it as measured, and it is not — it is a judgement about
/// retrieval quality that would be false precision at two decimal places.
enum AnswerConfidence {
  low,
  medium,
  high;

  static AnswerConfidence parse(String? raw) => switch (raw) {
    'high' => high,
    'medium' => medium,
    _ => low,
  };

  /// Filled bars out of four.
  int get bars => switch (this) {
    high => 4,
    medium => 3,
    low => 2,
  };

  String get label => name.toUpperCase();
}

/// One source behind an answer — architecture §28.
///
/// An uncited answer is a bug, not a degraded result: traceability is the
/// whole difference between this and a general chatbot. So a [Citation] always
/// carries enough to *find* the original, never just its name.
@freezed
abstract class Citation with _$Citation {
  const factory Citation({
    required String memoryId,

    /// The superscript number in the answer text. 1-based, and stable within
    /// one answer — the same source cited twice keeps one number.
    required int index,
    required String title,
    @Default(MemoryType.file) MemoryType type,

    /// "p2", "TRANSCRIPT LINE 412" — where in the source, in the source's own
    /// terms. A page number for a PDF and a timestamp for audio are not
    /// interchangeable, so this stays a string rather than an offset.
    String? locator,

    /// 0-100. Retrieval relevance, set in the metadata face on 3B.
    @Default(0) int score,

    /// The original, where there is one.
    ///
    /// §28's promise is that an answer is *traceable* — a title and a page
    /// number you cannot open is a reference, not a citation. Null for a
    /// typed note, which is its own original.
    String? url,

    /// Where the kept file lives in the vault. See [Match.storagePath].
    String? storagePath,
    DateTime? updatedAt,
  }) = _Citation;

  const Citation._();

  bool get isOpenable => (url ?? '').trim().isNotEmpty;

  /// "PDF · UPDATED 14 AUG" — the second line of a source row.
  String get provenance {
    final kind = type.name.toUpperCase();
    if (locator != null && locator!.isNotEmpty) return '$kind · $locator';
    return kind;
  }
}

/// One paragraph of an answer, with the citations that back it.
///
/// Split per paragraph rather than held as one blob because the superscripts
/// have to render *inline* at the position they were claimed — an answer whose
/// citations are collected at the end is not traceable, it is footnoted.
@freezed
abstract class AnswerBlock with _$AnswerBlock {
  const factory AnswerBlock({
    required String text,

    /// Citation indices appearing at the end of this block, in order.
    @Default(<int>[]) List<int> citations,

    /// The lead paragraph is set larger on 3B.
    @Default(false) bool isLead,
  }) = _AnswerBlock;
}

/// One retrieved file, as screen 2C lists it while you are still speaking.
///
/// Deliberately not an [Answer]. Matches come from `search`, which does no
/// generation — so they appear in the time one embedding call takes, rather
/// than waiting on a model to write prose. That difference is the whole
/// reason the home screen can show anything at all mid-sentence.
@freezed
abstract class Match with _$Match {
  const factory Match({
    required String memoryId,
    required String chunkId,
    required String title,
    @Default(MemoryType.file) MemoryType type,

    /// A readable fragment of the passage that matched.
    @Default('') String excerpt,

    /// 0-100 relevance, set in the metadata face.
    @Default(0) int score,

    /// "part 3" — where in the source.
    String? locator,
    String? url,

    /// Where the kept file lives in the vault, for a device that never had
    /// it. Read through the Storage SDK under `storage.rules`.
    String? storagePath,
  }) = _Match;

  const Match._();

  bool get isOpenable => (url ?? '').trim().isNotEmpty;
}

/// How the server read the question — §24's extracted signals.
///
/// Shown so a user who gets nothing can see *why*: a question read as
/// "videos, July" that returns nothing is a filter problem, not an empty
/// vault, and only one of those is worth acting on.
@freezed
abstract class QuerySignals with _$QuerySignals {
  const factory QuerySignals({
    String? type,
    String? after,
    String? before,
    @Default(false) bool rewritten,
  }) = _QuerySignals;

  const QuerySignals._();

  bool get isEmpty => type == null && after == null && before == null;

  /// "videos · from July" — what was filtered, in the user's terms.
  String? get summary {
    if (isEmpty) return null;
    final parts = <String>[
      if (type != null) '${type}s',
      if (after != null && before != null)
        '${_short(after!)}–${_short(before!)}'
      else if (after != null)
        'since ${_short(after!)}'
      else if (before != null)
        'before ${_short(before!)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _short(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

@freezed
abstract class Answer with _$Answer {
  const factory Answer({
    required String id,
    required String question,
    @Default(<AnswerBlock>[]) List<AnswerBlock> blocks,
    @Default(<Citation>[]) List<Citation> citations,
    @Default(AnswerConfidence.low) AnswerConfidence confidence,

    /// False when the vault did not contain the answer.
    ///
    /// Distinct from an error: retrieval worked, the model read the passages,
    /// and none of them answered the question. The screen has to be able to
    /// say that plainly instead of dressing a shrug up as a result — and it
    /// must not show a confidence meter next to one.
    @Default(true) bool answered,

    /// The thread this answer belongs to, for follow-ups.
    String? conversationId,
    @Default(QuerySignals()) QuerySignals signals,
    DateTime? answeredAt,

    /// Wall-clock the server spent. Shown as "0.9S" — the product's claim is
    /// that recall is fast, so the number is on the screen rather than hidden.
    Duration? latency,
  }) = _Answer;

  const Answer._();

  /// "21:04 · 3 SOURCES · 0.9S"
  String get meta {
    final parts = <String>[];
    final at = answeredAt;
    if (at != null) {
      parts.add(
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}',
      );
    }
    // Files, not passages: three [n] markers into one PDF are one source.
    final sources = {
      for (final c in citations)
        c.memoryId.isEmpty ? '#${c.index}' : c.memoryId,
    }.length;
    parts.add('$sources SOURCE${sources == 1 ? '' : 'S'}');
    final ms = latency?.inMilliseconds;
    if (ms != null) parts.add('${(ms / 1000).toStringAsFixed(1)}S');
    return parts.join(' · ');
  }

  Citation? citation(int index) =>
      citations.where((c) => c.index == index).firstOrNull;

  /// A confidence meter beside "I could not find that" is noise — it rates
  /// the quality of a non-answer.
  bool get showsConfidence => answered && citations.isNotEmpty;
}
