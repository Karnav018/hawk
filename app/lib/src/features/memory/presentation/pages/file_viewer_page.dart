import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/files/original_access.dart';
import '../../../../core/files/original_actions.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../domain/entities/memory.dart';
import '../../domain/entities/memory_enums.dart';
import '../bloc/audio_player_cubit.dart';
import '../bloc/file_viewer_cubit.dart';
import '../bloc/pending_removals.dart';
import '../widgets/memory_row.dart';
import '../widgets/remove_sheet.dart';
import 'library_page.dart';

/// Screen 1M — FILE VIEWER.
///
/// **The white card is the document, and it is the only one on the screen.**
/// That is the whole composition: chrome above it, two actions below it, and
/// between them the thing you came to read, on paper. v2 had no viewer at all
/// — tapping a library row threw the file at whatever app the OS picked, so a
/// 90 MB PDF meant a vault download before anything appeared, and a file
/// captured on another phone meant a snack saying so.
///
/// What is rendered is the **extracted text**, not the original. That is not
/// a compromise: it is the text the answers were built from, so reading it is
/// reading what Hawk actually knows. The original is one tap away for anyone
/// who wants the real thing, and "Open in app" says exactly that.
///
/// **The trash removes the index entry, never the file.** See
/// [FileViewerCubit.removeFromIndex].
class FileViewerPage extends StatelessWidget {
  const FileViewerPage({super.key});

  static const routeName = 'fileViewer';
  static const routePath = '/file/:memoryId';

  @override
  Widget build(BuildContext context) {
    // Removal is not this screen's to finish: it hands the memory to
    // [PendingRemovals] and leaves, and the undo window, the delete and any
    // failure all happen after it has gone.
    return BlocBuilder<FileViewerCubit, FileViewerState>(
      builder: (context, state) {
        final memory = state.memory;
        final exception = state.exception;

        // A load failure replaces the whole screen; a *delete* failure is a
        // snack over a screen that is still perfectly readable.
        if (memory == null && exception != null) {
          return AppScreen(
            ambientOpacity: 0,
            scrollable: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ViewerHeader(memory: null, pageLabel: ''),
                Expanded(
                  child: ErrorView(
                    exception: exception,
                    onRetry: context.read<FileViewerCubit>().load,
                  ),
                ),
              ],
            ),
          );
        }

        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          footer: memory == null ? null : _ViewerActions(memory: memory),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ViewerHeader(
                memory: memory,
                // A recording has no pages; "PAGE 1 OF 1" over a player would
                // be the screen describing a document that is not there.
                //
                // A photo has no pages either: 2I's line is when and where
                // — "24 AUG · PHOTO · ON DEVICE" — not "PAGE 1 OF 1".
                pageLabel: (memory?.type.isAudio ?? false)
                    ? _Paper._provenance(memory).toUpperCase()
                    : (memory?.type.isVisual ?? false)
                    ? '${_shortDay(memory!.createdAt)} · '
                              '${_Paper._provenance(memory)}'
                          .toUpperCase()
                    : state.pageLabel,
              ),
              const SizedBox(height: AppSpacing.inset),
              Expanded(
                child: state.isLoading
                    ? const _DocumentPlaceholder()
                    : (memory?.type.isAudio ?? false)
                    ? _AudioBody(memory: memory!, pages: state.pages)
                    : (memory?.type.isVisual ?? false)
                    ? _ImageViewer(
                        memory: memory!,
                        text: state.pages.join('\n\n'),
                      )
                    : _DocumentCard(state: state),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Back, the filename over its page marker, and share.
///
/// The filename is the only title on the screen — there is no second headline
/// under it, because the document has its own and repeating it would be the
/// screen saying the same thing twice in two type sizes.
class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({required this.memory, required this.pageLabel});

  final Memory? memory;
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        CircleButton(
          icon: HawkIcons.chevronLeft,
          semanticLabel: 'Back to your library',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/library'),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                memory?.displayTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  letterSpacing: -0.3,
                  color: p.textPrimary,
                ),
              ),
              if (pageLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                MetaText(pageLabel),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        if (memory != null)
          CircleButton(
            icon: HawkIcons.share,
            semanticLabel: 'Share ${memory!.displayTitle}',
            onPressed: () => shareOriginal(MemoryRow.originalOf(memory!)),
          ),
      ],
    );
  }
}

