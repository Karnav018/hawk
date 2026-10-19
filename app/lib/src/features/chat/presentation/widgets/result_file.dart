import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/files/original_actions.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../memory/domain/entities/memory_enums.dart';
import '../../domain/entities/answer.dart';

/// What v3 lets a result say about a file, and nothing more.
///
/// The design is strict here in a way v2 was not. A result is **the short
/// answer, the file, and where the file lives** — so this record carries the
/// four things needed to draw that and to open the original, and deliberately
/// drops the three v2 put on every row: the relevance score, the matched
/// excerpt, and the "indexed from" provenance line. Those described how
/// retrieval worked; the design's claim is that a person wants the file, not
/// a report on the search that found it.
///
/// A record rather than a class because it is a *view* of either a [Match] or
/// a [Citation]. Screens 1O and 1P draw the same row from whichever of the
/// two arrived first — matches land in about a second, citations only when
/// the model has finished writing — and neither screen should have to know
/// which one it is holding.
typedef ResultFile = ({
  String memoryId,
  String title,
  MemoryType type,

  /// "page 2" — where inside the file. Part of the design's own file line.
  String? locator,
  String? url,
  String? storagePath,
});

ResultFile resultFileFromMatch(Match match) => (
  memoryId: match.memoryId,
  title: match.title,
  type: match.type,
  locator: match.locator,
  url: match.url,
  storagePath: match.storagePath,
);

ResultFile resultFileFromCitation(Citation citation) => (
  memoryId: citation.memoryId,
  title: citation.title,
  type: citation.type,
  locator: citation.locator,
  url: citation.url,
  storagePath: citation.storagePath,
);

/// The files behind an answer — **only its citations, and only once it
/// exists**, one per file.
///
/// While "Reading your files…" is on screen there are no files at all. The
/// quick `search` lands seconds before the answer, and its matches used to
/// stand in during the gap; but they are whatever retrieval found nearest,
/// not what the answer used, and people read them as the last thing they
/// uploaded or searched for (user report, 14 Oct 2026). An answer that cited
/// nothing likewise shows nothing: "hi" retrieves an invoice, and a greeting
/// written from nothing must not sit over files as if they were its source.
///
/// Citations are *passages*, not files, so the eight best passages from one
/// PDF would otherwise be eight rows of the same file. [distinctFiles] folds
/// them into one row per file, in the order the best passage of each ranked.
List<ResultFile> resultFilesFor({
  required List<Citation> citations,
  required bool answered,
}) => answered
    ? distinctFiles([for (final c in citations) resultFileFromCitation(c)])
    : const [];

/// One row per file, first-ranked first, with every place inside it that
/// matched named on the row: "parts 2, 4, 5".
List<ResultFile> distinctFiles(List<ResultFile> files) {
  final order = <String>[];
  final first = <String, ResultFile>{};
  final places = <String, List<String>>{};

  for (final f in files) {
    // A file without an id — never expected, but a result must not vanish
    // for it — is told apart by what it is called and where it points.
    final key = f.memoryId.isNotEmpty ? f.memoryId : '${f.title}|${f.url}';
    if (!first.containsKey(key)) {
      order.add(key);
      first[key] = f;
      places[key] = [];
    }
    final where = f.locator?.trim() ?? '';
    if (where.isNotEmpty && !places[key]!.contains(where)) {
      places[key]!.add(where);
    }
  }

  return [
    for (final key in order)
      (
        memoryId: first[key]!.memoryId,
        title: first[key]!.title,
        type: first[key]!.type,
        locator: mergedLocator(places[key]!),
        url: first[key]!.url,
        storagePath: first[key]!.storagePath,
      ),
  ];
}

/// "part 4" for one place, "parts 2, 4, 5" for several, "parts 1, 2, 3 +4"
/// past three — sorted, because a reader scans a document front to back.
///
/// Locators the backend did not write as "part N" are not guessed at: the
/// best-ranked one is shown alone rather than a list mixing two schemes.
@visibleForTesting
String? mergedLocator(List<String> places) {
  if (places.isEmpty) return null;
  if (places.length == 1) return places.single;

  final numbers = <int>[];
  for (final place in places) {
    final match = RegExp(r'^part (\d+)$').firstMatch(place);
    if (match == null) return places.first;
    numbers.add(int.parse(match[1]!));
  }
  numbers.sort();
  const shown = 3;
  final listed = numbers.take(shown).join(', ');
  final more = numbers.length - shown;
  return more > 0 ? 'parts $listed +$more' : 'parts $listed';
}

/// The mark for a file kind, in v3's own icon set.
///
/// `iconForMemoryType` in the memory feature still answers with the v2 set
/// and a seven-hue colour to go with it. v3 has one accent and one weight of
/// file glyph, so this is the v3 answer to the same question. **It belongs in
/// `hawk_icons.dart`** once lane B stops needing the v2 map — it is declared
/// here only because lane C may not edit core.
String hawkIconForMemory(MemoryType type) => switch (type) {
  MemoryType.screenshot ||
  MemoryType.photo ||
  MemoryType.video => HawkIcons.image,
  MemoryType.audio || MemoryType.voiceNote => HawkIcons.audio,
  MemoryType.link => HawkIcons.link,
  MemoryType.text || MemoryType.note => HawkIcons.file,
  MemoryType.pdf || MemoryType.document || MemoryType.file => HawkIcons.file,
};

