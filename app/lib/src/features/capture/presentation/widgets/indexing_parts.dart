import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../bloc/upload_job.dart';
import 'upload_icons.dart';

/// The ring with a number in it — a row that is still being read (F2·2).
///
/// A ring rather than the filled dot it replaces, because the dot was the
/// loudest thing on a row that was, by definition, not ready to be opened.
/// The ring says "working, this far" and leaves the accent to the arc.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.fraction,
    this.size = 34,
    this.track,
    super.key,
  });

  final double fraction;
  final double size;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final percent = (fraction.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      label: '$percent per cent',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            value: fraction.clamp(0.0, 1.0),
            color: p.accent,
            track: track ?? p.raised,
          ),
          child: Center(
            child: Text(
              '$percent',
              style: AppTypography.meta.copyWith(
                fontSize: 8.5,
                letterSpacing: 0,
                color: p.textPrimary,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    // The design's geometry: r 14 in a 36 box, stroke 3.5.
    final unit = size.width / 36;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: 14 * unit,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * unit;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// A 6px bar — accent while it moves, red where it stopped (E6).
class ThinBar extends StatelessWidget {
  const ThinBar({required this.value, this.failed = false, super.key});

  final double value;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.round),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: p.raised),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: failed ? p.danger : p.accent,
                  borderRadius: BorderRadius.circular(AppRadius.round),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The file being indexed, its size and type, and the bar (F1·4).
class FileProgressCard extends StatelessWidget {
  const FileProgressCard({
    required this.icon,
    required this.name,
    required this.meta,
    required this.fraction,
    this.failed = false,
    super.key,
  });

  final String icon;
  final String name;
  final String meta;
  final double fraction;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return HawkCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: icon, size: 52, radius: 17, strokeWidth: 1.7),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleLarge.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MetaText(meta),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${(fraction.clamp(0.0, 1.0) * 100).round()}%',
                style: AppTypography.meta.copyWith(
                  fontSize: 13,
                  letterSpacing: 0,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.inset),
          ThinBar(value: fraction, failed: failed),
        ],
      ),
    );
  }
}

/// The four steps, in one card, hairlines between them.
class StepList extends StatelessWidget {
  const StepList({required this.steps, super.key});

  final List<IndexStep> steps;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return HawkCard(
      radius: AppRadius.card,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (final (i, step) in steps.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: i == steps.length - 1
                  ? null
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.divider)),
                    ),
              child: StepRow(step: step),
            ),
        ],
      ),
    );
  }
}

class StepRow extends StatelessWidget {
  const StepRow({required this.step, super.key});

  final IndexStep step;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final note = step.note;
    return Semantics(
      label:
          '${step.label}, ${step.state.name}${note == null ? '' : ', $note'}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox.square(dimension: 26, child: StepMark(state: step.state)),
          const SizedBox(width: AppSpacing.group),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    letterSpacing: -0.145,
                    color: step.state == IndexStepState.pending
                        ? p.textFaint
                        : p.textPrimary,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  MetaText(
                    note,
                    color: step.state == IndexStepState.failed
                        ? p.danger
                        : p.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 26px mark at the start of a step — the parts sheet's five states.
class StepMark extends StatelessWidget {
  const StepMark({required this.state, super.key});

  final IndexStepState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget dot(Color fill, Widget glyph) => Container(
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: glyph,
    );

    return switch (state) {
      IndexStepState.done => dot(
        p.accent,
        AppIcon(HawkIcons.check, size: 14, color: p.onAccent),
      ),
      IndexStepState.active => Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(p.accent),
            backgroundColor: p.raised,
          ),
        ),
      ),
      IndexStepState.waiting => dot(
        p.raised,
        AppIcon(
          UploadIcons.offline,
          size: 13,
          color: p.textPrimary,
          strokeWidth: 2.2,
        ),
      ),
      IndexStepState.failed => dot(
        p.danger,
        AppIcon(UploadIcons.bang, size: 14, color: p.onAccent, strokeWidth: 3),
      ),
      IndexStepState.pending => Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.raised, width: 2),
          ),
        ),
      ),
    };
  }
}

/// One file of several (F3·4): its own state, and its own bar while it is
/// still going.
class BatchFileCard extends StatelessWidget {
  const BatchFileCard({
    required this.icon,
    required this.name,
    required this.meta,
    required this.fraction,
    required this.outcome,
    this.onRetry,
    super.key,
  });

  final String icon;
  final String name;
  final String meta;
  final double fraction;
  final JobOutcome outcome;

  /// Offered when trying again could help.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final working = outcome == JobOutcome.working;
    final broken =
        outcome == JobOutcome.failed ||
        outcome == JobOutcome.stopped ||
        outcome == JobOutcome.held;

    Widget dot(Color fill, String glyph, Color ink) => Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: AppIcon(glyph, size: 14, color: ink, strokeWidth: 3),
    );

    return HawkCard(
      radius: AppRadius.row,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.inset,
        vertical: AppSpacing.group,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: icon, strokeWidth: 1.7),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)],
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    MetaText(meta, color: broken ? p.danger : null),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (working)
                Text(
                  '${(fraction.clamp(0.0, 1.0) * 100).round()}%',
                  style: AppTypography.meta.copyWith(
                    fontSize: 12,
                    letterSpacing: 0,
                    color: p.textPrimary,
                  ),
                )
              else if (onRetry != null)
                InlineChip(label: 'Retry', onPressed: onRetry)
              else if (broken)
                dot(p.danger, UploadIcons.bang, p.onAccent)
              else
                dot(p.accent, HawkIcons.check, p.onAccent),
            ],
          ),
          if (working) ...[
            const SizedBox(height: AppSpacing.md),
            ThinBar(value: fraction),
          ],
        ],
      ),
    );
  }
}
