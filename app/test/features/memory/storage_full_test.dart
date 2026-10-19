import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/account/presentation/widgets/profile_pieces.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';

/// Screen 1V — the vault is full.
///
/// The card's two actions are not the same action twice, and which of them
/// appears is a claim about what the user can actually do. Offering "Go Pro"
/// on the top tier sells something that does not exist; the existing
/// [PlanLock.upgradeable] already encodes that, and this pins that the card
/// is driven by it rather than by "is the vault full".
void main() {
  // `remaining`, not `used >= limit`. Exhaustion is the server's call —
  // `Allowance.isExhausted` reads `remaining` on purpose, so a client can
  // never disagree with the server about whether a vault is full.
  Subscription full(Tier tier) => Subscription(
    tier: tier,
    index: const Allowance(limit: 100, used: 100, remaining: 0),
  );

  group('the lock decides what is offered', () {
    test('a full index on an upgradeable tier offers the upgrade', () {
      final lock = full(Tier.free).indexLock;
      expect(lock, isNotNull);
      expect(lock!.upgradeable, isTrue);
    });

    test('a full index on the top tier does not', () {
      final lock = full(Tier.premium).indexLock;
      expect(lock, isNotNull);
      expect(
        lock!.upgradeable,
        isFalse,
        reason: 'there is nothing above premium to sell',
      );
    });

    test('the reason is the plan\'s sentence, not the free tier\'s', () {
      // The design writes "move to Pro for 1 TB". A premium user reading that
      // would be told to buy what they already have.
      expect(full(Tier.premium).indexLock!.reason, contains('Free up space'));
      expect(full(Tier.free).indexLock!.reason, isNot(contains('1 TB')));
    });

    test('a vault with room shows no card at all', () {
      const room = Subscription(
        index: Allowance(limit: 100, used: 20, remaining: 80),
      );
      expect(room.indexLock, isNull);
    });

    test('a server that sends no remaining is not treated as full', () {
      // The field is nullable and an older deploy omits it. Guessing "full"
      // from used == limit would lock the whole library on a rounding error.
      const unknown = Subscription(index: Allowance(limit: 100, used: 100));
      expect(unknown.indexLock, isNull);
    });
  });

  group('the ratio the card prints', () {
    test('reads as the design writes it — unit once, on the limit', () {
      expect(
        byteRatio(15 * 1024 * 1024 * 1024, 15 * 1024 * 1024 * 1024),
        '15 / 15 GB',
      );
    });

    test('an empty vault has no unit on the zero', () {
      expect(byteRatio(0, 15 * 1024 * 1024 * 1024), '0 / 15 GB');
    });
  });

  group('the bar', () {
    test('is full when the vault is', () {
      expect(full(Tier.free).index.fraction, 1.0);
    });

    test('cannot overflow its own card when the server over-reports', () {
      const over = Allowance(limit: 100, used: 137);
      expect(over.fraction, 1.0);
    });
  });
}
