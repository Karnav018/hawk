import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/billing_cubit.dart';
import 'package:knowra/src/features/billing/presentation/bloc/subscription_cubit.dart';
import 'package:knowra/src/features/billing/presentation/pages/billing_page.dart';
import 'package:knowra/src/features/billing/presentation/store_links.dart';

class _Billing implements BillingRepository {
  _Billing({
    this.plan = const Subscription(),
    this.receipts = const [],
    this.catalogue = const [],
  });

  final Subscription plan;
  final List<Receipt> receipts;
  final List<StoreProduct> catalogue;

  @override
  Stream<Subscription> watchSubscription() => Stream.value(plan);
  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(receipts);
  @override
  Future<List<StoreProduct>> products() async => catalogue;

  @override
  Future<Map<Tier, PlanSummary>> plans() async => const {};
  @override
  Future<Subscription> buy(StoreProduct product) async => plan;
  @override
  Future<Subscription> restore() async => plan;
}

Receipt receipt({
  required String id,
  int? micros,
  String? currency = 'USD',
  bool trial = false,
  int months = 12,
  String product = 'knowra.premium.yearly',
  DateTime? at,
}) => Receipt(
  id: id,
  productId: product,
  tier: Tier.premium,
  months: months,
  chargedAt: at ?? DateTime(2026, 8, 14),
  amountMicros: micros,
  currency: currency,
  trial: trial,
  store: 'app_store',
);

