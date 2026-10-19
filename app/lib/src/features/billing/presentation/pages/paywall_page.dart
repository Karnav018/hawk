import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../domain/entities/plan_summary.dart';
import '../../domain/entities/store_product.dart';
import '../../domain/entities/subscription.dart';
import '../bloc/paywall_cubit.dart';
import '../widgets/payment_sheet.dart';

/// Screen 1S — PRICING.
///
/// The design sells one plan, "Pro", against Free. This product sells two,
/// Standard and Premium, and the store products and the backend's
/// entitlement table are both built on that — so the design's layout is
/// applied to the real plans rather than the plans bent to the layout:
///
/// * **The white card is the plan the button buys.** Premium starts there —
///   it is the design's RECOMMENDED card, and the only tier that keeps
///   memories forever, which is what the headline promises. Tapping
///   Standard's dark card moves the white card to it.
/// * **Every line on a card comes from the backend** (`list_products`
///   returns `billing.ENTITLEMENTS`). The design's "15 GB · 100 asks a
///   month" and "1 TB indexed" are not this product's numbers, and a price
///   screen is the one place a made-up number is a promise.
/// * **Prices are the store's strings,** and every plan is monthly
///   (`products.CATALOGUE`), so there is no period toggle and no derived
///   per-month figure — the price on the card is what the store charges.
///
/// Led by what the user already has when there is something: a free user
/// with dormant memories is told how many are waiting, because retention
/// demotes rather than deletes (§36) and upgrading restores something they
/// already own.
class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key});

  static const routeName = 'paywall';
  static const routePath = '/upgrade';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PaywallCubit>();

    return BlocConsumer<PaywallCubit, PaywallState>(
      listenWhen: (a, b) =>
          a.purchased != b.purchased || a.exception != b.exception,
      listener: (context, state) {
        final error = state.exception;
        if (error != null) {
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Not completed',
              mark: SnackMark.failure,
              subtitle: error.displayMessage,
            ),
          );
          cubit.dismissError();
        }
        final tier = state.purchased;
        if (tier != null) {
          cubit.acknowledge();
          getIt<SnackController>().show(
            Snack.confirmation(message: '${tier.label} is active'),
          );
          if (context.canPop()) context.pop();
        }
      },
      builder: (context, state) => AppScreen(
        footer: state.isLoading || state.storeUnavailable
            ? null
            : _Checkout(
                state: state,
                // Screen 1T first. Choosing a plan is not agreeing to be
                // charged; the sheet says what is charged when, and only a
                // "Continue" there reaches the store's own sheet.
                onBuy: (product) async {
                  if (await PaymentSheet.show(context, product)) {
                    await cubit.buy(product);
                  }
                },
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              isRestoring: state.isRestoring,
              onRestore: state.isBusy ? null : cubit.restore,
            ),
            const SizedBox(height: AppSpacing.cardWide),
            const Headline('Keep everything,\nforever'),
            const SizedBox(height: AppSpacing.md),
            Text(
              _lead(state),
              style: AppTypography.bodyMedium.copyWith(
                color: context.palette.textTertiary,
              ),
            ),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.storeUnavailable) ...[
              const SizedBox(height: AppSpacing.card),
              _Unavailable(onRetry: cubit.load),
            ] else ...[
              const SizedBox(height: AppSpacing.card),
              // Every paid plan in full — price and every feature — so they can
              // be compared without tapping. The white one is what the button
              // buys; tapping a dark one makes it the white one.
              for (final tier in state.paidTiers) ...[
                _PaidPlan(
                  tier: tier,
                  product: state.optionFor(tier)!,
                  plan: state.plans[tier],
                  current: state.isCurrent(tier),
                  selected: tier == state.selected,
                  onTap: state.isBusy ? null : () => cubit.choose(tier),
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (!state.isLoading)
              _OtherPlan(
                tier: Tier.free,
                plan: state.plans[Tier.free],
                current: state.isCurrent(Tier.free),
              ),
          ],
        ),
      ),
    );
  }

  /// The line under the headline.
  ///
  /// The design's "Free keeps memories 30 days. Pro never forgets." — with
  /// both numbers read from the plans, so it cannot say 30 while the backend
  /// enforces something else. A user with dormant memories is told how many
  /// instead: that is the sentence that is actually about them.
  static String _lead(PaywallState state) {
    final sub = state.subscription;
    final free = state.plans[Tier.free];
    final premium = state.plans[Tier.premium];

    if (sub.memoriesDormant > 0) {
      final days = sub.memoryWindowDays;
      final count = sub.memoriesDormant == 1
          ? '1 memory is'
          : '${_grouped(sub.memoriesDormant)} memories are';
      return days == null
          ? '$count outside your window — still here. Upgrading makes them '
                'answerable again.'
          : '$count older than $days days — still here. Upgrading makes '
                'them answerable again.';
    }

    if (sub.isPaid && sub.tier == Tier.standard) {
      return 'You are on Standard. Premium removes every limit, including '
          'the memory window.';
    }

    if (free?.memoryWindowDays case final days?) {
      final paid = premium == null
          ? 'Paid plans keep them longer.'
          : premium.keepsForever
          ? 'Premium never forgets.'
          : 'Premium keeps them ${premium.memoryWindowDays} days.';
      return 'Free keeps memories $days days. $paid';
    }
    return 'Free forgets. Premium keeps every memory you give it.';
  }

  static String _grouped(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// Close, and RESTORE — the design's quiet top-right text.
///
/// Small, but not optional: both stores require a visible restore action,
/// and it is the only way onto a new phone.
class _Header extends StatelessWidget {
  const _Header({required this.isRestoring, required this.onRestore});

  final bool isRestoring;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleButton(
        icon: HawkIcons.close,
        semanticLabel: 'Close',
        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
      ),
      const Spacer(),
      Semantics(
        button: true,
        label: 'Restore a purchase',
        child: GestureDetector(
          onTap: onRestore,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // The text is 9.5px; the target is not.
            padding: const EdgeInsets.all(AppSpacing.md),
            child: MetaText(isRestoring ? 'Restoring…' : 'Restore'),
          ),
        ),
      ),
    ],
  );
}

