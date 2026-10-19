import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme.dart';
import 'ambient_background.dart';

/// Standard screen chrome: ambient ground, 56/20/34 padding, correct status
/// bar styling.
///
/// The design draws every screen inside a 402×874 frame with that exact
/// padding, so encoding it once here keeps screens from re-deriving it.
///
/// [footer] is how the design's `margin-top:auto` blocks are expressed: the
/// body scrolls in the space that is left, the footer stays pinned to the
/// bottom. That split is deliberate — the obvious alternative
/// (`SingleChildScrollView` + `ConstrainedBox(minHeight:)` + `IntrinsicHeight`
/// + `Spacer`) silently mis-measures, because `IntrinsicHeight` asks children
/// for their height at the *outer* width and `ConstrainedBox`/`SizedBox` do not
/// narrow that width for their child. Any width-capped paragraph then reports
/// a one-line height, the column is sized short, and the content overflows.
/// Splitting body and footer avoids intrinsics entirely.
class AppScreen extends StatelessWidget {
  const AppScreen({
    required this.child,
    this.footer,
    this.ambientOpacity = 0,
    this.padding,
    this.scrollable = true,
    this.safeArea = false,
    this.bottomBar,
    super.key,
  });

  final Widget child;

  /// Pinned to the bottom of the screen, outside the scroll area.
  final Widget? footer;

  /// The space between the body's end and the footer's top. Named so a
  /// screen that floats something over that seam — home's camera — can
  /// measure from it rather than guess.
  static const footerGap = AppSpacing.block;

  /// No longer has any effect: v3 draws no wash, and [AmbientBackground] is a
  /// flat ground. Kept so existing call sites compile unchanged.
  final double ambientOpacity;

  final EdgeInsets? padding;

  final bool scrollable;

  /// Use the real device insets instead of the design's fixed 56/34.
  final bool safeArea;

  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pad =
        padding ??
        const EdgeInsets.fromLTRB(
          AppSpacing.screenSide,
          AppSpacing.screenTop,
          AppSpacing.screenSide,
          AppSpacing.screenBottom,
        );

    final bodyPadding = footer == null ? pad : pad.copyWith(bottom: footerGap);

    Widget body = scrollable
        ? SingleChildScrollView(padding: bodyPadding, child: child)
        : Padding(padding: bodyPadding, child: child);

    Widget content = footer == null
        ? body
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  pad.left,
                  0,
                  pad.right,
                  pad.bottom,
                ),
                child: footer,
              ),
            ],
          );

    if (safeArea) content = SafeArea(child: content);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(p),
      child: Scaffold(
        backgroundColor: p.ground,
        extendBody: true,
        bottomNavigationBar: bottomBar,
        body: AmbientBackground(opacity: ambientOpacity, child: content),
      ),
    );
  }
}
