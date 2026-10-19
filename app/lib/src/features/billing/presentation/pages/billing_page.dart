import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/plan_gate.dart';
import '../../../account/presentation/pages/profile_page.dart';
import '../../../account/presentation/widgets/profile_pieces.dart';
import '../../domain/entities/plan_summary.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/subscription.dart';
import '../bloc/billing_cubit.dart';
import '../store_links.dart';
import 'paywall_page.dart';

/// Screen 2J — BILLING AND RECEIPTS.
///
/// Every number on this screen comes from a store's own authenticated
/// answer: the next date from the verified subscription, the next amount
/// from the store's current price, and each receipt from a transaction the
/// backend fetched from Apple or Google itself. None of it is the app's
/// estimate, because a billing screen that is wrong once is not trusted
/// again.
///
/// **Where the design draws a card, this names the store.** Under store
/// billing the app never sees the card — Apple and Google hold it — so
/// "Visa ···· 4218" would be a card the app made up. "Change" opens the
/// store's own subscription page, which is also where cancelling lives.
class BillingPage extends StatelessWidget {
  const BillingPage({super.key});

  static const routeName = 'billing';
  static const routePath = '/billing';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final plan = context.plan;

    return BlocBuilder<BillingCubit, BillingState>(
      builder: (context, state) => AppScreen(
        ambientOpacity: 0,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenSide,
          AppSpacing.screenTop,
          AppSpacing.screenSide,
          AppSpacing.screenBottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleButton(
                  icon: HawkIcons.chevronLeft,
                  semanticLabel: 'Back',
                  onPressed: () => context.popOrGo(ProfilePage.routeName),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(child: Headline('Billing', size: 24)),
              ],
            ),
            const SizedBox(height: AppSpacing.card),
            _NextCharge(plan: plan, state: state),
            const SizedBox(height: AppSpacing.card),
            const MetaText('RECEIPTS'),
            const SizedBox(height: 10),
            Expanded(
              child: state.isLoading
                  ? const SizedBox.shrink()
                  : state.receipts.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: InfoNote(
                        'Receipts appear here once a purchase has been '
                        'confirmed by the store.',
                        icon: HawkIcons.info,
                        iconColor: p.textMuted,
                      ),
                    )
                  : ListView.separated(
                      itemCount: state.receipts.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.gap),
                      itemBuilder: (context, i) =>
                          _ReceiptRow(receipt: state.receipts[i]),
                    ),
            ),
            if (state.receipts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.inset),
              PillButton.secondary(
                label: 'Export all receipts',
                leadingIcon: HawkIcons.share,
                onPressed: () => unawaited(
                  SharePlus.instance.share(
                    ShareParams(
                      text: context.read<BillingCubit>().exportCsv(),
                      subject: 'Hawk receipts',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The white card: what happens next, and where it is managed.
class _NextCharge extends StatelessWidget {
  const _NextCharge({required this.plan, required this.state});

  final Subscription plan;
  final BillingState state;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final end = plan.currentPeriodEnd;
    // **Billed** is not the same as **paid-tier**. It used to be one test —
    // a paid tier *and* a period end — so a plan the server granted without
    // a store purchase (a test account, say) has no period end and was
    // drawn as "Free" here while the profile, reading the tier, said
    // Premium. The tier says what the plan is; the store fields say whether
    // anyone is charged for it.
    final billed =
        plan.tier.isPaid &&
        (end != null || plan.store != null || plan.productId != null);
    final amount = state.nextAmount(plan.productId);

    // Four honest states. A cancelled plan has no next charge — printing one
    // would tell somebody they are about to pay for a thing they have
    // already cancelled, on the screen they opened to check exactly that.
    final (String label, String figure, String? date) = !billed
        ? ('YOUR PLAN', plan.tier.label, null)
        : !plan.autoRenewing
        ? ('ENDS', 'No further charges', end == null ? null : billingDay(end))
        : amount != null
        ? ('NEXT CHARGE', amount, end == null ? null : billingDay(end))
        // Renewing, but no price known yet — no receipt, no store
        // catalogue. Say what renews rather than printing an empty headline.
        : ('RENEWS', plan.tier.label, end == null ? null : billingDay(end));

    return HawkCard(
      tone: CardTone.paper,
      padding: const EdgeInsets.all(AppSpacing.cardWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetaText(label, color: paper.muted, wide: true),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            figure,
                            style:
                                (figure.length > 12
                                        ? AppTypography.display22
                                        : AppTypography.display32)
                                    .copyWith(color: paper.ink),
                          ),
                        ),
                        if (date != null)
                          Text(
                            date,
                            style: AppTypography.numeral.copyWith(
                              color: paper.ink,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Only where an upgrade changes something, and never on a
              // billed plan — changing a store subscription is the store's
              // job, which is what "Change" below is for.
              if (!billed && plan.canUpgrade) ...[
                const SizedBox(width: AppSpacing.md),
                PaperAction(
                  label: 'Upgrade',
                  onPressed: () => context.pushNamed(PaywallPage.routeName),
                ),
              ],
            ],
          ),
          if (planLine(plan) case final line?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              line,
              style: AppTypography.footnote.copyWith(color: paper.muted),
            ),
          ],
          if (billed || plan.tier.isPaid) ...[
            const SizedBox(height: AppSpacing.inset),
            Divider(height: 1, color: paper.divider),
            const SizedBox(height: AppSpacing.inset),
            Row(
              children: [
                AppIcon(HawkIcons.shield, size: 18, color: paper.ink),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    billed
                        ? 'Paid through ${storeName(plan.store)}'
                        : 'Not billed through a store',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: paper.ink,
                    ),
                  ),
                ),
                if (billed)
                  GestureDetector(
                    onTap: () => unawaited(
                      launchUrl(
                        manageUrl(plan.store, plan.productId),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'Change',
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: paper.ink,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
            if (!billed) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(left: 18 + AppSpacing.md),
                child: Text(
                  'This plan was granted to the account. Nothing is charged '
                  'for it.',
                  style: AppTypography.footnote.copyWith(color: paper.muted),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// What the plan includes, from the allowances the server sent: "2 answers
/// every 2 hours · 30-day memory · 2 GB index". Null when none are known yet.
String? planLine(Subscription plan) {
  final asks = plan.window.limit;
  final days = plan.memoryWindowDays;
  final index = plan.index.limit;
  final parts = [
    if (asks != null)
      asks == 1
          ? '1 answer every ${plan.windowHours} hours'
          : '$asks answers every ${plan.windowHours} hours',
    switch (days) {
      null when plan.tier == Tier.premium => 'memories kept forever',
      null => null,
      365 => 'a year of memory',
      final d => '$d-day memory',
    },
    if (index != null) '${PlanSummary.allowance(index)} index',
  ].whereType<String>().toList();
  if (parts.isEmpty) return null;
  final line = parts.join(' · ');
  return '${line[0].toUpperCase()}${line.substring(1)}';
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = receipt.amountLabel(
      locale: Localizations.maybeLocaleOf(context)?.toString(),
    );

    return HawkRow(
      title: receipt.planName,
      meta: '${billingDay(receipt.chargedAt)} · ${receipt.statusLabel}',
      trailing: Text(
        // An em dash, not "$0.00", when the store did not report a price:
        // zero is a claim (a free trial), and this is the absence of one.
        amount ?? '—',
        style: AppTypography.numeralCode.copyWith(color: p.textPrimary),
      ),
    );
  }
}

/// "29 SEP 2026" — the design's receipt date.
///
/// From a fixed table, not `DateFormat`. `intl` only formats dates after
/// `initializeDateFormatting` has loaded the locale's symbols, which this app
/// never calls — `DateFormat('d MMM y', 'en')` threw on the first build of
/// this card. The design is English and the months are fixed; a table cannot
/// fail to initialise.
@visibleForTesting
String billingDay(DateTime date) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final d = date.toLocal();
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
