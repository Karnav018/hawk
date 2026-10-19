import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import 'app_icons.dart';
import 'hawk_icons.dart';

/// The v3 component vocabulary.
///
/// Every screen in `Hawk App v3.dc.html` is built from about a dozen shapes
/// repeated exactly. Putting them here rather than re-describing them per
/// screen is what makes that repetition real: the design's claim is that the
/// whole product speaks one language, and a `Container(borderRadius: 28)`
/// written out eighteen times is eighteen chances to say 26.
///
/// The rules these encode, which the design states and does not bend:
///
/// * **One accent per screen.** [PillButton.primary] and a live state are the
///   only things that get it.
/// * **A white card is the one thing that matters** — the answer, the plan,
///   the document. [CardTone.paper] exists so that is a decision rather than
///   a colour someone picked.
/// * **Mono is metadata.** [MetaText] upper-cases its own string, because the
///   tracking assumes caps and a lower-case mono string looks broken.

// ===========================================================================
// Buttons
// ===========================================================================

enum PillTone {
  /// The one accented control on the screen.
  primary,

  /// A card-coloured action. The default for anything that is not *the*
  /// action.
  secondary,

  /// Text on the ground, for "Skip" and its relatives. A real choice, so it
  /// is a labelled action and not a greyed-out hint.
  ghost,

  /// Destructive. Red ink on its own tinted bed, never a red fill — a filled
  /// red button is the easiest thing on a screen to press by accident.
  danger,

  /// Quieter than [secondary] and on the same surface: a paired action that
  /// shares its row with a heavier one, like Deactivate beside Delete.
  tertiary,

  /// The affirmative on a **white sheet** — ink fill, paper label.
  ///
  /// A sheet cannot use [primary]: the accent is tuned to carry a screen on
  /// #0c0c0d and on #fff it is a highlighter. Every confirmation in the
  /// product had grown its own private copy of this button before it existed
  /// here — three of them, at the last count.
  paper,

  /// The way out on a white sheet — chip fill, ink label. "Cancel", "Keep".
  paperQuiet,

  /// Destructive on a white sheet. See [PaperInk.danger] for why this is not
  /// [danger] reused.
  paperDanger,

  /// White fill, ink label — the way *forward* when the accent is spoken for
  /// or would be too loud: "Back to Library" while indexing, "Try again",
  /// "Open Settings". From `Hawk Library.dc.html`'s button set.
  white,

  /// The raised grey — a second action beside [white] or [primary], and the
  /// one that stays visible on a sheet, where [secondary]'s card grey is the
  /// sheet itself.
  raised,

  /// No fill, white label — the way out of a decision sheet ("Cancel",
  /// "Not now"). Brighter than [ghost], which is for skipping a step and is
  /// meant to recede.
  clear,
}

