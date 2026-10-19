import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';

/// The accent-washed reassurance strip pinned above the legal line on 3E.
class SecurityBanner extends StatelessWidget {
  const SecurityBanner({super.key});

  static const _copy =
      'ENCRYPTED IN TRANSIT AND AT REST · YOUR VAULT IS YOURS ALONE';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.panel,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: p.accentWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.accentWashBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(AppIcons.shieldCheck, size: 16, color: p.accentSoft),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _copy,
              style: AppTypography.labelWide.copyWith(
                color: p.isDark ? const Color(0xFFB9CDFF) : p.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
