import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/core/widgets/app_icon_artwork.dart';
import 'package:knowra/src/core/widgets/hawk_mark.dart';
import 'package:knowra/src/core/widgets/hawk_orb.dart';

/// Why this file exists.
///
/// The launcher icon was a render of the v2 orb on v2 navy, and it stayed
/// that way through an entire design generation — the app went dark-ink and
/// two-circle everywhere while the thing on the home screen kept the old
/// sphere. Nothing caught it because nothing asserted what the icon *was*;
/// the generator ran green either way, since its only expectation was that a
/// file had been written.
///
/// So these tests pin identity, not pixels: the icon is the mark, on the
/// product's ground, at the design's own proportion.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: child),
  );

  testWidgets('the icon is the mark, never the orb', (tester) async {
    await pump(tester, const AppIconArtwork(size: 256));

    expect(find.byType(HawkMark), findsOneWidget);
    expect(
      find.byType(HawkOrb),
      findsNothing,
      reason: 'the orb is a different object; it lives inside the app',
    );
  });

  test('the mark fills the square the way a launcher needs', () {
    // The design sheet's 65/112 is kept as a record but is not what ships:
    // a launcher masks the square to a squircle and sets the icon beside
    // others whose glyphs fill far more of their tile.
    expect(AppIconArtwork.designMarkRatio, 65 / 112);
    expect(AppIconArtwork.launcherMarkRatio, 96 / 112);

    // The visible disc is 3/4 of the mark box (r24 on a 64 grid).
    final disc = AppIconArtwork.launcherMarkRatio * 0.75;
    expect(disc, greaterThan(0.6), reason: 'it read as a dot at 0.43');
    // Still clear of anything the squircle crops.
    expect(disc, lessThan(0.75));

    // Android crops an adaptive layer to its middle 72 of 108, so the mark
    // has to start smaller to end up the same size on screen.
    expect(
      AppIconArtwork.adaptiveMarkRatio,
      lessThan(AppIconArtwork.launcherMarkRatio),
    );
    expect(AppIconArtwork.adaptiveMarkRatio, (96 / 112) * (72 / 108));
  });

  testWidgets('the shipping icon sits on the product ground', (tester) async {
    await pump(tester, const AppIconArtwork(size: 256));

    final ground = tester.widget<Container>(find.byType(Container).first);
    expect(ground.color, const Color(0xFF0C0C0D));
    expect(
      ground.color,
      isNot(const Color(0xFF070B16)),
      reason: 'the v2 navy; if this ever comes back the icon has regressed',
    );
  });

  testWidgets('both Android layers are groundless', (tester) async {
    for (final v in [IconVariant.foreground, IconVariant.monochrome]) {
      await pump(tester, AppIconArtwork(size: 256, variant: v));
      final c = tester.widget<Container>(find.byType(Container).first);
      expect(c.color, Colors.transparent, reason: '$v');
    }
  });

  testWidgets('only the monochrome layer punches its highlight out', (
    tester,
  ) async {
    // The themed icon is tinted flat, so an accent highlight would arrive as
    // a featureless circle. It has to be a hole in the alpha channel.
    await pump(
      tester,
      const AppIconArtwork(size: 256, variant: IconVariant.monochrome),
    );
    expect(tester.widget<HawkMark>(find.byType(HawkMark)).knockout, isTrue);

    for (final v in [
      IconVariant.dark,
      IconVariant.light,
      IconVariant.foreground,
    ]) {
      await pump(tester, AppIconArtwork(size: 256, variant: v));
      expect(
        tester.widget<HawkMark>(find.byType(HawkMark)).knockout,
        isFalse,
        reason: '$v',
      );
    }
  });

  testWidgets('on paper the highlight is the ground, not a dot', (
    tester,
  ) async {
    await pump(
      tester,
      const AppIconArtwork(size: 256, variant: IconVariant.light),
    );

    final mark = tester.widget<HawkMark>(find.byType(HawkMark));
    final ground = tester.widget<Container>(find.byType(Container).first);
    expect(mark.highlight, ground.color);
  });
}
