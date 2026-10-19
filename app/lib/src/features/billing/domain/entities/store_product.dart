import 'package:freezed_annotation/freezed_annotation.dart';

import 'subscription.dart';

part 'store_product.freezed.dart';

/// One purchasable plan, with the price the *store* reports.
///
/// The price never comes from our server. Store prices are localised,
/// tax-inclusive where the jurisdiction requires it, and change without a
/// deploy — so a price we returned ourselves would eventually disagree with
/// what the user is actually charged, which is the one discrepancy a store
/// will reject a build over.
@freezed
abstract class StoreProduct with _$StoreProduct {
  const factory StoreProduct({
    required String productId,
    required Tier tier,

    /// 1 or 12.
    required int months,

    /// Already formatted and localised by the store: "£8.99", "¥1,200".
    required String price,
    @Default('') String currencyCode,
    @Default(0.0) double rawPrice,

    /// Length of a free introductory offer, in days, or null when there is
    /// none — or when the store did not say. Null is the safe reading: the
    /// payment sheet then shows the full price as charged today, and a
    /// sheet that under-promises a trial is wrong in the harmless direction.
    int? trialDays,

    /// False for a plan the store does not list yet — shown at the
    /// backend's reference price so the paywall can still compare plans,
    /// and never sold: its button reads "Coming soon".
    @Default(true) bool purchasable,

    /// False for a Razorpay pass (Android): one payment buys
    /// [StoreProduct.passDays] days and nothing renews. Store subscriptions
    /// renew until cancelled.
    @Default(true) bool autoRenews,
  }) = _StoreProduct;

  const StoreProduct._();

  bool get isAnnual => months == 12;

  /// Days one Razorpay pass lasts (`razorpay_payments.PASS_DAYS`).
  static const passDays = 30;

  /// "£90.00 / year" — the period, spelled out rather than abbreviated.
  String get priceLine => !autoRenews
      ? '$price / $passDays days'
      : isAnnual
      ? '$price / year'
      : '$price / month';
}
