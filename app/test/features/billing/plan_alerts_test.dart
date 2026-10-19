import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/subscription_cubit.dart';
import 'package:knowra/src/features/billing/presentation/widgets/plan_alerts.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/presentation/widgets/memory_row.dart';

/// Screen 1X — the plan alerts.
///
/// The design's own note: "these appear inside real screens, never stacked
/// together like this." So the rules here are about *which one*, and about
/// never printing a number the app does not have.
void main() {
  final now = DateTime(2026, 9, 23, 12);

  Subscription free({int limit = 20, int left = 3, DateTime? reset}) =>
      Subscription(
        week: Allowance(limit: limit, used: limit - left, remaining: left),
        weekResetsAt: reset ?? now.add(const Duration(hours: 5)),
      );

  group('home', () {
    test('the week nearly spent: the banner, with the real reset time', () {
      final a = homeAlert(free(), now: now)!;
      expect(a.kind, PlanAlertKind.asksLow);
      expect(a.title, '17 of 20 answers used this week');
      expect(a.subtitle, 'Resets in 5 hours');
      expect(a.action, 'Upgrade');
    });

    test('plenty left: nothing to say', () {
      expect(homeAlert(free(limit: 100, left: 60), now: now), isNull);
    });

    test('the last fifth of a larger allowance counts as low', () {
      expect(
        homeAlert(free(limit: 100, left: 18), now: now)?.kind,
        PlanAlertKind.asksLow,
      );
    });

    test('spent is 1W\'s blocking sheet, not a banner', () {
      expect(homeAlert(free(left: 0), now: now), isNull);
    });

    test('the top tier has nothing to upgrade to', () {
      final premium = free().copyWith(tier: Tier.premium);
      expect(homeAlert(premium, now: now), isNull);
    });

    test('payment trouble outranks everything, and one alert only', () {
      final plan = free().copyWith(
        tier: Tier.standard,
        status: SubscriptionStatus.inGrace,
      );
      final a = homeAlert(plan, now: now)!;
      expect(a.kind, PlanAlertKind.paymentFailed);
      // No invented countdown — no store records when grace ends.
      expect(a.subtitle, isNot(contains('days')));
      expect(a.action, 'Fix');
    });

    test('a cancelled paid plan says when it returns to Free', () {
      final plan = Subscription(
        tier: Tier.standard,
        currentPeriodEnd: now.add(const Duration(days: 14, hours: 1)),
      );
      final a = homeAlert(plan, now: now)!;
      expect(a.kind, PlanAlertKind.downgrade);
      expect(a.title, 'Back on Free in 14 days');
      // No invented "842 memories over": the app does not know Free's limits.
      expect(a.subtitle, isNot(contains(RegExp(r'\d'))));
    });

    test('a renewing plan is not downgrading', () {
      final plan = Subscription(
        tier: Tier.standard,
        autoRenewing: true,
        currentPeriodEnd: now.add(const Duration(days: 14)),
      );
      expect(homeAlert(plan, now: now), isNull);
    });
  });

  group('profile', () {
    Subscription trial({bool renewing = true}) => Subscription(
      tier: Tier.premium,
      status: SubscriptionStatus.inTrial,
      autoRenewing: renewing,
      currentPeriodEnd: now.add(const Duration(days: 6, hours: 2)),
      productId: 'knowra.premium.yearly',
    );

    test('the trial strip names the amount and the date', () {
      final a = profileAlert(trial(), price: r'$96.00', now: now)!;
      expect(a.kind, PlanAlertKind.trial);
      expect(a.title, '6 days of Premium left');
      expect(a.subtitle, r'$96.00 on 29 Sep unless cancelled');
      expect(a.action, 'Manage');
    });

    test('without the store\'s price, the date alone — never a guess', () {
      expect(
        profileAlert(trial(), now: now)!.subtitle,
        'Renews 29 Sep unless cancelled',
      );
    });

    test(
      'a trial that will not renew is a downgrade, not a charge warning',
      () {
        final a = profileAlert(trial(renewing: false), now: now)!;
        expect(a.kind, PlanAlertKind.downgrade);
      },
    );
  });

  test('reset wording across the range', () {
    expect(
      resetsIn(now.add(const Duration(minutes: 20)), now: now),
      'Resets in under an hour',
    );
    expect(
      resetsIn(now.add(const Duration(hours: 1)), now: now),
      'Resets in 1 hour',
    );
    expect(
      resetsIn(now.add(const Duration(days: 1, hours: 2)), now: now),
      'Resets tomorrow',
    );
    expect(
      resetsIn(now.add(const Duration(days: 9)), now: now),
      'Resets in 9 days',
    );
    expect(resetsIn(null, now: now), 'Resets soon');
  });

  group('the library row lock', () {
    Future<void> pump(WidgetTester tester, Memory m, Tier tier) async {
      final plan = SubscriptionCubit(_Billing(Subscription(tier: tier)));
      addTearDown(plan.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: BlocProvider.value(
            value: plan,
            child: Scaffold(body: MemoryRow(memory: m)),
          ),
        ),
      );
      await tester.pump();
    }

    Memory over(ProcessingStatus status) => Memory(
      id: 'q3',
      type: MemoryType.pdf,
      status: status,
      createdAt: now,
      title: 'q3-review-deck.pdf',
      overQuota: true,
    );

    testWidgets('nothing indexed: dimmed, with Unlock', (tester) async {
      await pump(tester, over(ProcessingStatus.extracted), Tier.free);
      expect(find.text('OVER QUOTA · NOT INDEXED'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      final row = tester.widget<HawkRow>(find.byType(HawkRow));
      expect(row.tone, CardTone.dim);
    });

    testWidgets('partly indexed says so, not "not indexed"', (tester) async {
      await pump(tester, over(ProcessingStatus.ready), Tier.free);
      expect(find.text('OVER QUOTA · PARTLY INDEXED'), findsOneWidget);
    });

    testWidgets('on the top tier, the action is to make room', (tester) async {
      await pump(tester, over(ProcessingStatus.extracted), Tier.premium);
      expect(find.text('Unlock'), findsNothing);
      expect(find.text('Free up'), findsOneWidget);
    });
  });
}

class _Billing implements BillingRepository {
  _Billing(this.plan);
  final Subscription plan;
  @override
  Stream<Subscription> watchSubscription() => Stream.value(plan);
  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(const []);
  @override
  Future<List<StoreProduct>> products() async => const [];

  @override
  Future<Map<Tier, PlanSummary>> plans() async => const {};
  @override
  Future<Subscription> buy(StoreProduct product) async => plan;
  @override
  Future<Subscription> restore() async => plan;
}
