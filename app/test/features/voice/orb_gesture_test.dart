import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/eye/eye_orb.dart';
import 'package:knowra/src/features/billing/domain/entities/plan_summary.dart';
import 'package:knowra/src/features/billing/domain/entities/receipt.dart';
import 'package:knowra/src/features/billing/domain/entities/store_product.dart';
import 'package:knowra/src/features/billing/domain/entities/subscription.dart';
import 'package:knowra/src/features/billing/domain/repositories/billing_repository.dart';
import 'package:knowra/src/features/billing/presentation/bloc/subscription_cubit.dart';
import 'package:knowra/src/features/chat/domain/entities/answer.dart';
import 'package:knowra/src/features/chat/domain/repositories/answer_repository.dart';
import 'package:knowra/src/features/memory/domain/entities/memory.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';
import 'package:knowra/src/features/voice/data/speech_recogniser.dart';
import 'package:knowra/src/features/voice/presentation/bloc/suggestions_cubit.dart';
import 'package:knowra/src/features/voice/presentation/bloc/voice_cubit.dart';
import 'package:knowra/src/features/voice/presentation/pages/result_stack_page.dart';
import 'package:knowra/src/features/voice/presentation/pages/voice_home_page.dart';

/// Listening happens **on home**, and both gestures reach it.
///
/// The orb used to push a screen. Now it changes state in place, which puts a
/// small gesture state machine in one widget — and the case that breaks
/// silently is the crossing one: tap to latch, rest a finger on the orb, lift.
/// If lifting sends, a latched session is cut off mid-sentence by a gesture
/// nobody meant as an ending.
///
/// These assert **what the widget asks the cubit to do**, not what the cubit
/// then does about it. `VoiceCubit.release` has its own tests in
/// `release_test.dart`; driving it through a widget only adds an event-loop
/// hop that `tester.pump` does not drain — which made a working gesture look
/// broken for a reason that had nothing to do with gestures.
class _Spy extends VoiceCubit {
  _Spy() : super(_Recogniser(), _Answers());

  int starts = 0;
  int sends = 0;
  int abandons = 0;

  @override
  Future<void> abandonDictation() async {
    if (state.phase != VoicePhase.listening) return;
    abandons++;
    emit(state.copyWith(phase: VoicePhase.ready, transcript: ''));
  }

  @override
  Future<void> toggleDictation() async {
    starts++;
    emit(state.copyWith(phase: VoicePhase.listening, transcript: 'a question'));
  }

  @override
  Future<void> release() async {
    sends++;
    emit(state.copyWith(phase: VoicePhase.retrieving, finished: 'a question'));
  }
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
  }) async => throw UnimplementedError();
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
  Stream<Subscription> watchSubscription() =>
      Stream.value(const Subscription());

  @override
  Stream<List<Receipt>> watchReceipts() => Stream.value(const <Receipt>[]);

  @override
  Future<List<StoreProduct>> products() async => const [];

  @override
  Future<Map<Tier, PlanSummary>> plans() async => const {};

  @override
  Future<Subscription> buy(StoreProduct product) async => const Subscription();

  @override
  Future<Subscription> restore() async => const Subscription();
}

