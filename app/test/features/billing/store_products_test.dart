import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:knowra/src/features/billing/data/firebase/firebase_billing_repository.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/presentation/widgets/payment_sheet.dart';

/// Which price the paywall shows: the store's wherever it lists the product,
/// the backend's reference price until then.
void main() {
  const catalogue = <String, CatalogueEntry>{
    'knowra.standard.monthly': (
      tier: 'standard',
      months: 1,
      price: r'$4.99',
      amount: 4.99,
      currency: 'USD',
      inrPrice: '₹199',
      inrAmount: 199,
    ),
    'knowra.premium.monthly': (
      tier: 'premium',
      months: 1,
      price: r'$9.99',
      amount: 9.99,
      currency: 'USD',
      inrPrice: '₹399',
      inrAmount: 399,
    ),
  };

  ProductDetails listed(String id, String price, double raw) => ProductDetails(
    id: id,
    title: id,
    description: '',
    price: price,
    rawPrice: raw,
    currencyCode: 'INR',
  );

  test('with no store, both plans show at the reference price, unsold', () {
    final products = storeProductsFrom(catalogue, const []);
    expect(products.map((p) => p.price), [r'$4.99', r'$9.99']);
    expect(products.every((p) => !p.purchasable), isTrue);
    expect(products.map((p) => p.tier), [Tier.standard, Tier.premium]);
  });

  test("the store's own price wins where it lists the product", () {
    final products = storeProductsFrom(catalogue, [
      listed('knowra.premium.monthly', '₹899.00', 899),
    ]);
    final premium = products.firstWhere((p) => p.tier == Tier.premium);
    final standard = products.firstWhere((p) => p.tier == Tier.standard);
    expect(premium.price, '₹899.00');
    expect(premium.currencyCode, 'INR');
    expect(premium.purchasable, isTrue);
    expect(standard.price, r'$4.99');
    expect(standard.purchasable, isFalse);
  });

  test(
    'a product with no store listing and no reference price is left out',
    () {
      final products = storeProductsFrom(const {
        'knowra.mystery': (
          tier: 'premium',
          months: 1,
          price: null,
          amount: 0,
          currency: '',
          inrPrice: null,
          inrAmount: 0,
        ),
      }, const []);
      expect(products, isEmpty);
    },
  );

  group('Android pays through Razorpay', () {
    test('every plan shows its rupee price, and every one is for sale', () {
      final products = razorpayProductsFrom(catalogue);
      expect(products.map((p) => p.price), ['₹199', '₹399']);
      expect(products.map((p) => p.currencyCode).toSet(), {'INR'});
      expect(products.every((p) => p.purchasable), isTrue);
      expect(products.map((p) => p.tier), [Tier.standard, Tier.premium]);
    });

    test('a pass says it lasts 30 days and does not renew', () {
      final standard = razorpayProductsFrom(catalogue).first;
      expect(standard.autoRenews, isFalse);
      expect(standard.priceLine, '₹199 / 30 days');
      expect(PaymentSheet.terms(standard), '₹199 / 30 DAYS');
    });

    test('a plan with no rupee price is not offered', () {
      final products = razorpayProductsFrom(const {
        'knowra.mystery': (
          tier: 'premium',
          months: 1,
          price: r'$1',
          amount: 1,
          currency: 'USD',
          inrPrice: null,
          inrAmount: 0,
        ),
      });
      expect(products, isEmpty);
    });
  });
}
