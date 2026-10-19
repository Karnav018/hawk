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
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../bloc/permissions_cubit.dart';
import 'choose_folders_page.dart';
import 'connect_storage_page.dart';

/// Screen 1H — DRIVE PERMISSION.
///
/// **A sheet, not a page.** v2 made this a full screen in the onboarding run,
/// which put our permission question on the same footing as Google's own
/// consent screen that follows it. v3 draws it as a sheet over the dimmed
/// storage screen: it is a question *about* the thing behind it, and the
/// thing behind it stays visible so the user can see what they are answering
/// for.
///
/// The two rows are the two scope levels, and only one of them is a choice.
/// Read is stated as required and has no control beside it; manage is a
/// toggle that starts off. A screen where the mandatory permission also has
/// a switch teaches people that switches here do not mean anything.
class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  static const routeName = 'permissions';
  static const routePath = '/welcome/permissions';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PermissionsCubit>();

    return BlocConsumer<PermissionsCubit, PermissionsState>(
      listenWhen: (a, b) =>
          a.exception != b.exception || a.needsReconnect != b.needsReconnect,
      listener: (context, state) {
        final error = state.exception;
        if (error != null) {
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Permissions unchanged',
              mark: SnackMark.failure,
              subtitle: error.displayMessage,
            ),
          );
          cubit.dismissError();
        }
        if (state.needsReconnect) {
          getIt<SnackController>().show(
            const Snack.detail(
              title: 'Manage access removed',
              subtitle: 'Reconnect to keep indexing this account.',
            ),
          );
        }
      },
      builder: (context, state) {
        final account = state.account;

        return SheetScaffold(
          headline: 'Hawk wants access\nto your Drive files',
          children: [
            _PermissionRow(
              icon: HawkIcons.eye,
              title: 'See and download files',
              detail: 'Required to build the index.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _PermissionRow(
              icon: HawkIcons.trash,
              title: 'Move files to trash',
              detail: 'Optional, only for cleanups you confirm.',
              dimIcon: true,
              trailing: _PaperSwitch(
                value: state.canManage,
                onChanged: state.isSubmitting ? null : cubit.setManage,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    // Cancelling a permission sheet returns to the source
                    // list it was asked from, whether or not that screen is
                    // still on the stack.
                    onPressed: () =>
                        context.popOrGo(ConnectStoragePage.routeName),
                  ),
                ),
                const SizedBox(width: AppSpacing.md - 2),
                // Wider than Cancel, in the design's own 1 : 1.4 ratio. The
                // affirmative is the expected answer and is sized to say so,
                // without Cancel becoming a link somebody has to hunt for.
                Expanded(
                  flex: 14,
                  child: _SheetButton(
                    label: 'Allow',
                    isPrimary: true,
                    isBusy: state.isSubmitting,
                    onPressed: () => context.pushNamed(
                      ChooseFoldersPage.routeName,
                      pathParameters: {'accountId': account.id},
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One permission, as an inset chip on the sheet's paper.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.trailing,
    this.dimIcon = false,
  });

  final String icon;
  final String title;
  final String detail;
  final Widget? trailing;

  /// The optional permission's icon is drawn in the muted ink, so the
  /// required one reads as the one that matters.
  final bool dimIcon;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.inset),
      decoration: BoxDecoration(
        color: paper.chip,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Row(
        crossAxisAlignment: trailing == null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: trailing == null ? 2 : 0),
            child: AppIcon(
              icon,
              size: 19,
              color: dimIcon ? paper.muted : paper.ink,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(color: paper.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppTypography.footnote.copyWith(color: paper.muted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The design's own switch, drawn rather than themed.
///
/// `Switch` cannot be made to look like this — its track and thumb sizes are
/// fixed ratios and its Material states paint a hover halo the design has no
/// vocabulary for.
class _PaperSwitch extends StatelessWidget {
  const _PaperSwitch({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;

    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? paper.ink : paper.handle,
            borderRadius: BorderRadius.circular(AppRadius.round),
          ),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: paper.surface,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A 54px button on paper. Ink for the affirmative, chip grey for the way out.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final paper = AppPalette.onPaper;
    final foreground = isPrimary ? paper.surface : paper.ink;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: isPrimary ? paper.ink : paper.chip,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          child: SizedBox(
            height: AppSize.buttonSmall,
            child: Center(
              child: isBusy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(foreground),
                      ),
                    )
                  : Text(
                      label,
                      style: AppTypography.titleMedium.copyWith(
                        color: foreground,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
