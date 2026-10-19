import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../memory/presentation/pages/library_page.dart';
import '../../../memory/presentation/widgets/memory_icon.dart';
import '../../../voice/presentation/pages/home_page.dart';
import '../bloc/capture_cubit.dart';
import '../bloc/upload_center.dart';
import '../upload_flow.dart';
import '../widgets/indexing_parts.dart';

/// INDEXING — one batch, from the first byte to "Ready to ask".
///
/// One file is F1·4–F1·6: the file, a bar, and four steps named in plain
/// words. Several are F3·4: a card per file, each with its own state,
/// because four files do not move in step — one is being read while the next
/// is still uploading.
///
/// **Full screen, not a sheet, and leaving is fine.** The screen is pushed
/// over the Library with no nav pill, and its one button is "Back to
/// Library": the upload lives in `UploadCenter`, not here, so going back
/// hands the progress to the island (F2) rather than cancelling anything.
/// The line under the button says so, because the natural fear on a
/// progress screen is that leaving it stops the progress.
///
/// Also the end of every exception that happens after the upload starts:
/// waiting for a connection (E5), upload stopped (E6), mostly ready (E7).
class IndexingPage extends StatefulWidget {
  const IndexingPage({required this.batchId, super.key});

  static const routeName = 'indexing';
  static const routePath = '/indexing/:batchId';

  final String batchId;

  @override
  State<IndexingPage> createState() => _IndexingPageState();
}

class _IndexingPageState extends State<IndexingPage> {
  late final UploadCenter _center = context.read<UploadCenter>();

  @override
  void initState() {
    super.initState();
    _center.attach(widget.batchId);
  }

  @override
  void dispose() {
    _center.detach(widget.batchId);
    super.dispose();
  }

  void _back() => context.popOrGo(LibraryPage.routeName);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UploadCenter, UploadCenterState>(
      // Everything in the batch was removed: nothing is left to show.
      listenWhen: (a, b) =>
          a.batch(widget.batchId).isNotEmpty && b.batch(widget.batchId).isEmpty,
      listener: (context, _) => _back(),
      builder: (context, state) {
        final jobs = state.batch(widget.batchId);
        if (jobs.isEmpty) return const _Gone();

        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenSide,
            AppSpacing.screenTop,
            AppSpacing.screenSide,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackRow(onTap: _back),
              const SizedBox(height: AppSpacing.sm),
              Headline(_title(jobs), size: 28),
              const SizedBox(height: AppSpacing.inset),
              Expanded(
                child: jobs.length == 1
                    ? _Single(job: jobs.single, online: state.online)
                    : _Batch(jobs: jobs, online: state.online),
              ),
              _Actions(jobs: jobs, onBack: _back),
            ],
          ),
        );
      },
    );
  }

  static String _title(List<UploadJob> jobs) {
    if (jobs.length == 1) {
      return switch (jobs.single.outcome) {
        JobOutcome.working => 'Indexing',
        JobOutcome.ready => 'Ready',
        JobOutcome.partial => 'Mostly ready',
        JobOutcome.held => 'Kept, not readable',
        JobOutcome.failed => 'Couldn’t read it',
        JobOutcome.stopped => 'Upload stopped',
      };
    }
    final ready = jobs.where((j) => j.outcome == JobOutcome.ready).length;
    if (jobs.every((j) => j.isSettled)) {
      return ready == jobs.length ? 'Ready' : '$ready of ${jobs.length} ready';
    }
    final noun = jobs.every((j) => j.kind == CaptureKind.images)
        ? 'images'
        : 'files';
    return 'Indexing ${jobs.length} $noun';
  }
}

