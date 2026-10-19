import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/app/theme/app_palette.dart';
import 'package:knowra/src/app/theme/app_theme.dart';
import 'package:knowra/src/app/theme/app_typography.dart';

void main() {
  test('there is one theme, and both entry points return it', () {
    // v3 is drawn on a single ground. `AppTheme.light` exists only so
    // MaterialApp can be handed both slots without either pretending a light
    // design exists — if these ever diverge, someone has invented a light
    // theme the design does not have.
    expect(AppTheme.dark.extension<AppPalette>(), AppPalette.dark);
    expect(AppTheme.light.extension<AppPalette>(), AppPalette.dark);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.light.brightness, Brightness.dark);
  });

  test('the ground and the accent are the values the design names', () {
    expect(AppPalette.dark.ground, const Color(0xFF0C0C0D));
    expect(AppPalette.dark.card, const Color(0xFF191A1B));
    expect(AppPalette.dark.accent, const Color(0xFF59D3FF));
    // Ink on the accent is the ground, not white: the accent is bright
    // enough that white on it fails contrast at body sizes.
    expect(AppPalette.dark.onAccent, AppPalette.dark.ground);
  });

  test('surfaces step upwards and never collide', () {
    const p = AppPalette.dark;
    final steps = [p.ground, p.cardDim, p.card, p.raised];
    expect(steps.toSet().length, steps.length);
    for (var i = 1; i < steps.length; i++) {
      expect(
        steps[i].computeLuminance(),
        greaterThan(steps[i - 1].computeLuminance()),
        reason: 'surface $i must be lighter than the one it sits on',
      );
    }
  });

  test('type uses two families, and the serif is gone', () {
    expect(AppTypography.display38.fontFamily, 'Archivo');
    expect(AppTypography.bodyLarge.fontFamily, 'Archivo');
    expect(AppTypography.meta.fontFamily, 'Poppins');
  });

  test('every display size is the same heavy, tight shape', () {
    for (final style in [
      AppTypography.display38,
      AppTypography.display34,
      AppTypography.display28,
      AppTypography.display24,
      AppTypography.display18,
    ]) {
      expect(style.fontWeight, FontWeight.w800);
      // Tracking is negative and proportional to the size — a headline set
      // at default tracking is the single clearest sign of an unported
      // screen.
      expect(style.letterSpacing, lessThan(0));
    }
  });

  test('mono is tracked, because it is always set in caps', () {
    expect(AppTypography.meta.letterSpacing, greaterThan(0));
    expect(
      AppTypography.metaWide.letterSpacing,
      greaterThan(AppTypography.meta.letterSpacing!),
    );
  });

  testWidgets('palette resolves through context', (tester) async {
    late AppPalette seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            seen = context.palette;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.ground, const Color(0xFF0C0C0D));
  });
}
