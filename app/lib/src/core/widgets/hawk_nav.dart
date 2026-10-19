import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'app_icons.dart';
import 'hawk_icons.dart';

/// The three destinations. Order is the design's, left to right.
enum HawkTab {
  /// Whatever "asking" means for this user — the orb, or the chat thread.
  home(HawkIcons.navHome, 'Home', '/'),

  /// Everything kept, and everything that adds to it.
  library(HawkIcons.navLibrary, 'Library', '/library'),

  /// The account, and the Vault inside it. Labelled "You" in the design; the
  /// path stays `/profile`, which is what the screen has always been called
  /// and what every existing link to it says.
  you(HawkIcons.navYou, 'You', '/profile');

  const HawkTab(this.icon, this.label, this.path);

  final String icon;
  final String label;
  final String path;
}

/// The bottom navigation pill.
///
/// **Three tabs, and storage is not one of them.** v2 floated a dock of
/// capture · voice · storage, which put a setup screen next to the two things
/// people actually do all day. v3 moves capture into Library (the six tiles
/// at the top of it) and storage into the profile, leaving a nav that answers
/// one question: are you asking, browsing, or managing yourself.
///
/// The selected tab is a **raised circle**, not an accent one. The accent is
/// spent on the primary action of whatever screen you are on; a permanently
/// accented nav item would mean every screen already had one.
/// How long the selected circle takes to travel between tabs.
///
/// Short enough that a double-tap across the bar still feels direct, long
/// enough to read as one object moving rather than as a redraw. Matches the
/// sheet transition, so the product has one sense of pace.
const Duration _travel = Duration(milliseconds: 240);

class HawkNav extends StatelessWidget {
  const HawkNav({required this.current, required this.onSelect, super.key});

  final HawkTab current;
  final ValueChanged<HawkTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Reduce motion means no motion. A nav that slides is the kind of
    // incidental movement the setting exists to switch off, and unlike a
    // launch animation it happens on every single navigation.
    final duration = (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : _travel;

    return Container(
      height: AppSize.nav,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      // One circle that travels, rather than three that change state.
      //
      // Painting the selection on each item and animating its colour would
      // read as three separate things switching on and off — and v3's whole
      // depth vocabulary is that a surface *is* somewhere, not that it lights
      // up. Moving one raised circle says "you are here now" with the same
      // grammar the rest of the product uses.
      //
      // A LayoutBuilder rather than `Alignment`, because the slot centres are
      // thirds of the available width and mapping those onto Align's -1..1
      // range is a width-dependent expression that is wrong the moment the
      // padding changes. Pixels are what this actually is.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / HawkTab.values.length;
          final inset = (slot - AppSize.navItem) / 2;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: slot * current.index + inset,
                // Measured, not derived from the bar's height: the padding
                // above is horizontal today, and a vertical one added later
                // would silently shift the circle off centre.
                top: (constraints.maxHeight - AppSize.navItem) / 2,
                width: AppSize.navItem,
                height: AppSize.navItem,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.raised,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Row(
                // Equal thirds, so the travelling circle's arithmetic above
                // and the tap targets below describe the same geometry.
                children: [
                  for (final tab in HawkTab.values)
                    Expanded(
                      child: _NavItem(
                        tab: tab,
                        isCurrent: tab == current,
                        duration: duration,
                        // Tapping the tab you are on is a no-op rather than a
                        // second copy of the screen you are looking at.
                        onTap: tab == current ? null : () => onSelect(tab),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.isCurrent,
    required this.duration,
    this.onTap,
  });

  final HawkTab tab;
  final bool isCurrent;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: tab.label,
      child: GestureDetector(
        onTap: onTap,
        // Opaque so the whole third is the target, not just the glyph. The
        // circle is 46px; the slot is a third of the bar, and there is no
        // reason to make somebody aim.
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: SizedBox(
            width: AppSize.navItem,
            height: AppSize.navItem,
            child: Center(
              // Two glyphs cross-fading, not one glyph changing colour.
              //
              // `AppIcon` rasterises SVG, so animating its colour would
              // re-render the drawing on every frame of every navigation.
              // Two static rasters and an opacity are effectively free, and
              // the fade is what keeps the icon from snapping bright a beat
              // before the circle arrives under it.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: duration,
                    curve: Curves.easeOut,
                    opacity: isCurrent ? 0 : 1,
                    child: AppIcon(tab.icon, size: 20, color: p.textFaint),
                  ),
                  AnimatedOpacity(
                    duration: duration,
                    curve: Curves.easeOut,
                    opacity: isCurrent ? 1 : 0,
                    child: AppIcon(tab.icon, size: 20, color: p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
