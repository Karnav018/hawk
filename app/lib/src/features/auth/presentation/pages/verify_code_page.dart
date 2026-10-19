import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../bloc/email_sign_in_cubit.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_header.dart';
import 'email_address_page.dart';

/// Screen 1E — VERIFY.
///
/// The address is on the lead line with **Change** beside it, rather than
/// behind the back button. Somebody who mistyped their address is looking at
/// it right now, and the fix should be where their eyes already are.
class VerifyCodePage extends StatelessWidget {
  const VerifyCodePage({super.key});

  static const routeName = 'signInVerify';
  static const routePath = '/sign-in/verify';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<EmailSignInCubit>();

    return AppScreen(
      ambientOpacity: 0,
      child: BlocBuilder<EmailSignInCubit, EmailSignInState>(
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuthHeader(fallbackRoute: EmailAddressPage.routeName),
            const SizedBox(height: AppSpacing.block),
            const Headline('Check your inbox', size: 32),
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
                children: [
                  TextSpan(text: 'Sent to ${state.email} · '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        'Change',
                        style: AppTypography.bodyMedium.copyWith(
                          color: p.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.blockWide),
            CodeField(
              length: EmailSignInCubit.codeLength,
              value: state.code,
              hasError: state.exception != null,
              onChanged: cubit.codeChanged,
              // Submit on the sixth digit. Making someone reach for a button
              // after typing a code they already know is pure friction.
              onCompleted: (_) => cubit.verify(),
            ),

            const SizedBox(height: AppSpacing.inset),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (state.isVerifying)
                  Row(
                    children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(p.accent),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const MetaText('Checking'),
                    ],
                  )
                else
                  GestureDetector(
                    onTap: state.canResend ? cubit.sendCode : null,
                    behavior: HitTestBehavior.opaque,
                    child: MetaText(
                      'Resend code',
                      color: state.canResend ? p.textSecondary : p.textMuted,
                    ),
                  ),
                // The countdown is white against the muted label beside it:
                // it is the only thing on the row that is changing, and the
                // design uses brightness rather than colour to say so.
                if (state.resendIn > 0)
                  Text(
                    _mmss(state.resendIn),
                    style: AppTypography.meta10.copyWith(color: p.textPrimary),
                  ),
              ],
            ),

            if (state.exception != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                state.exception!.displayMessage,
                style: AppTypography.footnote.copyWith(color: p.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
