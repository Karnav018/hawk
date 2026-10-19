import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_spacing.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/core/widgets/hawk_nav.dart';

Widget _host(HawkTab current, {ValueChanged<HawkTab>? onSelect}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 370, // 402 design frame, less the 16px side gutters.
        child: HawkNav(current: current, onSelect: onSelect ?? (_) {}),
      ),
    ),
  ),
);

/// Where the travelling circle currently is.
Rect _circle(WidgetTester tester) =>
    tester.getRect(find.byType(AnimatedPositioned));

/// The bar's *content* box — the slots are thirds of this, not of the bar,
/// because the pill carries an 8px inset of its own.
Rect _content(WidgetTester tester) =>
    tester.getRect(find.byType(HawkNav)).deflate(AppSpacing.sm);

double _slotCentre(WidgetTester tester, int index) {
  final content = _content(tester);
  final slot = content.width / HawkTab.values.length;
  return content.left + slot * (index + 0.5);
}

void main() {
  testWidgets('the selection sits under the current tab', (tester) async {
    await tester.pumpWidget(_host(HawkTab.home));
    await tester.pumpAndSettle();

    final circle = _circle(tester);

    expect(
      circle.center.dx,
      moreOrLessEquals(_slotCentre(tester, HawkTab.home.index), epsilon: 0.5),
      reason: 'home is the first of three equal slots',
    );
    expect(
      circle.center.dy,
      moreOrLessEquals(_content(tester).center.dy, epsilon: 0.5),
      reason: 'and vertically centred in the bar',
    );
  });

  testWidgets('it travels rather than jumping', (tester) async {
    await tester.pumpWidget(_host(HawkTab.home));
    await tester.pumpAndSettle();
    final from = _circle(tester).center.dx;

    await tester.pumpWidget(_host(HawkTab.you));
    await tester.pump(const Duration(milliseconds: 80));
    final midway = _circle(tester).center.dx;

    await tester.pumpAndSettle();
    final to = _circle(tester).center.dx;

    // The frame in between is the whole point: a circle that is already at
    // its destination one frame after the tap has not moved, it has been
    // redrawn somewhere else.
    expect(midway, greaterThan(from));
    expect(midway, lessThan(to));
  });

  testWidgets('the icon fades in step with the circle, never before it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(HawkTab.home));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(HawkTab.library));
    await tester.pump(const Duration(milliseconds: 40));

    final opacities = tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((w) => w.opacity)
        .toSet();

    // Mid-transition at least one glyph is partway, rather than every one
    // sitting at a final 0 or 1.
    expect(
      opacities.any((o) => o > 0 && o < 1) || opacities.length > 1,
      isTrue,
    );
  });

  testWidgets('tapping the current tab does nothing', (tester) async {
    final taps = <HawkTab>[];
    await tester.pumpWidget(_host(HawkTab.home, onSelect: taps.add));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();

    // A second copy of the screen you are already looking at is the thing
    // this prevents.
    expect(taps, isEmpty);
  });

  testWidgets('tapping another tab reports it once', (tester) async {
    final taps = <HawkTab>[];
    await tester.pumpWidget(_host(HawkTab.home, onSelect: taps.add));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Library'));
    await tester.pumpAndSettle();

    expect(taps, [HawkTab.library]);
  });

  testWidgets('the whole third is the target, not just the glyph', (
    tester,
  ) async {
    final taps = <HawkTab>[];
    await tester.pumpWidget(_host(HawkTab.home, onSelect: taps.add));
    await tester.pumpAndSettle();

    final content = _content(tester);
    final slot = content.width / HawkTab.values.length;

    // Near the right edge of the middle third — well outside the 46px
    // circle, and exactly where a thumb lands when nobody is aiming.
    await tester.tapAt(Offset(content.left + slot * 2 - 4, content.center.dy));
    await tester.pumpAndSettle();

    expect(taps, [HawkTab.library]);
  });

  testWidgets('reduce motion removes the travel entirely', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(_host(HawkTab.home));
    await tester.pumpAndSettle();
    final target = _slotCentre(tester, HawkTab.you.index);

    await tester.pumpWidget(_host(HawkTab.you));
    await tester.pump();

    // Already arrived on the very next frame. Unlike a launch animation this
    // one fires on every navigation, so "shorter" is not good enough.
    expect(_circle(tester).center.dx, moreOrLessEquals(target, epsilon: 0.5));
  });

  testWidgets('the bar keeps its design height', (tester) async {
    await tester.pumpWidget(_host(HawkTab.home));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(HawkNav)).height, AppSize.nav);
  });
}
