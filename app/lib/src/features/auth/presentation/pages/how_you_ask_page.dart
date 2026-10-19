import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_user.dart';
import '../bloc/onboarding_cubit.dart';
import '../bloc/session_cubit.dart';
import '../widgets/auth_header.dart';

/// Screen 1F — HOW YOU'LL ASK. Step 1 of 3.
///
/// **There is no name step any more.** v2 opened onboarding by asking what to
/// call you and offered the input preference underneath it as a secondary
/// question. v3 deletes the name field entirely: a social sign-in already
/// hands us a name, an email sign-in has an address to derive one from, and
/// nobody has ever been pleased to be asked their own name by software that
/// just read their Google profile.
///
/// What is left is the question that actually changes the product — the one
/// that decides whether home is an orb or a chat thread. Giving it a screen of
/// its own is what makes it read as a setting rather than as small print under
/// a text field.
class HowYouAskPage extends StatelessWidget {
  const HowYouAskPage({super.key});

  static const routeName = 'onboardingAsk';
  static const routePath = '/welcome/ask';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<OnboardingCubit>();

    final name = switch (context.watch<SessionCubit>().state) {
      AuthOnboarding(:final user) => user.displayName,
      AuthAuthenticated(:final user) => user.displayName,
      _ => '',
    };

    return BlocBuilder<OnboardingCubit, OnboardingState>(
      builder: (context, state) => AppScreen(
        ambientOpacity: 0,
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.exception != null) ...[
              Text(
                state.exception!.displayMessage,
                textAlign: TextAlign.center,
                style: AppTypography.footnote.copyWith(color: p.danger),
              ),
              const SizedBox(height: AppSpacing.group),
            ],
            PillButton(
              label: 'Continue',
              icon: HawkIcons.arrowRight,
              isBusy: state.isSubmitting,
              onPressed: state.isSubmitting ? null : cubit.submit,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthGreeting(name: name, step: const (1, 3)),
            const SizedBox(height: AppSpacing.blockWide),
            const Headline('How will you\nmostly ask?', size: 34),
            const SizedBox(height: AppSpacing.group),
            Text(
              'This sets what home opens to. Change it any time.',
              style: AppTypography.bodyMedium.copyWith(color: p.textTertiary),
            ),

            const SizedBox(height: AppSpacing.block),
            _PreferenceCard(
              icon: HawkIcons.mic,
              title: 'Speak',
              subtitle: 'Home is the orb. Hold, ask, let go.',
              selected: state.inputPreference == InputPreference.voice,
              onTap: () => cubit.preferenceChanged(InputPreference.voice),
            ),
            const SizedBox(height: AppSpacing.md - 2),
            _PreferenceCard(
              icon: HawkIcons.type,
              title: 'Type',
              subtitle: 'Home is a chat thread, keyboard first.',
              selected: state.inputPreference == InputPreference.typing,
              onTap: () => cubit.preferenceChanged(InputPreference.typing),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two choices.
///
/// The selected card goes **white** — the design's "this is the one that
/// matters" surface — rather than taking an accent border. Only its icon
/// bubble is accented, so the screen still spends its accent once.
class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final paper = AppPalette.onPaper;

    return Semantics(
      selected: selected,
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: HawkCard(
        tone: selected ? CardTone.paper : CardTone.dark,
        onTap: onTap,
        child: Row(
          children: [
            IconTile.round(
              icon: icon,
              size: AppSize.tileHero,
              background: selected ? p.accent : p.raised,
              foreground: selected ? p.onAccent : p.textPrimary,
              strokeWidth: 2,
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
                      color: selected ? paper.ink : p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: selected ? paper.muted : p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Ink dot with a white tick when chosen, empty ring when not —
            // the inverse of [CheckDot], because this one sits on paper.
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? paper.ink : Colors.transparent,
                shape: BoxShape.circle,
                border: selected ? null : Border.all(color: p.border, width: 2),
              ),
              alignment: Alignment.center,
              child: selected
                  ? AppIcon(HawkIcons.check, size: 13, color: paper.surface)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
