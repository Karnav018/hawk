import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../billing/domain/entities/subscription.dart';
import '../../../billing/presentation/store_links.dart';

/// The shapes lane D needs that `hawk_kit.dart` does not draw yet.
///
/// Everything here is a *local* component on purpose: the kit is owned by
/// another lane and the port runs in parallel, so a shape that only 1Q and 1R
/// use lives with 1Q and 1R until somebody promotes it. Each one carries a
/// note saying what it would be called in the kit, so promoting it is a move
/// rather than a redesign.
///
/// v2's version of this file held `ProfileSection`, `ProfileRow` and
/// `ProfileStat` — a card with a tracked-caps header, a two-line row with a
/// coloured hue bubble, and a stat tile. All three are gone. v3 has one row
/// vocabulary (`RowGroup` + a row), no hue wheel, and no section headers: the
/// white card *is* the heading, and a group of settings needs no label above
/// it because the three things in it are self-describing.

// ===========================================================================
// Rows
// ===========================================================================

/// A settings row inside a [RowGroup] — 1Q's three destinations.
///
/// Not `HawkRow`. The kit's row is built for a *file*: it puts the glyph in a
/// 42px raised tile and stacks a title over metadata, which lands at about
/// 47px for a title-only row. The design draws a settings row at 62px with a
/// bare 19px stroke and nothing under the title — the icon is a signpost, not
/// a thumbnail, and giving it a tile would make three settings look like
/// three documents.
///
/// Candidate for the kit as `HawkRow.setting`.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    super.key,
  });

  final String icon;
  final String title;

  /// Mono caps on the right, in the accent — the row reports a *setting* the
  /// user has chosen rather than leading somewhere. When it is set, no
  /// chevron is drawn: a row that both shows a value and promises a screen is
  /// two rows pretending to be one.
  final String? value;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: onTap != null,
      label: value == null ? title : '$title. $value',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            // 62. Not in [AppSize] because the theme belongs to no lane; it
            // wants to be `AppSize.settingRow` once this row is promoted.
            height: 62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  AppIcon(
                    icon,
                    size: 19,
                    color: p.textPrimary,
                    strokeWidth: 1.9,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSoft.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  if (value != null)
                    MetaText(value!, color: p.accent)
                  else
                    AppIcon(
                      HawkIcons.chevronRight,
                      size: 17,
                      color: p.textFaint,
                      strokeWidth: 2.2,
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

/// The 10px accent dot the design puts on a source that is live.
///
/// A dot, never a chevron, and never both: the dot says "this is working and
/// there is nothing to do", the chevron says "there is more in here". Drawing
/// them together is how a settings screen ends up with a row that leads
/// nowhere.
class LiveDot extends StatelessWidget {
  const LiveDot({this.size = 10, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.palette.accent,
      shape: BoxShape.circle,
    ),
  );
}

// ===========================================================================
// On paper
// ===========================================================================

/// The ink-filled pill inside a white card — 1Q's "Upgrade".
///
/// [InlineChip] cannot be it: its two tones are `raised` and `accent`, both of
/// which are colours for a *dark* surface, and neither is legible on #fff. On
/// paper the accent would also break the one-accent rule twice over — the
/// white card is already the loudest thing on the screen, so its own action is
/// ink.
///
/// Candidate for the kit as `InlineChip.paper`.
class PaperAction extends StatelessWidget {
  const PaperAction({required this.label, this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: paper.ink,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: AppSize.chipLarge,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              label,
              style: AppTypography.chip.copyWith(
                fontSize: 14,
                color: paper.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A static pill on paper — 1R's breakdown chips.
///
/// Not [PaperAction] with a null callback: this one is a *fact*, so it takes
/// the card's inset grey rather than ink, and carries no button semantics. A
/// count that looks pressable is a count somebody will press.
class PaperPill extends StatelessWidget {
  const PaperPill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Container(
      height: AppSize.chip,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: paper.chip,
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: Text(
        label,
        style: AppTypography.chip.copyWith(
          fontWeight: FontWeight.w600,
          fontVariations: const [FontVariation('wght', 600)],
          color: paper.ink,
        ),
      ),
    );
  }
}

/// One allowance on the plan card: a label, the figure, and a 10px bar.
///
/// The figure is mono and the label is not, which is the whole typographic
/// rule in one row — "9.1 / 15 GB" is metadata, "Storage" is a word.
///
/// [fraction] is null when the plan has no ceiling, and then no bar is drawn
/// at all. The obvious alternative — a full bar — reads as *spent*, and the
/// other obvious one — an empty bar — reads as a limit at zero. An unlimited
/// allowance is not a meter, so it does not get one.
///
/// Candidate for the kit as `ProgressTrack`'s labelled form.
class PaperMeter extends StatelessWidget {
  const PaperMeter({
    required this.label,
    required this.value,
    this.fraction,
    super.key,
  });

  final String label;
  final String value;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: paper.body,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              value,
              style: AppTypography.numeral.copyWith(color: paper.ink),
            ),
          ],
        ),
        if (fraction != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ProgressTrack.onPaper(value: fraction!),
        ],
      ],
    );
  }
}

