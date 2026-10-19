import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_typography.dart';

/// The Hawk mark — `Hawk Logo v3.dc.html`.
///
/// A lit sphere, and the whole thing is two numbers: a disc at **r 24 on
/// (32,32)** and a highlight at **r 7 on (24,24)** of a 64-unit grid. The
/// highlight sits exactly 8 units up and 8 units left of centre — a 45°
/// offset — which is what makes the mark reproducible by anyone with a ruler
/// rather than by anyone with the file.
///
/// Drawn rather than shipped as a PNG. At these proportions a raster buys
/// nothing and costs the one thing the mark needs most: it appears at 16px in
/// a row and at 112px on the splash, and two circles are exact at both.
///
/// **The highlight never rotates.** It is upper-left in every lockup, every
/// colourway and every size. A rotating highlight reads as a loading spinner,
/// which is the one thing a logo must not look like.
class HawkMark extends StatelessWidget {
  const HawkMark({
    this.size = 48,
    this.disc,
    this.highlight,
    this.outlined = false,
    this.knockout = false,
    super.key,
  });

  /// The knocked-out mark for a dark ground: white disc, accent highlight.
  /// The default everywhere in the app, because the app is dark everywhere.
  const HawkMark.onInk({this.size = 48, super.key})
    : disc = null,
      highlight = null,
      outlined = false,
      knockout = false;

  /// One colour, for a surface that cannot carry two — an embossed stamp, a
  /// monochrome export.
  const HawkMark.outlined({this.size = 48, this.disc, super.key})
    : highlight = null,
      outlined = true,
      knockout = false;

  final double size;

  /// Defaults to white — the mark's colour on the product's own ground.
  final Color? disc;

  /// Defaults to the accent. On a light ground this is the ground colour
  /// itself, so the highlight reads as a hole rather than as a dot.
  final Color? highlight;

  /// Disc as a 3-unit stroke instead of a fill.
  final bool outlined;

  /// Cut the highlight out of the disc instead of painting it, leaving a
  /// genuine hole in the alpha channel.
  ///
  /// For a layer that something else will colour: Android's themed icon tints
  /// every opaque pixel of the monochrome layer a single colour, so a white
  /// disc with an accent dot arrives as a featureless circle. Punched, the
  /// same layer tints to a lit sphere. [highlight] is ignored.
  final bool knockout;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          disc: disc ?? p.textPrimary,
          highlight: highlight ?? p.accent,
          outlined: outlined,
          knockout: knockout,
        ),
        // The mark is decoration wherever it appears beside the wordmark;
        // [HawkLockup] carries the single label for the pair, so a screen
        // reader says "Hawk" once instead of naming a circle.
        isComplex: false,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.disc,
    required this.highlight,
    required this.outlined,
    required this.knockout,
  });

  final Color disc;
  final Color highlight;
  final bool outlined;
  final bool knockout;

  /// The design's own optical correction, and the reason this is a painter
  /// rather than an `Image.asset`.
  ///
  /// > *"Below 32px the highlight grows one unit and the disc grows to the
  /// > safe area, so the two shapes stay readable instead of merging."*
  ///
  /// Scaled down linearly, a 7-unit highlight inside a 24-unit disc becomes a
  /// smudge on the edge of a circle at 22px. These are the three steps the
  /// design draws, read as: at what rendered size do the numbers change.
  static ({double discR, double hiR, double hiC}) _geometry(double px) {
    if (px >= 32) return (discR: 24, hiR: 7, hiC: 24);
    if (px >= 24) return (discR: 25, hiR: 8, hiC: 23);
    return (discR: 26, hiR: 9, hiC: 23);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is in the design's 64-unit space; one transform puts
    // it in pixels, so the numbers in this file are the numbers in the spec.
    final unit = size.width / 64;
    canvas.scale(unit);

    final g = _geometry(size.width);

    if (outlined) {
      canvas.drawCircle(
        const Offset(32, 32),
        g.discR,
        Paint()
          ..color = disc
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(const Offset(24, 24), g.hiR, Paint()..color = disc);
      return;
    }

    if (knockout) {
      // `BlendMode.clear` erases whatever is already on the surface, so it
      // only punches a hole if the disc is alone on its own layer. Without
      // the saveLayer it would clear the ground behind the mark too.
      canvas.saveLayer(const Rect.fromLTWH(0, 0, 64, 64), Paint());
      canvas.drawCircle(const Offset(32, 32), g.discR, Paint()..color = disc);
      canvas.drawCircle(
        Offset(g.hiC, g.hiC),
        g.hiR,
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.restore();
      return;
    }

    canvas.drawCircle(const Offset(32, 32), g.discR, Paint()..color = disc);
    canvas.drawCircle(
      Offset(g.hiC, g.hiC),
      g.hiR,
      Paint()
        ..color = highlight
        // The highlight is a hole in the disc, not a dot on top of it. With
        // a translucent highlight colour — which a caller passing a themed
        // accent can produce — `srcOver` would let the disc show through and
        // muddy it, where the design's own SVG simply paints over.
        ..blendMode = BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.disc != disc ||
      old.highlight != highlight ||
      old.outlined != outlined ||
      old.knockout != knockout;
}

/// Mark plus wordmark, side by side.
///
/// The wordmark is Archivo 800 at **−.045em** — tighter than any headline in
/// the product, which is what keeps "Hawk" reading as one object rather than
/// as a word set in the UI font.
class HawkLockup extends StatelessWidget {
  const HawkLockup({
    this.markSize = 48,
    this.wordmarkSize = 38,
    this.color,
    super.key,
  });

  final double markSize;
  final double wordmarkSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = color ?? p.textPrimary;

    return Semantics(
      label: 'Hawk',
      // One label for the pair. Without this a screen reader announces the
      // mark and then reads the wordmark, so the app introduces itself twice.
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HawkMark(size: markSize, disc: ink),
          SizedBox(width: markSize * 0.29),
          Text('Hawk', style: _wordmark(wordmarkSize, ink)),
        ],
      ),
    );
  }
}

/// Mark over wordmark, with the line underneath.
class HawkLockupStacked extends StatelessWidget {
  const HawkLockupStacked({
    this.markSize = 64,
    this.wordmarkSize = 34,
    this.tagline = 'Your second memory',
    super.key,
  });

  final double markSize;
  final double wordmarkSize;

  /// Set to null for the mark and name alone.
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      label: tagline == null ? 'Hawk' : 'Hawk. $tagline',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HawkMark(size: markSize),
          const SizedBox(height: 12),
          Text('Hawk', style: _wordmark(wordmarkSize, p.textPrimary)),
          if (tagline != null) ...[
            const SizedBox(height: 8),
            Text(
              tagline!.toUpperCase(),
              // .14em — wider than any other mono in the product. The tagline
              // is set as a rule, not as a caption.
              style: AppTypography.meta.copyWith(
                color: p.textMuted,
                letterSpacing: 9.5 * 0.14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle _wordmark(double size, Color color) => TextStyle(
  fontFamily: AppTypography.sans,
  fontSize: size,
  height: 1,
  letterSpacing: size * -0.045,
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation('wght', 800)],
  color: color,
);
