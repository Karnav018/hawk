import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

/// A file name short enough to sit inside a sentence.
///
/// Cut from the middle, never the end: the extension and the last few
/// characters are what tell two exports of the same form apart, and a name
/// like "College FeesFor…_order_SsihXiQXNYHBds.pdf" is otherwise three lines
/// of body copy.
@visibleForTesting
String shortTitle(String title, {int max = 40}) {
  if (title.length <= max) return title;
  const tail = 12;
  final head = title.substring(0, max - tail - 1).trimRight();
  return '$head…${title.substring(title.length - tail)}';
}

/// "Remove from your index?" — the one confirmation on the file viewer.
///
/// Asked, not assumed. The app's standing promise is that nothing goes
/// without a confirmation (1G says so in as many words), and this is the one
/// screen where a mis-tap removes something. The sheet's job is mostly to say
/// what is *not* being deleted — the file — because that is the fear, and it
/// is unfounded.
///
/// Its own widget so the layout can be pumped at phone width in a test.
/// That is how "Keep it" breaking after every syllable was caught: the two
/// pills were `Expanded` 1 : 14, which gave the quiet one a fifteenth of the
/// row.
class RemoveFromIndexSheet extends StatelessWidget {
  const RemoveFromIndexSheet({
    required this.title,
    required this.onKeep,
    required this.onRemove,
    super.key,
  });

  final String title;
  final VoidCallback onKeep;
  final VoidCallback onRemove;

  /// Shows the sheet over [context]. [onRemove] runs after it has closed.
  ///
  /// `showModalBottomSheet` rather than a route: `SheetScaffold` is a route
  /// shape, and a route for a yes/no is a route the router has to know about.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required VoidCallback onRemove,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.palette.ground.withValues(alpha: 0.75),
    builder: (sheetContext) => RemoveFromIndexSheet(
      title: title,
      onKeep: () => Navigator.of(sheetContext).pop(),
      onRemove: () {
        Navigator.of(sheetContext).pop();
        onRemove();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: paper.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.card,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: paper.handle,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.card),
            Text(
              'Remove from\nyour index?',
              style: AppTypography.display24.copyWith(color: paper.ink),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Hawk forgets what it learned from ${shortTitle(title)}. '
              'The file itself is not touched.',
              style: AppTypography.bodyMedium.copyWith(color: paper.muted),
            ),
            const SizedBox(height: AppSpacing.card),
            Row(
              children: [
                // The quiet way out is narrower than the action, not
                // vanishing: 5 : 7, so both labels sit on one line.
                Expanded(
                  flex: 5,
                  child: _PaperAction(label: 'Keep it', onPressed: onKeep),
                ),
                const SizedBox(width: AppSpacing.md - 2),
                Expanded(
                  flex: 7,
                  child: _PaperAction(
                    label: 'Remove',
                    isDanger: true,
                    onPressed: onRemove,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A button on paper. The destructive one is red ink on its own tinted bed,
/// never a red fill — a filled red button is the easiest thing on a screen
/// to press by accident.
///
/// The red is [PaperInk.danger], not [AppPalette.danger]: #ff6a5a is tuned to
/// glow on #0c0c0d and fails contrast on white at button size.
class _PaperAction extends StatelessWidget {
  const _PaperAction({
    required this.label,
    required this.onPressed,
    this.isDanger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: isDanger ? paper.dangerWash : paper.chip,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: AppSize.buttonSmall,
            child: Center(
              child: Text(
                label,
                // A pill label never wraps; if it cannot fit, that is a
                // layout bug to see, not a word to break.
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  color: isDanger ? paper.danger : paper.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