/// "PDF · PAGE 2" — what the file is, and where inside it.
///
/// The design's own line is `PDF · PAGE 2 · 1.2 MB`. The size is missing
/// because nothing on the wire carries it: `search` returns no byte count and
/// neither does `ask`. Printing a placeholder would be worse than leaving it
/// out — a file that claims "0 KB" is a file the user distrusts — so the line
/// is built from what is known and the third segment simply does not appear.
String fileLine(ResultFile file) => [
  file.type.label,
  if ((file.locator ?? '').trim().isNotEmpty) file.locator!.trim(),
].join(' · ');

/// "PHONE › DOCUMENTS › BOARD" — where the file lives.
///
/// The second half of what a v3 result is allowed to say, and the half people
/// actually navigate by: "it is in the board folder" is how somebody finds a
/// file again next week, where a chunk id is not.
///
/// Derived from the vault path rather than sent by the server, which is the
/// honest limit of what we can draw today — the path we hold is where *we*
/// keep the file, so the breadcrumb leads with PHONE. A file that only exists
/// as a link falls back to its host, because that is genuinely where it
/// lives. Returns null when neither is known, and the row then shows the file
/// line alone rather than an invented location.
String? whereItLives(ResultFile file) {
  final kept = (file.storagePath ?? '').trim();
  if (kept.isNotEmpty) {
    final segments = kept.split('/').where((s) => s.isNotEmpty).toList();
    // The last segment is the file itself; the breadcrumb is its folders.
    if (segments.isNotEmpty) segments.removeLast();
    // `users/<uid>/…` is addressing, not a folder anyone recognises.
    if (segments.length >= 2 && segments.first == 'users') {
      segments.removeRange(0, 2);
    }
    return ['Phone', ...segments].join(' › ');
  }

  final link = (file.url ?? '').trim();
  if (link.isEmpty) return null;
  final host = Uri.tryParse(link)?.host ?? '';
  return host.isEmpty ? null : host;
}

/// What a row or a card says under the title.
///
/// Where it lives wins when we know it, because that is the line the design
/// gives the primary file on 1P. The file line is the fallback, so a row is
/// never left with a bare title.
String resultMeta(ResultFile file) => whereItLives(file) ?? fileLine(file);

/// One file, as a row under an answer — screen 1P.
///
/// **The primary file is a white card.** That is the design's one rule about
/// this screen: of everything in the thread, the file that answers the
/// question is the thing that matters, so it takes the paper surface and the
/// dark chip. Every other file is a dark card with a raised chip — available,
/// not offered. Making that a parameter rather than a judgement per call site
/// is what stops a screen ending up with two white cards, which would say
/// nothing matters most.
class FileRow extends StatelessWidget {
  const FileRow({required this.file, this.isPrimary = false, super.key});

  final ResultFile file;
  final bool isPrimary;

  OriginalRef get _original => (
    memoryId: file.memoryId,
    title: file.title,
    url: file.url,
    storagePath: file.storagePath,
    // Where the passage sat, for a file that cannot travel to whoever is
    // being sent it.
    fallback: fileLine(file),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paper = AppPalette.onPaper;
    void open() => unawaited(openOriginal(_original));

    return Semantics(
      button: true,
      label: '${file.title}. ${resultMeta(file)}',
      excludeSemantics: true,
      child: HawkCard(
        tone: isPrimary ? CardTone.paper : CardTone.dark,
        radius: AppRadius.bubble,
        padding: const EdgeInsets.all(AppSpacing.inset),
        onTap: open,
        child: Row(
          children: [
            IconTile(
              icon: hawkIconForMemory(file.type),
              size: AppSize.tileLarge,
              radius: 15,
              background: isPrimary ? paper.chip : p.raised,
              foreground: isPrimary ? paper.ink : p.textPrimary,
              strokeWidth: 1.9,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      color: isPrimary ? paper.ink : p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  MetaText(
                    resultMeta(file),
                    color: isPrimary ? paper.muted : p.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            OpenChip(onPaper: isPrimary, onPressed: open),
          ],
        ),
      ),
    );
  }
}

/// "Open" — the one action a result row carries.
///
/// Not [InlineChip], which offers `raised` or `accent` and nothing else. The
/// chip on a white card has to be **ink**, so the row reads as one object
/// rather than as a grey chip that lost its background. Worth promoting to
/// `hawk_kit.dart` as an `onPaper` flag on [InlineChip] the moment a second
/// lane needs a chip on paper.
class OpenChip extends StatelessWidget {
  const OpenChip({required this.onPressed, this.onPaper = false, super.key});

  final VoidCallback onPressed;
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paper = AppPalette.onPaper;

    return Material(
      color: onPaper ? paper.ink : p.raised,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: AppSize.chipAction,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.group),
          child: Text(
            'Open',
            style: AppTypography.chip.copyWith(
              fontSize: 13.5,
              color: p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
