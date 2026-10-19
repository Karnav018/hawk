import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'app_icons.dart';

/// The button that anchors either end of a screen header.
///
/// Two treatments:
///
/// * **Filled** (default) — the design's 38×38 rounded square on a hairline.
///   Used where the control is one of several and needs to read as a control:
///   search, sort, the theme switch.
/// * **Ghost** ([HeaderIconButton.ghost]) — the mark alone, no fill and no
///   border. Used for back, where there is only one control and a filled box
///   competes with the headline directly beneath it.
///
/// Ghost keeps the same 38×38 *visual* footprint for alignment but expands its
/// hit area to 44pt, Apple's minimum. A borderless control that is also small
/// is a control people miss.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    super.key,
  }) : svg = null,
       ghost = false;

  /// Draws one of the design's own [AppIcons] paths instead of a Material
  /// glyph — used wherever the design ships a specific mark.
  const HeaderIconButton.svg({
    required String this.svg,
    this.onPressed,
    this.tooltip,
    super.key,
  }) : icon = null,
       ghost = false;

  /// Borderless: the mark alone, with a 44pt tap target.
  const HeaderIconButton.ghost({
    required String this.svg,
    this.onPressed,
    this.tooltip,
    super.key,
  }) : icon = null,
       ghost = true;

  final IconData? icon;
  final String? svg;
  final bool ghost;
  final VoidCallback? onPressed;
  final String? tooltip;

  static const size = AppSize.headerButton;

  /// Grows the hit area from 38 to 44pt without moving anything.
  static const _ghostPadding = 3.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppRadius.iconButton);

    final mark = svg != null
        ? Center(
            child: AppIcon(svg!, size: ghost ? 20 : 18, color: p.textPrimary),
          )
        : Icon(icon, size: 18, color: p.textPrimary);

    final Widget button = ghost
        ? SizedBox(
            // 38 wide keeps the header's optical alignment with the filled
            // buttons on other screens; the ripple is circular because there
            // is no box for it to fill.
            width: size,
            height: size,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                // Restores Apple's 44pt minimum without changing the layout.
                child: Padding(
                  padding: const EdgeInsets.all(_ghostPadding),
                  child: mark,
                ),
              ),
            ),
          )
        : SizedBox(
            width: size,
            height: size,
            child: Material(
              color: p.panel,
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: onPressed,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: p.hairline),
                  ),
                  child: mark,
                ),
              ),
            ),
          );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Invisible spacer that keeps a header title optically centred when only one
/// side has a button.
class HeaderIconPlaceholder extends StatelessWidget {
  const HeaderIconPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: HeaderIconButton.size,
    height: HeaderIconButton.size,
  );
}
