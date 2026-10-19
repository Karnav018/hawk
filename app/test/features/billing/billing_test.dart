import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';

void main() {
  StoreProduct product({
    required int months,
    double raw = 9.0,
    String currency = 'USD',
    Tier tier = Tier.standard,
  }) => StoreProduct(
    productId: 'knowra.${tier.name}.${months == 12 ? 'annual' : 'monthly'}',
    tier: tier,
    months: months,
    price: '\$${raw.toStringAsFixed(2)}',
    currencyCode: currency,
    rawPrice: raw,
  );

  group('price line', () {
    test('names the period rather than abbreviating it', () {
      expect(product(months: 12, raw: 90).priceLine, '\$90.00 / year');
      expect(product(months: 1, raw: 9).priceLine, '\$9.00 / month');
    });
  });

  group('SubscriptionStatus', () {
    test('grace still entitles', () {
      // A declined card must not read as data loss while the store is still
      // retrying the payment.
      expect(SubscriptionStatus.inGrace.isEntitled, isTrue);
      expect(SubscriptionStatus.inGrace.needsAttention, isTrue);
    });

    test('expired and refunded do not entitle', () {
      expect(SubscriptionStatus.expired.isEntitled, isFalse);
      expect(SubscriptionStatus.refunded.isEntitled, isFalse);
    });

    test('an unknown status from a newer backend fails closed', () {
      expect(
        SubscriptionStatus.parse('something_new'),
        SubscriptionStatus.expired,
      );
    });
  });

  group('Allowance', () {
    test('unlimited shows no meter', () {
      // A full bar would imply a ceiling that does not exist.
      expect(const Allowance().fraction, 0);
      expect(const Allowance().isUnlimited, isTrue);
    });

    test('fraction never exceeds one', () {
      expect(const Allowance(limit: 4, used: 9).fraction, 1.0);
    });

    test('a zero limit does not divide by zero', () {
      expect(const Allowance(limit: 0, used: 3).fraction, 0);
    });

    test('exhausted is distinct from unlimited', () {
      expect(
        const Allowance(limit: 4, used: 4, remaining: 0).isExhausted,
        isTrue,
      );
      expect(const Allowance().isExhausted, isFalse);
    });
  });

  group('Subscription', () {
    test('a paid tier with a lapsed status is not paid', () {
      const lapsed = Subscription(
        tier: Tier.premium,
        status: SubscriptionStatus.expired,
      );
      expect(lapsed.isPaid, isFalse);
      expect(
        lapsed.canUpgrade,
        isFalse,
        reason: 'already on the top tier — the fix is renewal, not upgrade',
      );
    });

    test('free can upgrade; premium cannot', () {
      expect(const Subscription().canUpgrade, isTrue);
      expect(const Subscription(tier: Tier.premium).canUpgrade, isFalse);
    });

    test('an unknown tier from a newer backend degrades to free', () {
      expect(Tier.parse('platinum'), Tier.free);
    });
  });
}
