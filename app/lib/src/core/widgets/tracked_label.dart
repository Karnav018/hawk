import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_typography.dart';

/// Archivo at 10.5/600 in tracked caps — the label style used everywhere.
///
/// Uppercasing happens here rather than at call sites so the tracking and the
/// casing can never drift apart.
class TrackedLabel extends StatelessWidget {
  const TrackedLabel(
    this.text, {
    this.color,
    this.tracking = LabelTracking.wide,
    super.key,
  });

  final String text;
  final Color? color;
  final LabelTracking tracking;

  @override
  Widget build(BuildContext context) {
    final style = switch (tracking) {
      LabelTracking.wide => AppTypography.label,
      LabelTracking.tight => AppTypography.labelTight,
      LabelTracking.banner => AppTypography.labelWide,
    };

    return Text(
      text.toUpperCase(),
      style: style.copyWith(color: color ?? context.palette.textTertiary),
    );
  }
}

enum LabelTracking { wide, tight, banner }

/// The metadata face (Poppins), reserved strictly for numerals: scores,
/// timers, dates, percentages. Never route prose through this.
class Numeral extends StatelessWidget {
  const Numeral(this.text, {this.color, this.large = false, super.key});

  final String text;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = large
        ? AppTypography.numeralLarge
        : AppTypography.numeralSmall;
    return Text(
      text,
      style: style.copyWith(color: color ?? context.palette.textTertiary),
    );
  }
}
