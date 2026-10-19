import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_kit.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/presentation/widgets/ask_limit_sheet.dart';

/// Screen 1W — the answers are spent.
///
/// The sheet's job is the order of the sentences: your library is fine, here
/// is when an answer comes back, and only then — and only if it would help —
/// pay. Searching is never limited, so this is only ever about answers.
void main() {
  final now = DateTime(2026, 9, 23, 12);

  Widget host(Subscription plan) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: AskLimitSheet(
        lock: plan.askLock!,
        asks: plan.blockingAnswers,
        resetAt: plan.askAvailableAt,
        weekly: plan.askBlockedForWeek,
        now: now,
      ),
    ),
  );

  Subscription window({Tier tier = Tier.free, DateTime? back}) => Subscription(
    tier: tier,
    window: const Allowance(limit: 2, used: 2, remaining: 0),
    week: const Allowance(limit: 20, used: 5, remaining: 15),
    windowNextAt: back,
  );

  Subscription week({Tier tier = Tier.free}) => Subscription(
    tier: tier,
    window: const Allowance(limit: 2, remaining: 2),
    week: const Allowance(limit: 20, used: 20, remaining: 0),
    weekResetsAt: now.add(const Duration(days: 5)),
  );

  testWidgets('a spent window: the number, and when the next one is back', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(window(back: now.add(const Duration(minutes: 40)))),
    );
    expect(find.textContaining("You've used your 2"), findsOneWidget);
    expect(find.text('Last 2 hours'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('NEXT ONE BACK IN 40 MIN'), findsOneWidget);
    expect(find.text('Wait until 12:40 pm'), findsOneWidget);
  });

  testWidgets('a spent week: this week, and the day it resets', (tester) async {
    await tester.pumpWidget(host(week()));
    expect(find.textContaining("You've used all 20"), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('20 / 20'), findsOneWidget);
    expect(find.text('RESETS IN 5 DAYS'), findsOneWidget);
    expect(find.text('Wait until 28 Sep'), findsOneWidget);
  });

  testWidgets('more answers are offered where they exist', (tester) async {
    await tester.pumpWidget(
      host(window(back: now.add(const Duration(hours: 1)))),
    );
    expect(find.text('Get more answers'), findsOneWidget);
  });

  testWidgets('and withheld on Premium, where they do not', (tester) async {
    final premium = Subscription(
      tier: Tier.premium,
      window: const Allowance(limit: 25, used: 25, remaining: 0),
      week: const Allowance(limit: 400, remaining: 100),
    );
    await tester.pumpWidget(host(premium));
    expect(find.text('Get more answers'), findsNothing);
    expect(
      find.text('Not now'),
      findsOneWidget,
      reason:
          'with no time from the plan, still a way out — never an invented one',
    );
  });

  testWidgets('a plan with no ceiling never claims a number', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AskLimitSheet(
            lock: PlanLock(reason: 'r', upgradeable: true),
            asks: Allowance(),
          ),
        ),
      ),
    );
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('No answers left'), findsOneWidget);
    expect(find.byType(ProgressTrack), findsOneWidget);
  });

  testWidgets('the bar is full, and cannot overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AskLimitSheet(
            lock: PlanLock(reason: 'r', upgradeable: false),
            // The server over-reporting must not blow out the card.
            asks: Allowance(limit: 100, used: 137, remaining: 0),
          ),
        ),
      ),
    );
    final bar = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
    expect(bar.value.clamp(0.0, 1.0), 1.0);
  });

  group('wording', () {
    test('the next one back, in minutes and hours', () {
      expect(
        AskLimitSheet.backIn(now.add(const Duration(minutes: 20)), now: now),
        'Next one back in 20 min',
      );
      expect(
        AskLimitSheet.backIn(now.add(const Duration(minutes: 90)), now: now),
        'Next one back in 1 hr 30 min',
      );
      expect(
        AskLimitSheet.backIn(now.add(const Duration(hours: 2)), now: now),
        'Next one back in 2 hr',
      );
      expect(
        AskLimitSheet.backIn(now.add(const Duration(seconds: 20)), now: now),
        'Next one back in a moment',
      );
    });

    test('a dated wait for the week', () {
      expect(
        AskLimitSheet.waitLabel(DateTime(2026, 10, 1), now: now),
        'Wait until 1 Oct',
      );
      expect(
        AskLimitSheet.waitLabel(DateTime(2026, 9, 24, 0, 5), now: now),
        'Wait until tomorrow',
      );
      expect(AskLimitSheet.waitLabel(null, now: now), 'Not now');
    });
  });
}