/// The white sheet lane D's three confirmations are asked in.
///
/// A deliberate near-copy of `SheetScaffold`, and the reason is worth writing
/// down: `SheetScaffold` is a **route**, presented by the router with a
/// transparent page so the screen behind shows through. Lane D cannot add
/// routes — the router belongs to nobody's feature — so these three are
/// presented with `showModalBottomSheet` instead, and the route-shaped
/// scaffold does not fit inside one.
///
/// Promote by giving `SheetScaffold` a body-only constructor that both the
/// route and an imperative sheet can share; the geometry here is copied from
/// it exactly so that the move changes no pixels.
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    required this.headline,
    required this.children,
    this.footnote,
    super.key,
  });

  final String headline;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Padding(
      // The delete sheet has a text field in it, so the sheet has to ride the
      // keyboard rather than sit under it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // Scrollable so a sheet cannot overflow: the delete sheet is the tallest
      // in the app and it grows by a keyboard's height the moment it is
      // touched. A bottom sheet does not scroll on its own, and the failure
      // mode is a black-and-yellow stripe across a confirmation.
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: paper.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.card,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: paper.handle,
                      borderRadius: BorderRadius.circular(AppRadius.round),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.card),
                Text(
                  headline,
                  style: AppTypography.display24.copyWith(color: paper.ink),
                ),
                const SizedBox(height: AppSpacing.lg),
                ...children,
                if (footnote != null) ...[
                  const SizedBox(height: AppSpacing.inset),
                  Text(
                    footnote!,
                    style: AppTypography.footnote.copyWith(color: paper.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Numbers
// ===========================================================================

/// Every count is set in the metadata face with a thousands comma, so the
/// grouping is done here rather than by an intl formatter: `NumberFormat`
/// would localise the separator, and "1.516 files" next to "9.1 GB" would read
/// as a decimal.
String groupedCount(int value) => value.abs().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Bytes as the shortest honest string: "9.1 GB", "612 MB", "15 GB".
///
/// One decimal only below 10, because "15.0 GB" claims a precision the
/// allowance does not have — the limit is exactly 15.
String byteLabel(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    final value = bytes / gib;
    return '${value >= 10 || value == value.roundToDouble() ? value.round() : value.toStringAsFixed(1)} GB';
  }
  if (bytes >= mib) {
    final value = bytes / mib;
    return '${value >= 10 ? value.round() : value.toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// "9.1 / 15 GB" — the unit is printed once, on the limit, the way the design
/// writes it. Spelling it out twice is correct and reads like a receipt.
String byteRatio(int used, int limit) {
  const gib = 1024 * 1024 * 1024;
  // An empty vault is "0 / 15 GB", not "0 KB / 15 GB". Zero has no unit, and
  // printing one makes the smallest possible number look like a measurement.
  if (used <= 0) return '0 / ${byteLabel(limit)}';
  final sameUnit = used >= gib == (limit >= gib);
  if (!sameUnit) return '${byteLabel(used)} / ${byteLabel(limit)}';
  final usedLabel = byteLabel(used);
  return '${usedLabel.split(' ').first} / ${byteLabel(limit)}';
}

/// Screen 1U's two rows — "Payment method" and "Cancel subscription" — on a
/// paid plan only. A free plan has nothing to pay with and nothing to cancel.
///
/// The design prints "VISA 4218". Under store billing the app never sees
/// the card, so the value is the store that holds it, and both rows open
/// that store's own subscription page: that is where a card is changed and
/// where a subscription is cancelled. A cancel button that did anything
/// else would be one the store does not honour.
List<Widget> paidPlanRows(BuildContext context) {
  final plan = context.plan;
  if (plan.tier == Tier.free) return const [];

  void openStore() => unawaited(
    launchUrl(
      manageUrl(plan.store, plan.productId),
      mode: LaunchMode.externalApplication,
    ),
  );

  return [
    SettingRow(
      icon: HawkIcons.shield,
      title: 'Payment method',
      // "APP STORE" / "GOOGLE PLAY" — the value column is mono caps.
      value: storeName(plan.store).replaceFirst('the ', '').toUpperCase(),
      onTap: openStore,
    ),
    SettingRow(
      icon: HawkIcons.close,
      title: 'Cancel subscription',
      onTap: openStore,
    ),
  ];
}
