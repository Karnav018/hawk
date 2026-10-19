import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/account/presentation/widgets/profile_pieces.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/subscription_cubit.dart';

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

/// Screen 1U's "Payment method" and "Cancel subscription" rows.
void main() {
  Future<void> pump(WidgetTester tester, Subscription plan) async {
    final cubit = SubscriptionCubit(_Billing(plan));
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(children: paidPlanRows(context)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a paid plan shows both, naming the store — never a card', (
    tester,
  ) async {
    await pump(
      tester,
      const Subscription(tier: Tier.premium, store: 'app_store'),
    );
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('APP STORE'), findsOneWidget);
    expect(find.text('Cancel subscription'), findsOneWidget);
    expect(find.textContaining('····'), findsNothing);
  });

  testWidgets('Google Play plans name Google Play', (tester) async {
    await pump(
      tester,
      const Subscription(tier: Tier.standard, store: 'google_play'),
    );
    expect(find.text('GOOGLE PLAY'), findsOneWidget);
  });

  testWidgets('a free plan has nothing to pay with or cancel', (tester) async {
    await pump(tester, const Subscription());
    expect(find.text('Payment method'), findsNothing);
    expect(find.text('Cancel subscription'), findsNothing);
  });
}