Future<_Spy> _pump(WidgetTester tester, {ValueNotifier<bool>? visible}) async {
  final voice = _Spy();
  addTearDown(voice.close);
  final plan = SubscriptionCubit(_Billing());
  addTearDown(plan.close);

  // A real router, because a finished question pushes the result screen and
  // the face would otherwise throw "No GoRouter found in context" the moment
  // a gesture succeeded. The destination is a stub: where the question goes
  // is the router's business and is covered by the route tests.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<VoiceCubit>.value(value: voice),
              BlocProvider.value(value: plan),
              // An empty library: no chips, so these tests measure the face
              // exactly as they did before 1Y's suggestions existed.
              BlocProvider(create: (_) => SuggestionsCubit(_EmptyLibrary())),
            ],
            // Stands in for the shell hiding this tab, or a screen pushed
            // over home: both switch TickerMode off.
            child: visible == null
                ? const VoiceHomeFace()
                : ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, on, _) =>
                        TickerMode(enabled: on, child: const VoiceHomeFace()),
                  ),
          ),
        ),
        routes: [
          GoRoute(
            path: ResultStackPage.routePath,
            name: ResultStackPage.routeName,
            builder: (context, state) => const Scaffold(body: SizedBox()),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  await tester.pump();
  return voice;
}

/// A few frames. `pumpAndSettle` never returns here: the orb runs a
/// continuous ticker, so there is no settled frame to wait for.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The gestures target the orb, not the face — the face's own centre moves
/// once listening starts, because the transcript and the meter push it down.
Finder get _orb => find.byType(EyeOrb);

void main() {
  _layout();

  group('leaving while it listens', () {
    testWidgets('another tab or a pushed screen closes the microphone', (
      tester,
    ) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final voice = await _pump(tester, visible: visible);

      await tester.tap(_orb);
      await _frames(tester);
      expect(voice.state.phase, VoicePhase.listening);

      visible.value = false;
      await _frames(tester);

      expect(voice.abandons, 1);
      expect(voice.state.phase, VoicePhase.ready);
      expect(voice.sends, 0, reason: 'walking away is not asking');
    });

    testWidgets('coming back does not reopen it', (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final voice = await _pump(tester, visible: visible);
      await tester.tap(_orb);
      await _frames(tester);

      visible.value = false;
      await _frames(tester);
      visible.value = true;
      await _frames(tester);

      expect(voice.starts, 1);
      expect(voice.state.phase, VoicePhase.ready);
    });

    testWidgets('the app going to the background closes it', (tester) async {
      final voice = await _pump(tester);
      await tester.tap(_orb);
      await _frames(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _frames(tester);
      addTearDown(() {
        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });

      expect(voice.abandons, 1);
      expect(voice.state.phase, VoicePhase.ready);
    });

    testWidgets('not listening: leaving does nothing', (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final voice = await _pump(tester, visible: visible);
      visible.value = false;
      await _frames(tester);
      expect(voice.abandons, 0);
    });
  });

  testWidgets('tap opens the microphone, and a second tap sends', (
    tester,
  ) async {
    final voice = await _pump(tester);

    await tester.tap(_orb);
    await _frames(tester);
    expect(voice.starts, 1);
    expect(voice.sends, 0);

    await tester.tap(_orb);
    await _frames(tester);
    expect(voice.sends, 1, reason: 'the second tap is the send');
    expect(voice.starts, 1, reason: 'and must not re-open the microphone');
  });

  testWidgets('hold opens it, and letting go sends', (tester) async {
    final voice = await _pump(tester);

    final press = await tester.startGesture(tester.getCenter(_orb));
    await tester.pump(const Duration(milliseconds: 600));
    expect(voice.starts, 1, reason: 'the long press started it');

    await press.up();
    await _frames(tester);
    expect(voice.sends, 1, reason: 'letting go is the send');
  });

  testWidgets('letting go does NOT end a session a tap started', (
    tester,
  ) async {
    // The crossing case, and the only reason the widget tracks which gesture
    // is running.
    final voice = await _pump(tester);

    await tester.tap(_orb);
    await _frames(tester);
    expect(voice.starts, 1);

    final rest = await tester.startGesture(tester.getCenter(_orb));
    await tester.pump(const Duration(milliseconds: 600));
    await rest.up();
    await _frames(tester);

    expect(voice.sends, 0, reason: 'a rested finger is not an ending');
  });

  testWidgets('a press cannot re-open a microphone a tap already opened', (
    tester,
  ) async {
    // Otherwise the recogniser is torn down and rebuilt mid-sentence.
    final voice = await _pump(tester);

    await tester.tap(_orb);
    await _frames(tester);

    final press = await tester.startGesture(tester.getCenter(_orb));
    await tester.pump(const Duration(milliseconds: 600));
    expect(voice.starts, 1);

    await press.up();
    await _frames(tester);
  });

  testWidgets('the copy follows the gesture, not the state', (tester) async {
    // "Release to search" in front of somebody who tapped is an instruction
    // they cannot follow — their finger is not on the screen.
    await _pump(tester);

    await tester.tap(_orb);
    await _frames(tester);

    expect(find.text('Tap the orb to search'), findsOneWidget);
    expect(find.text('Release to search'), findsNothing);
  });

  testWidgets('holding says release, because a finger is down', (tester) async {
    await _pump(tester);

    final press = await tester.startGesture(tester.getCenter(_orb));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Release to search'), findsOneWidget);
    expect(find.text('Tap the orb to search'), findsNothing);

    await press.up();
    await _frames(tester);
  });

  testWidgets('at rest it offers both ways in, and claims nothing', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Hold to ask'), findsOneWidget);
    expect(find.text('Answers open the actual file.'), findsOneWidget);
    expect(find.text('Listening'), findsNothing);
  });
}

