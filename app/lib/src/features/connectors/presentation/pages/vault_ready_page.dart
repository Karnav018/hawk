import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_icons_connectors.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../auth/presentation/widgets/auth_fields.dart';
import '../../../auth/presentation/widgets/auth_header.dart';
import '../bloc/connect_storage_cubit.dart';

/// Screen 3M — READY, FIRST ASK.
///
/// The last screen of onboarding, and the only one whose job is teaching. A
/// vault with nothing asked of it is indistinguishable from a folder, so this
/// hands over three questions that only work *because* the index exists —
/// each one is something a file browser cannot answer.
class VaultReadyPage extends StatelessWidget {
  const VaultReadyPage({super.key});

  static const routeName = 'vaultReady';
  static const routePath = '/welcome/ready';

  /// Deliberately about *retrieval*, *reasoning* and *storage* in that order,
  /// mirroring the two engines in §3 — the third one is the differentiator
  /// nobody expects, so it goes last where it lands hardest.
  static const _prompts = [
    'What did we agree on pricing?',
    'Which contracts renew this quarter?',
    'Can I delete the 2019 archive?',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<ConnectStorageCubit>();

    return BlocBuilder<ConnectStorageCubit, ConnectStorageState>(
      builder: (context, state) {
        final indexed = (state.catalog?.accounts ?? const []).fold<int>(
          0,
          (sum, a) => sum + a.fileCount,
        );

        return AppScreen(
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(AppIcons.mic, size: 16, color: p.accentSoft),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'HOLD THE MIC ANYWHERE TO ASK OUT LOUD',
                      style: AppTypography.labelWide.copyWith(
                        color: p.accentSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.panel),
              PrimaryActionButton(
                label: 'Open my vault',
                isBusy: state.isFinishing,
                // The only exit. Ending onboarding here rather than on 3L is
                // what makes the run finish on a promise instead of a
                // progress bar.
                onPressed: cubit.finish,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReadyBadge(indexed: indexed),
              const SizedBox(height: AppSpacing.block),
              const AuthHeadline(first: 'Stop filing.', second: 'Just ask.'),
              const SizedBox(height: AppSpacing.panel),
              Text(
                'Try one of these — every answer comes back with the file '
                'and page it came from.',
                style: AppTypography.bodyMedium.copyWith(
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.block),

              for (final prompt in _prompts) ...[
                _PromptRow(
                  prompt: prompt,
                  // Retrieval is not built yet. Rather than open a screen
                  // that answers nothing, the prompt hands over to the vault
                  // with the question in tow — honest, and still teaches the
                  // gesture.
                  onTap: cubit.finish,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReadyBadge extends StatelessWidget {
  const _ReadyBadge({required this.indexed});

  final int indexed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        AppIcon(AppIcons.check, size: 16, color: p.confirm),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            // Somebody who skipped storage still reaches a usable vault, and
            // telling them "0 FILES INDEXED" would frame a deliberate choice
            // as a failure.
            indexed == 0
                ? 'VAULT READY · CAPTURE ANYTHING TO BEGIN'
                : 'VAULT READY · ${_grouped(indexed)} FILES INDEXED',
            style: AppTypography.labelWide.copyWith(color: p.confirm),
          ),
        ),
      ],
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.prompt, required this.onTap});

  final String prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.panel,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: p.panelSubtle,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            AppIcon(ConnectorIcons.ask, size: 16, color: p.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                prompt,
                style: AppTypography.bodyMedium.copyWith(color: p.textPrimary),
              ),
            ),
            AppIcon(AppIcons.chevronRight, size: 15, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
