import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/store_product.dart';
import '../../domain/repositories/billing_repository.dart';

part 'billing_cubit.freezed.dart';

@freezed
abstract class BillingState with _$BillingState {
  const factory BillingState({
    @Default(<Receipt>[]) List<Receipt> receipts,
    @Default(true) bool isLoading,

    /// The store's catalogue, for pricing the next charge. Empty on a device
    /// with no store, which is a state the screen handles, not an error.
    @Default(<StoreProduct>[]) List<StoreProduct> products,
    AppException? exception,
  }) = _BillingState;

  const BillingState._();

  /// What the next renewal of [productId] will cost, as a display string.
  ///
  /// The store's own current price first — it is what will actually be
  /// charged, and prices change. Only without a store does it fall back to
  /// the last *paid* receipt for the same product, and never to a trial's
  /// zero. Null when neither is known, and the card then shows the date
  /// alone rather than a number it cannot stand behind.
  String? nextAmount(String? productId, {String? locale}) {
    if (productId == null) return null;
    for (final p in products) {
      if (p.productId == productId) return p.price;
    }
    for (final r in receipts) {
      if (r.productId == productId && !r.trial && r.amountMicros != null) {
        return r.amountLabel(locale: locale);
      }
    }
    return null;
  }
}

/// Screen 2J — BILLING AND RECEIPTS.
@injectable
class BillingCubit extends Cubit<BillingState> with SafeEmit<BillingState> {
  BillingCubit(this._billing) : super(const BillingState()) {
    _subscription = _billing.watchReceipts().listen(
      (receipts) => emit(state.copyWith(receipts: receipts, isLoading: false)),
      onError: (Object error, StackTrace stackTrace) => emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      ),
    );
    unawaited(_loadProducts());
  }

  final BillingRepository _billing;
  StreamSubscription<List<Receipt>>? _subscription;

  Future<void> _loadProducts() async {
    try {
      // Awaited into a local first. `state.copyWith(products: await …)`
      // reads `state` *before* the await, so when the catalogue arrived it
      // re-emitted the stale initial state — wiping the receipts that had
      // landed meanwhile and putting the screen back into loading.
      final products = await _billing.products();
      emit(state.copyWith(products: products));
    } on Object {
      // The catalogue only prices the next charge. Without it the card falls
      // back to the last paid receipt, so a store hiccup is not an error.
    }
  }

  /// All receipts as CSV, for "Export all receipts".
  ///
  /// CSV rather than a PDF: it opens in every spreadsheet and accounting
  /// tool, which is where an exported receipt list goes next. Amounts are
  /// written as plain decimals with the currency in its own column, so a
  /// spreadsheet can sum them — "$96.00" in one cell is text, not a number.
  String exportCsv() {
    final rows = <String>['Date,Plan,Status,Amount,Currency,Store,Reference'];
    for (final r in state.receipts) {
      final amount = r.amountMicros == null
          ? ''
          : (r.amountMicros! / 1000000).toStringAsFixed(2);
      rows.add(
        [
          r.chargedAt.toIso8601String().substring(0, 10),
          r.planName,
          r.trial ? 'Trial started' : 'Paid',
          amount,
          r.currency ?? '',
          r.store ?? '',
          r.id,
        ].map(_cell).join(','),
      );
    }
    return rows.join('\n');
  }

  static String _cell(String value) => value.contains(RegExp('[",\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;

  void dismissError() => emit(state.copyWith(exception: null));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
