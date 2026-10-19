import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'app_icons.dart';

/// Ask the home screen to start listening the moment it is built.
///
/// Travels as go_router `extra` so that tapping the microphone from the
/// library or the answer screen does what the icon says — starts dictation —
/// rather than depositing the user on the home screen to tap it a second
/// time. The alternative was a longer-lived [VoiceCubit] shared across
/// routes, which would mean one cubit holding a live microphone
/// subscription while other screens are on top of it.
class StartDictation {
  const StartDictation();
}

/// The floating pill dock: capture · voice · storage.
///
/// Voice is the centre and the largest target because the product is
/// voice-first — the home screen *is* the voice screen (design §3, screen 2C).
///
/// **The dock routes itself.** Every screen that shows it used to pass three
/// callbacks, and they drifted: the same microphone button started dictation
/// on the home screen and navigated home from the library, and two of the
/// four screens the design puts the dock on did not have it at all. Reading
/// the current location here means there is one description of what the dock
/// does, and it cannot disagree with itself.
///
/// [onVoice] is the single intended override — the home screen already *is*
/// the voice screen, so there the microphone starts dictation instead of
/// navigating anywhere.
///
/// **The accent fill is the selected state.** Every dock in the design has
/// exactly one accent button and it moves with the screen: left on capture,
/// centre on home, right on storage, the other two white. This code used to
/// paint the storage button accent on every screen — so storage always
/// looked current — and marked the real current screen by dimming it to 45%,
/// on my reading that the design drew an identical dock everywhere. It does
/// not; I had read one instance and generalised from it.
class VaultDock extends StatelessWidget {
  const VaultDock({this.onVoice, this.isListening = false, super.key});

  /// Handles the microphone in place, rather than navigating. Home only.
  final VoidCallback? onVoice;

  /// Dictation is running, so the microphone takes the design's deeper blue.
  ///
  /// `v2MicBg: v.bars ? '#2f5fe0' : '#ffffff'` — bound only on the home
  /// screen, and `bars` is true only while listening. A darker fill than the
  /// resting accent, so "listening" does not read the same as "you are on
  /// this screen".
  final bool isListening;

  /// The design's listening fill for the microphone.
  static const _listeningFill = Color(0xFF2F5FE0);

  /// Where each button goes. Paths, not names, so they can be compared
  /// against the current location without a lookup.
  static const _home = '/';
  static const _capture = '/capture';
  static const _storage = '/storage';

  /// True when the dock is being shown by the screen a button leads to.
  ///
  /// Tapping it is then a no-op rather than a second copy of the screen you
  /// are already looking at — which is what `push` would do, and did.
  static bool _isCurrent(String location, String destination) =>
      destination == _home
      ? location == _home
      : location == destination || location.startsWith('$destination/');

  void _go(BuildContext context, String destination) {
    final location = GoRouterState.of(context).matchedLocation;
    if (_isCurrent(location, destination)) return;

    // `go` for home, `push` for the other two.
    //
    // Home is the root, so arriving there should leave nothing underneath —
    // pushing it on top of the library would leave a back button that goes
    // *into* a list from the screen that list belongs to. Capture and
    // storage are tasks you finish and come back from, so they stack.
    if (destination == _home) {
      context.go(destination);
    } else {
      context.push(destination);
    }
  }

  void _voice(BuildContext context) {
    if (onVoice != null) {
      onVoice!();
      return;
    }
    // Not on home: go there and start listening on arrival.
    context.go(_home, extra: const StartDictation());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final location = GoRouterState.of(context).matchedLocation;

    // A Row that centres, not a Center.
    //
    // `Center` expands on BOTH axes under loose constraints. Inside a Column
    // that is harmless — the Column bounds the height. As a Scaffold's
    // `bottomNavigationBar` it is given the full screen height to centre
    // within, so the pill floats in the middle of the screen. A Row sizes to
    // its child's height and centres only horizontally, which is all this
    // ever wanted.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.round),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.isDark
                    ? const Color(0xB8090E1C)
                    : const Color(0xE6FFFFFF),
                borderRadius: BorderRadius.circular(AppRadius.round),
                border: Border.all(color: p.hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: p.isDark ? 0.5 : 0.12,
                    ),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DockButton(
                    icon: AppIcons.capture,
                    size: 52,
                    isCurrent: _isCurrent(location, _capture),
                    onTap: () => _go(context, _capture),
                    semanticLabel: 'Capture',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _DockButton(
                    icon: AppIcons.mic,
                    size: 60,
                    // Home is where the microphone lives, so the centre
                    // button is the current one there — and turns the
                    // deeper blue while it is actually listening.
                    isCurrent: _isCurrent(location, _home),
                    fill: isListening ? _listeningFill : null,
                    // The one button that stays tappable on its own screen:
                    // its job there is to listen, not to navigate.
                    isActionable: true,
                    onTap: () => _voice(context),
                    semanticLabel: 'Ask with voice',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _DockButton(
                    icon: AppIcons.storage,
                    size: 52,
                    isCurrent: _isCurrent(location, _storage),
                    onTap: () => _go(context, _storage),
                    semanticLabel: 'Storage',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.size,
    required this.semanticLabel,
    this.onTap,
    this.isCurrent = false,
    this.isActionable = false,
    this.fill,
  });

  final String icon;
  final double size;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// This button leads to the screen already on display.
  ///
  /// Drives the accent fill, which is the design's selected state — and, for
  /// every button except the microphone, makes the tap a no-op, since `push`
  /// would otherwise stack a second copy of the screen you are looking at.
  final bool isCurrent;

  /// Still does something on its own screen. True only for the microphone,
  /// whose job on the home screen is to listen rather than to navigate.
  final bool isActionable;

  /// Overrides the fill. Used for the microphone's listening blue.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = isActionable || !isCurrent;

    // White when elsewhere, accent when here. Straight from the design,
    // where each dock has exactly one accent button and it is the one for
    // the screen you are on.
    final background = fill ?? (isCurrent ? p.accent : p.textPrimary);
    final foreground = fill != null
        ? Colors.white
        : (isCurrent ? p.onAccent : p.ground);

    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: live,
      selected: isCurrent,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: live ? onTap : null,
            child: Center(
              child: AppIcon(icon, size: size * 0.4, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
