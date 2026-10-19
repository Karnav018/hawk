import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/di/injector.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/features/account/domain/entities/account_overview.dart';
import 'package:knowra/src/features/account/domain/repositories/account_repository.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_session.dart';
import 'package:knowra/src/features/auth/domain/entities/auth_user.dart';
import 'package:knowra/src/features/auth/presentation/bloc/session_cubit.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/subscription_cubit.dart';
import 'package:knowra/src/features/capture/data/file_capture.dart';
import 'package:knowra/src/features/capture/presentation/bloc/quick_shot_cubit.dart';
import 'package:knowra/src/features/chat/data/recent_finds.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/chat/presentation/bloc/answer_cubit.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/voice/presentation/bloc/suggestions_cubit.dart';
import 'package:knowra/src/features/voice/presentation/pages/home_page.dart';
import 'package:knowra/src/features/voice/presentation/widgets/home_chrome.dart';

import '../../support/fake_auth.dart';
import '../../support/memory_cache.dart';

class _Accounts extends Fake implements AccountRepository {
  @override
  Future<AccountOverview> overview() async =>
      const AccountOverview(memories: 3, indexed: 3);
}

class _Library extends Fake implements MemoryRepository {
  @override
  Future<MemoryPage> fetchMemories({
    int limit = 20,
    int offset = 0,
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) async => (
    items: [
      for (final (i, name) in const [
        'pricing-schedule-v4.pdf',
        'standup-notes.m4a',
        'whiteboard.jpg',
      ].indexed)
        Memory(
          id: 'm$i',
          type: switch (i) {
            0 => MemoryType.pdf,
            1 => MemoryType.voiceNote,
            _ => MemoryType.photo,
          },
          status: ProcessingStatus.ready,
          title: name,
          createdAt: DateTime(2026, 9, 20),
        ),
    ],
    hasMore: false,
    offset: 0,
  );
}

class _Answers implements AnswerRepository {
  @override
  Future<MatchResults> search(String query) async =>
      (matches: const <Match>[], signals: const QuerySignals());

  @override
  Future<Answer> ask(
    String question, {
    String? conversationId,
    List<String> earlier = const [],
  }) async => Answer(id: 'a', question: question);
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

/// Free, near the end of the week's answers — the state that puts the
/// answers-low banner on home.
const _lastAsk = Subscription(
  window: Allowance(limit: 2, remaining: 2),
  week: Allowance(limit: 20, used: 17, remaining: 3),
);

/// Phones by logical size, with a keyboard height typical of each (the
/// Samsung keyboard with its suggestion strip is the tall one).
const _phones = <String, (Size, double)>{
  'small Android 360x640': (Size(360, 640), 290),
  'Galaxy 384x832': (Size(384, 832), 360),
  'Galaxy+ 412x915': (Size(412, 915), 370),
  'iPhone 402x874': (Size(402, 874), 336),
};

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double keyboard,
  Subscription plan = const Subscription(),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  final session = SessionCubit(
    FakeAuthRepository(
      initial: AuthStatus.authenticated(
        testUser.copyWith(inputPreference: InputPreference.typing),
      ),
    ),
  );
  addTearDown(session.close);
  final subscription = SubscriptionCubit(_Billing(plan));
  addTearDown(subscription.close);

  // The shell as it is: a Scaffold with the nav pill as its bottom bar and
  // `extendBody: true`, so home's own Scaffold sits inside another one —
  // which is what decides who absorbs the keyboard.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          extendBody: true,
          bottomNavigationBar: const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: SizedBox(height: 62),
          ),
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: session),
              BlocProvider.value(value: subscription),
            ],
            child: const HomePage(),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  await tester.pump();
  await tester.pump();
}

final _files = _Files();

