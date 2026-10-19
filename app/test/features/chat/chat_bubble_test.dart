import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_spacing.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/chat/presentation/widgets/chat_bubble.dart';

/// Screen 1P's bubbles.
///
/// The square corner is the only thing telling a reader who spoke — there are
/// no avatars, no names and no timestamps in the design — so it is worth a
/// test rather than an eye. A bubble that rounds all four corners is not a
/// cosmetic regression; it is an unattributed sentence.
void main() {
  Widget host({required bool isUser, bool isQuiet = false}) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: ChatBubble(text: 'pricing', isUser: isUser, isQuiet: isQuiet),
    ),
  );

  BorderRadius radiusOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(ChatBubble),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    return decoration.borderRadius! as BorderRadius;
  }

  Color colourOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(ChatBubble),
        matching: find.byType(Container),
      ),
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('the question squares its bottom-right corner', (tester) async {
    await tester.pumpWidget(host(isUser: true));
    final radius = radiusOf(tester);

    expect(radius.bottomRight.x, AppRadius.tail);
    expect(radius.bottomLeft.x, AppRadius.bubble);
    expect(radius.topLeft.x, AppRadius.bubble);
  });

  testWidgets('the answer squares its bottom-left corner', (tester) async {
    await tester.pumpWidget(host(isUser: false));
    final radius = radiusOf(tester);

    expect(radius.bottomLeft.x, AppRadius.tail);
    expect(radius.bottomRight.x, AppRadius.bubble);
  });

  testWidgets('the accent is spent on what you said, not on the reply', (
    tester,
  ) async {
    // One accent per screen, and in a thread it belongs to the question.
    // v2 accented the answer, which made the machine the loudest voice in
    // its own transcript.
    await tester.pumpWidget(host(isUser: true));
    expect(colourOf(tester), AppPalette.dark.accent);

    await tester.pumpWidget(host(isUser: false));
    expect(colourOf(tester), AppPalette.dark.card);
  });

  testWidgets('an earlier turn keeps the shape and loses the accent', (
    tester,
  ) async {
    // A thread of six bubbles must still have exactly one accented one.
    await tester.pumpWidget(host(isUser: true, isQuiet: true));

    expect(colourOf(tester), isNot(AppPalette.dark.accent));
    expect(radiusOf(tester).bottomRight.x, AppRadius.tail);
  });
}
