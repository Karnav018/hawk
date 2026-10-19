import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../bloc/email_sign_in_cubit.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_header.dart';
import 'sign_in_page.dart';
import 'verify_code_page.dart';

/// Screen 1D — EMAIL.
///
/// The field and its button sit together directly under the lead, rather than
/// under a "EMAIL ADDRESS" caps label. v3 drops those labels everywhere: a
/// single field on a screen headed "What's your email?" does not need naming
/// twice, and the label was the only thing between the question and the answer.
class EmailAddressPage extends StatefulWidget {
  const EmailAddressPage({super.key});

  static const routeName = 'signInEmail';
  static const routePath = '/sign-in/email';

  @override
  State<EmailAddressPage> createState() => _EmailAddressPageState();
}

class _EmailAddressPageState extends State<EmailAddressPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<EmailSignInCubit>().state.email,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<EmailSignInCubit>();

    return AppScreen(
      ambientOpacity: 0,
      child: BlocConsumer<EmailSignInCubit, EmailSignInState>(
        // Navigation belongs to the screen, not the cubit: the cubit reports
        // that a code is in flight, and the screen decides that means moving
        // on. Keeping it here is what lets the cubit be tested without a
        // navigator.
        listenWhen: (previous, current) =>
            !previous.codeSent && current.codeSent,
        listener: (context, state) =>
            context.pushNamed(VerifyCodePage.routeName),
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuthHeader(fallbackRoute: SignInPage.routeName),
            const SizedBox(height: AppSpacing.block),
            const Headline("What's your email?", size: 32),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Six-digit code, no password to forget.',
              style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
            ),

            const SizedBox(height: AppSpacing.block),
            VaultTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.go,
              autofillHints: const [AutofillHints.email],
              hasError: state.emailError != null,
              onChanged: cubit.emailChanged,
              onBlur: cubit.emailBlurred,
              onSubmitted: (_) => cubit.sendCode(),
            ),
            FieldNote(
              error: state.emailError,
              suggestion: state.emailSuggestion,
              onAccept: () {
                cubit.acceptEmailSuggestion();
                _controller.text = context.read<EmailSignInCubit>().state.email;
              },
            ),

            if (state.exception != null) ...[
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.cardWide),
                child: Text(
                  state.exception!.displayMessage,
                  style: AppTypography.footnote.copyWith(color: p.danger),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md - 2),
            PillButton(
              label: 'Send code',
              icon: HawkIcons.arrowRight,
              isBusy: state.isSending,
              onPressed: state.canSend ? cubit.sendCode : null,
              height: AppSize.buttonMedium,
            ),
          ],
        ),
      ),
    );
  }
}