void main() {
  setUp(() {
    getIt
      ..registerFactory<AccountRepository>(_Accounts.new)
      ..registerFactoryParam<AnswerCubit, String, void>(
        (question, _) =>
            AnswerCubit(_Answers(), RecentFinds(MemoryCacheStore()), question),
      )
      ..registerFactory<SuggestionsCubit>(() => SuggestionsCubit(_Library()))
      ..registerFactory<QuickShotCubit>(
        () => QuickShotCubit(_files, _Library(), _Originals(), _Logger()),
      );
  });
  tearDown(() => getIt.reset(dispose: false));

  testWidgets('tapping the floating camera opens it, without an error', (
    tester,
  ) async {
    // The first build of this button read the plan with `context.plan` —
    // a watch — inside its tap handler, and the tap threw "tried to listen
    // to a value exposed with provider, from outside of the widget tree".
    await _pump(tester, size: const Size(402, 874), keyboard: 0);
    final before = _files.shots;

    await tester.tap(find.byType(CameraFab));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_files.shots, before + 1);
  });

  /// Slides the keyboard in the way the platform does — a run of growing
  /// insets, a frame each — so an overflow that exists only mid-slide fails
  /// here too, not only the resting states either side of it.
  Future<void> slide(WidgetTester tester, double from, double to) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      final inset = from + (to - from) * i / steps;
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at a keyboard inset of ${inset.round()}px',
      );
    }
  }

  testWidgets('a tap anywhere outside the field puts the keyboard away', (
    tester,
  ) async {
    await _pump(tester, size: const Size(402, 874), keyboard: 336);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.widget.focusNode.hasFocus, isTrue);

    // The headline is nothing tappable — the ground of the screen. It used
    // to leave the keyboard exactly where it was.
    await tester.tap(find.text('Ask your library'));
    await tester.pump();
    expect(field.widget.focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('the camera has its own room at the end of the chat face', () {
    /// How much space the list under [finder] ends in.
    double reserved(WidgetTester tester, Finder finder) => tester
        .widget<SliverPadding>(
          find.descendant(of: finder, matching: find.byType(SliverPadding)),
        )
        .padding
        .resolve(TextDirection.ltr)
        .bottom;

    /// How far the camera reaches up into the list.
    double intrusion(WidgetTester tester, Finder finder) =>
        tester.getRect(finder).bottom -
        tester.getRect(find.byType(CameraFab)).top;

    testWidgets('before anything is asked', (tester) async {
      await _pump(tester, size: const Size(402, 874), keyboard: 0);
      final list = find.byType(ListView);
      expect(intrusion(tester, list), greaterThan(0), reason: 'it overlaps');
      expect(reserved(tester, list), greaterThan(intrusion(tester, list)));
    });

    testWidgets('and under the thread', (tester) async {
      await _pump(tester, size: const Size(402, 874), keyboard: 0);
      await tester.enterText(find.byType(TextField), 'what is the price?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('what is the price?'), findsOneWidget);

      final list = find.byType(ListView);
      expect(reserved(tester, list), greaterThan(intrusion(tester, list)));
    });

    testWidgets('but not while typing, when the camera is away', (
      tester,
    ) async {
      await _pump(tester, size: const Size(402, 874), keyboard: 336);
      expect(find.byType(CameraFab), findsNothing);
      expect(reserved(tester, find.byType(ListView)), 0);
    });
  });

  for (final MapEntry(key: name, value: (size, keyboard)) in _phones.entries) {
    group(name, () {
      testWidgets('opening the keyboard on the chat face', (tester) async {
        await _pump(tester, size: size, keyboard: 0, plan: _lastAsk);
        expect(find.text('17 of 20 answers used this week'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await slide(tester, 0, keyboard);

        // Typing: the thread and the field have the screen; the banner and
        // the greeting step aside rather than squeeze the thread to nothing.
        expect(find.text('17 of 20 answers used this week'), findsNothing);
        expect(find.text('Ask your library'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await slide(tester, keyboard, 0);
        expect(find.text('17 of 20 answers used this week'), findsOneWidget);
      });

      testWidgets('built with the keyboard already up', (tester) async {
        await _pump(tester, size: size, keyboard: keyboard, plan: _lastAsk);
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('asking with the keyboard up opens the thread', (
        tester,
      ) async {
        await _pump(tester, size: size, keyboard: keyboard);
        await tester.enterText(find.byType(TextField), 'what is the price?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('what is the price?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}

class _Files extends Fake implements FileCapture {
  var shots = 0;

  /// The user opens the camera and backs out.
  @override
  Future<PickedImage?> takePhoto() async {
    shots++;
    return null;
  }
}

class _Originals extends Fake implements LocalOriginals {}

class _Logger implements AppLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}
