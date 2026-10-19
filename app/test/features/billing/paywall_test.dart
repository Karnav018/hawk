import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/di/injector.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/paywall_cubit.dart';
import 'package:knowra/src/features/billing/presentation/pages/paywall_page.dart';

const _gib = 1024 * 1024 * 1024;

/// `billing.plan_summaries()` as the backend sends it today.
const _table = {
  Tier.free: PlanSummary(
    memoryWindowDays: 30,
    indexBytes: 2 * _gib,
    fileBytes: 512 * 1024 * 1024,
    connectedAccounts: 1,
    windowQueries: 2,
    weeklyQueries: 20,
  ),
  Tier.standard: PlanSummary(
    memoryWindowDays: 365,
    indexBytes: 32 * _gib,
    fileBytes: 5 * _gib,
    connectedAccounts: 3,
    windowQueries: 10,
    weeklyQueries: 150,
  ),
  Tier.premium: PlanSummary(
    indexBytes: 256 * _gib,
    fileBytes: 15 * _gib,
    windowQueries: 25,
    weeklyQueries: 400,
  ),
};

StoreProduct _product(
  Tier tier,
  int months,
  String price,
  double raw, {
  int? trialDays,
}) => StoreProduct(
  productId: 'knowra.${tier.name}.${months == 12 ? 'yearly' : 'monthly'}',
  tier: tier,
  months: months,
  price: price,
  currencyCode: 'USD',
  rawPrice: raw,
  trialDays: trialDays,
);

/// What the stores sell: monthly only (`products.CATALOGUE`).
final _catalogue = [
  _product(Tier.standard, 1, r'$4.99', 4.99),
  _product(Tier.premium, 1, r'$9.99', 9.99, trialDays: 7),
];

class _Billing implements BillingRepository {
  _Billing({
    this.plan = const Subscription(),
    List<StoreProduct>? catalogue,
    this.plansFail = false,
  }) : catalogue = catalogue ?? _catalogue;

  final Subscription plan;
  final List<StoreProduct> catalogue;
  final bool plansFail;

  @override
  Stream<Subscription> watchSubscription() => Stream.value(plan);
  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(const []);
  @override
  Future<List<StoreProduct>> products() async => catalogue;
  @override
  Future<Map<Tier, PlanSummary>> plans() async {
    if (plansFail) throw StateError('backend unreachable');
    return _table;
  }

  /// Every product a purchase was attempted for.
  final bought = <String>[];

  @override
  Future<Subscription> buy(StoreProduct product) async {
    bought.add(product.productId);
    return plan;
  }

  @override
  Future<Subscription> restore() async => plan;
}

Future<PaywallCubit> _cubit(_Billing billing) async {
  final cubit = PaywallCubit(billing);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return cubit;
}

