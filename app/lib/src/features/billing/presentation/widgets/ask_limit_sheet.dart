import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../domain/entities/subscription.dart';
import '../pages/paywall_page.dart';
import 'plan_alerts.dart';

/// Screen 1W — the ask allowance is spent.
///
/// **This is the first thing that enforces it.** `Subscription.askLock` has
/// existed since the billing entity was written and was referenced by exactly
/// nothing — the limit was computed, surfaced nowhere, and a user with no
/// asks left could keep asking until the server refused. A plan limit the
/// client never mentions is worse than no limit: the failure arrives as an
/// error from a question the user was allowed to type.
///
/// Blocking, but not punishing. The first sentence the sheet spends is that
/// the library is *fine* — nothing was lost, nothing was un-indexed, and the
/// thing they have paid attention to building is still there. Only then does
/// it mention paying.
///
/// The two ways out are both real: upgrade, or wait. "Wait" is written as a
/// labelled action rather than a dismiss X, because waiting is a legitimate
/// choice here and a plan sheet that only offers the paid door is a
/// different kind of screen.
class AskLimitSheet extends StatelessWidget {
  const AskLimitSheet({
    required this.lock,
    required this.asks,
    this.resetAt,
    this.weekly = false,
    this.now,
    super.key,
  });

  final PlanLock lock;

  /// The allowance that is spent — the window's or the week's.
  final Allowance asks;

  /// When an answer comes back: the oldest one in the window returning, or
  /// the week resetting. Drives the reset line and the dated wait button;
  /// both are left out when the plan does not say.
  final DateTime? resetAt;

  /// Whether it is the week that is spent, rather than the window.
  final bool weekly;

  /// Injected for tests.
  final DateTime? now;

  static const _window = '2 hours';

  /// Shown from wherever a question is actually asked. Returns true when the
  /// caller should go on to ask — which, from this sheet, it never is.
  static Future<void> show(
    BuildContext context, {
    required PlanLock lock,
    required Allowance asks,
    DateTime? resetAt,
    bool weekly = false,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        AskLimitSheet(lock: lock, asks: asks, resetAt: resetAt, weekly: weekly),
  );

  /// Shown from a plan, which knows which limit is spent and when it frees.
  static Future<void> showFor(BuildContext context, Subscription plan) => show(
    context,
    lock: plan.askLock!,
    asks: plan.blockingAnswers,
    resetAt: plan.askAvailableAt,
    weekly: plan.askBlockedForWeek,
  );

  /// "Next one back in 40 minutes" — the window's line. Answers return one
  /// at a time, so it names the next one, never "all of them".
  @visibleForTesting
  static String backIn(DateTime at, {DateTime? now}) {
    final gap = at.difference(now ?? DateTime.now());
    if (gap.inMinutes < 1) return 'Next one back in a moment';
    if (gap.inMinutes < 60) return 'Next one back in ${gap.inMinutes} min';
    final h = gap.inHours;
    final m = gap.inMinutes % 60;
    return m == 0 ? 'Next one back in $h hr' : 'Next one back in $h hr $m min';
  }

  /// "Wait until 1 Oct" — or "later today" / "tomorrow" on a daily allowance,
  /// where a date alone would name today.
  @visibleForTesting
  static String waitLabel(DateTime? resetAt, {DateTime? now}) {
    if (resetAt == null) return 'Not now';
    final today = now ?? DateTime.now();
    final at = resetAt.toLocal();
    final days = DateTime(
      at.year,
      at.month,
      at.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days <= 0) return 'Wait until later today';
    if (days == 1) return 'Wait until tomorrow';
    return 'Wait until ${shortDate(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final limit = asks.limit;

    return SheetScaffold(
      // The design writes "You've used all 100\nasks this month". The number
      // is the plan's, and the sheet says nothing at all when the plan has
      // no ceiling — a headline claiming a limit that does not exist is the
      // one sentence this screen cannot afford to get wrong.
      headline: limit == null
          ? 'No answers left\nright now'
          : weekly
          ? "You've used all $limit\nanswers this week"
          : "You've used your $limit\nanswers for now",
      children: [
        Text(
          // The plan's own sentence. It carries the reset time, which is the
          // single fact that turns this from a wall into a wait.
          lock.reason,
          style: AppTypography.bodyMedium.copyWith(
            height: 1.6,
            color: paper.body,
          ),
        ),
        const SizedBox(height: AppSpacing.inset),

        // A quiet panel inside the white sheet — the design's #f3f5f0, which
        // is the paper surface a step down, not another card tone.
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F5F0),
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          padding: const EdgeInsets.all(AppSpacing.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      weekly ? 'This week' : 'Last $_window',
                      style: AppTypography.bodySmall.copyWith(
                        color: paper.body,
                      ),
                    ),
                  ),
                  if (limit != null)
                    Text(
                      '${asks.used} / $limit',
                      style: AppTypography.numeral.copyWith(color: paper.ink),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.gap + 1),
              ProgressTrack.onPaper(value: asks.fraction),
              if (resetAt != null) ...[
                const SizedBox(height: AppSpacing.gap + 1),
                MetaText(
                  (weekly
                          ? resetsIn(resetAt, now: now)
                          : backIn(resetAt!, now: now))
                      .toUpperCase(),
                  color: paper.muted,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.inset),

        // Only when paying would actually change the outcome. A fair-use
        // ceiling on the top tier is not upgradeable, and an upgrade button
        // there sells something that does not exist.
        if (lock.upgradeable)
          PillButton(
            label: 'Get more answers',
            icon: null,
            onPressed: () {
              Navigator.of(context).pop();
              context.pushNamed(PaywallPage.routeName);
            },
          ),
        const SizedBox(height: AppSpacing.md),
        PillButton(
          // 1W's quiet way out, dated — waiting is a real choice, and saying
          // until *when* is what makes it one.
          label: weekly || resetAt == null
              ? waitLabel(resetAt, now: now)
              : 'Wait until ${answerClock(resetAt!)}',
          tone: PillTone.paperQuiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
