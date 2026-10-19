import 'package:intl/intl.dart';

import 'subscription.dart';

/// One charge, as a store's own authenticated API reported it — screen 2J.
///
/// Written only by the backend (`billing_api._record_receipt`), from the
/// App Store Server API or Play's `subscriptionsv2`, never from anything the
/// client said about its own purchase. The rules forbid client writes.
class Receipt {
  const Receipt({
    required this.id,
    required this.productId,
    required this.tier,
    required this.chargedAt,
    required this.trial,
    this.months,
    this.amountMicros,
    this.currency,
    this.store,
  });

  final String id;
  final String productId;
  final Tier tier;
  final int? months;
  final DateTime chargedAt;

  /// Micros of [currency]. Null when the store did not report a price —
  /// which is shown as missing, never as zero. Zero means a free trial.
  final int? amountMicros;
  final String? currency;
  final bool trial;
  final String? store;

  /// "Hawk Premium · Yearly".
  String get planName {
    final period = switch (months) {
      12 => ' · Yearly',
      1 => ' · Monthly',
      _ => '',
    };
    return 'Hawk ${tier.label}$period';
  }

  /// "TRIAL STARTED" or "PAID".
  String get statusLabel => trial ? 'TRIAL STARTED' : 'PAID';

  /// "$96.00", in the currency it was charged in — or null when unknown.
  ///
  /// Formatted by `intl` from the currency code rather than by hand: a
  /// receipt is the one place a wrong decimal count ("¥1,200.00") or a
  /// dollar sign on a pound charge would be read as an error in the bill.
  String? amountLabel({String? locale}) {
    final micros = amountMicros;
    if (micros == null) return null;
    final value = micros / 1000000;
    // A locale `intl` has no number data for throws rather than formats. The
    // one screen about money must not crash on an unusual device setting, so
    // an unknown locale falls back to English grouping.
    final safe = locale == null
        ? null
        : Intl.verifiedLocale(
            locale,
            NumberFormat.localeExists,
            onFailure: (_) => 'en',
          );
    final code = currency;
    if (code == null || code.isEmpty) {
      return NumberFormat.decimalPatternDigits(
        locale: safe,
        decimalDigits: 2,
      ).format(value);
    }
    return NumberFormat.simpleCurrency(locale: safe, name: code).format(value);
  }
}