/// Screen 2J. Every figure here is a store's authenticated answer, so the
/// tests are about the cases where a lazier screen would print something it
/// does not know: a trial's zero as a price, a cancelled plan's "next
/// charge", a missing amount as $0.00.
void main() {
  _unknownLocale();

  group('receipts', () {
    test('amounts are formatted in the currency they were charged in', () {
      expect(
        receipt(id: 'a', micros: 96000000).amountLabel(locale: 'en_US'),
        r'$96.00',
      );
      expect(
        receipt(
          id: 'b',
          micros: 1200000000,
          currency: 'JPY',
        ).amountLabel(locale: 'en_US'),
        '¥1,200',
        reason: 'yen has no minor unit — "¥1,200.00" reads as an error',
      );
      expect(
        receipt(
          id: 'c',
          micros: 8990000,
          currency: 'GBP',
        ).amountLabel(locale: 'en_GB'),
        '£8.99',
      );
    });

    test('a missing price is missing, not free', () {
      expect(receipt(id: 'a').amountLabel(), isNull);
      expect(
        receipt(id: 'a', micros: 0, trial: true).amountLabel(locale: 'en_US'),
        r'$0.00',
      );
    });

    test('names and statuses read as the design writes them', () {
      final r = receipt(id: 'a', micros: 1, trial: true);
      expect(r.planName, 'Hawk ${Tier.premium.label} · Yearly');
      expect(r.statusLabel, 'TRIAL STARTED');
      expect(
        receipt(id: 'b', micros: 1, months: 1).planName,
        'Hawk ${Tier.premium.label} · Monthly',
      );
      expect(receipt(id: 'c', micros: 1).statusLabel, 'PAID');
    });
  });

  group('the next charge', () {
    test('the store\'s current price wins — prices change', () {
      final s = BillingState(
        products: const [
          StoreProduct(
            productId: 'knowra.premium.yearly',
            tier: Tier.premium,
            months: 12,
            price: r'$99.00',
          ),
        ],
        receipts: [receipt(id: 'a', micros: 96000000)],
      );
      expect(s.nextAmount('knowra.premium.yearly'), r'$99.00');
    });

    test('without a store, the last paid receipt — never a trial\'s zero', () {
      final s = BillingState(
        receipts: [
          receipt(id: 'trial', micros: 0, trial: true),
          receipt(id: 'paid', micros: 96000000),
        ],
      );
      expect(s.nextAmount('knowra.premium.yearly', locale: 'en_US'), r'$96.00');
    });

    test('nothing known is nothing shown', () {
      final s = BillingState(
        receipts: [receipt(id: 'trial', micros: 0, trial: true)],
      );
      expect(s.nextAmount('knowra.premium.yearly'), isNull);
      expect(const BillingState().nextAmount(null), isNull);
    });
  });

  group('export', () {
    test('CSV with plain decimals and the currency in its own column', () {
      final cubit = BillingCubit(
        _Billing(receipts: [receipt(id: 'GPA.1..0', micros: 96490000)]),
      );
      addTearDown(cubit.close);
      return Future<void>.delayed(Duration.zero, () {
        final lines = cubit.exportCsv().split('\n');
        expect(lines.first, 'Date,Plan,Status,Amount,Currency,Store,Reference');
        // "96.49", not "$96.49": a spreadsheet can sum a number, not text.
        expect(lines[1], contains(',96.49,USD,'));
        expect(lines[1], startsWith('2026-08-14,'));
      });
    });

    test('a missing amount exports as empty, not zero', () {
      final cubit = BillingCubit(_Billing(receipts: [receipt(id: 'x')]));
      addTearDown(cubit.close);
      return Future<void>.delayed(Duration.zero, () {
        expect(cubit.exportCsv().split('\n')[1], contains(',Paid,,USD,'));
      });
    });
  });

  group('where to change it', () {
    test('a plan is managed at the store that sold it', () {
      expect(manageUrl('app_store', null).host, 'apps.apple.com');
      final play = manageUrl('google_play', 'knowra.premium.yearly');
      expect(play.host, 'play.google.com');
      expect(play.queryParameters['package'], 'in.hawkapp.app');
      expect(play.queryParameters['sku'], 'knowra.premium.yearly');
    });

    test('named, so the user knows where to go to cancel', () {
      expect(storeName('app_store'), 'the App Store');
      expect(storeName('google_play'), 'Google Play');
    });
  });

  group('the card', () {
    Future<void> pump(WidgetTester tester, _Billing billing) async {
      final plan = SubscriptionCubit(billing);
      final receipts = BillingCubit(billing);
      addTearDown(plan.close);
      addTearDown(receipts.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: plan),
              BlocProvider.value(value: receipts),
            ],
            child: const BillingPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final end = DateTime(2026, 9, 29, 12);

    testWidgets('renewing: the next charge and its date', (tester) async {
      await pump(
        tester,
        _Billing(
          plan: Subscription(
            tier: Tier.premium,
            autoRenewing: true,
            currentPeriodEnd: end,
            productId: 'knowra.premium.yearly',
            store: 'app_store',
          ),
          catalogue: const [
            StoreProduct(
              productId: 'knowra.premium.yearly',
              tier: Tier.premium,
              months: 12,
              price: r'$96.00',
            ),
          ],
        ),
      );
      expect(find.text('NEXT CHARGE'), findsOneWidget);
      expect(find.text(r'$96.00'), findsOneWidget);
      expect(find.text('29 SEP 2026'), findsOneWidget);
      expect(find.text('Paid through the App Store'), findsOneWidget);
    });

    testWidgets('cancelled: it ends, and says nothing more will be charged', (
      tester,
    ) async {
      await pump(
        tester,
        _Billing(
          plan: Subscription(
            tier: Tier.premium,
            currentPeriodEnd: end,
            productId: 'knowra.premium.yearly',
          ),
        ),
      );
      expect(find.text('NEXT CHARGE'), findsNothing);
      expect(find.text('ENDS'), findsOneWidget);
      expect(find.text('No further charges'), findsOneWidget);
    });

    testWidgets('no card number is ever drawn', (tester) async {
      await pump(
        tester,
        _Billing(
          plan: Subscription(
            tier: Tier.premium,
            autoRenewing: true,
            currentPeriodEnd: end,
          ),
        ),
      );
      expect(find.textContaining('····'), findsNothing);
    });

    testWidgets('a granted plan is its tier, not "Free"', (tester) async {
      // The QA account on 26 Sep: Premium from the server, no store
      // purchase, so no period end. The card said "Free" while the profile
      // said Premium.
      await pump(
        tester,
        _Billing(
          plan: const Subscription(
            tier: Tier.premium,
            window: Allowance(limit: 25, remaining: 25),
            index: Allowance(limit: 274877906944),
          ),
        ),
      );
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Free'), findsNothing);
      expect(
        find.text(
          '25 answers every 2 hours · memories kept forever · 256 GB index',
        ),
        findsOneWidget,
      );
      expect(find.text('Not billed through a store'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(find.text('Upgrade'), findsNothing);
    });

    testWidgets('free shows what it includes, and the way up', (tester) async {
      await pump(
        tester,
        _Billing(
          plan: const Subscription(
            window: Allowance(limit: 2, used: 1, remaining: 1),
            memoryWindowDays: 30,
            index: Allowance(limit: 2147483648),
          ),
        ),
      );
      expect(find.text('Free'), findsOneWidget);
      expect(
        find.text('2 answers every 2 hours · 30-day memory · 2 GB index'),
        findsOneWidget,
      );
      expect(find.text('Upgrade'), findsOneWidget);
      expect(find.text('Not billed through a store'), findsNothing);
    });

    testWidgets('renewing with no price known says what renews', (
      tester,
    ) async {
      await pump(
        tester,
        _Billing(
          plan: Subscription(
            tier: Tier.premium,
            autoRenewing: true,
            currentPeriodEnd: end,
            productId: 'knowra.premium.yearly',
            store: 'app_store',
          ),
        ),
      );
      expect(find.text('RENEWS'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('29 SEP 2026'), findsOneWidget);
      expect(find.text('Paid through the App Store'), findsOneWidget);
    });

    testWidgets('free, with no receipts, explains rather than blanks', (
      tester,
    ) async {
      await pump(tester, _Billing());
      expect(find.text('Free'), findsOneWidget);
      expect(find.textContaining('Receipts appear here'), findsOneWidget);
      expect(find.text('Export all receipts'), findsNothing);
    });
  });
}

void _unknownLocale() {
  test('an unknown device locale falls back instead of crashing', () {
    // intl throws for a locale it has no number data for. On the one screen
    // about money that would be a crash on an unusual phone setting.
    expect(
      receipt(id: 'a', micros: 96000000).amountLabel(locale: 'xx_YY'),
      r'$96.00',
    );
  });
}
