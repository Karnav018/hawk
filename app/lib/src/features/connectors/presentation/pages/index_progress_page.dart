import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/eye/eye_orb.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../domain/entities/index_job.dart';
import '../bloc/index_progress_cubit.dart';
import 'vault_ready_page.dart';

/// Screen 1J — INDEXING.
///
/// A window onto one Firestore document. The worker writes progress, this
/// listens — no polling endpoint, no websocket, and the screen keeps updating
/// while the app is backgrounded and resumed.
///
/// **The numbers live in one card.** v2 spread the percentage, the bar, the
/// stage label and the per-kind rows down the screen as separate blocks; v3
/// collects them into a single 28px card under the orb, which turns "how is
/// it going" into one object you glance at rather than four you read.
class IndexProgressPage extends StatelessWidget {
  const IndexProgressPage({super.key});

  static const routeName = 'indexProgress';
  static const routePath = '/welcome/indexing/:jobId';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<IndexProgressCubit, IndexProgressState>(
      builder: (context, state) {
        final job = state.job;
        final remaining = job?.estimateRemaining();

        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          footer: PillButton(
            // The button follows the promise: you are not held here.
            label: switch (job?.state) {
              IndexJobState.complete => 'Start asking',
              _ when state.hasFailed => 'Continue anyway',
              _ => 'Keep going in the background',
            },
            tone: job?.state == IndexJobState.complete
                ? PillTone.primary
                : PillTone.secondary,
            // Onboarding does not end here. A failed index still finished the
            // run — the connection exists and the folders are recorded, so
            // moving on and letting the sweep retry beats stranding the user
            // in front of a bar that has stopped.
            onPressed: !state.canLeave
                ? null
                : () => context.pushReplacementNamed(VaultReadyPage.routeName),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const MetaText('Building your library', size: 10),
                  // Withheld until the throughput sample is worth trusting —
                  // an estimate that swings from 30 seconds to nine minutes
                  // is worse than no estimate.
                  if (remaining != null)
                    Text(
                      '${_clock(remaining)} LEFT',
                      style: AppTypography.meta10.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                ],
              ),

              // The eye takes the whole middle. This is the one moment the
              // app is working *for* you rather than with you — and its lids
              // are the progress indicator, opening with the job fraction,
              // so the screen says how far along it is without a spinner.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EyeOrb(
                      size: 190,
                      state: OrbState.indexing,
                      progress: job?.fraction ?? 0,
                      semanticLabel: 'Indexing',
                    ),
                    const SizedBox(height: AppSpacing.blockWide),
                    Headline(
                      switch (job?.state) {
                        IndexJobState.complete => 'Your library is ready',
                        IndexJobState.failed => 'Indexing stopped',
                        _ when state.hasFailed => 'Indexing stopped',
                        _ when job == null && !state.isLoading =>
                          'That index job is gone',
                        _ when (job?.totalFiles ?? 0) > 0 =>
                          'Reading ${_grouped(job!.totalFiles)} files',
                        _ => 'Looking through your folders',
                      },
                      size: 30,
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    Text(
                      // `state.failure` covers both a job that recorded an
                      // error and a stream that was refused — the second was
                      // previously invisible, so a permission-denied looked
                      // like a job that had simply not started.
                      state.failure ?? 'Ask as soon as the first ones land.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: state.hasFailed ? p.danger : p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.blockWide),
                    _ProgressCard(job: job),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Everything numeric, in one card.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.job});

  final IndexJob? job;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fraction = job?.fraction ?? 0;

    return HawkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(fraction * 100).round()}%',
                style: AppTypography.numeralLarge.copyWith(
                  color: p.textPrimary,
                ),
              ),
              Text(
                '${_grouped(job?.processed ?? 0)} / '
                '${_grouped(job?.totalFiles ?? 0)}',
                style: AppTypography.meta10.copyWith(color: p.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
          // Animated so a jump from 193 to 218 reads as motion rather than a
          // redraw — progress that teleports looks broken even when it is not.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ProgressTrack(value: value),
          ),
          for (final kind in job?.byKind ?? const <IndexKindProgress>[]) ...[
            const SizedBox(height: AppSpacing.group),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  kind.label,
                  style: AppTypography.caption.copyWith(
                    fontSize: 13,
                    color: p.textSecondary,
                  ),
                ),
                Text(
                  '${_grouped(kind.done)} / ${_grouped(kind.total)}',
                  style: AppTypography.meta.copyWith(
                    fontSize: 11,
                    color: p.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _clock(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
