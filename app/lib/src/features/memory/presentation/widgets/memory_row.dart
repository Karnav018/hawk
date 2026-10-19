import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/files/original_actions.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../account/presentation/pages/vault_page.dart';
import '../../../billing/presentation/pages/paywall_page.dart';
import '../../../capture/presentation/bloc/upload_job.dart';
import '../../../capture/presentation/widgets/indexing_parts.dart';
import '../../domain/entities/memory.dart';
import '../../domain/entities/memory_enums.dart';
import 'memory_icon.dart';

/// One file in the library — screen 1K's list.
///
/// **A card, not a table row.** v2 drew a 64px row inside one bordered panel,
/// with the title on the left and a second stack of time-over-state on the
/// right: four columns of information competing for the same glance. v3 gives
/// every file its own 22px card, nine pixels apart, and reduces the right-hand
/// stack to a single affordance — a chevron, or the dot counting an index
/// down. Everything that used to live on the right is now one mono line under
/// the title, which is the line a person actually reads.
///
/// That line is `DATE · STATE · RETENTION`, and the order is the order of the
/// questions: when did I save this, is it askable yet, and how long will it
/// stay that way. While it is still being read the third claim is left off
/// (`JUST NOW · INDEXING`): how long a file stays askable is not a question
/// until it is askable.
class MemoryRow extends StatelessWidget {
  const MemoryRow({
    required this.memory,
    this.onTap,
    this.windowDays,
    this.now,
    this.progress,
    this.justIndexed = false,
    super.key,
  });

  final Memory memory;
  final VoidCallback? onTap;

  /// The ring's value, from the upload that made this memory when there is
  /// one — so the row, the island and the Indexing screen agree to the
  /// percent. Estimated from the pipeline's stage otherwise.
  final double? progress;

  /// Finished in front of the user a moment ago: the mono line turns accent
  /// (the parts sheet's JUST INDEXED), so the new row is findable in a list
  /// of rows that all say INDEXED.
  final bool justIndexed;

  /// The plan's retention window, from `Subscription.memoryWindowDays`. Null
  /// means no ceiling, which the row prints as "KEPT FOREVER".
  final int? windowDays;

  /// The moment the date and the retention countdown are measured from.
  ///
  /// Injectable because both are functions of the wall clock — a golden
  /// captured today would fail tomorrow, having changed nothing. Production
  /// leaves it null and gets `DateTime.now()`.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // Screen 1X's inline lock: the plan's allowance stopped this one. Dimmed
    // rather than hidden — it is still in the library, and the file is
    // still the user's — with the one action that changes it. On the top
    // tier there is nothing to unlock, so the action is to make room.
    if (memory.overQuota) {
      final upgradeable = context.plan.canUpgrade;
      return HawkRow(
        title: memory.displayTitle,
        meta: overQuotaLine(memory),
        icon: iconForMemoryType(memory.type),
        tone: CardTone.dim,
        onTap: onTap,
        trailing: InlineChip(
          label: upgradeable ? 'Unlock' : 'Free up',
          onPressed: () => context.pushNamed(
            upgradeable ? PaywallPage.routeName : VaultPage.routeName,
          ),
        ),
      );
    }

