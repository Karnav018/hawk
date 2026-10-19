import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';

/// A panel on a hairline — the single container primitive in the design.
///
/// Dark: translucent white fill over the ambient wash. Light: solid white with
/// a 1px hairline and a 1px shadow. One widget, both behaviours, because the
/// tokens carry the difference.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.panel),
    this.radius = AppRadius.panel,
    this.subtle = false,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Uses the quieter fill (`panelSubtle`) — for inert rows and secondary
  /// buttons.
  final bool subtle;

  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final border = BorderRadius.circular(radius);

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? (subtle ? p.panelSubtle : p.panel),
        borderRadius: border,
        border: Border.all(color: borderColor ?? p.hairline),
        boxShadow: p.isDark
            ? null
            : [
                BoxShadow(
                  color: p.panelShadow,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: border, onTap: onTap, child: decorated),
    );
  }
}
