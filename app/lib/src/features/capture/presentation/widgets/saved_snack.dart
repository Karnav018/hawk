import 'package:flutter/foundation.dart';

import '../../../../core/feedback/snack.dart';
import '../../../billing/domain/entities/subscription.dart';

/// What saving [count] files says — from the library's tiles and home's
/// camera alike, so the two never word the same event differently.
///
/// On a plan with a memory window, the moment of saving is when the window
/// is worth saying out loud (screen 1X's upload toast): "goes dormant", not
/// "expires", because nothing is deleted and an upgrade brings it back.
/// Everywhere else it is the everyday confirmation.
Snack savedSnack(
  Subscription plan, {
  required int count,
  required VoidCallback onKeep,
}) {
  final window = plan.memoryWindowDays;
  if (window != null && plan.canUpgrade) {
    return Snack.detail(
      title: count > 1
          ? 'Saved $count files — dormant in $window days'
          : 'Saved — goes dormant in $window days',
      subtitle: '${plan.tier.label} plan memory window',
      mark: SnackMark.clock,
      action: SnackAction(
        label: 'Keep',
        style: SnackActionStyle.text,
        onPressed: onKeep,
      ),
    );
  }
  // The count, because a batch that silently reported "Saved" would leave
  // somebody who picked four files wondering whether all four arrived.
  return Snack.confirmation(
    message: count > 1
        ? 'Saved $count files — reading them now'
        : 'Saved — reading it now',
  );
}
