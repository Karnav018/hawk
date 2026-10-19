import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/cache/cache_store.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/plan_summary.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/store_product.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/repositories/billing_repository.dart';
import '../iap/purchase_gateway.dart';
import '../iap/trial_offer.dart';
import '../live_plan.dart';
import '../razorpay/razorpay_checkout.dart';

/// [BillingRepository] over the store SDK plus our callables.
///
/// The division of labour is the important part, and it is not negotiable:
///
/// * The **store** owns prices and takes the money.
/// * The **server** owns what the user gets. It re-asks the store whether the
///   purchase is real; the token the client sends is a lookup key and nothing
///   more.
/// * The **client** owns nothing. It cannot name its own tier, and does not
///   write the subscription document — `firestore.rules` denies that — so a
///   patched build cannot grant itself Premium.
///
/// Reading is a Firestore listener rather than a call, because the things that
/// change a subscription mostly happen while the app is closed: a renewal, a
/// lapse, a refund. Those arrive as store notifications that write Firestore,
/// so the app has to be watching rather than asking.
@LazySingleton(as: BillingRepository)
class FirebaseBillingRepository implements BillingRepository {
  FirebaseBillingRepository(
    this._firestore,
    this._functions,
    this._auth,
    this._purchases,
    this._logger,
    this._cache,
    this._razorpay,
  );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final fb.FirebaseAuth _auth;
  final PurchaseGateway _purchases;
  final AppLogger _logger;

  /// Holds the last plan answer, so the app opens on the real plan instead
  /// of the free tier while `get_subscription` is in flight.
  final CacheStore _cache;

  /// Android and iOS pay in rupees through Razorpay (user decisions,
  /// 14 Oct 2026); anywhere else buys through the store.
  final RazorpayCheckout _razorpay;

  @override
  Stream<Subscription> watchSubscription() {
    // Keyed to the auth state, not to whoever is signed in when this is
    // called. SubscriptionCubit subscribes once, before the first frame and
    // before anyone has signed in, and lives through every sign-in, sign-out
    // and account switch. Reading the uid once threw on launch, and would
    // otherwise have kept showing the first account's plan to the next.
    StreamSubscription<String?>? users;
    StreamSubscription<Subscription>? plan;

    final controller = StreamController<Subscription>();
    controller
      ..onListen = () {
        users = _auth
            .authStateChanges()
            .map((user) => user?.uid)
            .distinct()
            .listen((uid) {
              unawaited(plan?.cancel());
              plan = null;
              if (uid == null) {
                // Signed out is the free tier rather than an error: the same
                // safe default the cubit starts on.
                controller.add(const Subscription());
                return;
              }
              plan = _watchPlan(
                uid,
              ).listen(controller.add, onError: controller.addError);
            }, onError: controller.addError);
      }
      ..onCancel = () async {
        await plan?.cancel();
        await users?.cancel();
      };

    return controller.stream.handleError(_rethrow);
  }

