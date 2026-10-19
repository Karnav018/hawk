import 'package:flutter/material.dart';

/// Semantic colour tokens — Hawk v3.
///
/// **One theme.** v3 is drawn on a single near-black ground and nothing else;
/// there is no light counterpart in the design, and inventing one would mean
/// every screen carries a second appearance nobody drew and nobody reviews.
/// The extension shape is kept so `context.palette` still reads the same at
/// every call site, and so a light palette can be added later as data rather
/// than as a refactor.
///
/// Three rules the design states outright, and this file encodes:
///
/// * **The accent is for one thing per screen** — the primary action, or live
///   state. A second accented element on a screen is a bug, not a flourish.
/// * **A white card is the one thing that matters** on the screen it appears
///   on: the answer, the plan, the document. Its own ink scale lives in
///   [onPaper] because #fff needs genuinely different text values, not the
///   dark scale at some opacity.
/// * **Surfaces step, they do not glow.** [ground] → [card] → [raised] is the
///   whole depth vocabulary. No shadows, no blur, no gradient.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ground,
    required this.card,
    required this.cardDim,
    required this.raised,
    required this.divider,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.dangerWash,
    required this.textPrimary,
    required this.textBright,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.textFaint,
  });

  /// Page background. #0c0c0d — neutral, not navy.
  final Color ground;

  /// The workhorse surface: every card, row, pill and inactive control.
  final Color card;

  /// A step *down* from [card], for things that are present but not offered —
  /// an unselected row, an empty OTP box, a footnote panel.
  final Color cardDim;

  /// A step up from [card]: icon tiles inside a card, the selected nav pill,
  /// a secondary chip. The only lift the design allows.
  final Color raised;

  /// Hairline between rows inside one card.
  final Color divider;

  /// The ring on an unselected checkbox or radio.
  final Color border;

  /// The single accent. Primary actions and live state, nothing else.
  final Color accent;

  /// Ink on top of [accent] — the ground colour, not white. The accent is
  /// bright enough that white on it fails contrast at body sizes.
  final Color onAccent;

  /// Destructive only: delete, and the trash affordance in the viewer.
  final Color danger;

  /// The tinted bed behind a destructive button.
  final Color dangerWash;

  /// #fff — headlines and anything that must be read first.
  final Color textPrimary;

  /// Body copy inside a dark card, one notch below white.
  final Color textBright;

  /// Supporting copy on a card.
  final Color textSecondary;

  /// Lead paragraphs under a headline.
  final Color textTertiary;

  /// Metadata, mono caps, inactive labels.
  final Color textMuted;

  /// Chevrons and the quietest possible text. Below this, use nothing.
  final Color textFaint;

  /// The one and only palette.
  static const dark = AppPalette(
    ground: Color(0xFF0C0C0D),
    card: Color(0xFF191A1B),
    cardDim: Color(0xFF141516),
    raised: Color(0xFF2A2C2D),
    divider: Color(0xFF242627),
    border: Color(0xFF3A3C3D),
    accent: Color(0xFF59D3FF),
    onAccent: Color(0xFF0C0C0D),
    danger: Color(0xFFFF6A5A),
    dangerWash: Color(0xFF241516),
    textPrimary: Color(0xFFFFFFFF),
    textBright: Color(0xFFE6E7E4),
    textSecondary: Color(0xFFC9CAC7),
    textTertiary: Color(0xFFA4A6A1),
    textMuted: Color(0xFF8B8D88),
    textFaint: Color(0xFF7C7E79),
  );

  /// The ink scale for content sitting on a **white card**.
  ///
  /// Authored rather than derived: a white card is a different surface with a
  /// different job, and `textSecondary` at 60% opacity on #fff is a grey the
  /// design never chose. Reached as `context.palette.onPaper`.
  static const onPaper = PaperInk();

  @override
  AppPalette copyWith({
    Color? ground,
    Color? card,
    Color? cardDim,
    Color? raised,
    Color? divider,
    Color? border,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? dangerWash,
    Color? textPrimary,
    Color? textBright,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? textFaint,
  }) => AppPalette(
    ground: ground ?? this.ground,
    card: card ?? this.card,
    cardDim: cardDim ?? this.cardDim,
    raised: raised ?? this.raised,
    divider: divider ?? this.divider,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    danger: danger ?? this.danger,
    dangerWash: dangerWash ?? this.dangerWash,
    textPrimary: textPrimary ?? this.textPrimary,
    textBright: textBright ?? this.textBright,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    textMuted: textMuted ?? this.textMuted,
    textFaint: textFaint ?? this.textFaint,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      ground: Color.lerp(ground, other.ground, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardDim: Color.lerp(cardDim, other.cardDim, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerWash: Color.lerp(dangerWash, other.dangerWash, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textBright: Color.lerp(textBright, other.textBright, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
    );
  }
}

/// Ink for content on a white card. See [AppPalette.onPaper].
@immutable
class PaperInk {
  const PaperInk();

  /// The card itself.
  final Color surface = const Color(0xFFFFFFFF);

  /// Headlines and primary text on paper.
  final Color ink = const Color(0xFF101010);

  /// Body copy on paper.
  final Color body = const Color(0xFF3B4237);

  /// Metadata and fine print on paper.
  final Color muted = const Color(0xFF6B6F67);

  /// An inset row or chip inside a white card.
  final Color chip = const Color(0xFFF3F5F0);

  /// Hairline inside a white card.
  final Color divider = const Color(0xFFE4E7E1);

  /// An unfilled progress track on a white card.
  ///
  /// Darker than the design's `#eceee9`, which is 1.17:1 against white —
  /// invisible on a phone, so an unused meter read as a blank line. This is
  /// 1.55:1: plainly a bar, and still far enough from [ink] (12.3:1) that
  /// used and unused never look alike. A full 3:1 track would be a mid-grey
  /// as heavy as the fill itself; the fill and the number beside it are what
  /// carry the reading, the track only says where full is.
  final Color track = const Color(0xFFCDD1C9);

  /// The grab handle at the top of a sheet.
  final Color handle = const Color(0xFFDFE2DC);

  /// Destructive ink on paper.
  ///
  /// Authored, not [AppPalette.danger] reused: #ff6a5a is tuned to glow on
  /// #0c0c0d and fails contrast on white at button size, while the dark
  /// theme's tinted bed reads as a bruise there. A confirmation sheet is the
  /// one place a red button has to be unmistakable *and* legible.
  final Color danger = const Color(0xFFB02616);
  final Color dangerWash = const Color(0xFFFBE7E3);
}

/// `context.palette` instead of `Theme.of(context).extension<AppPalette>()!`.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;

  /// Ink for whatever sits on a white card on this screen.
  PaperInk get paper => AppPalette.onPaper;
}

// ===========================================================================
// v2 compatibility — deleted as each lane lands.
// ===========================================================================
//
// The v3 port runs lane by lane (A onboarding, B library, C search, D
// profile), which is only possible if the screens that have NOT been ported
// still build. These map v2's names onto the v3 tokens so they do.
//
// Every one of these is a screen that has not been redesigned yet. When the
// last reference to a member here is gone, delete the member — the count
// going to zero is how this file says the port is finished.
//
// `grep -rn 'isDark\|\.panel\b\|hairline\|hue(' lib` is the to-do list.

/// v2's seven-hue wheel. v3 has no hue system: a file icon is white, or it is
/// the accent, and that is the whole vocabulary. Kept only until lanes B and D
/// stop asking for it.
@Deprecated('v3 has one accent. Use palette.accent or palette.textPrimary.')
enum Hue { indigo, violet, teal, mint, amber, coral, rose }

/// @nodoc
extension AppPaletteV2Compat on AppPalette {
  @Deprecated('Use card.')
  Color get panel => card;

  @Deprecated('Use cardDim.')
  Color get panelSubtle => cardDim;

  @Deprecated('Use divider.')
  Color get hairline => divider;

  @Deprecated('Use border.')
  Color get hairlineStrong => border;

  /// v2 lifted the accent for text on dark. v3's accent is already a bright
  /// cyan chosen to be legible on #0c0c0d, so there is nothing to lift.
  @Deprecated('Use accent.')
  Color get accentSoft => accent;

  @Deprecated('Use a card on the ground instead of a tinted wash.')
  Color get accentWash => accent.withValues(alpha: 0.12);

  @Deprecated('v3 has no washed borders.')
  Color get accentWashBorder => accent.withValues(alpha: 0.30);

  /// v2 had a three-colour state vocabulary. v3 keeps only destructive red —
  /// success is shown by the thing having happened, not by a green.
  @Deprecated('Success is not a colour in v3.')
  Color get confirm => accent;

  @Deprecated('Use danger, or say it in words.')
  Color get caution => danger;

  @Deprecated('v3 has no shadows.')
  Color get panelShadow => const Color(0x00000000);

  /// Always true. v3 has one theme; every `isDark ? a : b` in the codebase is
  /// an unported v2 conditional, and collapsing it to `a` is part of porting
  /// that screen.
  @Deprecated('There is one theme. Take the dark branch and delete the check.')
  bool get isDark => true;

  @Deprecated('Use accent or textPrimary.')
  Color hue(Hue h) => switch (h) {
    Hue.mint => accent,
    Hue.coral || Hue.rose => danger,
    _ => textPrimary,
  };

  @Deprecated('Use raised.')
  Color hueWash(Hue h) => raised;

  @Deprecated('Use divider.')
  Color hueEdge(Hue h) => divider;
}
