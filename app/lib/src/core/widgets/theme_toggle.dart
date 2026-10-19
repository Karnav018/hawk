import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/theme_cubit.dart';
import 'app_icons.dart';

/// The sun/moon segmented switch from the design's screen headers.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mode = context.watch<ThemeCubit>().state;
    final isDark = mode == ThemeMode.dark;

    return Container(
      height: AppSize.headerButton,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(AppRadius.iconButton),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: AppIcons.sun,
            active: !isDark,
            onTap: () => isDark ? context.read<ThemeCubit>().toggle() : null,
          ),
          _Segment(
            icon: AppIcons.moon,
            active: isDark,
            onTap: () => isDark ? null : context.read<ThemeCubit>().toggle(),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? p.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: AppIcon(
          icon,
          size: 14,
          color: active ? p.ground : p.textTertiary,
        ),
      ),
    );
  }
}