/// The document, on paper.
///
/// Its own stateful widget because a [PageController] has to be owned
/// somewhere, and the cubit is the wrong place: which page is showing is a
/// gesture in progress, not application state that anything else reads. The
/// cubit is told afterwards so the header can print the number.
/// The document, as a page in a mount — screen 1M, redesigned.
///
/// **This is a page, not a card.** The earlier build showed the extracted
/// text on the design system's own white card, which made a PDF look like
/// every other surface in the app. The design now mounts a *sheet of paper*
/// in a grey surround: serif, justified, with a running head and a page
/// number, and the matched sentence struck through in accent. The point is
/// recognition — you should see the document you remember, and see where in
/// it the answer lives, before you read a word.
///
/// What is on the paper is still the **extracted text**, not a render of the
/// original: see [FileViewerCubit]. So the running head reports what the
/// index knows — the type and where it came from — where the design's mock
/// shows a confidential stamp it read off a real PDF.
class _DocumentCard extends StatefulWidget {
  const _DocumentCard({required this.state});

  final FileViewerState state;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  late final PageController _controller = PageController(
    initialPage: widget.state.page,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The passage worth marking on this page.
  ///
  /// The model's summary is the only thing the index holds that is *about* a
  /// specific part of the document — but a summary is not a quote, so it is
  /// only ever highlighted where it genuinely occurs in the text. Where it
  /// does not, it stays the separate block it has always been, because
  /// painting an accent over a sentence the document does not contain would
  /// be the screen inventing a citation.
  String? _matchIn(String page) {
    final summary = widget.state.memory?.description?.trim();
    if (summary == null || summary.isEmpty) return null;
    return page.contains(summary) ? summary : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = widget.state;

    return Column(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              // The mount. A step above the ground so the paper reads as
              // resting *in* something rather than floating on the screen.
              color: p.border,
              borderRadius: BorderRadius.circular(AppRadius.code),
            ),
            child: Center(
              child: ConstrainedBox(
                // 262px in the design — a measure, not a breakpoint. Wider
                // than this and justified 9.5px serif starts to comb.
                constraints: const BoxConstraints(maxWidth: 262),
                // Screen 2I. The kind of memory decides the body, and it
                // has to be asked *before* "is there text", not after.
                //
                // The first cut of this branched on `pages.isEmpty`, which
                // got the empty photo right and the interesting one exactly
                // wrong: a whiteboard with OCR text has pages, so it showed
                // the transcription and never the picture — on a screen
                // whose entire subject is the picture. 2I wants both, in
                // that order, and the text is captioned as what it is:
                // something Hawk read *out of* the image, not the document.
                // Photos never reach here — they get [_ImageViewer], 2I's own
                // screen, rather than a picture pasted onto a page.
                child: state.pages.isEmpty
                    ? _Paper(
                        memory: state.memory,
                        pageNumber: 1,
                        pageCount: 1,
                        child: _NothingExtracted(memory: state.memory),
                      )
                    : PageView.builder(
                        controller: _controller,
                        itemCount: state.pages.length,
                        onPageChanged: context.read<FileViewerCubit>().showPage,
                        itemBuilder: (context, index) => _Paper(
                          memory: state.memory,
                          pageNumber: index + 1,
                          pageCount: state.pages.length,
                          child: _PageBody(
                            text: state.pages[index],
                            title: index == 0
                                ? state.memory?.displayTitle
                                : null,
                            highlight: _matchIn(state.pages[index]),
                            // Only where it is not already struck into the
                            // prose above.
                            summary:
                                _matchIn(state.pages[index]) == null &&
                                    index == 0
                                ? state.memory?.description?.trim()
                                : null,
                            footnote: index == state.pages.length - 1
                                ? state.memory?.indexNote
                                : null,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md - 2),
        _Filmstrip(
          count: state.pageCount,
          current: state.page,
          matchOn: state.pages.isEmpty
              ? null
              : state.pages.indexWhere((page) => _matchIn(page) != null),
          onSelect: (index) => _controller.animateToPage(
            index,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }
}

/// One sheet: the running head, then whatever is on it.
class _Paper extends StatelessWidget {
  const _Paper({
    required this.memory,
    required this.pageNumber,
    required this.pageCount,
    required this.child,
  });

  final Memory? memory;
  final int pageNumber;
  final int pageCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Container(
      width: double.infinity,
      color: paper.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The running head. Set in the interface font on purpose — it is
          // the only thing on the sheet that is ours rather than the
          // document's, and the design keeps that distinction in the type.
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _provenance(memory).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.meta.copyWith(
                      fontFamily: AppTypography.sans,
                      fontSize: 7.5,
                      letterSpacing: 7.5 * 0.14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF555555),
                    ),
                  ),
                ),
                Text(
                  '$pageNumber / $pageCount',
                  style: AppTypography.footnote.copyWith(
                    fontSize: 7.5,
                    color: const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFC9C9C9)),
          Expanded(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }

  /// `PDF · GOOGLE DRIVE`, or `AUDIO · ON DEVICE`.
  static String _provenance(Memory? memory) {
    if (memory == null) return '';
    final where = switch (memory.source?.provider) {
      StorageProvider.googleDrive => 'Google Drive',
      _ => 'On device',
    };
    return '${memory.type.label} · $where';
  }
}

/// The document's own words, set as a document sets them.
class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.text,
    this.title,
    this.highlight,
    this.summary,
    this.footnote,
  });

  final String text;
  final String? title;

  /// A passage that genuinely occurs in [text], struck in accent.
  final String? highlight;

  /// The model's summary, where it is *not* a quote. Kept as a block.
  final String? summary;

  final String? footnote;

  /// Georgia, then Times, then whatever the platform calls a serif.
  ///
  /// The app bundles no body serif — Instrument Serif is a display face and
  /// combs badly at 9.5px — so this asks the platform for the same stack the
  /// design names. A document should look like a document, and that is the
  /// one place in the product where the interface font would be wrong.
  static const _serif = <String>['Georgia', 'Times New Roman', 'serif'];

  TextStyle get _body => const TextStyle(
    fontFamilyFallback: _serif,
    fontSize: 9.5,
    height: 1.75,
    color: Color(0xFF1A1A1A),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          const SizedBox(height: AppSpacing.inset),
          Text(
            title!,
            style: const TextStyle(
              fontFamilyFallback: _serif,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
        ] else
          const SizedBox(height: AppSpacing.inset),

        // Justified, because the design justifies it and because a document
        // is the one thing in this product that is read rather than scanned.
        Text.rich(
          _spans(text, highlight, p.accent),
          textAlign: TextAlign.justify,
          style: _body,
        ),

        if (summary != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Highlight(text: summary!),
        ],
        if (footnote != null) ...[
          const SizedBox(height: AppSpacing.md),
          _IndexFootnote(note: footnote!),
        ],
      ],
    );
  }

  /// [text], with [mark] wrapped in an accent ground where it occurs.
  ///
  /// One occurrence, the first: a passage highlighted three times down a page
  /// stops reading as *the* match and starts reading as a search result.
  static TextSpan _spans(String text, String? mark, Color accent) {
    if (mark == null || mark.isEmpty) return TextSpan(text: text);
    final at = text.indexOf(mark);
    if (at < 0) return TextSpan(text: text);

    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: mark,
          // A background, not a colour: the words stay black and the paper
          // behind them changes, which is what a highlighter does and what
          // keeps the sentence readable.
          style: TextStyle(backgroundColor: accent),
        ),
        TextSpan(text: text.substring(at + mark.length)),
      ],
    );
  }
}