/// The pill. Every button in v3 is one of these.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    this.onPressed,
    this.tone = PillTone.primary,
    this.icon,
    this.leadingIcon,
    this.isBusy = false,
    this.height,
    super.key,
  });

  const PillButton.secondary({
    required this.label,
    this.onPressed,
    this.icon,
    this.leadingIcon,
    this.isBusy = false,
    this.height,
    super.key,
  }) : tone = PillTone.secondary;

  final String label;
  final VoidCallback? onPressed;
  final PillTone tone;

  /// Trailing glyph. The design puts an arrow on a button that advances a
  /// run, and nothing on a button that completes one.
  final String? icon;

  /// Leading glyph, before the label.
  ///
  /// Which side a glyph sits on is not decoration: a trailing arrow means
  /// *this takes you onward*, and a leading plus means *this adds a thing*.
  /// Putting the plus on the right would make "Add a source" read as
  /// navigation.
  final String? leadingIcon;

  final bool isBusy;
  final double? height;

  bool get _onPaper =>
      tone == PillTone.paper ||
      tone == PillTone.paperQuiet ||
      tone == PillTone.paperDanger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !isBusy;

    final (background, foreground) = switch (tone) {
      PillTone.primary => (p.accent, p.onAccent),
      PillTone.secondary => (p.card, p.textPrimary),
      PillTone.ghost => (Colors.transparent, p.textMuted),
      PillTone.danger => (p.dangerWash, p.danger),
      PillTone.tertiary => (p.card, p.textSecondary),
      PillTone.paper => (AppPalette.onPaper.ink, AppPalette.onPaper.surface),
      PillTone.paperQuiet => (AppPalette.onPaper.chip, AppPalette.onPaper.ink),
      PillTone.paperDanger => (
        AppPalette.onPaper.dangerWash,
        AppPalette.onPaper.danger,
      ),
      PillTone.white => (AppPalette.onPaper.surface, AppPalette.onPaper.ink),
      PillTone.raised => (p.raised, p.textPrimary),
      PillTone.clear => (Colors.transparent, p.textPrimary),
    };

    // Tertiary is a step down in weight as well as colour — the pair it
    // belongs to must not read as two primary actions.
    final labelStyle = tone == PillTone.tertiary
        ? AppTypography.titleSmall
        : AppTypography.button;

    final disabledInk = _onPaper ? AppPalette.onPaper.muted : p.textFaint;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        // A disabled button falls back to the surface it sits on, which is
        // not the same surface on paper as on the ground.
        color: enabled
            ? background
            : (_onPaper ? AppPalette.onPaper.chip : p.card),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: height ?? AppSize.button,
            child: Center(
              child: isBusy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          enabled ? foreground : disabledInk,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (leadingIcon != null) ...[
                          AppIcon(
                            leadingIcon!,
                            size: 18,
                            color: enabled ? foreground : disabledInk,
                          ),
                          const SizedBox(width: AppSpacing.gap),
                        ],
                        Text(
                          label,
                          style: labelStyle.copyWith(
                            color: enabled ? foreground : disabledInk,
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: AppSpacing.gap),
                          AppIcon(
                            icon!,
                            size: 17,
                            color: enabled ? foreground : disabledInk,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44px circular header button — back, close, search, add.
class CircleButton extends StatelessWidget {
  const CircleButton({
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.tone,
    this.iconColor,
    this.size = AppSize.headerButton,
    super.key,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Overrides the fill — the avatar uses the accent.
  final Color? tone;

  /// Overrides the glyph colour alone.
  ///
  /// For the one case where the *action* is destructive but the button is
  /// not: 1M's trash is a card fill with a red glyph. Tinting the whole
  /// circle would make the most destructive control the most eye-catching
  /// thing on the screen.
  final Color? iconColor;

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: tone ?? p.card,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: AppIcon(
                icon,
                size: size * 0.43,
                color: iconColor ?? (tone == null ? p.textPrimary : p.onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small inline action inside a row — "Open", "Index", "Upgrade".
class InlineChip extends StatelessWidget {
  const InlineChip({
    required this.label,
    this.onPressed,
    this.isAccent = false,
    this.height = AppSize.chip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Accent means *this row is offering you something* — an unindexed file
  /// offering to be indexed. A row whose action is neutral ("Open") is not
  /// offering, it is available, and stays [AppPalette.raised].
  final bool isAccent;

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: isAccent ? p.accent : p.raised,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Text(
              label,
              style: AppTypography.chip.copyWith(
                color: isAccent ? p.onAccent : p.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Surfaces
// ===========================================================================

enum CardTone {
  /// The default dark card.
  dark,

  /// A step down — present, but not being offered.
  dim,

  /// White. **The one thing that matters on this screen.** Use it once.
  paper,

  /// Accent-filled. The front card of a result stack, and nothing else.
  accent,
}

/// The 28px card — the signature shape of v3.
class HawkCard extends StatelessWidget {
  const HawkCard({
    required this.child,
    this.tone = CardTone.dark,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.onTap,
    this.radius = AppRadius.card,
    super.key,
  });

  final Widget child;
  final CardTone tone;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  Color _background(AppPalette p) => switch (tone) {
    CardTone.dark => p.card,
    CardTone.dim => p.cardDim,
    CardTone.paper => AppPalette.onPaper.surface,
    CardTone.accent => p.accent,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    final body = Padding(padding: padding, child: child);

    return Material(
      color: _background(p),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// A rounded icon tile — the square that sits beside a file name.
class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    this.size = AppSize.tile,
    this.radius = AppRadius.tile,
    this.background,
    this.foreground,
    this.strokeWidth,
    super.key,
  });

  const IconTile.round({
    required this.icon,
    this.size = AppSize.tileHero,
    this.background,
    this.foreground,
    this.strokeWidth,
    super.key,
  }) : radius = AppRadius.round;

  final String icon;
  final double size;
  final double radius;
  final Color? background;
  final Color? foreground;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? p.raised,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        icon,
        size: size * 0.45,
        color: foreground ?? p.textPrimary,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

/// A list row: icon tile, title, metadata, trailing affordance.
///
/// The workhorse of lanes B and D. [meta] is mono caps by construction — pass
/// the words, not the styling, so a row cannot end up with a sentence in the
/// metadata slot.
class HawkRow extends StatelessWidget {
  const HawkRow({
    required this.title,
    this.meta,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.tone = CardTone.dark,
    this.iconColor,
    this.metaColor,
    super.key,
  });

  final String title;

  /// Mono caps, under the title. "14 AUG · INDEXED · KEPT FOREVER".
  final String? meta;

  /// Sentence case, under the title. Used where a row explains itself rather
  /// than reporting state — the two are never both present.
  final String? subtitle;

  final String? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final CardTone tone;
  final Color? iconColor;

  /// The mono line's colour, when it says something the grey would bury —
  /// the accent on a row that has just finished indexing.
  final Color? metaColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkCard(
      tone: tone,
      radius: AppRadius.row,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.inset,
        vertical: AppSpacing.group,
      ),
      onTap: onTap,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (icon != null)
            IconTile(icon: icon!, foreground: iconColor),
          if (leading != null || icon != null)
            const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: p.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppTypography.caption.copyWith(color: p.textMuted),
                  ),
                ],
                if (meta != null) ...[
                  const SizedBox(height: 3),
                  MetaText(meta!, color: metaColor),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: AppSpacing.md),
            AppIcon(HawkIcons.chevronRight, size: 17, color: p.textFaint),
          ],
        ],
      ),
    );
  }
}

/// A stack of rows sharing one card, divided by hairlines — the profile's
/// settings group and the Vault's source list.
class RowGroup extends StatelessWidget {
  const RowGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        color: p.card,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: p.divider),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Text
// ===========================================================================

/// Mono metadata. Upper-cases its own string, because the tracking assumes
/// caps — a lower-case mono string in this style looks like a bug, and it is.
class MetaText extends StatelessWidget {
  const MetaText(
    this.text, {
    this.color,
    this.wide = false,
    this.size,
    super.key,
  });

  final String text;
  final Color? color;

  /// Wider tracking, for a section label inside a white card.
  final bool wide;

  final double? size;

  @override
  Widget build(BuildContext context) {
    final base = wide ? AppTypography.metaWide : AppTypography.meta;
    return Text(
      text.toUpperCase(),
      style: base.copyWith(
        color: color ?? context.palette.textMuted,
        fontSize: size,
      ),
    );
  }
}

/// A headline. Sized by the design's own scale rather than by a guess.
class Headline extends StatelessWidget {
  const Headline(
    this.text, {
    this.size = 34,
    this.color,
    this.align,
    super.key,
  });

  final String text;
  final double size;
  final Color? color;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    final style = switch (size) {
      >= 38 => AppTypography.display38,
      >= 34 => AppTypography.display34,
      >= 32 => AppTypography.display32,
      >= 30 => AppTypography.display30,
      >= 28 => AppTypography.display28,
      >= 26 => AppTypography.display26,
      >= 24 => AppTypography.display24,
      >= 22 => AppTypography.display22,
      _ => AppTypography.display18,
    };
    return Text(
      text,
      textAlign: align,
      style: style.copyWith(color: color ?? context.palette.textPrimary),
    );
  }
}

// ===========================================================================
// Indicators
// ===========================================================================

/// A status pill — "LISTENING", "3 FILES". The dot is present only when the
/// state is *live*; a count does not pulse.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.showDot = false,
    this.color,
    super.key,
  });

  final String label;
  final bool showDot;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: AppSize.statusPill,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          MetaText(label, color: color ?? p.textSecondary),
        ],
      ),
    );
  }
}