/// "‹ Library" — the way back, in words, because the page it goes to is the
/// thing the user is worried about.
class _BackRow extends StatelessWidget {
  const _BackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Back to Library',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: AppSize.headerButton,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(HawkIcons.chevronLeft, size: 20, color: p.textPrimary),
                const SizedBox(width: 6),
                Text(
                  'Library',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    letterSpacing: 0,
                    color: p.textPrimary,
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

class _Single extends StatelessWidget {
  const _Single({required this.job, required this.online});

  final UploadJob job;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final outcome = job.outcome;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FileProgressCard(
            icon: iconForMemoryType(job.memoryType),
            name: job.name,
            meta: '${megabytes(job.file.bytes)} · ${_typeLabel(job)}',
            // A finished file reads 100% however its stages were weighted:
            // "Ready" beside 96% would look like something was left behind.
            fraction:
                outcome == JobOutcome.ready || outcome == JobOutcome.partial
                ? 1
                : progressOf(job),
            failed:
                outcome == JobOutcome.stopped || outcome == JobOutcome.failed,
          ),
          const SizedBox(height: 10),
          StepList(steps: stepsOf(job, online: online)),
        ],
      ),
    );
  }

  /// `PDF`, `HEIC`, `M4A` — the extension says more than "Document".
  static String _typeLabel(UploadJob job) {
    final ext = p.extension(job.name).replaceFirst('.', '');
    return ext.isEmpty ? job.memoryType.label : ext.toUpperCase();
  }
}

class _Batch extends StatelessWidget {
  const _Batch({required this.jobs, required this.online});

  final List<UploadJob> jobs;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final center = context.read<UploadCenter>();
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.gap),
      itemBuilder: (context, i) {
        final job = jobs[i];
        final outcome = job.outcome;
        final canRetry =
            outcome == JobOutcome.stopped ||
            (outcome == JobOutcome.failed && (job.memory?.retryable ?? false));
        return BatchFileCard(
          icon: iconForMemoryType(job.memoryType),
          name: job.name,
          meta:
              '${megabytes(job.file.bytes)} · '
              '${stateWordOf(job, online: online)}',
          fraction: progressOf(job),
          outcome: outcome,
          onRetry: canRetry ? () => unawaited(center.retry(job.id)) : null,
        );
      },
    );
  }
}

/// The buttons at the foot of the screen — which ones depends on how it
/// ended, and there are never more than two.
class _Actions extends StatelessWidget {
  const _Actions({required this.jobs, required this.onBack});

  final List<UploadJob> jobs;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final center = context.read<UploadCenter>();
    final single = jobs.length == 1 ? jobs.single : null;
    final settled = jobs.every((j) => j.isSettled);
    final allReady = jobs.every((j) => j.outcome == JobOutcome.ready);

    PillButton button(String label, PillTone tone, VoidCallback onPressed) =>
        PillButton(
          label: label,
          tone: tone,
          height: AppSize.buttonSmall,
          onPressed: onPressed,
        );

    void ask() => context.go(HomePage.routePath);

    final buttons = <Widget>[
      if (!settled)
        button('Back to Library', PillTone.white, onBack)
      else if (allReady) ...[
        button('Ask about it', PillTone.primary, ask),
        button('Back to Library', PillTone.raised, onBack),
      ] else if (single != null)
        ...switch (single.outcome) {
          // E6: "Clear cause, two ways out."
          JobOutcome.stopped => [
            button('Try again', PillTone.white, () {
              unawaited(center.retry(single.id));
            }),
            button('Remove', PillTone.raised, () {
              unawaited(center.remove(single.id));
            }),
          ],
          JobOutcome.failed => [
            if (single.memory?.retryable ?? false)
              button('Try again', PillTone.white, () {
                unawaited(center.retry(single.id));
              })
            else
              button('Back to Library', PillTone.white, onBack),
            button('Remove', PillTone.raised, () {
              unawaited(center.remove(single.id));
            }),
          ],
          // E7: "The file is kept either way."
          _ => [
            button('Back to Library', PillTone.white, onBack),
            if (single.kind == CaptureKind.scan)
              button('Rescan the pages', PillTone.raised, () {
                unawaited(
                  UploadFlow.run(context, CaptureKind.scan, replace: true),
                );
              }),
          ],
        }
      else
        button('Back to Library', PillTone.white, onBack),
    ];

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.inset,
        bottom: AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            b,
          ],
          if (!settled) ...[
            const SizedBox(height: 10),
            Center(
              child: MetaText(
                'Indexing keeps going if you leave',
                color: p.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reached with a batch nobody is following — a stale link, or the app was
/// restarted under it. The Library has the rows.
class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppScreen(
      ambientOpacity: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Headline('Nothing uploading', size: 28),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Everything you added is in your Library.',
            style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
          ),
          const SizedBox(height: AppSpacing.card),
          PillButton(
            label: 'Back to Library',
            tone: PillTone.white,
            height: AppSize.buttonSmall,
            onPressed: () => context.popOrGo(LibraryPage.routeName),
          ),
        ],
      ),
    );
  }
}
