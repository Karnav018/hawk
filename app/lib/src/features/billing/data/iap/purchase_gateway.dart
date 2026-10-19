import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';

/// The store SDK, behind an interface.
///
/// Wrapped for the usual reason — nothing above the data layer should know
/// what `PurchaseDetails` is — and for one specific to purchases: the flow is
/// **asynchronous and out-of-band**. `buyNonConsumable` returns almost
/// immediately; the actual result arrives later on a broadcast stream, and can
/// arrive for a purchase made on another device, or one the store retried
/// while the app was closed. Anything that models buying as a request with a
/// response gets that wrong.
abstract interface class PurchaseGateway {
  Future<bool> isAvailable();

  /// Store-formatted, localised prices for the ids we sell.
  Future<List<ProductDetails>> load(Set<String> productIds);

  /// Starts the flow and waits for *this* product's outcome.
  Future<PurchaseDetails> buy(ProductDetails product);

  /// Everything the device holds. Both stores replay past purchases onto the
  /// purchase stream rather than returning them, so this listens for a beat.
  Future<List<PurchaseDetails>> held();

  /// Tells the store the purchase was delivered.
  ///
  /// Not optional: an unacknowledged Android purchase is auto-refunded after
  /// three days, and an unfinished iOS transaction is replayed on every
  /// launch forever.
  Future<void> settle(PurchaseDetails purchase);

  String get storeName;
}

@LazySingleton(as: PurchaseGateway)
class StorePurchaseGateway implements PurchaseGateway {
  StorePurchaseGateway(this._logger) {
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      _updates.add,
      onError: (Object error) =>
          _logger.warning('Purchase stream failed', name: 'billing'),
    );
  }

  final AppLogger _logger;
  final _updates = StreamController<List<PurchaseDetails>>.broadcast();
  late final StreamSubscription<List<PurchaseDetails>> _subscription;

  /// Long enough for a card entry, a 2FA prompt and a password. A purchase
  /// that has not resolved by then has almost certainly been abandoned, and
  /// the store will replay it on the next launch if it was not.
  static const _timeout = Duration(minutes: 5);

  @override
  String get storeName =>
      Platform.isIOS || Platform.isMacOS ? 'app_store' : 'google_play';

  @override
  Future<bool> isAvailable() => InAppPurchase.instance.isAvailable();

  @override
  Future<List<ProductDetails>> load(Set<String> productIds) async {
    final response = await InAppPurchase.instance.queryProductDetails(
      productIds,
    );
    if (response.error != null) {
      throw AppException.badRequest(message: response.error!.message);
    }
    if (response.notFoundIDs.isNotEmpty) {
      // Not fatal: a half-configured store console is the normal state during
      // development, and the paywall should show what it can.
      _logger.warning(
        'Products missing from the store',
        name: 'billing',
        data: {'missing': response.notFoundIDs.join(',')},
      );
    }
    return response.productDetails;
  }

  @override
  Future<PurchaseDetails> buy(ProductDetails product) async {
    // Subscribed to *before* starting the flow. The store can deliver the
    // outcome faster than the await unwinds — especially for a purchase the
    // user already owns — and a listener attached afterwards misses it.
    final outcome = _updates.stream
        .expand((batch) => batch)
        .where((p) => p.productID == product.id)
        .firstWhere((p) => p.status != PurchaseStatus.pending)
        .timeout(_timeout);

    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );

    final purchase = await outcome;

    if (purchase.status == PurchaseStatus.canceled) {
      throw const AppException.cancelled(message: 'Purchase cancelled.');
    }
    if (purchase.status == PurchaseStatus.error) {
      throw AppException.badRequest(
        message:
            purchase.error?.message ?? 'The store could not complete that.',
      );
    }
    return purchase;
  }

  @override
  Future<List<PurchaseDetails>> held() async {
    final collected = <PurchaseDetails>[];
    final sub = _updates.stream.listen(collected.addAll);

    await InAppPurchase.instance.restorePurchases();
    // Restored purchases arrive on the stream, not as a return value, and
    // there is no completion signal — so this waits a bounded moment rather
    // than for an event that never comes.
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();

    return collected;
  }

  @override
  Future<void> settle(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    await InAppPurchase.instance.completePurchase(purchase);
  }

  /// Not annotated with `@disposeMethod`.
  ///
  /// injectable would generate the teardown call against the *interface*
  /// type this is registered as, and `PurchaseGateway` has no `dispose` — so
  /// the generated DI file stops compiling. The same annotation broke the
  /// build once before on a different repository.
  ///
  /// Not a leak in practice: this is a lazySingleton that lives as long as
  /// the app, and the purchase stream must stay subscribed for exactly that
  /// long anyway — a store can deliver a purchase made on another device, or
  /// one it retried while the app was closed, at any moment.
  @visibleForTesting
  void dispose() {
    _subscription.cancel();
    _updates.close();
  }
}