/// Screen 1S. The design sells one "Pro" plan with numbers that are not this
/// product's; these pin the decisions that replaced them — two real tiers on
/// the design's layout, every line read from the backend's table, and
/// nothing on a price screen that the backend would not honour.
void main() {
  group('plan lines come from the entitlement table', () {
    test('premium reads as the design\'s Pro card, with real numbers', () {
      expect(_table[Tier.premium]!.features, [
        'Memories kept forever',
        '25 answers every 2 hours',
        '256 GB, every account',
      ]);
    });

    test('standard says a year, not forever', () {
      expect(_table[Tier.standard]!.features, [
        'Memories kept a year',
        '10 answers every 2 hours',
        '32 GB, up to 3 accounts',
      ]);
    });

    test('free is its real allowance, not "15 GB · 100 asks a month"', () {
      expect(
        _table[Tier.free]!.summary,
        '2 GB · 2 answers every 2 hours · 30-day memory',
      );
    });

    test('every plan counts its answers — none is sold as unlimited', () {
      expect(
        _table[Tier.standard]!.answersPerWindow,
        '10 answers every 2 hours',
      );
      expect(_table[Tier.free]!.answersPerWindow, '2 answers every 2 hours');
      expect(const PlanSummary().answersPerWindow, 'unlimited answers');
      expect(
        const PlanSummary(windowQueries: 1).answersPerWindow,
        '1 answer every 2 hours',
      );
    });

    test('allowances are round, and a terabyte is a terabyte', () {
      expect(PlanSummary.allowance(2 * _gib), '2 GB');
      expect(PlanSummary.allowance(1024 * _gib), '1 TB');
      expect(PlanSummary.allowance(512 * 1024 * 1024), '512 MB');
    });

    test('parses the callable\'s payload, nulls included', () {
      final plan = PlanSummary.fromJson(const {
        'memoryWindowDays': null,
        'indexBytes': 274877906944,
        'connectedAccounts': null,
        'windowQueries': 25,
        'windowHours': 2,
        'weeklyQueries': 400,
      });
      expect(plan.keepsForever, isTrue);
      expect(plan.connectedAccounts, isNull);
      expect(plan.indexLine, '256 GB, every account');
      expect(plan.answersLine, '25 answers every 2 hours');
      expect(plan.weeklyQueries, 400);
    });
  });

  group('prices', () {
    test('a monthly price reads as a month', () {
      expect(
        _product(Tier.premium, 1, r'$9.99', 9.99).priceLine,
        r'$9.99 / month',
      );
    });
  });

  group('choosing', () {
    test('premium starts on the white card, monthly', () async {
      final cubit = await _cubit(_Billing());
      addTearDown(cubit.close);
      expect(cubit.state.selected, Tier.premium);
      expect(cubit.state.chosen?.productId, 'knowra.premium.monthly');
    });

    test('a store selling only standard starts on standard', () async {
      final cubit = await _cubit(
        _Billing(catalogue: [_product(Tier.standard, 1, r'$4.99', 4.99)]),
      );
      addTearDown(cubit.close);
      expect(cubit.state.selected, Tier.standard);
      expect(cubit.state.chosen?.months, 1);
    });

    test('a plan at its reference price is never bought', () async {
      final billing = _Billing(
        catalogue: [
          _product(
            Tier.premium,
            1,
            r'$9.99',
            9.99,
          ).copyWith(purchasable: false),
        ],
      );
      final cubit = await _cubit(billing);
      addTearDown(cubit.close);
      await cubit.buy(cubit.state.chosen!);
      expect(billing.bought, isEmpty);
      expect(cubit.state.purchasing, isNull);
    });

    test('free cannot be chosen — there is nothing to buy', () async {
      final cubit = await _cubit(_Billing());
      addTearDown(cubit.close);
      cubit.choose(Tier.free);
      expect(cubit.state.selected, Tier.premium);
    });

    test('unreadable plans leave the cards plainer, not unsellable', () async {
      final cubit = await _cubit(_Billing(plansFail: true));
      addTearDown(cubit.close);
      expect(cubit.state.products, hasLength(2));
      expect(cubit.state.plans, isEmpty);
      expect(cubit.state.exception, isNull);
    });
  });

  group('screen', () {
    setUp(() {
      if (!getIt.isRegistered<SnackController>()) {
        getIt.registerSingleton<SnackController>(SnackController());
      }
    });
    tearDown(() => getIt.reset(dispose: false));

    Future<void> pump(WidgetTester tester, _Billing billing) async {
      tester.view
        ..physicalSize = const Size(402, 874)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = PaywallCubit(billing);
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: BlocProvider.value(value: cubit, child: const PaywallPage()),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the design\'s structure, with the real plans', (tester) async {
      await pump(tester, _Billing());

      expect(find.text('Keep everything,\nforever'), findsOneWidget);
      expect(find.text('RESTORE'), findsOneWidget);
      expect(
        find.text('Free keeps memories 30 days. Premium never forgets.'),
        findsOneWidget,
      );
      // Monthly only: no period toggle, no savings badge.
      expect(find.text('Yearly'), findsNothing);
      expect(find.byType(SegmentedTabs), findsNothing);

      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text(r'$9.99'), findsOneWidget);
      expect(find.text(r'$4.99'), findsOneWidget);
      expect(find.text('PER MONTH'), findsNWidgets(2));
      expect(find.text('Memories kept forever'), findsOneWidget);

      expect(
        find.text('2 GB · 2 answers every 2 hours · 30-day memory'),
        findsOneWidget,
      );
      expect(find.text('CURRENT'), findsOneWidget);

      expect(find.text('Start 7 days free'), findsOneWidget);
      expect(
        find.text(r'Then $9.99 a month. Cancel any time.'),
        findsOneWidget,
      );
    });

    testWidgets('both plans are readable in full without a tap', (
      tester,
    ) async {
      await pump(tester, _Billing());
      // Standard's own features, while Premium is the selected plan.
      expect(find.text('Memories kept a year'), findsOneWidget);
      expect(find.text('10 answers every 2 hours'), findsOneWidget);
      expect(find.text('32 GB, up to 3 accounts'), findsOneWidget);
      expect(find.text('Memories kept forever'), findsOneWidget);
      expect(find.text('25 answers every 2 hours'), findsOneWidget);
    });

    testWidgets('only one white card, and it is the plan being bought', (
      tester,
    ) async {
      await pump(tester, _Billing());

      final paper = find.byWidgetPredicate(
        (w) => w is HawkCard && w.tone == CardTone.paper,
      );
      expect(paper, findsOneWidget);
      expect(
        find.descendant(of: paper, matching: find.text('Premium')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Standard'));
      await tester.tap(find.text('Standard'));
      await tester.pump();

      expect(paper, findsOneWidget);
      expect(
        find.descendant(of: paper, matching: find.text('Standard')),
        findsOneWidget,
      );

      // Both plans stay in full; only which one is white changes.
      expect(
        find.descendant(of: paper, matching: find.text('Memories kept a year')),
        findsOneWidget,
      );
      expect(find.text('Memories kept forever'), findsOneWidget);
      expect(
        find.descendant(
          of: paper,
          matching: find.text('Memories kept forever'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: paper, matching: find.text('RECOMMENDED')),
        findsNothing,
      );
      expect(
        find.text('Get Standard'),
        findsOneWidget,
        reason: 'standard has no trial — the button must not promise one',
      );
      expect(find.text(r'$4.99 a month. Cancel any time.'), findsOneWidget);
    });

    testWidgets('without a trial the charge is today, so no "then"', (
      tester,
    ) async {
      await pump(
        tester,
        _Billing(
          catalogue: [
            _product(Tier.standard, 1, r'$4.99', 4.99),
            _product(Tier.premium, 1, r'$9.99', 9.99),
          ],
        ),
      );

      expect(find.text(r'$9.99'), findsOneWidget);
      expect(find.text('PER MONTH'), findsNWidgets(2));
      expect(find.text('Get Premium'), findsOneWidget);
      expect(find.text(r'$9.99 a month. Cancel any time.'), findsOneWidget);
    });

    testWidgets('no store: says so, sells nothing, still describes free', (
      tester,
    ) async {
      await pump(tester, _Billing(catalogue: const []));

      expect(find.text('Plans could not load'), findsOneWidget);
      expect(find.byType(PillButton), findsNothing);
      expect(
        find.text('2 GB · 2 answers every 2 hours · 30-day memory'),
        findsOneWidget,
      );
    });

    testWidgets('before the store lists the plans: full prices, nothing sold', (
      tester,
    ) async {
      // What a fresh install saw as "Purchases are not available here": the
      // store has no products yet, so the plans come at the reference price.
      final billing = _Billing(
        catalogue: [
          _product(
            Tier.standard,
            1,
            r'$4.99',
            4.99,
          ).copyWith(purchasable: false),
          _product(
            Tier.premium,
            1,
            r'$9.99',
            9.99,
          ).copyWith(purchasable: false),
        ],
      );
      await pump(tester, billing);

      expect(find.text('Plans could not load'), findsNothing);
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text(r'$9.99'), findsOneWidget);
      expect(find.text('PER MONTH'), findsNWidgets(2));
      expect(find.text(r'$4.99'), findsOneWidget);
      expect(find.text('Memories kept forever'), findsOneWidget);

      final button = tester.widget<PillButton>(
        find.widgetWithText(PillButton, 'Coming soon'),
      );
      expect(button.onPressed, isNull, reason: 'shown, never sold');
      expect(find.text(r'$9.99 a month. Purchases open soon.'), findsOneWidget);
      expect(billing.bought, isEmpty);
    });

    testWidgets('dormant memories lead, as an offer', (tester) async {
      await pump(
        tester,
        _Billing(
          plan: const Subscription(memoryWindowDays: 30, memoriesDormant: 1204),
        ),
      );
      expect(
        find.text(
          '1,204 memories are older than 30 days — still here. Upgrading '
          'makes them answerable again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('on premium already: nothing to buy', (tester) async {
      await pump(
        tester,
        _Billing(plan: const Subscription(tier: Tier.premium)),
      );
      expect(find.text("You're on Premium"), findsOneWidget);
      final cta = tester.widget<PillButton>(find.byType(PillButton));
      expect(cta.onPressed, isNull);
    });
  });
}
