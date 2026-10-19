import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the Material theme from the v3 design tokens.
///
/// One theme, because v3 is drawn on one ground. [AppPalette.dark] is the
/// source of truth and [ColorScheme] is derived from it, so a stock Material
/// widget that nobody has styled still lands close to the design instead of
/// arriving in Material purple.
abstract final class AppTheme {
  static ThemeData get dark => _build(AppPalette.dark);

  /// Kept so `MaterialApp.theme` and `darkTheme` can both be handed something
  /// without either pretending a light design exists. Both are the same
  /// object; see [AppPalette].
  static ThemeData get light => dark;

  /// The status bar is always light-on-dark, because the ground always is.
  static SystemUiOverlayStyle overlayStyle(AppPalette palette) =>
      SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: palette.ground,
        systemNavigationBarIconBrightness: Brightness.light,
      );

  static ThemeData _build(AppPalette p) {
    final scheme = const ColorScheme.dark().copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      surface: p.ground,
      onSurface: p.textPrimary,
      surfaceContainer: p.card,
      surfaceContainerHigh: p.raised,
      outline: p.divider,
      error: p.danger,
      onError: p.onAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ground,
      canvasColor: p.ground,
      fontFamily: AppTypography.sans,
      extensions: [p],
      // No ripple. v3 has no elevation and no glow; an expanding light
      // circle is the one piece of Material vocabulary that would read as
      // borrowed from a different product.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.white.withValues(alpha: 0.04),
      textTheme: _textTheme(p),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle(p),
        titleTextStyle: AppTypography.display18.copyWith(color: p.textPrimary),
      ),
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: 19),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.card,
          disabledForegroundColor: p.textFaint,
          minimumSize: const Size.fromHeight(AppSize.button),
          shape: const StadiumBorder(),
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          backgroundColor: p.card,
          minimumSize: const Size.fromHeight(AppSize.button),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          textStyle: AppTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: AppTypography.titleSoft,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardWide,
          vertical: AppSpacing.lg,
        ),
        hintStyle: AppTypography.bodyLarge.copyWith(color: p.textFaint),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.round)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.round)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.card,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: p.textBright,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.raised,
        linearMinHeight: 8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppPalette.onPaper.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
    );
  }

  static TextTheme _textTheme(AppPalette p) => TextTheme(
    displayLarge: AppTypography.display38.copyWith(color: p.textPrimary),
    displayMedium: AppTypography.display34.copyWith(color: p.textPrimary),
    displaySmall: AppTypography.display30.copyWith(color: p.textPrimary),
    headlineMedium: AppTypography.display24.copyWith(color: p.textPrimary),
    headlineSmall: AppTypography.display18.copyWith(color: p.textPrimary),
    titleLarge: AppTypography.titleLarge.copyWith(color: p.textPrimary),
    titleMedium: AppTypography.titleMedium.copyWith(color: p.textPrimary),
    titleSmall: AppTypography.titleSmall.copyWith(color: p.textPrimary),
    bodyLarge: AppTypography.bodyLarge.copyWith(color: p.textBright),
    bodyMedium: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
    bodySmall: AppTypography.bodySmall.copyWith(color: p.textTertiary),
    labelLarge: AppTypography.button.copyWith(color: p.textPrimary),
    labelMedium: AppTypography.meta.copyWith(color: p.textMuted),
    labelSmall: AppTypography.meta.copyWith(color: p.textMuted),
  );
}
