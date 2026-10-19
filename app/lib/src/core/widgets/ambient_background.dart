import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// The ground every screen sits on — flat, in v3.
///
/// **This used to paint the v2 wash, and it kept painting it after v3
/// switched it off.** v2 put a blurred orb-emission texture behind every
/// dark screen, two coloured blooms (violet top-left, teal low right) and a
/// navy `#070B16` scrim over the lot. v3 deleted all of it — "surfaces step,
/// they do not glow" — and every v3 screen passes `ambientOpacity: 0` with a
/// comment saying so. But the opacity only ever faded the emission texture:
/// the blooms and the navy scrim were painted unconditionally, so every
/// screen in the app still sat on a violet-and-navy gradient instead of the
/// design's `#0c0c0d`. It showed in device screenshots as a navy glow behind
/// the home screen, and passed every test because no test looked at the
/// ground.
///
/// The v3 file has no gradient, no blur and no shadow anywhere: 37 screens on
/// `#0c0c0d`. So the ground is now exactly that, and [opacity] is kept only
/// so the dozens of call sites that pass it do not all have to change at
/// once. It has no effect.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({this.opacity = 0, this.child, super.key});

  /// Ignored — see the class comment. Retained for source compatibility.
  final double opacity;

  final Widget? child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.ground,
    child: child ?? const SizedBox.expand(),
  );
}
