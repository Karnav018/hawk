import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/feedback/snack.dart';
import 'package:knowra/src/core/feedback/snack_controller.dart';
import 'package:knowra/src/core/feedback/snack_host.dart';
import 'package:knowra/src/core/feedback/snack_timing.dart';
import 'package:knowra/src/core/feedback/widgets/snack_surface.dart';

/// Where a snack sits and how it arrives — `Hawk Snackbars.dc.html`
/// section 2: "TOP = SAFE AREA + 8PX · 20PX SIDE INSET · ENTER 500MS · DROPS
/// 14PX FROM THE NOTCH · DISMISS · SWIPE UP".
void main() {
  const inset = 59.0; // an island iPhone's status bar

  Future<SnackController> pump(
    WidgetTester tester, {
    required bool island,
  }) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: inset);
    addTearDown(tester.view.reset);
    final controller = SnackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) =>
            SnackHost(controller: controller, island: island, child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    return controller;
  }

  Rect surface(WidgetTester tester) =>
      tester.getRect(find.byType(SnackSurface).first);

  const detail = Snack.detail(
    title: 'Could not connect',
    subtitle: "Google Drive didn't respond. Try again in a moment.",
    mark: SnackMark.failure,
  );

  testWidgets('it rests at the top, under the safe area, inset 20px', (
    tester,
  ) async {
    final controller = await pump(tester, island: false);
    controller.show(detail);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final rect = surface(tester);
    expect(rect.top, inset + SnackTiming.topGap);
    expect(rect.left, SnackTiming.sideInset);
    expect(rect.right, 402 - SnackTiming.sideInset);

    controller.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('on an island iPhone it starts as the island', (tester) async {
    final controller = await pump(tester, island: true);
    controller.show(detail);
    await tester.pump(); // the first frame of the entrance

    final start = surface(tester);
    expect(start.top, closeTo(SnackIsland.top, 0.5));
    expect(start.width, closeTo(SnackIsland.width, 0.5));

    await tester.pump(const Duration(milliseconds: 600));
    final rest = surface(tester);
    expect(rest.top, inset + SnackTiming.topGap);
    expect(rest.width, 402 - 2 * SnackTiming.sideInset);

    controller.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('elsewhere it drops 14px into place and fades in', (
    tester,
  ) async {
    final controller = await pump(tester, island: false);
    controller.show(detail);
    await tester.pump();

    expect(
      surface(tester).top,
      closeTo(inset + SnackTiming.topGap - SnackTiming.dropDistance, 0.5),
    );
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(SnackSurface),
            matching: find.byType(FadeTransition),
          )
          .last,
    );
    expect(fade.opacity.value, 0);

    controller.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a swipe up dismisses it', (tester) async {
    final controller = await pump(tester, island: false);
    controller.show(
      const Snack.confirmation(message: 'Saved — reading it now'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.drag(
      find.text('Saved — reading it now'),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(controller.current, isNull);
  });

  testWidgets('progress is status: no swipe away, only its ×', (tester) async {
    final controller = await pump(tester, island: false);
    controller.show(
      const Snack.progress(message: 'Indexing 24 files', fraction: 0.62),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.drag(find.text('Indexing 24 files'), const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.current, isA<ProgressSnack>());

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Dismiss',
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.current, isNull);
  });

  // The Indexing screen pokes `UploadCenter` from its initState (attach) and
  // its dispose (detach), and either can put a snack up or take the island
  // down — from inside a frame, while the widget tree is locked. The host
  // has to take that without asserting.
  testWidgets('a snack shown while a screen is being built waits for the '
      'end of the frame', (tester) async {
    final controller = SnackController();
    addTearDown(controller.dispose);
    // Built in a later frame, the way a route is pushed: in the first frame
    // everything is under the build target and nothing would assert.
    final pushed = ValueNotifier(false);
    addTearDown(pushed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) =>
            SnackHost(controller: controller, island: false, child: child!),
        home: ValueListenableBuilder<bool>(
          valueListenable: pushed,
          builder: (_, on, _) =>
              on ? _ShowsOn(controller, _When.built) : const SizedBox.expand(),
        ),
      ),
    );

    pushed.value = true;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.current, isA<ConfirmationSnack>());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Saved — reading it now'), findsOneWidget);

    controller.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a snack shown from a leaving screen\'s dispose waits too', (
    tester,
  ) async {
    final controller = SnackController();
    addTearDown(controller.dispose);
    Widget app(Widget home) => MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) =>
          SnackHost(controller: controller, island: false, child: child!),
      home: home,
    );
    await tester.pumpWidget(app(_ShowsOn(controller, _When.disposed)));

    // Replacing the home unmounts the screen at the end of this frame.
    await tester.pumpWidget(app(const SizedBox.expand()));

    expect(tester.takeException(), isNull);
    expect(controller.current, isA<ProgressSnack>());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Indexing 1 file'), findsOneWidget);
  });

  test('an island is an iPhone inset of 59, never a notch or Android', () {
    MediaQueryData top(double inset) =>
        MediaQueryData(padding: EdgeInsets.only(top: inset));

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(SnackHost.hasIsland(top(59)), isTrue);
    expect(SnackHost.hasIsland(top(47)), isFalse, reason: 'a notch');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SnackHost.hasIsland(top(59)), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}

enum _When { built, disposed }

/// A screen that shows a snack from a lifecycle hook.
class _ShowsOn extends StatefulWidget {
  const _ShowsOn(this.controller, this.when);

  final SnackController controller;
  final _When when;

  @override
  State<_ShowsOn> createState() => _ShowsOnState();
}

class _ShowsOnState extends State<_ShowsOn> {
  @override
  void initState() {
    super.initState();
    if (widget.when == _When.built) {
      widget.controller.show(
        const Snack.confirmation(message: 'Saved — reading it now'),
      );
    }
  }

  @override
  void dispose() {
    if (widget.when == _When.disposed) {
      widget.controller.show(
        const Snack.progress(message: 'Indexing 1 file', fraction: 0.1),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
