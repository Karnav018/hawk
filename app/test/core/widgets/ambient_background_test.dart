import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/ambient_background.dart';
import 'package:knowra/src/core/widgets/app_screen.dart';

/// The ground every screen sits on.
///
/// Every v3 screen passed `ambientOpacity: 0`, and every one still sat on a
/// violet-and-navy gradient: the opacity faded only the orb texture, while
/// two colour blooms and a `#070B16` scrim painted regardless. Nothing
/// caught it, because nothing asserted what the ground *was*. The v3 file
/// has no gradient, blur or shadow anywhere — 37 screens on `#0c0c0d`.
void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark, home: child);

  List<Decoration> decorations(WidgetTester tester) => [
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ))
      box.decoration,
  ];

  testWidgets('the ground is flat #0c0c0d', (tester) async {
    await tester.pumpWidget(host(const AmbientBackground()));
    final ground = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(AmbientBackground),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(ground.color, const Color(0xFF0C0C0D));
  });

  testWidgets('no gradient is painted, at any opacity a caller asks for', (
    tester,
  ) async {
    for (final opacity in [0.0, 0.36, 0.4, 1.0]) {
      await tester.pumpWidget(host(AmbientBackground(opacity: opacity)));
      final gradients = decorations(
        tester,
      ).whereType<BoxDecoration>().where((d) => d.gradient != null);
      expect(gradients, isEmpty, reason: 'opacity $opacity');
      expect(find.byType(Image), findsNothing, reason: 'no emission texture');
    }
  });

  testWidgets('a screen gets the flat ground by default', (tester) async {
    await tester.pumpWidget(host(const AppScreen(child: SizedBox())));
    final gradients = decorations(
      tester,
    ).whereType<BoxDecoration>().where((d) => d.gradient != null);
    expect(gradients, isEmpty);
  });
}
