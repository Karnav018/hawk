import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/chat/presentation/widgets/result_file.dart';
import 'package:knowra/src/features/memory/domain/entities/memory_enums.dart';
import 'package:knowra/src/features/voice/presentation/widgets/result_stack.dart';

/// Screen 1O's stack, and the one thing about it that must be real.
///
/// The design puts a single file face up at full size and two dimmed cards
/// behind it. That is a confident arrangement — it says "this one, and there
/// are two others if I am wrong" — and it is only honest if getting to the
/// other two actually works. A stack that looked like this and did not cycle
/// would be an illustration of a feature.
void main() {
  ResultFile file(String title) => (
    memoryId: title,
    title: title,
    type: MemoryType.pdf,
    locator: 'page 2',
    url: null,
    storagePath: 'users/u1/board/$title.pdf',
  );

  Widget host(List<ResultFile> files) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          height: 520,
          child: ResultStack(files: files),
        ),
      ),
    ),
  );

  testWidgets('opens on the first file and says where it sits', (tester) async {
    await tester.pumpWidget(host([file('One'), file('Two'), file('Three')]));

    expect(find.text('One'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    // The others are shapes, not rows. Titling them would turn one confident
    // answer back into a list of three.
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('a drag past the threshold brings the next one up', (
    tester,
  ) async {
    await tester.pumpWidget(host([file('One'), file('Two'), file('Three')]));

    await tester.drag(find.text('One'), const Offset(0, 180));
    await tester.pumpAndSettle();

    expect(find.text('Two'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a short drag springs back rather than half-cycling', (
    tester,
  ) async {
    await tester.pumpWidget(host([file('One'), file('Two'), file('Three')]));

    // Under the threshold and slow enough not to read as a fling.
    await tester.timedDrag(
      find.text('One'),
      const Offset(0, 40),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();

    expect(find.text('One'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('the last card wraps back to the first', (tester) async {
    await tester.pumpWidget(host([file('One'), file('Two')]));

    await tester.drag(find.text('One'), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);

    await tester.drag(find.text('Two'), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
  });

  testWidgets('the hint is tappable, because a drag is not always possible', (
    tester,
  ) async {
    // A switch control or an unsteady hand cannot produce a drag, and "there
    // are two more files" must not be unreachable.
    await tester.pumpWidget(host([file('One'), file('Two'), file('Three')]));

    await tester.tap(find.text('DRAG FOR THE OTHER TWO'));
    await tester.pumpAndSettle();

    expect(find.text('Two'), findsOneWidget);
  });

  testWidgets('a single result is a card, not a stack', (tester) async {
    await tester.pumpWidget(host([file('Only')]));

    expect(find.text('Only'), findsOneWidget);
    // No hint, because there is nothing behind it to drag for.
    expect(find.textContaining('DRAG FOR'), findsNothing);

    // And the drag is inert rather than cycling to itself.
    await tester.drag(find.text('Only'), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('Only'), findsOneWidget);
  });

  // The deck changes while it is on screen: the matches land first, and the
  // answer then replaces them with only the files it cited.
  group('when the answer replaces the matches', () {
    testWidgets('a deck without the card on top opens at its first', (
      tester,
    ) async {
      final one = file('One');
      final two = file('Two');
      final three = file('Three');
      await tester.pumpWidget(host([one, two, three]));
      await tester.drag(find.text('One'), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.text('Two'), findsOneWidget);

      // One cited file, and it is not the one being looked at. This used to
      // read `files[1]` of a one-file list.
      await tester.pumpWidget(host([three]));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Three'), findsOneWidget);
    });

    testWidgets('a deck that still has the card keeps it on top', (
      tester,
    ) async {
      final one = file('One');
      final two = file('Two');
      final three = file('Three');
      await tester.pumpWidget(host([one, two, three]));
      await tester.drag(find.text('One'), const Offset(0, 180));
      await tester.pumpAndSettle();

      // Re-ordered by the answer, and shorter — but Two is still in it.
      await tester.pumpWidget(host([three, two]));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Three'), findsNothing);
    });

    testWidgets('a deck emptied mid-swipe settles without a next card', (
      tester,
    ) async {
      await tester.pumpWidget(host([file('One'), file('Two')]));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('One')),
      );
      await gesture.moveBy(const Offset(0, 180));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Gone while the card is still in flight.
      await tester.pumpWidget(host(const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no files is an empty box, not a crash', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(tester.takeException(), isNull);
  });
}
