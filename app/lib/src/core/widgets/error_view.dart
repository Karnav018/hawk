import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../error/app_exception.dart';

/// Renders an [AppException] with a retry affordance when one would help.
///
/// The icon is chosen from the exception case, so the user sees *why* it
/// failed before reading the message — offline and "server is down" call for
/// different reactions.
class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.exception,
    this.onRetry,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final AppException exception;
  final VoidCallback? onRetry;

  /// A way forward that is not a retry.
  ///
  /// Some failures are not retryable *and* not dead ends — a spent daily
  /// allowance is the clearest case: retrying cannot help, but seeing the
  /// plans can. Shown whether or not the exception is retryable, because the
  /// two affordances answer different questions.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.block),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (exception) {
                NetworkException() => Icons.wifi_off_rounded,
                TimeoutException() => Icons.timer_off_rounded,
                UnauthorizedException() => Icons.lock_outline_rounded,
                NotFoundException() => Icons.search_off_rounded,
                _ => Icons.error_outline_rounded,
              },
              size: 40,
              color: p.textTertiary,
            ),
            const SizedBox(height: AppSpacing.panel),
            Text(
              exception.displayMessage,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(color: p.textSecondary),
            ),
            if (exception.isRetryable && onRetry != null) ...[
              const SizedBox(height: AppSpacing.block),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(
                height: exception.isRetryable && onRetry != null
                    ? AppSpacing.sm
                    : AppSpacing.block,
              ),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