/// The page strip under the mount, and the MATCH chip beside it.
class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.count,
    required this.current,
    required this.onSelect,
    this.matchOn,
  });

  final int count;
  final int current;
  final ValueChanged<int> onSelect;

  /// Which page carries the highlighted passage, or -1 / null for none.
  final int? matchOn;

  /// Five at most. The strip is an orientation device, not a page list — a
  /// forty-page document would turn it into a grey smear.
  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paper = AppPalette.onPaper;
    final visible = count < _shown ? count : _shown;
    final hasMatch = matchOn != null && matchOn! >= 0;

    return SizedBox(
      height: 50,
      child: Row(
        children: [
          for (var i = 0; i < visible; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 34,
                height: 46,
                decoration: BoxDecoration(
                  // A page you have reached is white; one you have not is
                  // the paper's own dim grey. The strip shows how far in you
                  // are without printing a number nobody asked for.
                  color: i <= current ? paper.surface : paper.divider,
                  borderRadius: BorderRadius.circular(3),
                  border: i == current
                      ? Border.all(color: p.accent, width: 2)
                      : null,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (hasMatch)
            Container(
              height: AppSize.chipSmall,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(AppRadius.round),
              ),
              child: MetaText('Match', color: p.accent, size: 9),
            ),
        ],
      ),
    );
  }
}

