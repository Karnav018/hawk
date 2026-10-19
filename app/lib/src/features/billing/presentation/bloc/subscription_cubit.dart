import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/repositories/billing_repository.dart';

/// The current user's plan, available to every screen.
///
/// Provided above the router alongside `SessionCubit`, for the same reason:
/// entitlements are not one screen's concern. What the free tier permits
/// shapes the home screen's ask affordance, the capture screen's headroom,
/// the library's dormant banner and the connect screen's account limit — and
/// a plan that each screen fetched for itself would be four round trips and
/// four chances to disagree.
///
/// A stream rather than a fetch, because nothing the app does changes a
/// subscription: it changes when a store notification writes Firestore, which
/// happens while the app is closed. So the app watches rather than asks.
///
/// Starts on the free tier rather than on a loading state. Every screen has
/// to render *something* before the first snapshot arrives, and the free
/// tier's limits are the safe assumption — assuming Premium would briefly
/// show an unmetered UI to someone who is metered, which then snaps back.
@lazySingleton
class SubscriptionCubit extends Cubit<Subscription>
    with SafeEmit<Subscription> {
  SubscriptionCubit(this._billing) : super(const Subscription()) {
    _subscription = _billing.watchSubscription().listen(
      emit,
      // A failed read must not blank the plan. The last known value is a
      // better answer than nothing, and the free tier is a safe default for
      // a user who has never had one.
      onError: (Object _) {},
    );
  }

  final BillingRepository _billing;
  late final StreamSubscription<Subscription> _subscription;

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
