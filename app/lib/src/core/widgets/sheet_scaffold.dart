import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';

/// A white sheet over a dimmed screen — the design's modal shape.
///
/// A **route**, not a `showModalBottomSheet`. The design's sheets are steps in
/// a run: they have a back stack, a guard can redirect to one, and a deep link
/// can land on one. A sheet presented imperatively is none of those things,
/// and the cubit each one needs would have to be provided at the call site
/// rather than by the router.
///
/// The screen behind stays visible at a quarter strength rather than going
/// black. What is behind a sheet is the thing it is asking about, and dimming
/// it to nothing turns a question into an interruption.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    required this.headline,
    required this.children,
    this.footnote,
    super.key,
  });

  /// Set in 24px heavy ink. Newlines are the design's own line breaks.
  final String headline;

  /// The sheet's body, stacked. Padding and the handle are handled here.
  final List<Widget> children;

  /// A last line under everything, in muted ink.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paper = AppPalette.onPaper;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(p),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The route is transparent so the screen it was pushed from shows
        // through — that is what makes this a sheet rather than a page that
        // happens to be white at the bottom.
        body: Column(
          children: [
            Expanded(
              child: GestureDetector(
                // Tapping the dimmed area dismisses, the way every sheet on
                // both platforms does.
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: ColoredBox(
                  color: p.ground.withValues(alpha: 0.75),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Container(
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
                      headline,
                      style: AppTypography.display24.copyWith(color: paper.ink),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ...children,
                    if (footnote != null) ...[
                      const SizedBox(height: AppSpacing.inset),
                      Text(
                        footnote!,
                        style: AppTypography.footnote.copyWith(
                          color: paper.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
