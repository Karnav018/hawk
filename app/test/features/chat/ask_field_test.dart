import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/features/chat/presentation/widgets/ask_field.dart';

/// The ask bar's keyboard: a tap anywhere else puts it away, and the bar's
/// own circle does not count as anywhere else.
void main() {
  late TextEditingController controller;
  late List<String> submitted;

  setUp(() {
    controller = TextEditingController();
    submitted = [];
  });
  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester, {VoidCallback? onMic}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: Center(child: Text('the ground'))),
                AskField(
                  controller: controller,
                  onSubmit: submitted.add,
                  onMic: onMic,
                ),
              ],
            ),
          ),
        ),
      );

  bool focused(WidgetTester tester) => tester
      .state<EditableTextState>(find.byType(EditableText))
      .widget
      .focusNode
      .hasFocus;

  testWidgets('a tap on the ground drops the keyboard', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focused(tester), isTrue);

    await tester.tap(find.text('the ground'));
    await tester.pump();
    expect(focused(tester), isFalse);
  });

  testWidgets('so does the start of a scroll', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // A drag begins with a pointer down, and that is what counts.
    await tester.drag(find.text('the ground'), const Offset(0, -80));
    await tester.pump();
    expect(focused(tester), isFalse);
  });

  testWidgets('the circle is part of the bar: Send keeps the focus', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'what did I pay?');
    await tester.pump();
    expect(focused(tester), isTrue);

    // Pressing Send is not a tap outside the field. What happens to the
    // keyboard is then the screen's decision — both screens that use the
    // bar drop it themselves after a send, and the bar must not decide for
    // one that wants to keep it up for a follow-up.
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    expect(submitted, ['what did I pay?']);
    expect(focused(tester), isTrue);
  });

  testWidgets('and so is the microphone', (tester) async {
    var mic = 0;
    await pump(tester, onMic: () => mic++);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Ask out loud'));
    await tester.pump();
    expect(mic, 1);
    expect(focused(tester), isTrue);
  });
}
