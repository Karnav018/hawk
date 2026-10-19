import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// The free trial a store attaches to a product, in days — or null.
///
/// `ProductDetails` is deliberately platform-neutral and drops introductory
/// offers entirely, so the answer has to be read off each store's own
/// subclass. Anything unrecognised — a paid intro price, a pay-as-you-go
/// discount, a store we do not know — is null, never a guess: screen 1T
/// prints "Today · Free" on the strength of this number.
int? trialDaysOf(ProductDetails details) {
  if (details is AppStoreProductDetails) {
    final intro = details.skProduct.introductoryPrice;
    // `freeTrail` is the plugin's own spelling on the wrapper enum (its
    // pigeon enum says `freeTrial`). Not a typo here — correcting it breaks
    // the build.
    if (intro == null ||
        intro.paymentMode != SKProductDiscountPaymentMode.freeTrail) {
      return null;
    }
    final unit = switch (intro.subscriptionPeriod.unit) {
      SKSubscriptionPeriodUnit.day => 1,
      SKSubscriptionPeriodUnit.week => 7,
      SKSubscriptionPeriodUnit.month => 30,
      SKSubscriptionPeriodUnit.year => 365,
    };
    final periods = intro.numberOfPeriods < 1 ? 1 : intro.numberOfPeriods;
    return intro.subscriptionPeriod.numberOfUnits * unit * periods;
  }

  if (details is GooglePlayProductDetails) {
    final offers = details.productDetails.subscriptionOfferDetails;
    final index = details.subscriptionIndex;
    if (offers == null || index == null || index >= offers.length) return null;
    // A free trial is the pricing phase that costs nothing. The first one,
    // because Play orders phases chronologically.
    for (final phase in offers[index].pricingPhases) {
      if (phase.priceAmountMicros != 0) continue;
      final days = isoPeriodDays(phase.billingPeriod);
      if (days == null) return null;
      final cycles = phase.billingCycleCount < 1 ? 1 : phase.billingCycleCount;
      return days * cycles;
    }
    return null;
  }

  return null;
}

/// "P7D" → 7, "P1W" → 7, "P1M" → 30, "P1Y" → 365.
///
/// Play reports periods as ISO-8601 durations. Months and years are
/// counted at their calendar-naive lengths because this number is only ever
/// used to print a trial's end date on a confirmation sheet, where the store
/// itself is the authority and restates the exact date on its own screen.
int? isoPeriodDays(String period) {
  final match = RegExp(
    r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$',
  ).firstMatch(period.trim().toUpperCase());
  if (match == null) return null;
  int part(int group) => int.tryParse(match.group(group) ?? '') ?? 0;
  final days = part(1) * 365 + part(2) * 30 + part(3) * 7 + part(4);
  return days > 0 ? days : null;
}
