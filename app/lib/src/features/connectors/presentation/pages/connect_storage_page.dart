import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../account/presentation/pages/profile_page.dart';
import '../../../auth/presentation/widgets/auth_header.dart';
import '../../domain/entities/storage_provider.dart';
import '../bloc/connect_storage_cubit.dart';
import 'permissions_page.dart';

/// Which run screen 1G is part of.
///
/// The screen is the same either way — the same sources, the same limits, the
/// same OAuth. Only the way out differs, and that difference is real enough to
/// be a parameter rather than two copies of the screen: during onboarding
/// there is a run to advance and a skip to offer, and afterwards there is only
/// a way back.
enum ConnectFlow { onboarding, manage }

/// Screen 1G — BRING YOUR OWN STORAGE. Step 2 of 3.
///
/// **Two sources, drawn as peers.** Google Drive is an OAuth grant; the phone
/// vault is the device the app is already running on. v2 filtered the phone
/// out of this screen entirely and offered it only as the greyed-out
/// implication of "Skip" — which made device-only look like a failure to set
/// up rather than a choice. Here they are two rows of the same size, and
/// skipping is the third thing below both.
class ConnectStoragePage extends StatelessWidget {
  const ConnectStoragePage({this.flow = ConnectFlow.onboarding, super.key});

  final ConnectFlow flow;

  static const routeName = 'connectStorage';
  static const routePath = '/welcome/storage';

  /// The same screen, reached from the profile's Vault once onboarding is
  /// over. No longer reachable from a nav bar — v3 took storage out of it.
  static const manageRouteName = 'storageAccounts';
  static const manageRoutePath = '/storage';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<ConnectStorageCubit>();
    final onboarding = flow == ConnectFlow.onboarding;

    return BlocConsumer<ConnectStorageCubit, ConnectStorageState>(
      listenWhen: (a, b) =>
          a.justConnected != b.justConnected || a.exception != b.exception,
      listener: (context, state) {
        final error = state.exception;
        if (error != null) {
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Could not connect',
              mark: SnackMark.failure,
              subtitle: error.displayMessage,
            ),
          );
          cubit.dismissError();
        }

        // A fresh connection goes straight to 1H. A *re*connection does not:
        // the scope it had is the scope it still has, and asking again would
        // imply something changed.
        final connected = state.justConnected;
        if (connected != null) {
          cubit.acknowledgeConnection();
          context.pushNamed(PermissionsPage.routeName, extra: connected);
        }
      },
      builder: (context, state) {
        final catalog = state.catalog;
        final drive = catalog?.options
            .where((o) => o.provider == StorageProvider.googleDrive)
            .firstOrNull;
        final device = catalog?.options
            .where((o) => o.provider == StorageProvider.internal)
            .firstOrNull;

        return AppScreen(
          ambientOpacity: 0,
          footer: onboarding
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InfoNote(
                      'Hawk never deletes anything without your confirmation.',
                      icon: HawkIcons.shieldCheck,
                      iconColor: p.accent,
                      tone: CardTone.dark,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Skipping is a real choice, not a deferral — so it is a
                    // plain labelled action, and it says where the thing it
                    // skips can be found later.
                    GestureDetector(
                      onTap: state.isBusy ? null : cubit.finish,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          'Skip — add later from your profile',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: p.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : PillButton(
                  label: 'Done',
                  tone: PillTone.secondary,
                  // Reached by a push from the Vault, but also by a `go` when
                  // a deep link lands here — so "done" has to mean the
                  // profile when there is no stack to unwind.
                  onPressed: () => context.popOrGo(ProfilePage.routeName),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AuthHeader(
                // Nothing sits behind 1G during onboarding; afterwards the
                // profile does.
                canGoBack: !onboarding,
                fallbackRoute: onboarding ? null : '/profile',
                step: onboarding ? const (2, 3) : null,
              ),
              const SizedBox(height: AppSpacing.blockWide),
              Headline(
                onboarding ? 'Bring your\nown storage' : 'Connected\nstorage',
                size: 34,
              ),
              const SizedBox(height: AppSpacing.group),
              Text(
                onboarding
                    ? 'Originals stay where they live. Hawk reads them once '
                          'and keeps only the index.'
                    : 'Disconnecting keeps everything already indexed — '
                          'reconnect and it picks up where it left off.',
                style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
              ),

              const SizedBox(height: AppSpacing.block),

              if (state.isLoading)
                const _SourcesPlaceholder()
              else ...[
                _SourceCard(
                  icon: HawkIcons.googleDrive,
                  title: 'Google Drive',
                  subtitle: drive?.isConfigured == false
                      ? 'Not available in this build.'
                      : 'Read-only, stays in sync, never expires.',
                  connected: drive?.account != null,
                  isBusy: state.connecting == StorageProvider.googleDrive,
                  enabled: drive?.isConfigured ?? false,
                  onTap: () => cubit.connect(StorageProvider.googleDrive),
                ),
                const SizedBox(height: AppSpacing.md - 2),
                _SourceCard(
                  icon: HawkIcons.phoneVault,
                  title: 'Phone vault',
                  subtitle: 'Pick files here and index them on device.',
                  connected: device?.account != null,
                  isBusy: state.connecting == StorageProvider.internal,
                  onTap: cubit.connectDevice,
                ),
              ],

              if (onboarding) ...[
                const SizedBox(height: AppSpacing.block),
                PillButton(
                  label: 'Continue',
                  icon: HawkIcons.arrowRight,
                  isBusy: state.isFinishing,
                  onPressed: state.hasAnyConnection && !state.isBusy
                      ? cubit.finish
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One source. A card, not a row: these are the only two things on the screen
/// and the design gives them the full 28px treatment rather than the 22px list
/// shape it uses where there are many.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.connected,
    required this.onTap,
    this.isBusy = false,
    this.enabled = true,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool connected;
  final VoidCallback onTap;
  final bool isBusy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      enabled: enabled && !connected,
      label: '$title. $subtitle${connected ? '. Connected' : ''}',
      excludeSemantics: true,
      child: HawkCard(
        tone: enabled ? CardTone.dark : CardTone.dim,
        onTap: enabled && !isBusy && !connected ? onTap : null,
        child: Row(
          children: [
            IconTile.round(
              icon: icon,
              size: AppSize.tileHero,
              foreground: enabled ? p.textPrimary : p.textFaint,
              strokeWidth: 1.7,
            ),
            const SizedBox(width: AppSpacing.group),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.display18.copyWith(
                      color: enabled ? p.textPrimary : p.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (isBusy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              )
            // A connected source shows the design's live dot rather than a
            // chevron: there is nothing further in, and a chevron that leads
            // nowhere is the most common small lie in a settings screen.
            else if (connected)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              AppIcon(
                HawkIcons.chevronRight,
                size: 18,
                color: enabled ? p.textFaint : p.border,
              ),
          ],
        ),
      ),
    );
  }
}

class _SourcesPlaceholder extends StatelessWidget {
  const _SourcesPlaceholder();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md - 2),
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: p.cardDim,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        ],
      ],
    );
  }
}
