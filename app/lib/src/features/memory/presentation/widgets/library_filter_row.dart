import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../domain/entities/library_filter.dart';

/// The row of kinds under "Recent": All · Docs · Images · Audio · Notes ·
/// Links · Video. One is always selected.
///
/// Drawn like a segmented tab pulled apart into pills — the selected one is
/// white with ink, the rest card-grey with muted text — so it reads as the
/// same control family as the On device / Drive tabs above it, and never as
/// a row of buttons that each do something.
class LibraryFilterRow extends StatelessWidget {
  const LibraryFilterRow({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final LibraryFilter selected;
  final ValueChanged<LibraryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSize.chip,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: LibraryFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = LibraryFilter.values[i];
          return _Kind(
            filter: filter,
            selected: filter == selected,
            onTap: () => onChanged(filter),
          );
        },
      ),
    );
  }
}

class _Kind extends StatelessWidget {
  const _Kind({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final LibraryFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: filter.label,
      child: Material(
        color: selected ? AppPalette.onPaper.surface : p.card,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: AppSize.chip,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              filter.label,
              style: AppTypography.chip.copyWith(
                color: selected ? AppPalette.onPaper.ink : p.textMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
