import 'package:flutter/material.dart';

/// Type has two jobs in v3, and keeps to them.
///
/// * [sans] — Archivo. Everything a person reads. Headlines are set heavy
///   (800) and tight (-.035em); body is 400 and roomy. The whole hierarchy is
///   carried by weight and size, not by a second family.
/// * [meta] family — Poppins, **strictly metadata**: dates, counts, states,
///   percentages, step markers, timers. Always upper case, always tracked.
///   If a string is a sentence, it is not metadata.
///
/// Poppins replaced Martian Mono (27 Sep 2026): a monospace face on every
/// label read as a developer tool rather than a product. Two things changed
/// with it. Poppins is static, so its weights are separate files and
/// [FontWeight] alone picks them. And its figures are proportional — it has
/// no tabular set — so a number that ticks in place, like a percentage,
/// shifts by a pixel as its width changes.
///
/// The serif is gone. v2 set every headline in Instrument Serif with an
/// italic second line; v3 replaced that with heavy Archivo, so the family is
/// no longer bundled. Anything still reaching for a serif is v2 code that has
/// not been ported.
///
/// Archivo ships as a variable font, so its weight is applied with
/// [FontVariation] *as well as* [FontWeight] — the axis is what actually moves
/// the glyphs, while `fontWeight` keeps Flutter's own font matching and the
/// platform's accessibility behaviour correct.
abstract final class AppTypography {
  static const sans = 'Archivo';

  /// The metadata family. Named for its job rather than its face, so the
  /// next change of face is one line.
  static const metaFamily = 'Poppins';

  static List<FontVariation> _wght(double weight) => [
    FontVariation('wght', weight),
  ];

  /// Every display size is the same shape: Archivo 800, tight tracking, line
  /// height just above 1. Only the size changes, which is why they are built
  /// rather than written out sixteen times.
  static TextStyle _display(
    double size, {
    double tracking = -0.035,
    double height = 1.02,
  }) => TextStyle(
    fontFamily: sans,
    fontSize: size,
    height: height,
    letterSpacing: size * tracking,
    fontWeight: FontWeight.w800,
    fontVariations: _wght(800),
  );

  // ------------------------------------------------------------- display ---

  /// 38 — the sign-in headline, the largest type in the product.
  static TextStyle get display38 => _display(38, tracking: -0.04, height: 1.0);

  /// 34 — an onboarding step headline ("How will you mostly ask?").
  static TextStyle get display34 => _display(34);

  /// 32 — the wordmark, and the email headline.
  static TextStyle get display32 => _display(32);

  /// 30 — the indexing headline.
  static TextStyle get display30 => _display(30, height: 1.05);

  /// 28 — a tab-root screen title ("Library"), and a spoken transcript.
  static TextStyle get display28 => _display(28, height: 1.15);

  /// 26 — the title on a result card.
  static TextStyle get display26 => _display(26, tracking: -0.03, height: 1.05);

  /// 24 — a sheet headline, the profile name, an answer card.
  static TextStyle get display24 => _display(24, tracking: -0.03, height: 1.15);

  /// 22 — a document title inside the viewer.
  static TextStyle get display22 => _display(22, tracking: -0.03, height: 1.15);

  /// 18 — a card option's title, and a stacked screen's header.
  static TextStyle get display18 => _display(18, tracking: -0.025, height: 1.2);

  // ---------------------------------------------------------------- sans ---

