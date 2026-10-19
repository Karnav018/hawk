import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_icons_connectors.dart';
import '../../domain/entities/storage_account.dart';
import '../../domain/entities/storage_provider.dart';

/// One 68px provider row on screen 3F.
class ConnectorRow extends StatelessWidget {
  const ConnectorRow({
    required this.option,
    required this.onConnect,
    this.onDisconnect,
    this.isBusy = false,
    this.showDivider = true,
    this.subtitleOverride,
    this.actionOverride,
    super.key,
  });

  final ConnectorOption option;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;
  final bool isBusy;
  final bool showDivider;

  /// Replaces the derived status line.
  ///
  /// For the device row, which is a runtime *permission* rather than an OAuth
  /// connection — "NOT CONNECTED" is meaningless for storage already in your
  /// hand, so it states what it covers instead.
  final String? subtitleOverride;

  /// Replaces the derived action label ("Allow", not "Connect").
  final String? actionOverride;

  static String iconFor(StorageProvider provider) => switch (provider) {
    StorageProvider.googleDrive => ConnectorIcons.googleDrive,
    StorageProvider.internal => ConnectorIcons.device,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final account = option.account;
    final connected = option.isConnected;

    // A provider this build has no credentials for is dimmed with a reason
    // rather than hidden — same rule the sign-in screen follows. Hiding it
    // would make a misconfigured release look like a product decision.
    final enabled = option.isConfigured && !isBusy;
    final needsAttention = account?.state.needsAttention ?? false;

    final subtitle = switch (option) {
      _ when subtitleOverride != null => subtitleOverride!,
      _ when !option.isConfigured => 'NOT AVAILABLE IN THIS BUILD',
      _ when account != null => account.statusLine,
      _ => 'NOT CONNECTED',
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: '${option.provider.label}, $subtitle',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: p.hairline))
              : null,
        ),
        child: Opacity(
          opacity: option.isConfigured ? 1 : 0.45,
          child: SizedBox(
            height: 68,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.panel),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: p.hairlineStrong),
                    ),
                    child: Center(
                      child: AppIcon(
                        iconFor(option.provider),
                        size: 17,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.provider.label,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.22,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.numeralSmall.copyWith(
                            color: needsAttention ? p.caution : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Action(
                    // A revoked account offers "Reconnect", not "Connected" —
                    // the index survives revocation, so this is the one tap
                    // that brings it all back.
                    label: switch (account?.state) {
                      _ when actionOverride != null => actionOverride!,
                      ConnectorState.revoked => 'Reconnect',
                      ConnectorState.error => 'Retry',
                      _ when connected => 'Connected',
                      _ => 'Connect',
                    },
                    filled: !connected && option.isConfigured,
                    isBusy: isBusy,
                    onPressed: !enabled
                        ? null
                        : connected
                        ? onDisconnect
                        : onConnect,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.filled,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? p.textPrimary : p.panelSubtle,
          borderRadius: BorderRadius.circular(AppRadius.iconButton),
          border: filled ? null : Border.all(color: p.hairlineStrong),
        ),
        child: isBusy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: filled ? p.ground : p.textPrimary,
                ),
              )
            : Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: filled ? p.ground : p.textPrimary,
                ),
              ),
      ),
    );
  }
}