    final working = memoryOutcome(memory) == JobOutcome.working;
    return HawkRow(
      title: memory.displayTitle,
      meta: metaLine(memory, windowDays: windowDays, now: now),
      metaColor: justIndexed && !working ? context.palette.accent : null,
      icon: iconForMemoryType(memory.type),
      onTap: onTap,
      // A row that is still being read reports how far it has come *instead
      // of* offering a way in, because there is not much in there yet. The
      // chevron comes back when the file does.
      trailing: working
          ? ProgressRing(fraction: progress ?? memoryProgress(memory))
          : null,
    );
  }

  /// `OVER QUOTA · NOT INDEXED`, or `OVER QUOTA · PARTLY INDEXED`.
  ///
  /// The second is not in the design, which only draws the first — but the
  /// index budget degrades to *partial* before it refuses outright (the
  /// first pages of a document usually answer questions about it), and a
  /// partly indexed file labelled "NOT INDEXED" would be wrong about
  /// something the user can check.
  static String overQuotaLine(Memory memory) =>
      memory.status == ProcessingStatus.extracted
      ? 'OVER QUOTA · NOT INDEXED'
      : 'OVER QUOTA · PARTLY INDEXED';

  /// `14 AUG · INDEXED · KEPT FOREVER`.
  ///
  /// Assembled in one place, and exposed for tests, because it is three
  /// separate claims joined by a separator — and the one that goes wrong
  /// quietly is the middle one. See [debugStateLabel].
  static String metaLine(Memory memory, {int? windowDays, DateTime? now}) => [
    dateLabel(memory.createdAt, now: now),
    debugStateLabel(memory),
    if (memoryOutcome(memory) != JobOutcome.working)
      memory.retentionLabel(windowDays: windowDays, now: now),
  ].join(' · ');

  /// `JUST NOW` for the first couple of minutes, `14 AUG` after.
  ///
  /// Two minutes rather than one because that is about how long a PDF
  /// takes to go from the picker to indexed — so a row keeps saying
  /// JUST NOW for as long as the island is still talking about it.
  static String dateLabel(DateTime when, {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(when);
    if (!age.isNegative && age < const Duration(minutes: 2)) return 'JUST NOW';
    return _shortDate(when);
  }

  /// `14 AUG`. Hand-rolled rather than via `intl`.
  ///
  /// Set in the metadata face at 9.5px with caps tracking, which
  /// only works for a fixed two-token shape — a localised "14 août" or
  /// "2026年8月14日" would overflow the row at a size nobody could read. It is
  /// a compact timestamp, not prose, so it stays in one form.
  static String _shortDate(DateTime when) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final local = when.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }

  /// What a library row knows about its memory's original.
  ///
  /// A note's own text is the fallback: a typed note has no file anywhere, so
  /// sharing it means sharing what was written.
  static OriginalRef originalOf(Memory memory) => (
    memoryId: memory.id,
    title: memory.displayTitle,
    url: _urlOf(memory),
    storagePath: memory.storagePath,
    fallback: memory.text ?? memory.description,
  );

  /// A link's url; or, for a Drive file, the link derived from its id.
  ///
  /// The Drive sync stores the file id and never a url, so without this a
  /// Drive memory in the library had nothing to open. Mirrors `_drive_url`
  /// in `api.py`, which does the same for matches and citations.
  static String? _urlOf(Memory memory) {
    final source = memory.source;
    if (source == null) return null;
    if (source.url != null) return source.url;
    if (source.provider == StorageProvider.googleDrive &&
        source.id.isNotEmpty) {
      return 'https://drive.google.com/open?id=${Uri.encodeQueryComponent(source.id)}';
    }
    return null;
  }

  /// The row's state, which is not the same question as its `status`.
  ///
  /// Three outcomes share `extracted`, and one shares `ready`:
  ///
  /// * `ready` with no note — searchable. "INDEXED".
  /// * `ready` *with* a note — searchable, but only partly indexed, because
  ///   the plan's budget or the per-item ceiling stopped the rest. "PARTIAL",
  ///   because "INDEXED" beside a half-indexed document is how a user comes
  ///   to believe an answer was complete when it was not.
  /// * `extracted` with a note — held but not searchable, and the note says
  ///   why (a type with no OCR route, a blank scan, a full index). "HELD",
  ///   not "FAILED": nothing went wrong.
  /// * `failed` — something actually broke.
  ///
  /// v2 called the first one "READY", which described the *pipeline*. v3's
  /// word is "INDEXED", which describes the file — and it is the word the
  /// Drive tab, the plan meter and the indexing screen all use for the same
  /// condition, so the product now says one thing about it.
  ///
  /// Exposed for tests. The rule it encodes — that a partly indexed memory
  /// must not read as fully indexed — is worth pinning.
  ///
  /// Before extraction the word is what is happening to *this* file —
  /// READING, or TRANSCRIBING for a recording (F4·4, F6·5) — because "the
  /// pipeline has it" is not something anybody asked.
  @visibleForTesting
  static String debugStateLabel(Memory memory) => switch (memory.status) {
    // `indexed` is already answerable; what runs after it only improves
    // ranking. The row says so, as the Indexing screen's "Ready" does.
    ProcessingStatus.ready || ProcessingStatus.indexed =>
      memory.indexNote != null ? 'PARTIAL' : 'INDEXED',
    ProcessingStatus.failed => 'FAILED',
    ProcessingStatus.uploaded ||
    ProcessingStatus.processing => readingWord(memory.type),
    ProcessingStatus.extracted when memory.indexNote != null => 'HELD',
    _ => 'INDEXING',
  };
}