  @override
  Stream<List<Receipt>> watchReceipts() {
    final uid = _auth.currentUser?.uid;
    // 2J is only reachable signed in; signed out has no receipts to show.
    if (uid == null) return Stream.value(const <Receipt>[]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('receipts')
        .orderBy('chargedAt', descending: true)
        // A generous page. Years of monthly receipts is well under this, and
        // a billing screen that paginates is one people give up on.
        .limit(120)
        .snapshots()
        .map(
          (snap) => [for (final doc in snap.docs) _receipt(doc.id, doc.data())],
        )
        .handleError(_rethrow);
  }

  Receipt _receipt(String id, Map<String, dynamic> d) => Receipt(
    id: id,
    productId: d['productId'] as String? ?? '',
    tier: Tier.parse(d['tier'] as String?),
    months: (d['months'] as num?)?.toInt(),
    chargedAt: _moment(d['chargedAt']) ?? DateTime.now(),
    amountMicros: (d['amountMicros'] as num?)?.toInt(),
    currency: d['currency'] as String?,
    trial: d['trial'] as bool? ?? false,
    store: d['store'] as String?,
  );

  /// The plan, kept current with what the user uses — see [LivePlan] for
  /// why the subscription document alone was not enough.
  Stream<Subscription> _watchPlan(String uid) {
    final user = _firestore.collection('users').doc(uid);
    return LivePlan(
      plan: user
          .collection('subscription')
          .doc('current')
          .snapshots()
          .map((doc) => doc.data() ?? const {}),
      account: user.snapshots(),
      usage: user.collection('usage').doc('answers').snapshots(),
      allowances: _allowances,
      cached: () async => (await _cache.read(_allowancesKey))?.value,
    ).watch();
  }

  static const _allowancesKey = 'plan.allowances';

  /// The consumable allowances, computed server-side — or null when the call
  /// failed, so [LivePlan] keeps the last good numbers instead.
  Future<Map<String, dynamic>?> _allowances() async {
    try {
      final result = await _functions
          .httpsCallable('get_subscription')
          // The phone's zone, so "resets Monday" is the user's Monday.
          .call<Object?>({
            'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
          });
      final data = result.data;
      if (data is! Map) return null;
      final json = jsonSafe(data);
      unawaited(_cache.write(_allowancesKey, json));
      return json;
    } on FirebaseFunctionsException {
      return null;
    }
  }

  @override
  Future<List<StoreProduct>> products() async {
    final catalogue = await _productIds();
    if (catalogue.isEmpty) return const [];
    if (_razorpay.available) return razorpayProductsFrom(catalogue);

    // What the store lists, when there is a store. An emulator, a device
    // with no store, or a console not set up yet all come back as nothing —
    // and the paywall then shows the reference prices instead of an apology.
    var details = const <ProductDetails>[];
    try {
      if (await _purchases.isAvailable()) {
        details = await _purchases.load(catalogue.keys.toSet());
      }
    } on Object {
      details = const [];
    }
    return storeProductsFrom(catalogue, details);
  }

  @override
  Future<Map<Tier, PlanSummary>> plans() async => (await _catalogue()).plans;

  Future<Map<String, CatalogueEntry>> _productIds() async =>
      (await _catalogue()).ids;

  /// `list_products`, fetched once and shared.
  ///
  /// The paywall asks for products and plans together, and both come from
  /// the same callable — without this it made the same call twice on every
  /// open. Only a successful answer is kept: a failure is retried on the
  /// next ask rather than remembered as "there are no plans".
  Future<_Catalogue> _catalogue() {
    final pending = _listed ??= _listProducts();
    return pending.then((value) {
      if (value.isEmpty && identical(_listed, pending)) _listed = null;
      return value;
    });
  }

  Future<_Catalogue>? _listed;

  Future<_Catalogue> _listProducts() async {
    try {
      final result = await _functions
          .httpsCallable('list_products')
          .call<Object?>();
      final data = result.data;
      if (data is! Map) return const _Catalogue();
      final plans = data['plans'];
      return _Catalogue(
        ids: {
          for (final raw in (data['products'] as List? ?? const []))
            (raw as Map)['productId'] as String: (
              tier: raw['tier'] as String? ?? 'free',
              months: (raw['months'] as num?)?.toInt() ?? 1,
              price: raw['referencePrice'] as String?,
              amount: (raw['referenceAmount'] as num?)?.toDouble() ?? 0,
              currency: raw['currency'] as String? ?? '',
              inrPrice: raw['inrPrice'] as String?,
              inrAmount: (raw['inrAmount'] as num?)?.toDouble() ?? 0,
            ),
        },
        plans: {
          if (plans is Map)
            for (final MapEntry(:key, :value) in plans.entries)
              if (value is Map)
                Tier.parse(key as String?): PlanSummary.fromJson(value),
        },
      );
    } on FirebaseFunctionsException catch (error) {
      _logger.warning(
        'Could not list products',
        name: 'billing',
        data: {'code': error.code},
      );
      return const _Catalogue();
    }
  }

  @override
  Future<Subscription> buy(StoreProduct product) async {
    if (_razorpay.available) return _payWithRazorpay(product);
    final details = await _purchases.load({product.productId});
    final match = details.where((d) => d.id == product.productId).firstOrNull;
    if (match == null) {
      throw const AppException.badRequest(
        message: 'That plan is not available on this device.',
      );
    }

    final purchase = await _purchases.buy(match);
    final verified = await _verify([purchase]);

    // Settled only after the server has granted the tier. Acknowledging
    // first would tell the store the goods were delivered before we knew
    // whether they were — and on Android an unacknowledged purchase is
    // auto-refunded after three days, which is the safer failure.
    await _purchases.settle(purchase);
    return verified;
  }

  /// One 30-day pass through Razorpay: the server creates the order at its
  /// own price, the checkout takes the payment, and the server grants the
  /// plan only after checking the signature and the payment with Razorpay.
  Future<Subscription> _payWithRazorpay(StoreProduct product) async {
    final RazorpayOrder order;
    try {
      final result = await _functions
          .httpsCallable('create_razorpay_order')
          .call<Object?>({'productId': product.productId});
      final data = result.data;
      if (data is! Map || data['orderId'] is! String) {
        throw const AppException.parsing();
      }
      order = (
        orderId: data['orderId'] as String,
        amount: (data['amount'] as num).toInt(),
        currency: data['currency'] as String? ?? 'INR',
        keyId: data['keyId'] as String? ?? '',
        name: data['name'] as String? ?? 'Hawk',
        description: data['description'] as String? ?? '',
        email: data['email'] as String?,
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _mapError(error, stackTrace);
    }

    final paid = await _razorpay.pay(order);

    try {
      final result = await _functions
          .httpsCallable('verify_razorpay_payment')
          .call<Object?>({
            'orderId': paid.orderId,
            'paymentId': paid.paymentId,
            'signature': paid.signature,
          });
      final data = result.data;
      return _fromCallable(data is Map ? data : const {});
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _mapError(error, stackTrace);
    }
  }

  @override
  Future<Subscription> restore() async {
    final held = await _purchases.held();
    if (held.isEmpty) {
      return const Subscription();
    }

    final result = await _restoreCall(held);
    for (final purchase in held) {
      await _purchases.settle(purchase);
    }
    return result;
  }

  Future<Subscription> _verify(List<PurchaseDetails> purchases) async {
    final purchase = purchases.first;
    try {
      final result = await _functions
          .httpsCallable('verify_purchase')
          .call<Object?>({
            'store': _purchases.storeName,
            'productId': purchase.productID,
            'token': _token(purchase),
          });
      final data = result.data;
      return _fromCallable(data is Map ? data : const {});
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _mapError(error, stackTrace);
    }
  }

  Future<Subscription> _restoreCall(List<PurchaseDetails> held) async {
    try {
      final result = await _functions
          .httpsCallable('restore_purchases')
          .call<Object?>({
            'purchases': [
              for (final p in held)
                {
                  'store': _purchases.storeName,
                  'productId': p.productID,
                  'token': _token(p),
                },
            ],
          });
      final data = result.data;
      if (data is! Map) return const Subscription();
      if ((data['restored'] as num?)?.toInt() == 0) {
        return const Subscription();
      }
      return _fromCallable(data);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      throw _mapError(error, stackTrace);
    }
  }

  /// What the server uses to look the purchase up with the store.
  ///
  /// Google wants the purchase token; Apple wants the transaction id, and its
  /// `serverVerificationData` is the receipt rather than an id — so the id is
  /// taken from `purchaseID` where the platform provides it.
  static String _token(PurchaseDetails purchase) =>
      purchase.verificationData.serverVerificationData.isNotEmpty &&
          purchase.purchaseID == null
      ? purchase.verificationData.serverVerificationData
      : purchase.purchaseID ?? purchase.verificationData.serverVerificationData;

  AppException _mapError(
    FirebaseFunctionsException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthenticated' => const AppException.unauthorized(),
    // Purchases are not configured in this build — nothing will change by
    // retrying, so the UI must say so rather than offering one.
    'failed-precondition' => AppException.badRequest(
      message: error.message ?? 'Purchases are not available in this build.',
    ),
    'permission-denied' => AppException.badRequest(
      message: error.message ?? 'That purchase belongs to another account.',
    ),
    'invalid-argument' => AppException.badRequest(
      message: error.message ?? 'The store could not confirm that purchase.',
    ),
    'unavailable' => const AppException.network(
      message:
          'The store is not responding. Your purchase is safe — try '
          'Restore in a moment.',
    ),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  Subscription _fromCallable(Map<Object?, Object?> data) => Subscription(
    tier: Tier.parse(data['tier'] as String?),
    status: SubscriptionStatus.parse(data['status'] as String?),
    currentPeriodEnd: DateTime.tryParse(
      data['currentPeriodEnd'] as String? ?? '',
    ),
    autoRenewing: data['autoRenewing'] as bool? ?? false,
  );

  DateTime? _moment(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    String() => DateTime.tryParse(value),
    _ => null,
  };

  Never _rethrow(Object error, StackTrace stackTrace) {
    if (error is AppException) throw error;
    throw AppException.unknown(cause: error, stackTrace: stackTrace);
  }
}

/// What `list_products` returned: the store product ids to load, and the
/// entitlement table to describe them with.
class _Catalogue {
  const _Catalogue({this.ids = const {}, this.plans = const {}});

  final Map<String, CatalogueEntry> ids;
  final Map<Tier, PlanSummary> plans;

  bool get isEmpty => ids.isEmpty && plans.isEmpty;
}

/// One product as `list_products` describes it: its tier and period, and the
/// reference price shown until the store lists it.
typedef CatalogueEntry = ({
  String tier,
  int months,
  String? price,
  double amount,
  String currency,
  String? inrPrice,
  double inrAmount,
});

/// The paywall's products on a Razorpay device: every plan with a rupee
/// price, at that price, and all of them buyable. The price is the server's
/// (`inrPrice`), the same one the order is created at.
@visibleForTesting
List<StoreProduct> razorpayProductsFrom(
  Map<String, CatalogueEntry> catalogue,
) => [
  for (final MapEntry(key: id, value: entry) in catalogue.entries)
    if (entry.inrPrice case final price?)
      StoreProduct(
        productId: id,
        tier: Tier.parse(entry.tier),
        months: entry.months,
        price: price,
        currencyCode: 'INR',
        rawPrice: entry.inrAmount,
        autoRenews: false,
      ),
]..sort((a, b) => a.months.compareTo(b.months));

/// The paywall's products: the store's own where the store lists them —
/// its localised, tax-inclusive price, the only one ever sold at — and the
/// backend's reference price where it does not, marked not purchasable.
@visibleForTesting
List<StoreProduct> storeProductsFrom(
  Map<String, CatalogueEntry> catalogue,
  List<ProductDetails> details,
) {
  final listed = {for (final d in details) d.id: d};
  return [
    for (final MapEntry(key: id, value: entry) in catalogue.entries)
      if (listed[id] case final d?)
        StoreProduct(
          productId: d.id,
          tier: Tier.parse(entry.tier),
          months: entry.months,
          // The store's own formatted string. Never reformatted here — it is
          // localised and tax-inclusive where the jurisdiction requires it,
          // and rebuilding it from rawPrice would eventually disagree with
          // what the user is charged.
          price: d.price,
          currencyCode: d.currencyCode,
          rawPrice: d.rawPrice,
          trialDays: trialDaysOf(d),
        )
      else if (entry.price case final price?)
        StoreProduct(
          productId: id,
          tier: Tier.parse(entry.tier),
          months: entry.months,
          price: price,
          currencyCode: entry.currency,
          rawPrice: entry.amount,
          purchasable: false,
        ),
  ]..sort((a, b) => a.months.compareTo(b.months));
}
