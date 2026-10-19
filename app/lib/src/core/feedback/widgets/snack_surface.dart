import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_typography.dart';

/// The ground under every snack: black, on a hairline, with a soft shadow.
///
/// From `Hawk Snackbars.dc.html`: "black on the ink ground". Pure `#000`
/// rather than the card grey, because the snack drops from the Dynamic
/// Island and has to *be* the island's colour for the two to read as one
/// object. The hairline and the shadow are what lift it off `#0c0c0d`.
class SnackSurface extends StatelessWidget {
  const SnackSurface({
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;

  /// 999 for a one-line capsule; 26 for the two-line detail card — "same
  /// radius family".
  final double radius;
  final EdgeInsets padding;

  static const ground = Color(0xFF000000);
  static const hairline = Color(0xFF1E1F21);

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ground,
        borderRadius: border,
        border: Border.all(color: hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000), // rgba(0,0,0,.45)
            offset: Offset(0, 10),
            blurRadius: 26,
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The filled white pill — the undo snack's action, and the only filled
/// action in the system.
class SnackFilledAction extends StatelessWidget {
  const SnackFilledAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(999);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: p.textPrimary,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTypography.chip.copyWith(
                fontSize: 13,
                height: 1,
                color: p.ground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent text — "Keep", the soft path.
class SnackTextAction extends StatelessWidget {
  const SnackTextAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // The word is 13.5px; the target is the full height of the snack.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Text(
            label,
            style: AppTypography.chip.copyWith(
              fontSize: 13.5,
              height: 1,
              color: p.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line every snack leads with: 14/700, white, one line.
TextStyle snackTitleStyle(BuildContext context) => AppTypography.chip.copyWith(
  fontSize: 14,
  height: 1.3,
  letterSpacing: -0.14,
  color: context.palette.textPrimary,
);

/// The detail snack's second line: 12.5/1.4, the tertiary grey.
TextStyle snackSubtitleStyle(BuildContext context) => AppTypography.footnote
    .copyWith(fontSize: 12.5, height: 1.4, color: context.palette.textTertiary);