/// The accent block inside the white card.
///
/// The only accent on 1M, and it is on paper rather than on the ground — the
/// one place in the design where the accent is a *background* for reading
/// rather than a control. Ink on it is [AppPalette.onAccent], never white:
/// the accent is bright enough that white on it fails contrast at body sizes.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.inset),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(AppRadius.tileLarge),
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          height: 1.6,
          fontWeight: FontWeight.w600,
          fontVariations: const [FontVariation('wght', 600)],
          color: p.onAccent,
        ),
      ),
    );
  }
}

/// Why this document is only partly here, when it is.
///
/// A hairline and a muted line at the foot of the last page — the design's own
/// closing shape. It carries `indexNote`, which is the only thing that tells a
/// half-indexed document from a whole one; without it a user reads to the end
/// of page six and concludes that is the end of the file.
class _IndexFootnote extends StatelessWidget {
  const _IndexFootnote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          color: paper.divider,
        ),
        Text(note, style: AppTypography.bodySmall.copyWith(color: paper.muted)),
      ],
    );
  }
}

/// Screen 2H — the recording, and what was said in it.
///
/// The original plays in the dark card; the transcript sits on the white one
/// below, because the transcript is what the answers were built from and the
/// recording is how somebody checks it.
///
/// Two things the design draws are left out on purpose, not forgotten:
///
/// * **Timestamps.** The index transcribes speech verbatim with no times in
///   it, so a "17:52" beside a line would be invented — and a timestamp is
///   a claim somebody will seek to. The transcript is shown untimed.
/// * **The waveform's shape.** Nothing here decodes amplitudes. Bars of
///   made-up heights would pretend to be this recording's contour, so the
///   scrubber keeps the design's bars at one height and fills them with the
///   accent as it plays.
class _AudioBody extends StatelessWidget {
  const _AudioBody({required this.memory, required this.pages});

