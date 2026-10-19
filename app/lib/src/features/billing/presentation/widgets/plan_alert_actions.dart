import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../account/presentation/pages/vault_page.dart';
import '../bloc/subscription_cubit.dart';
import '../pages/billing_page.dart';
import '../pages/paywall_page.dart';
import '../store_links.dart';
import 'plan_alerts.dart';

/// Where each 1X alert's button goes. One place, so home and profile cannot
/// send the same alert to two different screens.
///
/// * **Fix** (payment failed) — the store's own subscription page, because
///   the store holds the card and is the only place it can be updated.
/// * **Upgrade** (asks low) — the paywall.
/// * **Review** (downgrade) — the vault, where storage is itemised and the
///   user can see what will cross the Free limits.
/// * **Manage** (trial) — Billing (2J), which names the date and the amount
///   and links on to the store for cancelling.
void onPlanAlert(BuildContext context, PlanAlert alert) {
  // `read`, not the `plan` extension's `watch`: this runs in a tap
  // handler, where subscribing to rebuilds is an error.
  final plan = context.read<SubscriptionCubit>().state;
  switch (alert.kind) {
    case PlanAlertKind.paymentFailed:
      unawaited(
        launchUrl(
          manageUrl(plan.store, plan.productId),
          mode: LaunchMode.externalApplication,
        ),
      );
    case PlanAlertKind.asksLow:
      unawaited(context.pushNamed(PaywallPage.routeName));
    case PlanAlertKind.downgrade:
      unawaited(context.pushNamed(VaultPage.routeName));
    case PlanAlertKind.trial:
      unawaited(context.pushNamed(BillingPage.routeName));
  }
}