/// The eye's position on the face.
///
/// It looked wrong on device — a large gap between the tabs and the eye, and
/// the whole composition sitting low. The cause was the listening pill: it
/// keeps its 50pt slot while hidden so that opening the microphone does not
/// shove the eye down, but `MainAxisAlignment.center` then centred that empty
/// slot along with everything else. What gets centred has to be the *visible*
/// middle, which is what the design's home block centres.
void _layout() {
  testWidgets('the visible middle is centred, not the middle plus a pill', (
    tester,
  ) async {
    await _pump(tester);

    final face = tester.getRect(find.byType(VoiceHomeFace));
    final eye = tester.getRect(find.byType(EyeOrb));
    final copy = tester.getRect(find.text('Answers open the actual file.'));

    final above = eye.top - face.top;
    final below = face.bottom - copy.bottom;

    expect(
      above,
      closeTo(below, 1),
      reason:
          'the eye sat half a pill low: $above above, $below below. '
          'The hidden pill\'s slot must be balanced, not centred.',
    );
  });

  testWidgets('the height from the device report scrolls, never overflows', (
    tester,
  ) async {
    // 370 x 364: the constraint in the RenderFlex report from the device.
    // The face needs ~418px there, and used to paint yellow-and-black.
    tester.view
      ..physicalSize = const Size(370, 364)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester);
    expect(tester.takeException(), isNull);
    // Shrunk as far as the legibility floor, and no further.
    expect(tester.getSize(find.byType(EyeOrb)).width, EyeOrb.minSize);
  });

  testWidgets('with some room short of full, the eye shrinks to fit', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(370, 480)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(EyeOrb)).width;
    expect(size, lessThan(224));
    expect(size, greaterThanOrEqualTo(EyeOrb.minSize));
  });

  testWidgets('with room to spare, the eye is the design\'s 224', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(402, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester);
    expect(tester.getSize(find.byType(EyeOrb)).width, 224);
  });

  testWidgets('the eye is horizontally centred', (tester) async {
    await _pump(tester);
    final face = tester.getRect(find.byType(VoiceHomeFace));
    final eye = tester.getRect(find.byType(EyeOrb));
    expect(eye.center.dx, closeTo(face.center.dx, 0.5));
  });

  testWidgets('opening the microphone does not move the eye', (tester) async {
    final voice = await _pump(tester);
    final before = tester.getRect(find.byType(EyeOrb));

    await voice.toggleDictation();
    await tester.pump();
    // Straight after the state change, before the size animation runs: the
    // eye must not have been displaced by the pill becoming visible.
    expect(tester.getRect(find.byType(EyeOrb)).top, closeTo(before.top, 0.5));
  });
}

class _EmptyLibrary extends Fake implements MemoryRepository {
  @override
  Future<MemoryPage> fetchMemories({
    int limit = 20,
    int offset = 0,
    Set<MemoryType> types = const {},
    ProcessingStatus? status,
  }) async => (items: const <Memory>[], hasMore: false, offset: 0);
}