  final Memory memory;
  final List<String> pages;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AudioPlayerCubit>(param1: memory),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PlayerCard(),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _Transcript(memory: memory, text: pages.join('\n\n')),
          ),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<AudioPlayerCubit, AudioPlayerState>(
      builder: (context, state) {
        final cubit = context.read<AudioPlayerCubit>();

        if (state.source == AudioSourceState.unavailable) {
          return HawkCard(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Row(
              children: [
                AppIcon(HawkIcons.audio, size: 20, color: p.textMuted),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    state.reason ?? 'Nothing to play here.',
                    style: AppTypography.bodySmall.copyWith(
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final ready = state.source == AudioSourceState.ready;
        return HawkCard(
          padding: const EdgeInsets.all(AppSpacing.card),
          child: Column(
            children: [
              _Scrubber(
                fraction: state.fraction,
                onSeek: ready ? cubit.seekFraction : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text(
                    clockOf(state.position),
                    style: AppTypography.numeralCode.copyWith(
                      color: p.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    state.duration == null ? '--:--' : clockOf(state.duration!),
                    style: AppTypography.numeralCode.copyWith(
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.inset),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkipButton(
                    label: '−15',
                    semantic: 'Back 15 seconds',
                    onTap: ready ? cubit.back : null,
                  ),
                  const SizedBox(width: AppSpacing.card),
                  Semantics(
                    button: true,
                    label: state.playing ? 'Pause' : 'Play',
                    child: GestureDetector(
                      onTap: ready ? cubit.toggle : null,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: ready ? p.accent : p.raised,
                          shape: BoxShape.circle,
                        ),
                        child: ready
                            ? Icon(
                                state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 32,
                                color: p.onAccent,
                              )
                            : Padding(
                                padding: const EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: p.textMuted,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.card),
                  _SkipButton(
                    label: '+15',
                    semantic: 'Forward 15 seconds',
                    onTap: ready ? cubit.forward : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The design's bars, at one height — see [_AudioBody] for why. Tap or drag
/// anywhere along it to seek.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.fraction, required this.onSeek});

  final double fraction;
  final ValueChanged<double>? onSeek;

  static const _bars = 48;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        void seek(Offset at) => onSeek?.call(at.dx / box.maxWidth);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < _bars; i++) ...[
                  if (i > 0) const SizedBox(width: 2.5),
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: (i + 0.5) / _bars <= fraction
                            ? p.accent
                            : p.border,
                        borderRadius: BorderRadius.circular(AppRadius.round),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.semantic, this.onTap});

  final String label;
  final String semantic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.numeralCode.copyWith(
              color: onTap == null ? p.textFaint : p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// What was said, untimed. The paragraph the model's summary was drawn from
/// is marked, the same way the text viewer marks it — and only when that
/// summary genuinely occurs in the words, never as an invented citation.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.memory, required this.text});

  final Memory memory;
  final String text;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final p = context.palette;
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final summary = memory.description?.trim();

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetaText('TRANSCRIPT', color: paper.muted, wide: true),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: paragraphs.isEmpty
                ? Text(
                    memory.indexNote ??
                        'No words were transcribed from this recording.',
                    style: AppTypography.bodySmall.copyWith(color: paper.muted),
                  )
                : ListView.separated(
                    itemCount: paragraphs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) {
                      final line = paragraphs[i];
                      final marked =
                          summary != null &&
                          summary.isNotEmpty &&
                          line.contains(summary);
                      return Text(
                        line,
                        style: AppTypography.bodySmall.copyWith(
                          height: 1.6,
                          fontWeight: marked ? FontWeight.w600 : null,
                          color: marked ? paper.ink : paper.body,
                          backgroundColor: marked ? p.accent : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// "18:20", or "1:04:05" past the hour.
@visibleForTesting
String clockOf(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Screen 2I — IMAGE VIEWER: the photo, at its own shape, on a dark stage.
///
/// **Not a page.** This used to put the picture inside the white paper
/// sheet the document viewer uses, with a running head, "PAGE 1 OF 1", a
/// filmstrip of one blank thumbnail and "Nothing readable in this file"
/// under a waterfall. A photo is not a document with a picture in it; the
/// picture *is* the content, so it gets the whole stage, sized by its own
/// ratio — portrait tall, panorama wide — and nothing is drawn around it.
///
/// Text read out of the image still matters — it is why a whiteboard photo
/// came back for a question about pricing — so it follows in its own card,
/// captioned as what it is. A photo with no text gets no card at all,
/// rather than a line apologising for a beach.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.memory, required this.text});

  final Memory memory;
  final String text;

  /// 2I's stage: a step below the cards, so the photo sits in it.
  static const _stage = Color(0xFF17191A);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final read = text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _stage,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(child: _OriginalImage(memory: memory)),
          ),
        ),
        if (read.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.group),
          HawkCard(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: ConstrainedBox(
              // A long transcription scrolls in its card rather than
              // squeezing the photo out of the screen.
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MetaText('Text read from this image'),
                    const SizedBox(height: 10),
                    Text(
                      read,
                      style: AppTypography.bodySmall.copyWith(
                        height: 1.6,
                        color: p.textBright,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The original itself, for a memory whose content is the picture.
///
/// Resolved once and held, not rebuilt: `OriginalAccess.resolve` may fetch
/// from the vault, and a `FutureBuilder` given a fresh future on every build
/// would re-download the file each frame.
///
/// Failure is not an error screen. A photo whose original this phone cannot
/// reach is still a real memory with a real row above it, so it falls back to
/// the same explanation any unreadable file gets, and the actions underneath
/// keep working.
class _OriginalImage extends StatefulWidget {
  const _OriginalImage({required this.memory});

  final Memory memory;

  @override
  State<_OriginalImage> createState() => _OriginalImageState();
}

class _OriginalImageState extends State<_OriginalImage> {
  late final Future<OriginalHandle> _handle = _resolve();

  Future<OriginalHandle> _resolve() async {
    final access = getIt<OriginalAccess>();
    final ref = MemoryRow.originalOf(widget.memory);
    final handle = await access.resolve(
      memoryId: ref.memoryId,
      url: ref.url,
      storagePath: ref.storagePath,
      filename: ref.title,
    );
    // A vault file has to be on disk before it can be decoded. On the phone
    // that took the photo this is already true and costs nothing.
    if (handle is OriginalInVault) {
      return access.materialise(handle, ref.memoryId);
    }
    return handle;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OriginalHandle>(
      future: _handle,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ImagePending();
        }

        final provider = switch (snap.data) {
          OriginalOnDevice(:final file) => FileImage(file),
          OriginalAtUrl(:final uri) => NetworkImage(uri.toString()),
          _ => null,
        };
        if (provider == null) return const _NoPicture();

        // No `fit` and no size: the image lays itself out at its own
        // ratio, scaled down to the stage — so the rounding lands on the
        // picture's corners, not on an invisible letterbox around it.
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image(
            image: provider as ImageProvider<Object>,
            // A decode that fails — a truncated download, a format this
            // phone has no decoder for — says so rather than breaking.
            errorBuilder: (context, _, _) => const _NoPicture(),
            frameBuilder: (context, child, frame, wasSync) =>
                frame == null && !wasSync ? const _ImagePending() : child,
          ),
        );
      },
    );
  }
}

/// The photo could not be shown on this phone — not on it, not reachable,
/// or not decodable. Said on the dark stage, where the paper's ink would be
/// unreadable; the actions below still work.
class _NoPicture extends StatelessWidget {
  const _NoPicture();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Text(
        'This photo is not on this phone. Open it in its own app to see '
        'the original.',
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: p.textMuted),
      ),
    );
  }
}

/// The paper's own height while the original is being fetched, so the card
/// does not collapse and then jump when the picture lands.
class _ImagePending extends StatelessWidget {
  const _ImagePending();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 180,
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

/// A file Hawk holds but could not read.
///
/// Not an error state. A blank scan, a type with no extraction route and a
/// document that crossed the plan's budget all land here, and in every case
/// the memory is real and the original is fine — so the screen explains
/// rather than apologises, and leaves both actions below it working.
class _NothingExtracted extends StatelessWidget {
  const _NothingExtracted({required this.memory});

  final Memory? memory;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final note = memory?.indexNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          note ?? 'There is no readable text in this file.',
          style: AppTypography.bodySmall.copyWith(color: paper.body),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Open it in its own app to see the original.',
          style: AppTypography.bodySmall.copyWith(color: paper.muted),
        ),
      ],
    );
  }
}

class _DocumentPlaceholder extends StatelessWidget {
  const _DocumentPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.cardDim,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}

/// The two things you can do with a file you are looking at.
///
/// Open is the secondary pill and remove is a circle, which is the design
/// stating the ratio: one of these is what you came for and the other is a
/// once-in-a-while. The trash is the only red on the screen.
class _ViewerActions extends StatelessWidget {
  const _ViewerActions({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PillButton(
            label: 'Open in app',
            tone: PillTone.secondary,
            // Leading, as the design draws it. The side carries meaning: a
            // trailing arrow means *onward*, a leading glyph labels what the
            // button is. This one is not navigation, it is a handoff.
            leadingIcon: HawkIcons.download,
            height: AppSize.buttonMedium,
            onPressed: () => openOriginal(MemoryRow.originalOf(memory)),
          ),
        ),
        const SizedBox(width: AppSpacing.gap),
        _RemoveButton(memory: memory),
      ],
    );
  }
}

/// The trash circle.
///
/// A local widget because `CircleButton` paints its glyph in either
/// [AppPalette.textPrimary] or [AppPalette.onAccent], and this one is a card
/// fill with a *danger* glyph — the combination the design uses here and
/// nowhere else. `CircleButton` wants an `iconColor`; until it has one, this
/// is the honest way to draw it rather than tinting the whole circle red,
/// which would make the most destructive control on the screen the most eye-
/// catching thing on it.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      label: 'Remove ${memory.displayTitle} from your index',
      child: Material(
        color: p.card,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _confirm(context),
          child: SizedBox(
            width: AppSize.buttonMedium,
            height: AppSize.buttonMedium,
            child: Center(
              child: AppIcon(
                HawkIcons.trash,
                size: 20,
                color: p.danger,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Asked, not assumed — see [RemoveFromIndexSheet], which is the sheet.
  void _confirm(BuildContext context) {
    RemoveFromIndexSheet.show(
      context,
      title: memory.displayTitle,
      onRemove: () {
        // Hidden now, deleted in five seconds unless Undo — the undo
        // snack's ring is the countdown (2E).
        getIt<PendingRemovals>().remove(memory.id);
        context.popOrGo(LibraryPage.routeName);
      },
    );
  }
}

const _months = [
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

/// "24 Aug". From a table, not `DateFormat`, which the app never
/// initialises and which throws without it.
String _shortDay(DateTime at) {
  final local = at.toLocal();
  return '${local.day} ${_months[local.month - 1]}';
}