/// The selection dot: filled accent with a tick, or an empty ring.
class CheckDot extends StatelessWidget {
  const CheckDot({required this.selected, this.size = 24, super.key});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? p.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: selected ? null : Border.all(color: p.border, width: 2),
      ),
      alignment: Alignment.center,
      child: selected
          ? AppIcon(HawkIcons.check, size: size * 0.54, color: p.onAccent)
          : null,
    );
  }
}

/// A progress track. 8px on a dark card, 10px on a white one.
///
/// **Anything above zero shows.** The fill is at least as wide as the bar is
/// tall — a round dot — whenever [value] is positive. Without that, a plan
/// with 41 KB used of 256 GB drew a fill 0.00004px wide: two empty bars on
/// the profile card that read as placeholders, not as "barely used". Zero
/// still draws no fill, because nothing used is a true statement.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    required this.value,
    this.height = 8,
    this.fill,
    this.track,
    super.key,
  });

  /// A track on a white card. Always [PaperInk.track] — four white-card
  /// meters had drifted to three hard-coded greys, all near-invisible.
  ProgressTrack.onPaper({required double value, Key? key})
    : this(
        value: value,
        height: 10,
        fill: AppPalette.onPaper.ink,
        track: AppPalette.onPaper.track,
        key: key,
      );

  /// 0..1. Clamped, because a job that reports 1,517 of 1,516 should render
  /// a full bar rather than overflow its own card.
  final double value;

  final double height;
  final Color? fill;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);

    return Semantics(
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.round),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              final width = v <= 0
                  ? 0.0
                  : (box.maxWidth * v).clamp(height, box.maxWidth).toDouble();
              return ColoredBox(
                color: track ?? p.raised,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: fill ?? p.accent,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A quiet note in a dimmed card — the reassurances the design puts at the
/// bottom of a screen ("Removing here only deletes the index").
class InfoNote extends StatelessWidget {
  const InfoNote(
    this.text, {
    this.icon,
    this.iconColor,
    this.tone = CardTone.dim,
    super.key,
  });

  final String text;
  final String? icon;
  final Color? iconColor;

  /// [CardTone.dim] for a footnote nobody needs to read twice; [CardTone.dark]
  /// where the note is a promise the screen is making — the design lifts the
  /// privacy strip on 1B and 1G to the same surface as the buttons above it,
  /// and leaves the "this only deletes the index" notes a step down.
  final CardTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.inset,
      ),
      decoration: BoxDecoration(
        color: tone == CardTone.dark ? p.card : p.cardDim,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 17, color: iconColor ?? p.textMuted),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTypography.footnote.copyWith(
                color: tone == CardTone.dark ? p.textSecondary : p.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Segmented tabs
// ===========================================================================

/// The two-up segmented control at the top of Library.
///
/// The selected segment is a **white pill**, which is the design's way of
/// saying "this is what you are looking at" without spending the accent on
/// it — the accent is reserved for the dot that says Drive has something new.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.dotOn,
    this.badges = const {},
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Index of a segment carrying a live dot.
  final int? dotOn;

  /// A small accent tag beside a segment's label, by index — 1S puts the
  /// yearly saving there ("−20%"). Shown whether or not that segment is
  /// selected: it is the reason to pick it.
  final Map<int, String> badges;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: AppSize.tabs,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: AppSize.tabsInner,
                    decoration: BoxDecoration(
                      color: i == selected
                          ? AppPalette.onPaper.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          labels[i],
                          style: AppTypography.titleSmall.copyWith(
                            color: i == selected
                                ? AppPalette.onPaper.ink
                                : p.textMuted,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        if (badges[i] case final badge?) ...[
                          const SizedBox(width: 7),
                          Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(
                                AppRadius.round,
                              ),
                            ),
                            child: Text(
                              badge,
                              style: AppTypography.meta.copyWith(
                                fontSize: 8.5,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w600,
                                fontVariations: const [
                                  FontVariation('wght', 600),
                                ],
                                color: p.onAccent,
                              ),
                            ),
                          ),
                        ],
                        if (dotOn == i && i != selected) ...[
                          const SizedBox(width: 7),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: p.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
