import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../core/error/app_exception.dart';

/// An order the backend created (`create_razorpay_order`), ready to pay.
typedef RazorpayOrder = ({
  String orderId,
  int amount,
  String currency,
  String keyId,
  String name,
  String description,
  String? email,
});

/// What a finished checkout hands back, for `verify_razorpay_payment`.
/// None of it is proof on its own: the server checks the signature and asks
/// Razorpay before granting anything.
typedef RazorpayPaid = ({String orderId, String paymentId, String signature});

/// Razorpay's native checkout, used on Android and iOS (user decisions,
/// 14 Oct 2026). On iOS this goes against App Store rule 3.1.1 for digital
/// plans; the user chose it knowing App Review may reject the app.
abstract interface class RazorpayCheckout {
  /// Whether this device pays through Razorpay.
  bool get available;

  /// Opens the checkout for [order]. Throws [AppException.cancelled] when the
  /// sheet is closed, and a bad-request [AppException] when the payment
  /// fails, with Razorpay's own reason.
  Future<RazorpayPaid> pay(RazorpayOrder order);
}

@LazySingleton(as: RazorpayCheckout)
class NativeRazorpayCheckout implements RazorpayCheckout {
  @override
  bool get available => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<RazorpayPaid> pay(RazorpayOrder order) {
    final done = Completer<RazorpayPaid>();
    final razorpay = Razorpay();

    void finish(void Function() settle) {
      if (done.isCompleted) return;
      settle();
      razorpay.clear();
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        finish(() {
          final paymentId = r.paymentId ?? '';
          final signature = r.signature ?? '';
          if (paymentId.isEmpty || signature.isEmpty) {
            done.completeError(
              const AppException.badRequest(
                message:
                    'The payment finished without a receipt. '
                    'If you were charged, it will be refunded.',
              ),
            );
            return;
          }
          done.complete((
            orderId: r.orderId ?? order.orderId,
            paymentId: paymentId,
            signature: signature,
          ));
        });
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        finish(() {
          // Closing the sheet is a choice, not an error: the paywall stays
          // quiet about it, as it does for a cancelled store purchase.
          if (r.code == Razorpay.PAYMENT_CANCELLED) {
            done.completeError(
              const AppException.cancelled(message: 'Payment cancelled.'),
            );
            return;
          }
          done.completeError(
            AppException.badRequest(
              message: (r.message?.trim().isNotEmpty ?? false)
                  ? r.message!.trim()
                  : 'The payment did not go through. Try again.',
            ),
          );
        });
      })
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
        finish(() {
          done.completeError(
            AppException.badRequest(
              message:
                  '${r.walletName ?? 'That wallet'} is not supported. '
                  'Pay by UPI or card instead.',
            ),
          );
        });
      });

    razorpay.open({
      'key': order.keyId,
      'amount': order.amount,
      'currency': order.currency,
      'order_id': order.orderId,
      'name': order.name,
      'description': order.description,
      if (order.email != null) 'prefill': {'email': order.email},
      'theme': {'color': '#59D3FF'},
    });
    return done.future;
  }
}