  /// 16/700 — a strong row title, a header label.
  static TextStyle get titleLarge => TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 1.25,
    letterSpacing: -0.32, // -.02em
    fontWeight: FontWeight.w700,
    fontVariations: _wght(700),
  );

  /// 15.5/700 — the label inside a primary button.
  static TextStyle get button => TextStyle(
    fontFamily: sans,
    fontSize: 15.5,
    height: 1.2,
    letterSpacing: -0.155, // -.01em
    fontWeight: FontWeight.w700,
    fontVariations: _wght(700),
  );

  /// 15/700 — a list-row title.
  static TextStyle get titleMedium => TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 1.25,
    letterSpacing: -0.225, // -.015em
    fontWeight: FontWeight.w700,
    fontVariations: _wght(700),
  );

  /// 15/600 — a settings row, where the label is a destination not a heading.
  static TextStyle get titleSoft => TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w600,
    fontVariations: _wght(600),
  );

  /// 14.5/700 — a segmented-tab label, and a file-row title.
  static TextStyle get titleSmall => TextStyle(
    fontFamily: sans,
    fontSize: 14.5,
    height: 1.25,
    letterSpacing: -0.2175, // -.015em
    fontWeight: FontWeight.w700,
    fontVariations: _wght(700),
  );

  /// 15/1.5 — a chat bubble, and copy inside a white card.
  static TextStyle get bodyLarge => TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: _wght(400),
  );

  /// 14.5/1.6 — the lead paragraph under a headline.
  static TextStyle get bodyMedium => TextStyle(
    fontFamily: sans,
    fontSize: 14.5,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: _wght(400),
  );

  /// 13.5/1.65 — running text inside the document viewer.
  static TextStyle get bodySmall => TextStyle(
    fontFamily: sans,
    fontSize: 13.5,
    height: 1.65,
    fontWeight: FontWeight.w400,
    fontVariations: _wght(400),
  );

  /// 13/1.5 — the subtitle under a card option's title.
  static TextStyle get caption => TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: _wght(400),
  );

  /// 12.5/1.55 — fine print, and the reassurance notes.
  static TextStyle get footnote => TextStyle(
    fontFamily: sans,
    fontSize: 12.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
    fontVariations: _wght(400),
  );

  /// 12.5/700 — the label in a small inline chip ("Open", "Index").
  static TextStyle get chip => TextStyle(
    fontFamily: sans,
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    fontVariations: _wght(700),
  );

  // ---------------------------------------------------------------- meta ---

  /// Metadata is built once: the size changes, the tracking follows it, and
  /// the family and weight never do.
  static TextStyle _meta(
    double size, {
    double tracking = 0.05,
    double height = 1.4,
  }) => TextStyle(
    fontFamily: metaFamily,
    fontSize: size,
    height: height,
    letterSpacing: size * tracking,
    fontWeight: FontWeight.w500,
  );

  /// 9.5 — the workhorse. Row metadata, step markers, states, screen labels.
  ///
  /// Render the string upper case yourself; the tracking assumes caps and
  /// looks broken under a lower-case string.
  static TextStyle get meta => _meta(9.5, tracking: 0.055);

  /// 9.5 with wider tracking — a section label inside a white card.
  static TextStyle get metaWide => _meta(9.5, tracking: 0.08);

  /// 10 — a header-level count or timer.
  static TextStyle get meta10 => _meta(10, tracking: 0.06);

  /// 10.5 — the metadata block on a result card, set over two lines.
  static TextStyle get meta11 => _meta(10.5, height: 1.7);

  /// 12.5/600 — a quota figure, read as a number rather than a label.
  static TextStyle get numeral => TextStyle(
    fontFamily: metaFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// 22 — a single digit in the verification code.
  static TextStyle get numeralCode => TextStyle(
    fontFamily: metaFamily,
    fontSize: 22,
    height: 1,
    fontWeight: FontWeight.w400,
  );

  /// 26/600 — the one big number on the indexing screen.
  static TextStyle get numeralLarge => TextStyle(
    fontFamily: metaFamily,
    fontSize: 26,
    height: 1,
    fontWeight: FontWeight.w600,
  );

  // ----------------------------------------------------- v2 compatibility ---
  // Deleted as each lane lands; see app_palette.dart for why these exist.
  //
  // The serif is the one that cannot be mapped honestly: v2 set headlines in
  // Instrument Serif and v3 sets them in heavy Archivo, so these return the
  // v3 display styles. An unported screen therefore already renders in the
  // right family at roughly the right size — it just has v2's layout around
  // it, which is what porting the screen fixes.

  @Deprecated('Use display38.')
  static TextStyle get displayLarge => display38;

  @Deprecated('Use display34.')
  static TextStyle get displayMedium => display34;

  @Deprecated('Use display30.')
  static TextStyle get displaySmall => display30;

  @Deprecated('Use display24.')
  static TextStyle get answer => display24;

  /// v3 has no italic: Archivo ships here as a single upright variable font,
  /// so asking for italic would get a synthesised slant nobody drew.
  @Deprecated('v3 has no italic. Use weight and size for emphasis.')
  static TextStyle italic(TextStyle base) => base;

  @Deprecated('Use meta — and upper-case the string yourself.')
  static TextStyle get label => meta;

  @Deprecated('Use meta.')
  static TextStyle get labelTight => meta;

  @Deprecated('Use metaWide.')
  static TextStyle get labelWide => metaWide;

  @Deprecated('Use meta.')
  static TextStyle get numeralSmall => meta10;

  @Deprecated('v3 does not mark citations inline.')
  static TextStyle get citation => meta10;
}
