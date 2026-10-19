import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/account/presentation/pages/profile_page.dart';

/// Screen 2L — the delete ledger.
///
/// A delete confirmation is the one screen where overstating the loss is
/// tempting and indefensible. Every line has to be a fact the screen was
/// handed: a count it was given, a plan it can name. The line that does the
/// most work is the last one, which says the files survive — because "my
/// files are gone" is the actual fear and it is not true.
void main() {
  Widget host({required int memories, String? plan}) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: DeleteLedger(memories: memories, plan: plan),
    ),
  );

  testWidgets('both losses are named when both are real', (tester) async {
    await tester.pumpWidget(host(memories: 1516, plan: 'Pro'));
    expect(find.text('1,516 indexed memories'), findsOneWidget);
    expect(find.text('Pro subscription, effective now'), findsOneWidget);
  });

  testWidgets('a free plan is never told it is losing a subscription', (
    tester,
  ) async {
    await tester.pumpWidget(host(memories: 40));
    expect(find.textContaining('subscription'), findsNothing);
    expect(find.text('40 indexed memories'), findsOneWidget);
  });

  testWidgets('an empty index drops the line rather than reading zero', (
    tester,
  ) async {
    await tester.pumpWidget(host(memories: 0, plan: 'Pro'));
    expect(find.textContaining('indexed memories'), findsNothing);
    expect(find.text('Pro subscription, effective now'), findsOneWidget);
  });

  testWidgets('what survives is always said, even with nothing to lose', (
    tester,
  ) async {
    // A brand-new free account deleting itself still needs the reassurance:
    // it is the sentence that answers the fear, not the one that lists it.
    await tester.pumpWidget(host(memories: 0));
    expect(find.text('Your files and Drive are kept'), findsOneWidget);
  });

  test('counts are grouped, so a loss reads as an amount', () {
    expect(DeleteLedger.grouped(1516), '1,516');
    expect(DeleteLedger.grouped(999), '999');
    expect(DeleteLedger.grouped(1000000), '1,000,000');
  });
}
