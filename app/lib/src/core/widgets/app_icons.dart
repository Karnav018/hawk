import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons lifted verbatim from the design's inline SVG.
///
/// Material's icon set does not match these shapes, and redrawing them by hand
/// would drift. Keeping the original path data means the rendered icon is the
/// designed icon; `{stroke}` / `{fill}` are substituted so a single definition
/// serves every colour it appears in.
abstract final class AppIcons {
  static const vault =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M4 7.5 12 3.5l8 4v9L12 20.5l-8-4z"/>'
      '<path d="M12 12v8.5M4 7.5l8 4.5 8-4.5"/></svg>';

  static const apple =
      '<svg viewBox="0 0 24 24" fill="{c}">'
      '<path d="M16.4 12.8c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.7-1.8-3.3-1.8-1.4-.1-2.6.8-3.3.8'
      '-.7 0-1.7-.8-2.8-.8-1.5 0-2.8.9-3.6 2.3-1.5 2.6-.4 6.5 1.1 8.6.7 1 1.6 2.2 2.7 2.1'
      '1.1 0 1.5-.7 2.8-.7s1.6.7 2.7.7 1.9-1 2.6-2c.8-1.2 1.1-2.3 1.1-2.4-.1 0-2.1-.8-2.1-3.3z'
      'M14.2 5.9c.6-.7 1-1.7.9-2.7-.9 0-2 .6-2.6 1.3-.6.6-1 1.6-.9 2.6 1 .1 2-.5 2.6-1.2z"/></svg>';

  static const google =
      '<svg viewBox="0 0 24 24">'
      '<path fill="{c}" d="M21.6 12.2c0-.7-.1-1.2-.2-1.8H12v3.4h5.4c-.1.9-.7 2.2-1.9 3.1l-.1.1 2.8 2.2c1.7-1.6 2.7-3.9 2.7-6.6z"/>'
      '<path fill="{c75}" d="M12 21.5c2.5 0 4.5-.8 6-2.2l-2.8-2.2c-.8.5-1.9.9-3.2.9-2.5 0-4.6-1.6-5.3-3.9l-.1.1-2.9 2.2C5.1 19.4 8.3 21.5 12 21.5z"/>'
      '<path fill="{c55}" d="M6.7 14.1c-.2-.6-.3-1.2-.3-1.9s.1-1.3.3-1.9L3.7 8.1C3 9.4 2.6 10.9 2.6 12.2s.4 2.8 1.1 4.1l3-2.2z"/>'
      '<path fill="{c90}" d="M12 6.4c1.8 0 3 .8 3.7 1.4l2.6-2.5C16.5 3.8 14.5 3 12 3 8.3 3 5.1 5.1 3.7 8.1l3 2.2c.7-2.2 2.8-3.9 5.3-3.9z"/></svg>';

  static const mail =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6">'
      '<rect x="3" y="5.5" width="18" height="13" rx="2.5"/>'
      '<path d="M3.5 7l8.5 6 8.5-6"/></svg>';

  static const shieldCheck =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 3.5l7 3v5.5c0 4-3 7-7 8.5-4-1.5-7-4.5-7-8.5V6.5z"/>'
      '<path d="M9 12l2 2 4-4"/></svg>';

  static const arrowRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12h13M13 7l5 5-5 5"/></svg>';

  static const search =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/>'
      '<path d="M16 16l4.5 4.5"/></svg>';

  static const sort =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><path d="M4 6h16M7 12h10M10 18h4"/></svg>';

  static const sun =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/>'
      '<path d="M12 3v2M12 19v2M3 12h2M19 12h2M6 6l1.4 1.4M16.6 16.6 18 18'
      'M18 6l-1.4 1.4M7.4 16.6 6 18"/></svg>';

  static const moon =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M19 14.5A8 8 0 0 1 9.5 5a7 7 0 1 0 9.5 9.5z"/></svg>';

  static const capture =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><rect x="4" y="4" width="16" height="16" rx="4.5"/>'
      '<path d="M9 9.5h6M12 9.5V16"/></svg>';

  static const mic =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><rect x="8.5" y="3" width="7" height="11.5" rx="3.5"/>'
      '<path d="M5.5 12a6.5 6.5 0 0 0 13 0M12 18.5V21"/></svg>';

  static const storage =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M3.5 7h6l2 2h9v10h-17z"/></svg>';

  // ---- memory-type marks, drawn in the same 24px stroke language ----------

  /// An arrow leaving a tray — the share mark on both iOS and Android, so
  /// it needs no label to be understood.
  static const share =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M12 14.5V3.5M8 7.5l4-4 4 4"/>'
      '<path d="M6 11v7.5A1.5 1.5 0 0 0 7.5 20h9a1.5 1.5 0 0 0 1.5-1.5V11"/></svg>';

  static const document =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M6 3.5h7l5 5V20.5H6z"/><path d="M13 3.5v5h5M9 13h6M9 16.5h4"/></svg>';

  static const image =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/>'
      '<circle cx="9" cy="10" r="1.6"/><path d="M4 17l5-4.5 4 3.5 3-2.5 4 3.5"/></svg>';

  static const waveform =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round"><path d="M4 11v2M8 8v8M12 5v14M16 9v6M20 11v2"/></svg>';

  static const video =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="3" y="6" width="12.5" height="12" rx="2.5"/>'
      '<path d="M15.5 10.5 21 7.5v9l-5.5-3z"/></svg>';

  static const link =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M10 13.5a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 1 0-5.7-5.7L11.5 6.3"/>'
      '<path d="M14 10.5a4 4 0 0 0-5.7 0L5.5 13.3a4 4 0 1 0 5.7 5.7l1.3-1.3"/></svg>';

  static const note =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<rect x="4" y="3.5" width="16" height="17" rx="3"/>'
      '<path d="M8 8.5h8M8 12.5h8M8 16.5h5"/></svg>';

  static const check =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

  static const close =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';

  static const chevronRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M9 5l7 7-7 7"/></svg>';

  static const chevronLeft =
      '<svg viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M14 5l-7 7 7 7"/></svg>';
}

/// Renders an [AppIcons] template at [size], substituting colour placeholders.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.svg, {
    required this.size,
    required this.color,
    this.strokeWidth,
    super.key,
  });

  final String svg;
  final double size;
  final Color color;

  /// Fills a `{w}` placeholder in the path data.
  ///
  /// v3 draws the same glyph at 1.7 as content and at 2.1 as chrome, and the
  /// difference is visible at 19px. Icons that are only ever one weight hard
  /// code it and ignore this; the handful that are reused across both put
  /// `{w}` in the source and take it from here.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _resolve(svg, color, strokeWidth ?? 1.9),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  static String _resolve(String svg, Color color, [double weight = 1.9]) {
    String hex(double opacity) {
      final a = ((color.a * opacity) * 255).round().clamp(0, 255);
      final r = (color.r * 255).round();
      final g = (color.g * 255).round();
      final b = (color.b * 255).round();
      return '#${_h(r)}${_h(g)}${_h(b)}${_h(a)}';
    }

    return svg
        .replaceAll('{w}', weight.toString())
        .replaceAll('{c90}', hex(0.90))
        .replaceAll('{c75}', hex(0.75))
        .replaceAll('{c55}', hex(0.55))
        .replaceAll('{c}', hex(1));
  }

  static String _h(int v) => v.toRadixString(16).padLeft(2, '0');
}
