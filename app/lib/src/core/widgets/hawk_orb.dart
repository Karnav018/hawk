import 'package:flutter/material.dart';

/// Which ground the orb is sitting on.
enum OrbVariant {
  /// On near-black navy: lit from inside, shaded from below.
  dark,

  /// On paper-white: the inner glow is replaced by a cast shadow, because a
  /// self-lit sphere on a light ground reads as a sticker.
  light,
}

/// The orb's material, without any shape of its own.
///
/// This draws `orb_sphere.png` — a path-traced render of `assets/voice_orb.glb`
/// (a glass shell around an emissive plasma core, using
/// `KHR_materials_transmission`), baked offline by `tool/render_orb.py`.
///
/// Rendering it at build time rather than at run time is deliberate. Real
/// refraction needs a path tracer, and the Flutter-side options are a WebView
/// running `<model-viewer>` — heavy, slow to first paint, unusable on a splash
/// — or `flutter_scene`, which has no transmission support and would draw the
/// glass wrong. Baking gives exact fidelity at zero runtime cost on every
/// device. The trade-off is that the viewing angle is fixed; re-run the script
/// with `--frames N` for a turntable if a screen needs the orb to move.
///
/// The image is cropped so the sphere reaches all four edges. Fills whatever
/// box it is given with [BoxFit.cover], so a full-screen rectangle and a 16px
/// circle show the same undistorted material — which is what lets the splash
/// morph the *shape* without the artwork ever stretching.
class HawkOrbSurface extends StatelessWidget {
  const HawkOrbSurface({
    required this.referenceExtent,
    this.variant = OrbVariant.dark,
    this.zoom = 1,
    super.key,
  });

  /// The box's shortest side. Kept so callers state their intent and so a
  /// future size-dependent effect has somewhere to hang.
  final double referenceExtent;

  final OrbVariant variant;

  /// Scales the sphere up within its box.
  ///
  /// Needed only when the box is wider than the sphere can cover — the splash
  /// draws this full-screen, where at 1.0 the sphere's own silhouette would
  /// leave the screen corners dark and "full bleed" would not be full bleed.
  /// At 1.0 the whole sphere is visible, which is what every other caller
  /// wants.
  final double zoom;

  static const asset = 'assets/images/orb_sphere.png';

  @override
  Widget build(BuildContext context) {
    const image = Image(
      image: AssetImage(asset),
      fit: BoxFit.cover,
      // Rendered material, not decoration: low-quality sampling bands badly
      // across a smooth gradient.
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );

    return zoom == 1 ? image : Transform.scale(scale: zoom, child: image);
  }
}

/// The Hawk mark — the product's own voice indicator, used as the logo.
///
/// Identity design `Knowra Logo.dc.html`, direction 1A. The lighting the CSS
/// faked with inset shadows and a radial sheen is now real: it comes from the
/// path-traced render, so there is nothing to approximate here.
class HawkOrb extends StatelessWidget {
  const HawkOrb({
    required this.size,
    this.variant = OrbVariant.dark,
    this.semanticLabel,
    super.key,
  });

  final double size;
  final OrbVariant variant;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget orb = SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: HawkOrbSurface(referenceExtent: size, variant: variant),
      ),
    );

    if (variant == OrbVariant.light) {
      // `box-shadow: 0 6px 18px rgba(14,17,22,.22)` — on a light ground the
      // sphere is lit from outside, so it casts instead of glowing.
      orb = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0x380E1116),
              blurRadius: size * 0.257,
              offset: Offset(0, size * 0.086),
            ),
          ],
        ),
        child: orb,
      );
    }

    return semanticLabel == null
        ? orb
        : Semantics(label: semanticLabel, image: true, child: orb);
  }
}
