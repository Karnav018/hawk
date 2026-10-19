import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/config/legal_links.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/hawk_mark.dart';
import '../../domain/entities/auth_user.dart';
import '../bloc/sign_in_cubit.dart';
import '../widgets/auth_provider_button.dart';
import 'email_address_page.dart';

/// Screen 1B — SIGN IN.
///
/// **Two ways in, not three.** v2 offered Apple, Google and email; v3 draws
/// Google and email and nothing else. That is a product decision the design
/// makes rather than a layout one, so the Apple button is gone from the
/// screen — the repository still knows how to do it, which costs nothing and
/// means bringing it back is a button rather than a feature.
///
/// The headline leads with what the product does ("Everything you keep,
/// askable") instead of what it is called. The mark above it is 44px and
/// unaccompanied: the wordmark would be the third time the screen says Hawk,
/// after the app icon the user just tapped and the name on the home screen.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  static const routeName = 'signIn';
  static const routePath = '/sign-in';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.watch<SignInCubit>();
    final state = cubit.state;
    final busy = state is SignInSubmitting;

    return AppScreen(
      ambientOpacity: 0,
      footer: const _Footer(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: HawkMark(size: 50),
          ),
          const SizedBox(height: AppSpacing.block + AppSpacing.xs),

          const Headline('Everything you\nkeep, askable.', size: 38),
          const SizedBox(height: AppSpacing.inset),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Text(
              'Save files, photos, recordings and links. Ask for them later '
              'in your own words.',
              style: AppTypography.bodyLarge.copyWith(color: p.textTertiary),
            ),
          ),

          const SizedBox(height: 32),

          // Google is the accented action — the one primary thing on the
          // screen. Email is the same size in a card fill, because it is an
          // equal way in and not a fallback.
          if (cubit.isAvailable(SocialProvider.google))
            AuthProviderButton(
              label: 'Continue with Google',
              icon: HawkIcons.google,
              variant: AuthButtonVariant.primary,
              isBusy:
                  state is SignInSubmitting &&
                  state.provider == SocialProvider.google,
              // Dimmed rather than hidden when this build has no client id: a
              // missing button reads as a design decision, and a release
              // built without credentials would ship that way unnoticed.
              isUnavailable: !cubit.isConfigured(SocialProvider.google),
              onPressed: busy
                  ? null
                  : () => cubit.signInWith(SocialProvider.google),
            ),
          const SizedBox(height: AppSpacing.md - 2),
          AuthProviderButton(
            label: 'Continue with email',
            icon: HawkIcons.mail,
            variant: AuthButtonVariant.secondary,
            onPressed: busy
                ? null
                // push, not go: `go` replaces the location, which leaves
                // nothing on the stack for the back button to pop.
                : () => context.pushNamed(EmailAddressPage.routeName),
          ),

          if (state is SignInFailure) ...[
            const SizedBox(height: AppSpacing.card),
            Text(
              state.exception.displayMessage,
              textAlign: TextAlign.center,
              style: AppTypography.footnote.copyWith(color: p.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// The design's `margin-top:auto` block: a reassurance, then the legal line.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A card, not an accent wash. v2 tinted this strip and set it in
        // tracked caps, which made a promise about privacy look like a
        // marketing banner. v3 says it once, in a sentence, in the same card
        // as everything else — the shield is the only accented thing in it.
        InfoNote(
          // The policy's own promises, not the design's "Indexed on your
          // device", which Hawk does not do — and this note sits directly
          // above the link to the policy that says so.
          'Drive files stay in your Drive. No ads, no selling, and you can '
          'delete it all.',
          icon: HawkIcons.shieldCheck,
          iconColor: p.accent,
          tone: CardTone.dark,
        ),
        const SizedBox(height: AppSpacing.group),
        // The two names are links. Both stores expect the privacy policy
        // to be reachable from sign-in, and a consent line naming documents
        // nobody can open is asking for agreement to text unseen.
        const _ConsentLine(),
      ],
    );
  }
}

/// "By continuing you accept the Terms and Privacy Policy." — with both
/// documents one tap away, on the landing site.
class _ConsentLine extends StatefulWidget {
  const _ConsentLine();

  @override
  State<_ConsentLine> createState() => _ConsentLineState();
}

class _ConsentLineState extends State<_ConsentLine> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => unawaited(LegalLinks.open(LegalLinks.terms));
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => unawaited(LegalLinks.open(LegalLinks.privacy));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = AppTypography.footnote.copyWith(color: p.textFaint);
    final link = base.copyWith(
      color: p.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: p.textSecondary,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By continuing you accept the '),
          TextSpan(text: 'Terms', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
