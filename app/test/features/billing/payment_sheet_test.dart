import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/billing/data/iap/trial_offer.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/presentation/widgets/payment_sheet.dart';

/// Screen 1T — what is charged, and when.
///
/// The card, "Add a card" and Face ID belong to the store's own sheet, which
/// the app cannot draw. What stays here is the schedule, and the schedule is
/// the thing people are nervous about: getting "Today · Free" wrong in
/// either direction is the one mistake this screen cannot make.
void main() {
  final now = DateTime(2026, 9, 22);

  StoreProduct yearly({int? trial}) => StoreProduct(
    productId: 'knowra.premium.yearly',
    tier: Tier.premium,
    months: 12,
    price: r'$96.00',
    trialDays: trial,
  );

  Widget host(StoreProduct p) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: PaymentSheet(product: p, now: now),
    ),
  );

  testWidgets('with a trial, nothing today and the price when it ends', (
    tester,
  ) async {
    await tester.pumpWidget(host(yearly(trial: 7)));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('29 Sep 2026'), findsOneWidget);
    expect(
      find.textContaining("before 29 Sep and you won't be charged"),
      findsOneWidget,
    );
  });

  testWidgets('without a trial, the price today — never a trial it lacks', (
    tester,
  ) async {
    await tester.pumpWidget(host(yearly()));
    expect(find.text('Free'), findsNothing);
    expect(find.text(r'$96.00'), findsNWidgets(2));
    expect(find.text('Renews 22 Sep 2027'), findsOneWidget);
    expect(find.textContaining("won't be charged"), findsNothing);
  });

  testWidgets('no card is drawn — the store holds it', (tester) async {
    await tester.pumpWidget(host(yearly(trial: 7)));
    expect(find.textContaining('····'), findsNothing);
    expect(find.textContaining('Add a card'), findsNothing);
    expect(find.textContaining('NEVER SEES THE CARD'), findsOneWidget);
  });

  test('the terms line reads as the design writes it', () {
    expect(
      PaymentSheet.terms(yearly(trial: 7)),
      r'7 DAYS FREE, THEN $96.00/YR',
    );
    expect(PaymentSheet.terms(yearly()), r'$96.00 / YEAR');
  });

  group('trial periods from Play', () {
    test('ISO-8601 durations become days', () {
      expect(isoPeriodDays('P7D'), 7);
      expect(isoPeriodDays('P1W'), 7);
      expect(isoPeriodDays('P2W'), 14);
      expect(isoPeriodDays('P1M'), 30);
      expect(isoPeriodDays('P1Y'), 365);
    });

    test('anything unreadable is no trial, never a guess', () {
      expect(isoPeriodDays(''), isNull);
      expect(isoPeriodDays('seven days'), isNull);
      expect(isoPeriodDays('P0D'), isNull);
    });
  });

  testWidgets('a month renewal lands on a real day', (tester) async {
    // 31 Jan + one month is 28 Feb, not 3 March — the renewal row must not
    // print a date the store will never charge on.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PaymentSheet(
            product: const StoreProduct(
              productId: 'm',
              tier: Tier.standard,
              months: 1,
              price: r'$9',
            ),
            now: DateTime(2027, 1, 31),
          ),
        ),
      ),
    );
    expect(find.text('Renews 28 Feb 2027'), findsOneWidget);
  });
}
