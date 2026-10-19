import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../domain/entities/store_product.dart';

/// Screen 1T — PAYMENT SHEET.
///
/// **A confirmation before the store's sheet, not a replacement for it.**
/// The design draws a saved card ("Visa ···· 4218"), "Add a card" and
/// "Confirm with Face ID". None of those belong to the app under store
/// billing: Apple and Google hold the card, present their own sheet, and run
/// Face ID themselves. `in_app_purchase` cannot skin that sheet, and an app
/// that drew a fake card row would be drawing a card it has never seen.
///
/// What the app *can* say, and what the design's sheet is really for, is
/// the schedule: what is charged today, what is charged when, and the date
/// before which cancelling costs nothing. That is the part people are
/// anxious about, and it is the part that stays here.
class PaymentSheet extends StatelessWidget {
  const PaymentSheet({required this.product, this.now, super.key});

  final StoreProduct product;

  /// Injected for tests; defaults to the real clock.
  final DateTime? now;

  /// Shows the sheet; resolves true when the user chose to go on to the
  /// store, false or null when they backed out.
  static Future<bool> show(BuildContext context, StoreProduct product) async =>
      await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => PaymentSheet(product: product),
      ) ??
      false;

  /// "the App Store" / "Google Play" — named, because "the store" leaves
  /// somebody unsure where to go to cancel.
  static String get storeName =>
      defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS
      ? 'the App Store'
      : 'Google Play';

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final today = now ?? DateTime.now();
    final trial = product.trialDays;
    final pass = !product.autoRenews;
    final payer = pass ? 'Razorpay' : storeName;
    final plan =
        'Hawk ${product.tier.label} · '
        '${pass
            ? '${StoreProduct.passDays} days'
            : product.isAnnual
            ? 'Yearly'
            : 'Monthly'}';

    // With a trial: nothing today, the full price when it ends. Without one:
    // the price today, and the date it renews — so the second row is never
    // empty and never a guess.
    final firstCharge = pass
        ? today.add(const Duration(days: StoreProduct.passDays))
        : trial != null
        ? today.add(Duration(days: trial))
        : _addMonths(today, product.months);

    return SheetScaffold(
      headline: 'Keep everything,\nforever',
      footnote: pass
          ? "One payment. It doesn't renew on its own."
          : trial != null
          ? 'Cancel any time before ${shortDay(firstCharge)} and you '
                "won't be charged."
          : 'Cancel any time in your $storeName account.',
      children: [
        Row(
          children: [
            AppIcon(HawkIcons.shieldCheck, size: 22, color: paper.ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan,
                    style: AppTypography.titleMedium.copyWith(color: paper.ink),
                  ),
                  const SizedBox(height: 3),
                  MetaText(terms(product), color: paper.muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.inset),

        // Where the design draws a card. The store holds it; this says so,
        // and says which store, which is where the user will go to change
        // it or to cancel.
        Container(
          decoration: BoxDecoration(
            color: paper.chip,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.inset,
            vertical: 15,
          ),
          child: Row(
            children: [
              AppIcon(HawkIcons.shield, size: 18, color: paper.ink),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paid through $payer',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: paper.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    MetaText(
                      pass
                          ? 'UPI, CARD OR NETBANKING · HAWK NEVER SEES THE CARD'
                          : 'YOUR STORE ACCOUNT · HAWK NEVER SEES THE CARD',
                      color: paper.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.inset),

        _Charge(
          when: 'Today',
          // "Free", not a hand-built "$0.00": the store's price string is
          // localised and tax-inclusive, and rebuilding a zero in the right
          // currency and format from `rawPrice` is exactly how a sheet ends
          // up disagreeing with the store's own.
          amount: trial != null ? 'Free' : product.price,
        ),
        const SizedBox(height: AppSpacing.gap),
        if (pass)
          _Charge(when: 'Lasts until', amount: shortDayYear(firstCharge))
        else
          _Charge(
            when: trial != null
                ? shortDayYear(firstCharge)
                : 'Renews ${shortDayYear(firstCharge)}',
            amount: product.price,
          ),
        const SizedBox(height: AppSpacing.card),

        PillButton(
          label: 'Continue to ${payer.replaceFirst('the ', '')}',
          tone: PillTone.paper,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // The design's "Confirm with Face ID" happens next, on the store's
          // own sheet. Saying so means the second sheet is expected rather
          // than alarming.
          '$payer confirms the payment on the next screen.',
          textAlign: TextAlign.center,
          style: AppTypography.footnote.copyWith(color: paper.muted),
        ),
      ],
    );
  }

  /// "7 DAYS FREE, THEN $96/YR", or "$96 / YEAR" without a trial.
  @visibleForTesting
  static String terms(StoreProduct product) {
    if (!product.autoRenews) return product.priceLine.toUpperCase();
    final per = product.isAnnual ? 'YR' : 'MO';
    final trial = product.trialDays;
    if (trial == null) return product.priceLine.toUpperCase();
    return '$trial DAYS FREE, THEN ${product.price}/$per';
  }

  static DateTime _addMonths(DateTime from, int months) {
    final month = from.month + months;
    final year = from.year + (month - 1) ~/ 12;
    final m = (month - 1) % 12 + 1;
    final lastDay = DateTime(year, m + 1, 0).day;
    return DateTime(year, m, from.day > lastDay ? lastDay : from.day);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @visibleForTesting
  static String shortDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  @visibleForTesting
  static String shortDayYear(DateTime d) => '${shortDay(d)} ${d.year}';
}

class _Charge extends StatelessWidget {
  const _Charge({required this.when, required this.amount});

  final String when;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    return Row(
      children: [
        Expanded(
          child: Text(
            when,
            style: AppTypography.bodySmall.copyWith(color: paper.body),
          ),
        ),
        Text(amount, style: AppTypography.numeral.copyWith(color: paper.ink)),
      ],
    );
  }
}
