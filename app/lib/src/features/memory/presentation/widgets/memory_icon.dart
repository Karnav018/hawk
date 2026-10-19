import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../domain/entities/memory_enums.dart';

/// The mark for a memory's kind.
///
/// v2 mapped eleven types onto a seven-hue wheel so a scrolled library read as
/// bands of colour. v3 deletes that outright: there is one accent, it belongs
/// to the primary action, and a file icon is white. What distinguishes a
/// recording from a contract here is the *glyph*, which is the thing that
/// actually says which it is — the colour never did, it only said "audio-ish".
///
/// Unknown types fall through to the document mark rather than rendering
/// nothing. A type a newer backend invents should look unfamiliar, not broken.
String iconForMemoryType(MemoryType type) => switch (type) {
  MemoryType.screenshot || MemoryType.photo => HawkIcons.image,
  MemoryType.audio || MemoryType.voiceNote => HawkIcons.audio,
  MemoryType.video => memoryVideoIcon,
  MemoryType.link => HawkIcons.link,
  MemoryType.text || MemoryType.note => HawkIcons.type,
  MemoryType.pdf || MemoryType.document || MemoryType.file => HawkIcons.file,
};

/// A video, drawn in v3's stroke language.
///
/// Lives here because `hawk_icons.dart` has no video glyph — the design never
/// draws one, since none of the three library screens happens to show a video
/// row. The product indexes them, so the library has to. Belongs in
/// `HawkIcons` the moment anything else needs it.
const memoryVideoIcon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<rect x="3" y="5.5" width="13" height="13" rx="3"/>'
    '<path d="M16 10.5 21 7.5v9l-5-3z"/></svg>';

/// The rounded tile that leads a library row, a match, or a citation.
///
/// A thin wrapper over [IconTile] rather than its own container: the tile is
/// one of v3's dozen shapes and re-describing it here is how a 14px radius
/// quietly becomes a 12px one. What this adds is the *mapping* — the type in,
/// the glyph out — which is the only part specific to memories.
class MemoryTypeBadge extends StatelessWidget {
  const MemoryTypeBadge({
    required this.type,
    this.color,
    this.size = AppSize.tile,
    super.key,
  });

  final MemoryType type;

  /// Overrides the glyph colour.
  ///
  /// Almost always left null. The design accents a row's *trailing* control —
  /// the chip offering to index, the dot counting a job down — and leaves the
  /// leading tile white, so a scanned list has one thing pulling the eye per
  /// row rather than two arguing about it.
  final Color? color;

  final double size;

  @override
  Widget build(BuildContext context) {
    return IconTile(
      icon: iconForMemoryType(type),
      size: size,
      // The design's tile is 42 at a 14px radius. Scaled rather than fixed so
      // the 26px badge on a match row is the same shape and not a square with
      // slightly rounded corners.
      radius: size * (AppRadius.tile / AppSize.tile),
      foreground: color ?? context.palette.textPrimary,
      strokeWidth: 1.9,
    );
  }
}
