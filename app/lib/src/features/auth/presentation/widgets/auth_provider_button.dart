import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';

/// How a sign-in button is weighted on the screen.
enum AuthButtonVariant {
  /// Accent-filled — the one primary action. Google, on screen 1B.
  primary,

  /// Card-filled. An equal way in, not a fallback: same height, same type,
  /// different surface.
  secondary,
}

/// The 58px provider button from screen 1B.
///
/// A pill, and no border at rest. v2 outlined the secondary button so it
/// would read as a button at all against a translucent fill; v3's fill is
/// opaque, so the outline is redundant and its absence is what makes the
/// stack look like two objects rather than two boxes.
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = AuthButtonVariant.secondary,
    this.isBusy = false,
    this.isUnavailable = false,
    super.key,
  });

  final String label;
  final String icon;
  final VoidCallback? onPressed;
  final AuthButtonVariant variant;
  final bool isBusy;

  /// The platform supports this provider but the build is missing its
  /// credentials. Still tappable — the error names what is missing.
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    var (background, foreground) = switch (variant) {
      AuthButtonVariant.primary => (p.accent, p.onAccent),
      AuthButtonVariant.secondary => (p.card, p.textPrimary),
    };

    if (isUnavailable) {
      background = p.cardDim;
      foreground = p.textFaint;
    }

    // The Google glyph carries its own colours and must not be recoloured —
    // a monochrome Google mark is not a Google mark, and their brand terms
    // say so. Every other provider icon takes the button's foreground.
    final tintable = !icon.contains('#');

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          child: SizedBox(
            height: AppSize.button,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isBusy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(foreground),
                    ),
                  )
                else
                  AppIcon(
                    icon,
                    size: 18,
                    color: tintable ? foreground : p.onAccent,
                  ),
                const SizedBox(width: AppSpacing.sm + 2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.button.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
