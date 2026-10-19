import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';

/// The v3 screen header: a circular back button on the left, and whatever the
/// screen wants on the right.
///
/// v2 centred a tracked-caps label between two buttons — a title bar. v3 has
/// no titles at this level: the headline three lines below *is* the title, and
/// repeating it in 10px caps above itself was the clearest thing v2 did that
/// v3 removed. What sits on the right instead is progress ("STEP 2 OF 3"),
/// which is the only thing a header here has to say that the headline cannot.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    @Deprecated('v3 headers carry no title; the headline below is the title.')
    this.label,
    this.onBack,
    this.fallbackRoute,
    this.canGoBack = true,
    this.step,
    this.trailing,
    super.key,
  });

  /// Ignored. Kept so screens awaiting their lane still compile.
  @Deprecated('v3 headers carry no title.')
  final String? label;

  final VoidCallback? onBack;

  /// Where to go when there is nothing on the stack to pop.
  ///
  /// A screen reached by a guard redirect, a deep link, or a `go` rather than
  /// a `push` has an empty back stack — and a back button that silently does
  /// nothing is worse than no back button at all.
  final String? fallbackRoute;

  /// False where the account already exists and there is nothing behind the
  /// screen. Nothing is drawn in the slot; the row simply starts empty.
  final bool canGoBack;

  /// `(1, 3)` renders "STEP 1 OF 3".
  final (int, int)? step;

  /// Anything else for the right-hand slot. Ignored when [step] is set.
  final Widget? trailing;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else if (fallbackRoute != null) {
      context.goNamed(fallbackRoute!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (canGoBack)
          CircleButton(
            icon: HawkIcons.chevronLeft,
            semanticLabel: 'Back',
            onPressed: onBack ?? () => _back(context),
          ),
        const Spacer(),
        if (step != null)
          MetaText('Step ${step!.$1} of ${step!.$2}')
        else
          ?trailing,
      ],
    );
  }
}

/// A greeting header — the mark, a name, and the step.
///
/// Screen 1F only. It is the first screen after an account exists, and the
/// design uses that one moment to say the name back: an avatar, "Hi Sam", and
/// the step marker. Every screen after it drops the greeting.
class AuthGreeting extends StatelessWidget {
  const AuthGreeting({required this.name, this.step, super.key});

  final String name;
  final (int, int)? step;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        Container(
          width: AppSize.headerButton,
          height: AppSize.headerButton,
          decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            initialsOf(name),
            style: AppTypography.titleSmall.copyWith(
              color: p.onAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'Hi $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleLarge.copyWith(color: p.textPrimary),
          ),
        ),
        if (step != null) ...[
          const SizedBox(width: AppSpacing.md),
          MetaText('Step ${step!.$1} of ${step!.$2}'),
        ],
      ],
    );
  }
}

/// Two letters, upper case.
///
/// Falls back to the first character so an avatar is never blank — an empty
/// circle looks like a failed image rather than like a person with a short
/// name.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '—';
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// A two-line headline.
///
/// v2 set the second line in italic serif; v3 has neither, so this is now one
/// heavy Archivo block with a line break in it. Kept as a name because the
/// screens awaiting their lane still ask for it — a ported screen uses
/// [Headline] with a `\n` and says what size it wants.
class AuthHeadline extends StatelessWidget {
  const AuthHeadline({
    required this.first,
    required this.second,
    this.fontSize = 34,
    super.key,
  });

  final String first;
  final String second;
  final double fontSize;

  @override
  Widget build(BuildContext context) =>
      Headline('$first\n$second', size: fontSize);
}
