import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router/pop_or.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/hawk_icons.dart';
import '../../../../core/widgets/hawk_kit.dart';
import '../../../memory/presentation/pages/library_page.dart';
import '../bloc/capture_cubit.dart';
import '../bloc/speak_capture_cubit.dart';
import '../bloc/upload_center.dart';

/// SPEAK — F7·3. A voice note, kept.
///
/// Opens already listening. The user tapped a tile labelled Speak; making
/// them press a second button to start would be asking the same question
/// twice.
///
/// **Stop saves.** The big red button is the end of the note, and the note
/// was the point — "Tap stop to save". The earlier cut stopped and then
/// asked Save or Discard, which is one decision spread over two taps, with
/// the more common answer on the second. Discard stays, on the left, for
/// the other answer.
///
/// **No live transcript on screen.** The words are what is kept, but
/// reading them while speaking makes people start correcting themselves
/// mid-sentence. The clock and the bars are enough to say it is listening.
class SpeakCapturePage extends StatefulWidget {
  const SpeakCapturePage({super.key});

  static const routeName = 'speak';
  static const routePath = '/speak';

  @override
  State<SpeakCapturePage> createState() => _SpeakCapturePageState();
}

class _SpeakCapturePageState extends State<SpeakCapturePage> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so a permission prompt appears over a screen
    // that has already explained what the microphone is for.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<SpeakCaptureCubit>().start(),
    );
  }

  Future<void> _leave() async {
    // Leaving is discarding. A note walked away from mid-sentence was not
    // one anybody chose to keep.
    await context.read<SpeakCaptureCubit>().discard();
    if (mounted) context.popOrGo(LibraryPage.routeName);
  }

  Future<void> _stop() async {
    final cubit = context.read<SpeakCaptureCubit>();
    if (cubit.state.canSave) {
      await cubit.save();
      return;
    }
    // Stopped before a word was heard: there is nothing to keep, and
    // saying so beats an empty note in the Library.
    await cubit.discard();
    if (!mounted) return;
    getIt<SnackController>().show(
      const Snack.detail(
        title: 'Nothing was heard',
        subtitle: 'Nothing saved. Try again a little closer.',
      ),
    );
    context.popOrGo(LibraryPage.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocConsumer<SpeakCaptureCubit, SpeakCaptureState>(
      listenWhen: (a, b) => a.phase != b.phase || a.exception != b.exception,
      listener: (context, state) {
        if (state.exception != null) {
          getIt<SnackController>().show(
            Snack.detail(
              title: 'Could not save',
              mark: SnackMark.failure,
              subtitle: state.exception!.displayMessage,
            ),
          );
          context.read<SpeakCaptureCubit>().dismissError();
        }
        final saved = state.saved;
        if (state.phase == SpeakPhase.saved && saved != null) {
          getIt<UploadCenter>().follow(saved, kind: CaptureKind.speak);
          getIt<SnackController>().show(
            const Snack.confirmation(message: 'Saved — transcribing it now'),
          );
          context.popOrGo(LibraryPage.routeName);
        }
      },
      builder: (context, state) {
        final cubit = context.read<SpeakCaptureCubit>();
        final recording = state.phase == SpeakPhase.recording;
        final paused = state.phase == SpeakPhase.paused;

        if (state.phase == SpeakPhase.unavailable) {
          return _Unavailable(onClose: () => unawaited(_leave()));
        }

        return AppScreen(
          ambientOpacity: 0,
          scrollable: false,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenSide,
            AppSpacing.screenTop,
            AppSpacing.screenSide,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Back to Library, discarding the note',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => unawaited(_leave()),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: AppSize.headerButton,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            HawkIcons.chevronLeft,
                            size: 20,
                            color: p.textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Library',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              fontVariations: const [
                                FontVariation('wght', 600),
                              ],
                              letterSpacing: 0,
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Headline('Speak', size: 28),
              const SizedBox(height: 6),
              Text(
                'Say it the way you’d tell a friend. Hawk keeps the words.',
                style: AppTypography.bodyMedium.copyWith(
                  fontSize: 14,
                  height: 1.5,
                  color: p.textTertiary,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      state.clock,
                      style: AppTypography.numeralLarge.copyWith(
                        fontSize: 54,
                        fontWeight: FontWeight.w500,
                        fontVariations: const [FontVariation('wght', 500)],
                        letterSpacing: -1.08,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 90,
                      child: _Waveform(level: state.level, live: recording),
                    ),
                    const SizedBox(height: 26),
                    MetaText(
                      paused
                          ? 'Paused'
                          : recording
                          ? 'Listening'
                          : state.phase == SpeakPhase.saving
                          ? 'Saving'
                          : 'Starting',
                      color: recording ? p.accent : p.textMuted,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SideAction(
                      label: 'Discard',
                      color: p.textMuted,
                      onTap: () => unawaited(_leave()),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    _StopButton(
                      enabled: recording || paused,
                      busy: state.phase == SpeakPhase.saving,
                      onPressed: () => unawaited(_stop()),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    _SideAction(
                      label: paused ? 'Resume' : 'Pause',
                      color: recording || paused ? p.textPrimary : p.textFaint,
                      alignEnd: true,
                      onTap: paused
                          ? () => unawaited(cubit.resume())
                          : recording
                          ? () => unawaited(cubit.pause())
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Discard" and "Pause" — text either side of the button, 60px wide each
/// so the button sits dead centre whatever the words say.
class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            label,
            style: AppTypography.titleSmall.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
              letterSpacing: 0,
              color: color,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The red circle with an ink square — stop, which saves.
///
/// Red, not the accent: this is the one control on the screen that ends
/// something, and the microphone being open is the one state on it worth a
/// warning colour.
class _StopButton extends StatelessWidget {
  const _StopButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Stop and save',
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled && !busy ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled || busy ? 1 : 0.35,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: busy
                ? SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(p.onAccent),
                    ),
                  )
                : Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: p.onAccent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Eighteen bars: the recent past in accent, the rest waiting in grey.
///
/// Driven by the microphone's own level, a sample a tick, so the bars are a
/// record of how loudly somebody actually spoke rather than a loop that
/// looks the same in silence. Fills from the left and then scrolls, the
/// newest sample always on the right edge of the accent run.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.level, required this.live});

  final double level;
  final bool live;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  static const _bars = 18;
  static const _lit = 12;

  /// The design's resting shape for the bars not yet spoken into.
  static const _rest = [48.0, 66.0, 36.0, 20.0, 44.0, 28.0];

  final _history = <double>[];

  @override
  void didUpdateWidget(_Waveform old) {
    super.didUpdateWidget(old);
    if (widget.live && widget.level != old.level) {
      _history.add(widget.level.clamp(0.0, 1.0));
      if (_history.length > _lit) _history.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _bars; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 6,
            height: i < _history.length
                ? 18 + 62 * _history[i]
                : _rest[(i - _history.length) % _rest.length],
            decoration: BoxDecoration(
              color: i < _history.length ? p.accent : p.raised,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppScreen(
      ambientOpacity: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Headline('Speech is off', size: 28),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This phone is not letting Hawk use the microphone or speech '
            'recognition. Turn both on for Hawk in Settings, then try again.',
            style: AppTypography.bodyMedium.copyWith(
              height: 1.5,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.card),
          PillButton(
            label: 'Back to Library',
            tone: PillTone.white,
            height: AppSize.buttonSmall,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