/// The white card: the plan the button buys.
/// A paid plan, in full: name, price and every feature.
///
/// White when it is the plan the button buys — the one white card on the
/// screen — and dark otherwise, with the same contents, so both plans can be
/// read side by side without tapping. Tapping a dark one selects it.
class _PaidPlan extends StatelessWidget {
  const _PaidPlan({
    required this.tier,
    required this.product,
    required this.plan,
    required this.current,
    required this.selected,
    this.onTap,
  });

  final Tier tier;
  final StoreProduct product;
  final PlanSummary? plan;
  final bool current;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final p = context.palette;
    final ink = selected ? paper.ink : p.textPrimary;
    final muted = selected ? paper.muted : p.textMuted;
    final rule = selected ? paper.divider : p.divider;
    final label = current
        ? 'Current'
        : tier == Tier.premium
        ? 'Recommended'
        : null;

    return Semantics(
      button: !selected && onTap != null,
      selected: selected,
      label: selected ? null : 'Choose ${tier.label}',
      child: HawkCard(
        tone: selected ? CardTone.paper : CardTone.dark,
        padding: const EdgeInsets.all(AppSpacing.cardWide),
        onTap: selected ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label != null) ...[
                        MetaText(label, wide: true, color: muted),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      Headline(tier.label, size: 30, color: ink),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Headline(product.price, size: 30, color: ink),
                    const SizedBox(height: AppSpacing.xs),
                    MetaText(
                      !product.autoRenews
                          ? 'For ${StoreProduct.passDays} days'
                          : product.isAnnual
                          ? 'Per year'
                          : 'Per month',
                      color: muted,
                      size: 9,
                    ),
                  ],
                ),
              ],
            ),
            if (plan case final plan?) ...[
              Padding(
                // Tighter than a lone card: two full plans and Free have to clear
                // the pinned button on a 402-point phone.
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: ColoredBox(
                  color: rule,
                  child: const SizedBox(height: 1),
                ),
              ),
              for (final (i, line) in plan.features.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    AppIcon(HawkIcons.check, size: 16, color: ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: AppTypography.bodySmall.copyWith(
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          fontVariations: const [FontVariation('wght', 600)],
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Free's card: one line of what it includes. Nothing to buy, so no price
/// and no tap.
class _OtherPlan extends StatelessWidget {
  const _OtherPlan({
    required this.tier,
    required this.plan,
    required this.current,
  });

  final Tier tier;
  final PlanSummary? plan;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Headline(tier.label, size: 18)),
              if (current) const MetaText('Current'),
            ],
          ),
          if (plan case final plan?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              plan.summary,
              style: AppTypography.caption.copyWith(
                height: 1.55,
                color: p.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The call to action, pinned to the bottom, and what it will cost.
class _Checkout extends StatelessWidget {
  const _Checkout({required this.state, required this.onBuy});

  final PaywallState state;
  final Future<void> Function(StoreProduct) onBuy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final product = state.chosen;
    if (product == null) return const SizedBox.shrink();

    final current = state.isCurrent(product.tier);
    final trial = product.trialDays;
    final period = product.isAnnual ? 'a year' : 'a month';

    // Listed at the backend's reference price: the store does not sell it
    // yet (no console set up, or a device with no store). Shown, never sold.
    if (!product.purchasable && !current) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PillButton(label: 'Coming soon'),
          const SizedBox(height: 10),
          Text(
            '${product.price} $period. Purchases open soon.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(color: p.textFaint),
          ),
        ],
      );
    }

    final label = current
        ? "You're on ${product.tier.label}"
        : trial != null
        ? 'Start ${trial == 1 ? '1 day' : '$trial days'} free'
        : 'Get ${product.tier.label}';

    // "Then $96 a year." only after a trial — without one, the first charge
    // is today, and "then" would hide it.
    final terms = !product.autoRenews
        ? '${product.price} for ${StoreProduct.passDays} days. '
              'No auto-renewal.'
        : trial != null
        ? 'Then ${product.price} $period. Cancel any time.'
        : '${product.price} $period. Cancel any time.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PillButton(
          label: label,
          icon: current ? null : HawkIcons.arrowRight,
          isBusy: state.purchasing == product.productId,
          onPressed: current || state.isBusy ? null : () => onBuy(product),
        ),
        const SizedBox(height: 10),
        Text(
          current ? 'Manage or cancel in your store account.' : terms,
          textAlign: TextAlign.center,
          style: AppTypography.footnote.copyWith(color: p.textFaint),
        ),
      ],
    );
  }
}

/// No plans at all — `list_products` could not be reached. A store with no
/// products is not this case: those plans show at their reference price.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return HawkCard(
      tone: CardTone.dim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plans could not load', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Check your connection and try again. Nothing is wrong with your '
            'account.',
            style: AppTypography.caption.copyWith(color: p.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          InlineChip(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}
