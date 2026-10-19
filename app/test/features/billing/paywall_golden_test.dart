import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/paywall_cubit.dart';
import 'package:knowra/src/features/billing/presentation/pages/paywall_page.dart';

import '../../support/load_app_fonts.dart';

const _gib = 1024 * 1024 * 1024;

class _Billing implements BillingRepository {
  @override
  Stream<Subscription> watchSubscription() =>
      Stream.value(const Subscription(memoryWindowDays: 30));
  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(const []);
  @override
  Future<List<StoreProduct>> products() async => const [
    StoreProduct(
      productId: 'knowra.standard.monthly',
      tier: Tier.standard,
      months: 1,
      price: r'$4.99',
      currencyCode: 'USD',
      rawPrice: 4.99,
    ),
    StoreProduct(
      productId: 'knowra.premium.monthly',
      tier: Tier.premium,
      months: 1,
      price: r'$9.99',
      currencyCode: 'USD',
      rawPrice: 9.99,

      trialDays: 7,
    ),
  ];
  @override
  Future<Map<Tier, PlanSummary>> plans() async => const {
    Tier.free: PlanSummary(
      memoryWindowDays: 30,
      indexBytes: 2 * _gib,
      connectedAccounts: 1,
      windowQueries: 2,
      weeklyQueries: 20,
    ),
    Tier.standard: PlanSummary(
      memoryWindowDays: 365,
      indexBytes: 32 * _gib,
      connectedAccounts: 3,
      windowQueries: 10,
      weeklyQueries: 150,
    ),
    Tier.premium: PlanSummary(
      indexBytes: 256 * _gib,
      windowQueries: 25,
      weeklyQueries: 400,
    ),
  };
  @override
  Future<Subscription> buy(StoreProduct product) async => const Subscription();
  @override
  Future<Subscription> restore() async => const Subscription();
}

/// Screen 1S on the real ground with the real fonts: the design's layout
/// carrying this product's two paid tiers. The picture is for the parts an
/// assertion cannot see — one white card, monthly prices only,
/// the price column aligned to the card's top edge, the CTA pinned low.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('pricing — 1S', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = PaywallCubit(_Billing());
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: BlocProvider.value(value: cubit, child: const PaywallPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pricing_1s.png'),
    );
  });
}
