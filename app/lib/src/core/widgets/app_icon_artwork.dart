import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'hawk_mark.dart';

/// Which ground the icon is cut for.
enum IconVariant {
  /// The shipping icon: white disc, accent highlight, on the product's ink.
  dark,

  /// For a light context — a store listing on white, a document.
  light,

  /// Android's adaptive foreground: the same mark as [dark], but the ground
  /// is a separate layer the launcher composites underneath.
  foreground,

  /// Android's themed icon. No ground, and the highlight is a hole rather
  /// than a colour, because the launcher tints this layer flat.
  monochrome,
}

/// The launcher icon, drawn rather than exported.
///
/// Rendering it from the same widget the app uses means the mark on the home
/// screen and the mark inside the app cannot drift apart.
/// `test/tools/generate_app_icons.dart` rasterises this to PNG.
///
/// **This is the v3 mark, not the old sphere.** The icon used to be a render
/// of the voice orb on a navy ground — right when the orb *was* the brand.
/// v3 separates them: the mark is two circles, the orb is a different object
/// that lives inside the app, and the icon is the mark. The design bundle's
/// own `assets/app_icon.png` is still the old sphere and is stale — the v3
/// screens stopped referencing it and draw the mark inline instead.
///
/// Proportions from `Hawk Logo v3.dc.html`, the APP ICON · 1024 → 16 row:
/// a 65px mark on a 112px tile of `#0c0c0d`.
class AppIconArtwork extends StatelessWidget {
  const AppIconArtwork({
    required this.size,
    this.variant = IconVariant.dark,
    this.markRatio = launcherMarkRatio,
    super.key,
  });

  final double size;
  final IconVariant variant;

  /// Mark box as a fraction of the canvas. The visible disc is 3/4 of that
  /// again, since the mark is drawn on a 64-unit grid with a radius of 24.
  final double markRatio;

  /// 65 on 112 — the design sheet's own app-icon tile.
  ///
  /// Kept as the record of what the design draws, but **not** what ships:
  /// see [launcherMarkRatio].
  static const designMarkRatio = 65 / 112;

  /// 96 on 112 — what actually goes on a home screen.
  ///
  /// The design sheet draws its icon row as flat squares on paper, where a
  /// 65/112 mark reads correctly. A real launcher does two things that sheet
  /// cannot: it masks the square to a squircle, eating the corners the mark
  /// was balanced against, and it sets the result beside thirty other icons
  /// whose glyphs fill far more of their tile. At 65/112 the disc is 43% of
  /// the square and reads as a small dot in a large black field.
  ///
  /// At 96/112 the disc is 64% — the proportion a single-glyph mark normally
  /// takes — and still leaves 18% clear on every side, comfortably outside
  /// anything the mask crops.
  static const launcherMarkRatio = 96 / 112;

  /// Android shows only the middle 72dp of a 108dp adaptive layer, so the
  /// mark shrinks to occupy the same fraction of the *visible* icon.
  static const adaptiveMarkRatio = launcherMarkRatio * (72 / 108);

  /// The product's own ground, not the old navy.
  static const darkGround = Color(0xFF0C0C0D);

  /// The design canvas's paper, which the mark is drawn against throughout
  /// the identity document.
  static const lightGround = Color(0xFFECEEE9);

  @override
  Widget build(BuildContext context) {
    final (ground, disc, highlight) = switch (variant) {
      // The shipping icon.
      IconVariant.dark => (darkGround, Colors.white, AppPalette.dark.accent),
      IconVariant.foreground => (
        Colors.transparent,
        Colors.white,
        AppPalette.dark.accent,
      ),
      // On paper the highlight is the ground colour, so it reads as a hole
      // rather than as a second dot.
      IconVariant.light => (lightGround, const Color(0xFF101010), lightGround),
      // Ground and highlight are both absent; see [HawkMark.knockout].
      IconVariant.monochrome => (
        Colors.transparent,
        Colors.white,
        Colors.transparent,
      ),
    };

    return Container(
      width: size,
      height: size,
      color: ground,
      alignment: Alignment.center,
      child: HawkMark(
        size: size * markRatio,
        disc: disc,
        highlight: highlight,
        knockout: variant == IconVariant.monochrome,
      ),
    );
  }
}
