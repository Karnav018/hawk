import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../features/billing/domain/entities/subscription.dart';
import '../../features/billing/presentation/bloc/subscription_cubit.dart';
import 'app_icons.dart';
import 'glass_panel.dart';
import 'tracked_label.dart';

/// Reads the current plan. Every gated affordance goes through this.
///
/// A helper rather than four screens each checking limits themselves: the
/// point of a plan is that it is one answer, and four call sites computing it
/// independently is four chances to disagree about what the same tier allows.
extension PlanContext on BuildContext {
  Subscription get plan => watch<SubscriptionCubit>().state;
}

/// The banner shown where something is locked by the plan.
///
/// Locked, not hidden. A feature that disappears teaches the user the product
/// cannot do it; one that is visibly locked teaches them what they would get —
/// and the same rule already governs screen 3F's unconfigured providers and
/// screen 3C's unbuilt capture paths. Consistency here is the point.
class PlanLockNotice extends StatelessWidget {
  const PlanLockNotice({required this.lock, this.compact = false, super.key});

  final PlanLock lock;

  /// A single line, for sitting under a control rather than replacing it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (compact) {
      return Row(
        children: [
          AppIcon(AppIcons.shieldCheck, size: 13, color: p.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              lock.reason,
              style: AppTypography.bodySmall.copyWith(color: p.textTertiary),
            ),
          ),
          if (lock.upgradeable)
            GestureDetector(
              onTap: () => context.pushNamed('paywall'),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Upgrade',
                style: AppTypography.bodySmall.copyWith(color: p.accentSoft),
              ),
            ),
        ],
      );
    }

    return GlassPanel(
      subtle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.shieldCheck, size: 15, color: p.caution),
              const SizedBox(width: AppSpacing.sm),
              TrackedLabel(
                // Named by what it is, not by the tier — "Free tier" reads as
                // a judgement, "Daily limit" as a fact.
                lock.upgradeable ? 'Plan limit' : 'Fair use',
                color: p.caution,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            lock.reason,
            style: AppTypography.bodyMedium.copyWith(
              color: p.textSecondary,
              height: 1.5,
            ),
          ),
          // No upgrade button where paying would not help. Offering one on a
          // fair-use ceiling would be selling something we cannot deliver.
          if (lock.upgradeable) ...[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: () => context.pushNamed('paywall'),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    'See plans',
                    style: AppTypography.bodyMedium.copyWith(
                      color: p.accentSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(AppIcons.arrowRight, size: 15, color: p.accentSoft),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
