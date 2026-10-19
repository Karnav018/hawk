import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/plan_summary.dart';
import '../../domain/entities/store_product.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/repositories/billing_repository.dart';

part 'paywall_cubit.freezed.dart';

@freezed
abstract class PaywallState with _$PaywallState {
  const factory PaywallState({
    @Default(Subscription()) Subscription subscription,
    @Default(<StoreProduct>[]) List<StoreProduct> products,

    /// What each tier includes, from the backend's own table. Empty when it
    /// could not be read — the cards then go without feature lines.
    @Default(<Tier, PlanSummary>{}) Map<Tier, PlanSummary> plans,
    @Default(true) bool isLoading,

    /// The plan on the white card. Premium to start: it is the design's
    /// RECOMMENDED card, and the only tier that removes the memory window —
    /// which is what the headline promises.
    @Default(Tier.premium) Tier selected,

    /// Which product's store sheet is open. One at a time.
    String? purchasing,
    @Default(false) bool isRestoring,

    /// Set once a purchase has been granted, so the screen can confirm.
    Tier? purchased,
    AppException? exception,
  }) = _PaywallState;

  const PaywallState._();

  bool get isBusy => purchasing != null || isRestoring;

  /// True when this build cannot sell anything — an emulator, or a store
  /// console with no products configured yet.
  ///
  /// Distinct from "still loading" and from "failed": the screen says
  /// purchases are unavailable rather than spinning or erroring, which is the
  /// same rule screen 3F follows for an unconfigured provider.
  bool get storeUnavailable => !isLoading && products.isEmpty;

  List<StoreProduct> forTier(Tier tier) => [
    for (final p in products)
      if (p.tier == tier) p,
  ];

  /// What [tier] is sold as. Plans are monthly only (`products.CATALOGUE`),
  /// so there is one option per tier and no period to choose.
  StoreProduct? optionFor(Tier tier) => forTier(tier).firstOrNull;

  /// What the call to action buys.
  StoreProduct? get chosen => optionFor(selected);

  /// Paid tiers the store actually sells, best first.
  List<Tier> get paidTiers => [
    for (final tier in const [Tier.premium, Tier.standard])
      if (forTier(tier).isNotEmpty) tier,
  ];

  /// Whether [tier] is what the user already pays for.
  bool isCurrent(Tier tier) =>
      subscription.tier == tier &&
      (tier == Tier.free || subscription.status.isEntitled);
}

/// The paywall.
@injectable
class PaywallCubit extends Cubit<PaywallState> with SafeEmit<PaywallState> {
  PaywallCubit(this._billing) : super(const PaywallState()) {
    _subscription = _billing.watchSubscription().listen(
      (value) => emit(state.copyWith(subscription: value)),
      onError: (Object error, StackTrace stackTrace) =>
          emit(state.copyWith(exception: ErrorMapper.map(error, stackTrace))),
    );
    load();
  }

  final BillingRepository _billing;
  late final StreamSubscription<Subscription> _subscription;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, exception: null));
    try {
      // Started together, each read into a local before the emit: the
      // subscription listener can emit while these are in flight, and a
      // `copyWith` built around an `await` writes back the older state.
      final plans = _plans();
      final products = await _billing.products();
      final summaries = await plans;
      emit(
        state.copyWith(
          products: products,
          plans: summaries,
          isLoading: false,
          selected: _startingTier(products),
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  /// The feature lines are description, not the sale: a failure to read
  /// them leaves the cards plainer and must not stop anyone buying.
  Future<Map<Tier, PlanSummary>> _plans() async {
    try {
      return await _billing.plans();
    } catch (_) {
      return const {};
    }
  }

  /// Premium when the store sells it; otherwise whatever it does sell, so
  /// the white card is never an empty plan.
  Tier _startingTier(List<StoreProduct> products) {
    final sold = {
      for (final p in products)
        if (p.tier.isPaid) p.tier,
    };
    if (sold.isEmpty || sold.contains(state.selected)) return state.selected;
    return sold.contains(Tier.premium) ? Tier.premium : sold.first;
  }

  void choose(Tier tier) {
    if (state.isBusy || tier == Tier.free) return;
    emit(state.copyWith(selected: tier));
  }

  Future<void> buy(StoreProduct product) async {
    // A plan shown at its reference price is not for sale yet.
    if (state.isBusy || !product.purchasable) return;
    emit(state.copyWith(purchasing: product.productId, exception: null));

    try {
      final result = await _billing.buy(product);
      emit(state.copyWith(purchasing: null, purchased: result.tier));
    } on CancelledException {
      // Backing out of a store sheet is a decision, not a failure. An error
      // toast here would tell somebody off for changing their mind about
      // spending money.
      emit(state.copyWith(purchasing: null));
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          purchasing: null,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  /// Both stores require this as a visible action, and it is the only way
  /// onto a new phone.
  Future<void> restore() async {
    if (state.isBusy) return;
    emit(state.copyWith(isRestoring: true, exception: null));

    try {
      final result = await _billing.restore();
      emit(
        state.copyWith(
          isRestoring: false,
          // Only announced when something was actually found — "restored"
          // with nothing restored reads as a failure the user caused.
          purchased: result.tier.isPaid ? result.tier : null,
          exception: result.tier.isPaid
              ? null
              : const AppException.notFound(
                  message: 'No previous purchase found on this account.',
                ),
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isRestoring: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void acknowledge() => emit(state.copyWith(purchased: null));

  void dismissError() => emit(state.copyWith(exception: null));

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
