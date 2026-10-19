import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../domain/entities/subscription.dart';

/// Screen 1X — ALERT PATTERNS.
///
/// The design draws these as a component sheet with a note under it: "these
/// appear inside real screens, never stacked together like this." So each is
/// chosen for the screen it sits on, and **at most one at a time** — two
/// banners about the same subscription read as the app nagging, and the
/// second one is never read.
enum PlanAlertKind {
  /// The store could not take the renewal. Most urgent: it is the only one
  /// where doing nothing loses something.
  paymentFailed,

  /// Nearly out of asks — the moment to mention the upgrade, before 1W
  /// blocks rather than after.
  asksLow,

  /// A paid plan that will not renew.
  downgrade,

  /// In a free trial that will turn into a charge.
  trial,
}

typedef PlanAlert = ({
  PlanAlertKind kind,
  String title,
  String subtitle,
  String action,
});

/// The alert for home's header, or null. Payment trouble first, then a
/// nearly-spent allowance, then a pending downgrade.
PlanAlert? homeAlert(Subscription plan, {DateTime? now}) =>
    _paymentFailed(plan) ?? _asksLow(plan, now) ?? _downgrade(plan, now);

/// The alert for the profile, or null. [price] is the store's price for the
/// plan's product, when known — the trial strip names what will be charged.
PlanAlert? profileAlert(Subscription plan, {String? price, DateTime? now}) =>
    _paymentFailed(plan) ?? _trial(plan, price, now) ?? _downgrade(plan, now);

PlanAlert? _paymentFailed(Subscription plan) {
  if (plan.status != SubscriptionStatus.inGrace) return null;
  // No "pauses in 3 days": no store path records when the grace period
  // ends, so a countdown here would be a number the app made up — on the
  // one alert about money going wrong.
  return (
    kind: PlanAlertKind.paymentFailed,
    title: 'Payment failed',
    subtitle: 'Update your payment to keep ${plan.tier.label}.',
    action: 'Fix',
  );
}

PlanAlert? _asksLow(Subscription plan, DateTime? now) {
  // The week, not the window. A two-hour window refills by itself within
  // the hour, so warning on it would put a banner up after every other
  // answer; the week is the allowance that runs out and stays out.
  final asks = plan.week;
  final limit = asks.limit;
  final left = asks.remaining;
  // Exhausted is 1W's job, not a banner's; unlimited has nothing to warn of;
  // the top tier has nothing to upgrade to.
  if (limit == null || limit == 0 || left == null || left <= 0) return null;
  if (!plan.canUpgrade) return null;
  // The last fifth, and always the last one.
  final threshold = (limit / 5).ceil().clamp(1, limit);
  if (left > threshold) return null;
  return (
    kind: PlanAlertKind.asksLow,
    title: '${asks.used} of $limit answers used this week',
    subtitle: resetsIn(plan.weekResetsAt, now: now),
    action: 'Upgrade',
  );
}

PlanAlert? _downgrade(Subscription plan, DateTime? now) {
  final end = plan.currentPeriodEnd;
  final today = now ?? DateTime.now();
  if (plan.tier == Tier.free || plan.autoRenewing || end == null) return null;
  if (!end.isAfter(today)) return null;
  if (plan.status == SubscriptionStatus.inGrace) return null;
  return (
    kind: PlanAlertKind.downgrade,
    title: 'Back on Free ${_inDays(end, today)}',
    // The design prints "842 memories over the 15 GB limit". The app does
    // not know Free's limits or how many memories would cross them, so it
    // says what will happen instead of inventing how much.
    subtitle: 'Anything over the Free limits goes dormant then.',
    action: 'Review',
  );
}

PlanAlert? _trial(Subscription plan, String? price, DateTime? now) {
  final end = plan.currentPeriodEnd;
  final today = now ?? DateTime.now();
  if (plan.status != SubscriptionStatus.inTrial || end == null) return null;
  if (!end.isAfter(today) || !plan.autoRenewing) return null;
  final days = end.difference(today).inDays.clamp(0, 9999);
  final left = days <= 1 ? 'Last day' : '$days days';
  return (
    kind: PlanAlertKind.trial,
    title: '$left of ${plan.tier.label} left',
    subtitle: price == null
        ? 'Renews ${shortDate(end)} unless cancelled'
        : '$price on ${shortDate(end)} unless cancelled',
    action: 'Manage',
  );
}

/// "in 14 days", "tomorrow", "today".
String _inDays(DateTime end, DateTime today) {
  final days = end.difference(today).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'tomorrow';
  return 'in $days days';
}

/// "Resets in 5 hours" — from the real reset time, which on a daily
/// allowance is hours away, not the design's "9 days".
String resetsIn(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Resets soon';
  final gap = at.difference(now ?? DateTime.now());
  if (gap.inMinutes < 60) return 'Resets in under an hour';
  if (gap.inHours < 24) {
    final h = gap.inHours;
    return 'Resets in $h hour${h == 1 ? '' : 's'}';
  }
  final d = gap.inDays;
  return d == 1 ? 'Resets tomorrow' : 'Resets in $d days';
}

String shortDate(DateTime d) {
  const months = [
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
  final l = d.toLocal();
  return '${l.day} ${months[l.month - 1]}';
}

/// One alert, drawn the way 1X draws its kind.
class PlanAlertCard extends StatelessWidget {
  const PlanAlertCard({required this.alert, required this.onAction, super.key});

  final PlanAlert alert;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Four surfaces, each meaning something: danger for money gone wrong,
    // accent for the trial (the one alert that is good news), and the
    // ordinary card for the two that are just information.
    final (
      Color bed,
      Color title,
      Color sub,
      Color pill,
      Color pillInk,
      String? icon,
    ) = switch (alert.kind) {
      PlanAlertKind.paymentFailed => (
        p.dangerWash,
        p.danger,
        p.danger.withValues(alpha: 0.72),
        p.danger,
        p.dangerWash,
        HawkIcons.info,
      ),
      PlanAlertKind.trial => (
        p.accent,
        p.onAccent,
        p.onAccent.withValues(alpha: 0.75),
        p.onAccent,
        p.textPrimary,
        null,
      ),
      PlanAlertKind.asksLow => (
        p.card,
        p.textPrimary,
        p.textMuted,
        p.accent,
        p.onAccent,
        HawkIcons.mic,
      ),
      PlanAlertKind.downgrade => (
        p.card,
        p.textPrimary,
        p.textMuted,
        p.raised,
        p.textSecondary,
        HawkIcons.info,
      ),
    };

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: bed,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.inset + 2,
          vertical: AppSpacing.inset,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              if (alert.kind == PlanAlertKind.paymentFailed)
                AppIcon(icon, size: 20, color: title)
              else
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.raised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(icon, size: 18, color: p.textSecondary),
                ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: AppTypography.titleSmall.copyWith(
                      color: title,
                      fontWeight: alert.kind == PlanAlertKind.trial
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.subtitle,
                    style: AppTypography.footnote.copyWith(
                      height: 1.5,
                      color: sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onAction,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pill,
                    borderRadius: BorderRadius.circular(AppRadius.round),
                  ),
                  child: Text(
                    alert.action,
                    style: AppTypography.footnote.copyWith(
                      fontWeight: FontWeight.w700,
                      color: pillInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
