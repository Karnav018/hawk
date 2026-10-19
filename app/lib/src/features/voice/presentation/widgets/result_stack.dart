import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/files/original_actions.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../chat/presentation/widgets/result_file.dart';

/// The card stack on screen 1O — the files behind a spoken answer.
///
/// **A stack rather than a list, and the difference is the claim it makes.**
/// A list of three files says "here are three results, you sort it out". A
/// stack with one card face up says "this one, and there are two others if I
/// am wrong". The design is confident enough to put a single file in front at
/// full size, which is only honest if getting to the other two is trivial —
/// hence the drag, and hence the drag being real rather than a decoration
/// under a static illustration.
///
/// The two cards behind are deliberately *not* rendered with content. They
/// are the shape of what is underneath, at the two dark surfaces the palette
/// steps through, and giving them titles would turn one confident answer back
/// into a list of three.
class ResultStack extends StatefulWidget {
  const ResultStack({required this.files, super.key});

  final List<ResultFile> files;

  @override
  State<ResultStack> createState() => _ResultStackState();
}

class _ResultStackState extends State<ResultStack>
    with SingleTickerProviderStateMixin {
  /// Built in `initState`, not as a `late final` field.
  ///
  /// The lazy form looks tidier and is a trap here: a stack with no files
  /// returns early from `build` and never touches the controller, so `dispose`
  /// becomes its first access — and constructing a ticker while the element is
  /// being unmounted asserts. A widget must not create anything in `dispose`.
  late final AnimationController _settle;

  /// Where the front card currently sits, in logical pixels below its rest
  /// position. Only ever positive: the chevron points down, so the gesture is
  /// down, and a card that could also be flung upwards would be a second
  /// gesture the screen never taught.
  double _drag = 0;

  /// The tween the release animates along. Replaced on every gesture end, so
  /// a spring-back and a dismissal are the same mechanism with different
  /// targets rather than two code paths that can disagree.
  Animation<double> _glide = const AlwaysStoppedAnimation(0);

  int _top = 0;

  /// How far down counts as "I want the next one".
  static const _threshold = 96.0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// The deck changes under the stack. The matches land first; the answer
  /// then replaces them with only the files it cited — usually fewer, and in
  /// the server's order. An index into the old deck means nothing in the new
  /// one, and past its end it was a crash: swipe to the second card while
  /// the answer is still being read, and it landed with `files[1]` of a
  /// one-file list. So the stack follows the *file*: the card that was on
  /// top stays on top if the new deck still has it, and otherwise the new
  /// deck opens at its first card, as a fresh answer should.
  @override
  void didUpdateWidget(ResultStack old) {
    super.didUpdateWidget(old);
    if (listEquals(old.files, widget.files)) return;
    final was = _top < old.files.length ? old.files[_top].memoryId : null;
    final next = widget.files.indexWhere((f) => f.memoryId == was);
    _top = next < 0 ? 0 : next;
    // A gesture in progress was on the old deck.
    _drag = 0;
  }

  double get _offset => _settle.isAnimating ? _glide.value : _drag;

  void _advance() {
    if (widget.files.length < 2) return;
    setState(() => _top = (_top + 1) % widget.files.length);
  }

  void _release(double travel, double velocity) {
    final cycles = widget.files.length > 1;
    final dismissed = cycles && (_drag > _threshold || velocity > 700);

    _glide = Tween<double>(begin: _drag, end: dismissed ? travel : 0).animate(
      CurvedAnimation(
        parent: _settle,
        // Out fast, back gently. A card being dismissed is following the
        // hand; a card springing back is correcting itself, and the two
        // should not feel the same.
        curve: dismissed ? Curves.easeInCubic : Curves.easeOutBack,
      ),
    );

    _settle.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        // The deck may have changed while the card was in flight, and an
        // empty one has no next card — `% 0` would throw.
        final count = widget.files.length;
        if (dismissed && count > 0) _top = (_top + 1) % count;
        _drag = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final files = widget.files;
    if (files.isEmpty) return const SizedBox.shrink();

    final hasMore = files.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The distance a dismissed card travels before the next one is face
        // up: its own height plus the hint row, so it is genuinely gone
        // rather than parked at the bottom of the screen.
        final travel = constraints.maxHeight;

        return Stack(
          children: [
            // The two behind. Insets straight from the design: 18/26/36 for
            // the deepest, 9/13/24 for the middle, so the stack reads as
            // perspective rather than as three cards at three sizes.
            if (files.length > 2)
              Positioned(
                left: 18,
                right: 18,
                top: 26,
                bottom: 36,
                child: _Peek(color: p.card),
              ),
            if (hasMore)
              Positioned(
                left: 9,
                right: 9,
                top: 13,
                bottom: 24,
                child: _Peek(color: p.raised),
              ),

            AnimatedBuilder(
              animation: _settle,
              builder: (context, child) => Positioned(
                left: 0,
                right: 0,
                top: _offset,
                // 46 of clearance under the card for the drag hint.
                bottom: 46 - _offset,
                child: Opacity(
                  // Fades as it leaves, so the card underneath is arriving
                  // rather than being uncovered.
                  opacity: (1 - (_offset / (travel * 0.7))).clamp(0.0, 1.0),
                  child: child!,
                ),
              ),
              child: GestureDetector(
                onVerticalDragUpdate: hasMore
                    ? (details) => setState(
                        () => _drag = (_drag + details.delta.dy).clamp(
                          0.0,
                          travel,
                        ),
                      )
                    : null,
                onVerticalDragEnd: hasMore
                    ? (details) =>
                          _release(travel, details.velocity.pixelsPerSecond.dy)
                    : null,
                child: _FrontCard(
                  file: files[_top],
                  position: _top + 1,
                  total: files.length,
                ),
              ),
            ),

            if (hasMore)
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Semantics(
                  button: true,
                  label: 'Show the next file',
                  child: GestureDetector(
                    // Tappable as well as draggable. A drag is the gesture
                    // the design teaches, but it is also the one gesture a
                    // switch-control or a shaky hand cannot produce, and
                    // "there are two more files" must not be unreachable.
                    onTap: _advance,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          HawkIcons.chevronDown,
                          size: 15,
                          color: p.textFaint,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        MetaText(
                          'Drag for the other ${_words(files.length - 1)}',
                          wide: true,
                          color: p.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// "the other two". Spelled, because the line is prose set in mono caps and
  /// a numeral in it would read as a count the user has to reconcile with the
  /// `1 / 3` chip above.
  static String _words(int count) => switch (count) {
    1 => 'one',
    2 => 'two',
    3 => 'three',
    4 => 'four',
    _ => '$count',
  };
}

/// A card underneath: the shape, and nothing else.
class _Peek extends StatelessWidget {
  const _Peek({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
  );
}

/// The file at the front — the one accented surface on screen 1O.
///
/// The accent goes here rather than on the answer above it, which is the
/// design's sharpest decision on this screen. The white card says *this is
/// what you asked*; the accent card says *this is what to press*. Reversing
/// them would make the sentence a button and the file a footnote.
class _FrontCard extends StatelessWidget {
  const _FrontCard({
    required this.file,
    required this.position,
    required this.total,
  });

  final ResultFile file;
  final int position;
  final int total;

  OriginalRef get _original => (
    memoryId: file.memoryId,
    title: file.title,
    url: file.url,
    storagePath: file.storagePath,
    fallback: fileLine(file),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final where = whereItLives(file);

    return HawkCard(
      tone: CardTone.accent,
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ink tile with an accent glyph — the accent card inverted, so
              // the icon reads as a hole punched in the card rather than as a
              // second element sitting on it.
              IconTile(
                icon: hawkIconForMemory(file.type),
                size: 48,
                radius: AppRadius.tileLarge,
                background: p.onAccent,
                foreground: p.accent,
                strokeWidth: 1.9,
              ),
              const Spacer(),
              _PositionChip(position: position, total: total),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            file.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.display26.copyWith(color: p.onAccent),
          ),
          const SizedBox(height: AppSpacing.sm + 2),

          // Two lines, and only two: what the file is, and where it lives.
          // The score, the excerpt and the "indexed from" line that v2 put
          // here are all gone — they described the search, not the file.
          Text(
            [fileLine(file), ?where].join('\n'),
            style: AppTypography.meta11.copyWith(
              // .72 on the design's own markup: metadata on a bright card
              // needs to recede or it competes with the title for the same
              // ink.
              color: p.onAccent.withValues(alpha: 0.72),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          _OpenFileButton(onPressed: () => openOriginal(_original)),
        ],
      ),
    );
  }
}

/// "1 / 3" — where you are in the stack.
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      height: AppSize.chipSmall,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.onAccent,
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: MetaText('$position / $total', color: p.textPrimary),
    );
  }
}

/// The card's own action, in ink on the accent.
class _OpenFileButton extends StatelessWidget {
  const _OpenFileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      label: 'Open file',
      child: Material(
        color: p.onAccent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: AppSize.buttonMedium,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Open file',
                  style: AppTypography.button.copyWith(color: p.textPrimary),
                ),
                const SizedBox(width: AppSpacing.gap + 1),
                // The arrow is accent: it is the one part of the button that
                // says *this leaves the app*, and it borrows the card it sits
                // on to say it.
                AppIcon(HawkIcons.arrowUpRight, size: 18, color: p.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
