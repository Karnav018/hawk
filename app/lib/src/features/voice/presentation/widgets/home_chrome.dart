import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../../core/widgets/hawk_mark.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../bloc/vault_ready_cubit.dart';

/// The greeting row both home faces open with.
///
/// From the final block of `Hawk Logo v3.dc.html`, which supersedes 1N: the
/// **mark at 48px**, the name, the count, and one circle. The order is the
/// argument — the product introduces itself with its own mark rather than
/// with an avatar, because the mark is the orb at rest and the orb is the
/// thing you are about to hold.
///
/// **No circle any more.** Search lives in the Library tab, one tap away in
/// the nav, and the camera floats bottom-right as [CameraFab], where the
/// thumb already is.
///
/// v2 opened home with a gradient initials avatar that led to the account
/// screen. That put "you" at the top of a screen whose subject is the vault,
/// and it spent the one slot a header has on a destination the nav already
/// owns. v3's nav has a You tab; this row does not need to duplicate it.
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        // 48px, knocked out: white disc, accent highlight. The one place the
        // accent appears on the orb home besides the orb itself.
        const HawkMark(size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // First name only. "Hi, Sam Okonkwo" is a database greeting.
                'Hi, ${_first(name)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 2),
              BlocBuilder<VaultReadyCubit, int?>(
                builder: (context, ready) => MetaText(
                  // An em dash while the count is unknown, never a zero — a
                  // home screen that opens with "0 MEMORIES READY" tells a
                  // user with a full vault that their vault is empty.
                  // "1 memory", not "1 memories" — it was printing the
                  // plural for a vault of one, on the first screen a new
                  // user sees.
                  '${ready == null ? '—' : _grouped(ready)} '
                  '${ready == 1 ? 'memory' : 'memories'} ready',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _first(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

/// Home's floating camera: shoot a photo and index it, bottom-right.
///
/// Accent-filled and 56px — the floating-button size — because it is the
/// one thing on home that is pressed rather than read. It floats where the
/// thumb rests instead of in the header, which a one-handed grip cannot
/// reach without shifting the phone.
class CameraFab extends StatelessWidget {
  const CameraFab({required this.onPressed, this.isBusy = false, super.key});

  final VoidCallback? onPressed;

  /// A photo is being uploaded and indexed; the button waits.
  final bool isBusy;

  static const size = 56.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      label: isBusy ? 'Saving your photo' : 'Take a photo and index it',
      child: Material(
        color: p.accent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: isBusy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: p.onAccent,
                      ),
                    )
                  : AppIcon(
                      HawkIcons.camera,
                      size: 26,
                      color: p.onAccent,
                      strokeWidth: 2.1,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Speak / Type control under the greeting.
///
/// The same question screen 1F asked during onboarding, asked again in one
/// tap — which is the point. The preference decides what home *is*, and a
/// setting that important should not live three screens deep in the account
/// section. Switching here changes the screen immediately and does not write
/// to the account: this is "how I want to ask right now", and the stored
/// preference is still what home opens to next time.
class ModeTabs extends StatelessWidget {
  const ModeTabs({required this.mode, required this.onChanged, super.key});

  final InputPreference mode;
  final ValueChanged<InputPreference> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedTabs(
    labels: const ['Speak', 'Type'],
    selected: mode == InputPreference.voice ? 0 : 1,
    onChanged: (index) =>
        onChanged(index == 0 ? InputPreference.voice : InputPreference.typing),
  );
}

/// "1,516". Grouped, because the count is read as a quantity rather than as
/// an identifier and four bare digits are read as a code.
String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);
