import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/router/tab_shell.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/di/injector.dart';
import 'package:knowra/src/core/files/local_originals.dart';
import 'package:knowra/src/core/logging/app_logger.dart';
import 'package:knowra/src/core/widgets/hawk_nav.dart';
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
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:knowra/src/features/voice/presentation/bloc/suggestions_cubit.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/pages/home_page.dart';
import 'package:knowra/src/features/voice/presentation/widgets/home_chrome.dart';

import '../../support/fake_auth.dart';
import '../../support/load_app_fonts.dart';
import '../../support/memory_cache.dart';

class _Accounts extends Fake implements AccountRepository {
  @override
  Future<AccountOverview> overview() async =>
      const AccountOverview(memories: 3, indexed: 3);
}

/// What a real library's newest files are called: a photo-picker number, a
/// phone recorder's timestamp, and one file a person named.
class _Library extends Fake implements MemoryRepository {
  @override
  Future<MemoryPage> fetchMemories({
    int limit = 20,
    int offset = 0,
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) async => (
    items: [
      for (final (name, type) in const [
        ('1000047716.jpg', MemoryType.photo),
        ('Recording 2026-09-23 14.23.11.m4a', MemoryType.voiceNote),
        ('pricing-schedule-v4.pdf', MemoryType.pdf),
      ])
        Memory(
          id: name,
          type: type,
          status: ProcessingStatus.ready,
          title: name,
          createdAt: DateTime(2026, 9, 23, 12),
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

class _Recogniser implements SpeechRecogniser {
  @override
  Future<bool> prepare() async => true;
  @override
  Stream<SpeechUpdate> listen() => const Stream<SpeechUpdate>.empty();
  @override
  Stream<SpeechUpdate> dictate() => const Stream<SpeechUpdate>.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Billing implements BillingRepository {
  @override
  Stream<Subscription> watchSubscription() => Stream.value(
    const Subscription(
      window: Allowance(limit: 2, used: 1, remaining: 1),
      week: Allowance(limit: 20, used: 1, remaining: 19),
    ),
  );
  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(const []);
  @override
  Future<List<StoreProduct>> products() async => const [];
  @override
  Future<Map<Tier, PlanSummary>> plans() async => const {};
  @override
  Future<Subscription> buy(StoreProduct product) async => const Subscription();
  @override
  Future<Subscription> restore() async => const Subscription();
}

/// Screen 1Y as a real user sees it: the chips built from real filenames,
/// sitting 14px clear of the nav rather than on it. The picture is the
/// point — the complaint was that the row read as a banner hanging off the
/// Home button, which no assertion can see.
void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    getIt
      ..registerFactory<AccountRepository>(_Accounts.new)
      ..registerFactoryParam<AnswerCubit, String, void>(
        (question, _) =>
            AnswerCubit(_Answers(), RecentFinds(MemoryCacheStore()), question),
      )
      ..registerFactory<SuggestionsCubit>(() => SuggestionsCubit(_Library()))
      ..registerSingleton<RecentFinds>(RecentFinds(MemoryCacheStore()))
      ..registerFactory<QuickShotCubit>(
        () => QuickShotCubit(_Files(), _Library(), _Originals(), _Logger()),
      );
  });
  tearDown(() => getIt.reset(dispose: false));

  testWidgets('home — voice, with suggestions', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = SessionCubit(
      FakeAuthRepository(
        initial: AuthStatus.authenticated(
          testUser.copyWith(inputPreference: InputPreference.voice),
        ),
      ),
    );
    addTearDown(session.close);
    final plan = SubscriptionCubit(_Billing());
    addTearDown(plan.close);
    final voice = VoiceCubit(_Recogniser(), _Answers());
    addTearDown(voice.close);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            extendBody: true,
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: HawkNav(current: HawkTab.values.first, onSelect: (_) {}),
            ),
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: session),
                BlocProvider.value(value: plan),
                BlocProvider.value(value: voice),
              ],
              child: const HomePage(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('ASK ABOUT A RECENT FILE'), findsOneWidget);
    expect(find.text('Photo · 23 Sep'), findsOneWidget);
    expect(find.text('Voice note · 23 Sep'), findsOneWidget);
    // The third is past the end of the row, a scroll away: the row stops
    // short of the camera now, rather than running to the screen's edge.
    expect(
      find.text('Pricing schedule v4', skipOffstage: false),
      findsOneWidget,
    );

    // Clear of the nav by the design's 14px, not touching it.
    final chipsBottom = tester
        .getBottomLeft(find.text('Photo · 23 Sep').last)
        .dy;
    final navTop = tester.getTopLeft(find.byType(HawkNav)).dy;
    expect(navTop - chipsBottom, greaterThanOrEqualTo(14));

    // The camera sits on the chip row's centre line — the end of the row,
    // not a button hovering above it — and the chips stop short of it.
    final chip = tester.getRect(
      find
          .ancestor(
            of: find.text('Photo · 23 Sep'),
            matching: find.byType(Material),
          )
          .first,
    );
    final camera = tester.getRect(find.byType(CameraFab));
    expect(camera.center.dy, moreOrLessEquals(chip.center.dy, epsilon: 0.5));
    // …and ends above the band the shell paints over the page's last
    // `navBand` pixels, which cut off its lower edge on a device.
    final band = tester.getSize(find.byType(MaterialApp)).height - navBand;
    expect(camera.bottom, lessThanOrEqualTo(band));
    final row = tester.getRect(
      find
          .ancestor(
            of: find.text('Photo · 23 Sep'),
            matching: find.byType(ListView),
          )
          .first,
    );
    expect(row.right, lessThanOrEqualTo(camera.left - 12));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_voice_1y.png'),
    );
  });
}

class _Files extends Fake implements FileCapture {}

class _Originals extends Fake implements LocalOriginals {}

class _Logger implements AppLogger {
  @override
  void noSuchMethod(Invocation invocation) {}
}
