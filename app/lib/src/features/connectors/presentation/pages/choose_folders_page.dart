import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../auth/presentation/widgets/auth_header.dart';
import '../../domain/entities/provider_folder.dart';
import '../bloc/folder_selection_cubit.dart';
import 'index_progress_page.dart';

/// Screen 1I — WHAT SHOULD WE INDEX? Step 3 of 3.
///
/// Each row is a **bucket with a count**: a name, how many files are in it,
/// and how much they weigh. For Drive those buckets are folders, which is
/// what the provider actually has — `list_provider_folders` already returns
/// `fileCount` and `bytes` per folder, which is exactly the row this screen
/// draws, so the design's shape needed no new API to satisfy.
///
/// The running total above the button is the point of the screen. Picking
/// "Camera roll" on a phone is a 92 GB decision, and a picker that only says
/// which boxes are ticked makes that discoverable at the end of the index
/// rather than before it starts.
class ChooseFoldersPage extends StatefulWidget {
  const ChooseFoldersPage({super.key});

  static const routeName = 'chooseFolders';
  static const routePath = '/welcome/folders/:accountId';

  @override
  State<ChooseFoldersPage> createState() => _ChooseFoldersPageState();
}

class _ChooseFoldersPageState extends State<ChooseFoldersPage> {
  @override
  void initState() {
    super.initState();
    context.read<FolderSelectionCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<FolderSelectionCubit>();

    return BlocConsumer<FolderSelectionCubit, FolderSelectionState>(
      listenWhen: (a, b) => a.jobId != b.jobId || a.exception != b.exception,
      listener: (context, state) {
        final error = state.exception;
        if (error != null && state.folders.isNotEmpty) {
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Could not start indexing',
              mark: SnackMark.failure,
              subtitle: error.displayMessage,
            ),
          );
        }
        final jobId = state.jobId;
        if (jobId != null) {
          // Replaces rather than pushes: once indexing has started there is
          // nothing to come back to here, and a Back tap that re-offered the
          // picker would imply the job could be un-started.
          context.pushReplacementNamed(
            IndexProgressPage.routeName,
            pathParameters: {'jobId': jobId},
          );
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const AppScreen(
            ambientOpacity: 0,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.exception != null && state.folders.isEmpty) {
          return AppScreen(
            ambientOpacity: 0,
            child: ErrorView(exception: state.exception!, onRetry: cubit.load),
          );
        }

        return AppScreen(
          ambientOpacity: 0,
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SelectedTotal(
                files: state.selectedFiles,
                bytes: state.selectedBytes,
              ),
              const SizedBox(height: AppSpacing.md),
              PillButton(
                label: 'Start indexing',
                icon: HawkIcons.arrowRight,
                isBusy: state.isStarting,
                onPressed: state.canStart ? cubit.start : null,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AuthHeader(fallbackRoute: '/welcome/storage', step: (3, 3)),
              const SizedBox(height: AppSpacing.blockWide),
              const Headline('What should\nwe index?', size: 34),
              const SizedBox(height: AppSpacing.group),
              Text(
                'Add more later. Everything else stays untouched.',
                style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: AppSpacing.cardWide),

              if (state.folders.isEmpty)
                Text(
                  'Nothing to index in this account yet.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: p.textTertiary,
                  ),
                )
              else
                for (var i = 0; i < state.folders.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.gap),
                  _BucketRow(
                    folder: state.folders[i],
                    selected: state.selected.contains(state.folders[i].id),
                    onTap: () => cubit.toggle(state.folders[i].id),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

/// One bucket: tick, name, and what picking it costs.
class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  final ProviderFolder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      checked: selected,
      button: true,
      label:
          '${folder.name}. ${_grouped(folder.fileCount)} files, '
          '${formatBytes(folder.bytes)}',
      excludeSemantics: true,
      child: HawkCard(
        // Chosen rows sit on [card]; unchosen ones a step down. The design
        // says "selected" with the surface rather than with a border, so a
        // long list reads as a filled-in form rather than as a grid of boxes.
        tone: selected ? CardTone.dark : CardTone.dim,
        radius: AppRadius.row,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.inset,
        ),
        onTap: onTap,
        child: Row(
          children: [
            CheckDot(selected: selected),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      color: selected ? p.textPrimary : p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  MetaText(
                    '${_grouped(folder.fileCount)} files · '
                    '${formatBytes(folder.bytes)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the current selection costs, directly above the button that commits
/// to it.
class _SelectedTotal extends StatelessWidget {
  const _SelectedTotal({required this.files, required this.bytes});

  final int files;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const MetaText('Selected', size: 10),
        Text(
          files == 0
              ? 'NOTHING YET'
              : '${_grouped(files)} FILES · ${formatBytes(bytes)}',
          style: AppTypography.meta10.copyWith(
            color: files == 0 ? p.textMuted : p.textPrimary,
          ),
        ),
      ],
    );
  }
}

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Sizes are shown to one decimal only while that decimal carries meaning —
/// "8.2 GB" is useful, "148.0 GB" is noise.
String formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) {
    final value = bytes / gib;
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} GB';
  }
  final value = bytes / mib;
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} MB';
}
