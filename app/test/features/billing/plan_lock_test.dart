import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';

/// What is locked, and — the part that matters — whether paying would unlock
/// it. An upgrade button on something an upgrade cannot fix is the app
/// selling what it cannot deliver.
void main() {
  Subscription plan({
    Tier tier = Tier.free,
    int? window = 2,
    int windowLeft = 2,
    int? week = 20,
    int weekLeft = 20,
    DateTime? windowNextAt,
    DateTime? weekResetsAt,
    int? indexLimit,
    int? indexRemaining,
    int? accounts = 1,
  }) => Subscription(
    tier: tier,
    window: Allowance(
      limit: window,
      remaining: window == null ? null : windowLeft,
    ),
    week: Allowance(limit: week, remaining: week == null ? null : weekLeft),
    windowNextAt: windowNextAt,
    weekResetsAt: weekResetsAt,
    index: Allowance(limit: indexLimit, remaining: indexRemaining),
    connectedAccounts: accounts,
  );

  final back = DateTime(2026, 9, 26, 15, 12);
  final monday = DateTime(2026, 9, 28);

  group('asking', () {
    test('unlocked with answers left', () {
      expect(plan().canAsk, isTrue);
      expect(plan().askLock, isNull);
      expect(plan().askAvailableAt, isNull);
    });

    test('a spent window names when the next answer comes back', () {
      final p = plan(windowLeft: 0, windowNextAt: back);
      final lock = p.askLock!;
      expect(lock.upgradeable, isTrue);
      expect(lock.reason, contains('2 answers for now'));
      expect(lock.reason, contains('back at 3:12 pm'));
      expect(p.askBlockedForWeek, isFalse);
      expect(p.askAvailableAt, back);
    });

    test('a spent week waits for Monday, even with the window free', () {
      final p = plan(weekLeft: 0, weekResetsAt: monday);
      expect(p.askLock!.reason, contains('20 answers this week'));
      expect(p.askLock!.reason, contains('Monday'));
      expect(p.askBlockedForWeek, isTrue);
      expect(p.blockingAnswers, p.week);
      expect(p.askAvailableAt, monday);
    });

    test('both spent: the one that frees later is what stops it', () {
      final p = plan(
        windowLeft: 0,
        weekLeft: 0,
        windowNextAt: back,
        weekResetsAt: monday,
      );
      expect(p.askBlockedForWeek, isTrue);
      expect(p.askAvailableAt, monday);
    });

    test('Standard is offered more, since Premium has more', () {
      final lock = plan(tier: Tier.standard, window: 10, windowLeft: 0).askLock;
      expect(lock!.upgradeable, isTrue);
    });

    test('Premium is never told to upgrade — there is nothing above it', () {
      final lock = plan(tier: Tier.premium, week: 400, weekLeft: 0).askLock;
      expect(lock!.upgradeable, isFalse);
    });

    test('an unmetered plan is never locked', () {
      final open = plan(tier: Tier.premium, window: null, week: null);
      expect(open.canAsk, isTrue);
      expect(open.askLock, isNull);
    });

    test('the clock reads the way a person writes it', () {
      expect(answerClock(DateTime(2026, 9, 26, 15, 12)), '3:12 pm');
      expect(answerClock(DateTime(2026, 9, 26, 0, 5)), '12:05 am');
      expect(answerClock(DateTime(2026, 9, 26, 12)), '12:00 pm');
    });
  });

  group('indexing', () {
    test('a full index on a paid-upgradeable tier offers the upgrade', () {
      final lock = plan(
        tier: Tier.standard,
        indexLimit: 100,
        indexRemaining: 0,
      ).indexLock;
      expect(lock!.upgradeable, isTrue);
    });

    test('a full index on premium does not — there is nothing above it', () {
      final lock = plan(
        tier: Tier.premium,
        indexLimit: 100,
        indexRemaining: 0,
      ).indexLock;
      expect(lock!.upgradeable, isFalse);
      expect(lock.reason, contains('Free up space'));
    });

    test('headroom means no lock', () {
      expect(plan(indexLimit: 100, indexRemaining: 50).indexLock, isNull);
    });
  });

  group('connecting', () {
    test('locked at the limit, not before it', () {
      expect(plan().canConnect(0), isTrue);
      expect(plan().canConnect(1), isFalse);
      expect(plan().connectLock(0), isNull);
      expect(plan().connectLock(1), isNotNull);
    });

    test('singular and plural read correctly', () {
      expect(plan().connectLock(1)!.reason, contains('one account'));
      expect(
        plan(tier: Tier.standard, accounts: 3).connectLock(3)!.reason,
        contains('3 accounts'),
      );
    });

    test('unlimited never locks', () {
      expect(plan(tier: Tier.premium, accounts: null).canConnect(99), isTrue);
      expect(plan(tier: Tier.premium, accounts: null).connectLock(99), isNull);
    });
  });

  test('every lock gives a reason', () {
    // A locked control with no explanation is indistinguishable from a broken
    // one, and the user cannot act on either.
    final locks = [
      plan(windowLeft: 0).askLock,
      plan(indexLimit: 10, indexRemaining: 0).indexLock,
      plan().connectLock(1),
    ];
    for (final lock in locks) {
      expect(lock, isNotNull);
      expect(lock!.reason.trim(), isNotEmpty);
    }
  });
}
