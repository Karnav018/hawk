import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/theme/app_palette.dart';
import 'eye_motion.dart';
import 'eye_painter.dart';
import 'eye_pose.dart';

export 'eye_pose.dart' show OrbState;

/// The Hawk eye — `design/blender/HANDOFF_eye_orb.md`.
///
/// Replaces `VoiceOrb` and `HawkOrb` at every placement 190px and up. The
/// two-circle [HawkMark] stays the logo, at the splash, the sign-in header
/// and the 34px snack glyph; this is a different object with a different job.
///
/// ## Why the work is split three ways
///
/// `EyePose` is *what the eye looks like* — 40 knobs, no time. `EyeMotion` is
/// *how those knobs move* — pure functions of elapsed seconds. This widget is
/// only the plumbing: a ticker, a morph controller, and a choice of painter.
/// None of the three can see the others' problems, which is the point: the
/// shader is the part that needs a GPU, and it is also the part with no
/// logic in it at all.
///
/// ## Transitions belong here, not in the shader
///
/// The shader infers nothing. Handed a pose it draws that pose. Everything
/// that makes one state *become* another is [EyePose.lerp] driven by
/// [_morph] — which is what lets the same code snap instead of ease when
/// reduce-motion is on, without the shader knowing the setting exists.
class EyeOrb extends StatefulWidget {
  const EyeOrb({
    required this.state,
    required this.size,
    this.level = 0,
    this.progress = 0,
    this.accent,
    this.reduceMotion,
    this.semanticLabel,
    super.key,
  });

  final OrbState state;

  /// The box is square and fully reserved. The outline ring is 77% of it at
  /// rest, but the brow reaches 1.22 of 1.3 and a pop scales by 1.08, so the
  /// headroom is not spare — nothing may clip.
  final double size;

  /// Microphone level, 0..1. Drives the wave's amplitude and nothing else.
  final double level;

  /// Job fraction, 0..1. [OrbState.indexing] only, where the lids *are* the
  /// progress indicator.
  final double progress;

  /// Defaults to the theme accent. Everything else is white on transparency.
  final Color? accent;

  /// Defaults to the platform setting. An override exists so a test can
  /// assert both paths without reaching for `MediaQuery`.
  final bool? reduceMotion;

  final String? semanticLabel;

  /// Below this the mark is used instead; the eye's detail does not survive.
  static const minSize = 190.0;

  @visibleForTesting
  static const shaderAsset = 'shaders/eye_orb.frag';

  /// Forces the fallback painter regardless of what the GPU can do.
  ///
  /// Tests run headless, so the program never resolves there anyway — this
  /// makes that deterministic rather than incidental, and lets a golden be
  /// taken of the path that actually ships on a device that fails to compile.
  @visibleForTesting
  static bool debugForceFallback = false;

  @override
  State<EyeOrb> createState() => _EyeOrbState();
}

class _EyeOrbState extends State<EyeOrb> with TickerProviderStateMixin {
  /// Loaded once per process, not per widget.
  ///
  /// Two orbs can be alive at once during a route transition, and compiling
  /// the program twice would drop frames at exactly the moment the user is
  /// watching it move.
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// This widget's own shader instance.
  ///
  /// The program is shared and immutable; a shader carries the uniforms, so
  /// two orbs on screen during a route transition need one each. It lives as
  /// long as the widget does — see [EyeShaderPainter] for why disposing it
  /// per frame renders nothing.
  ui.FragmentShader? _shader;

  late final Ticker _ticker;
  late final AnimationController _morph;

  /// Free-running elapsed seconds. Loops read this, so changing state does
  /// not restart the breathe or the wave's drift mid-cycle.
  double _t = 0;

  /// Seconds since the current state was entered. One-shots read this.
  double _since = 0;

  late OrbState _state;

  /// When the last pop fired, on the ticker's clock.
  ///
  /// The design's rule is "never two pops within 1s". Re-pressing during the
  /// silent exit resumes an eye that never finished leaving, and popping it
  /// again reads as a stutter rather than as acknowledgement.
  double _lastPop = double.negativeInfinity;

  /// Whether the state we are currently in is allowed its entry pop.
  bool _allowPop = true;

  /// The pose at the instant the state changed — the near end of the morph.
  /// Captured from what was actually on screen, including mid-blink, so the
  /// transition starts from the frame the user just saw.
  EyePose? _from;

  late final ValueNotifier<EyePose> _pose;

  @override
  void initState() {
    super.initState();
    _state = widget.state;
    _pose = ValueNotifier(
      EyeMotion.poseFor(_state, loopT: 0, sinceT: 0, progress: widget.progress),
    );
    _morph = AnimationController(vsync: this, duration: Duration.zero);
    _ticker = createTicker(_tick)..start();
    unawaited(_ensureProgram());
  }

  Future<void> _ensureProgram() {
    return _loading ??= () async {
      try {
        _program = await ui.FragmentProgram.fromAsset(EyeOrb.shaderAsset);
      } catch (_) {
        // Headless test, or a device whose driver rejected the program. The
        // fallback painter covers both, so this is not an error — but it is
        // permanent: retrying per frame would thrash.
      }
      if (mounted) setState(_attachShader);
    }();
  }

  void _attachShader() => _shader ??= _program?.fragmentShader();

  void _tick(Duration elapsed) {
    final now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _since += now - _t;
    _t = now;

    final reduce =
        widget.reduceMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;

    final target = EyeMotion.poseFor(
      _state,
      loopT: _t,
      sinceT: _since,
      level: widget.level,
      progress: widget.progress,
      reduceMotion: reduce,
      allowPop: _allowPop,
    );

    // Reduce motion snaps: the wave appears and disappears rather than
    // rippling. The morph is the one animation a user cannot look away from,
    // so the setting has to reach it.
    _pose.value = (_from == null || reduce || !_morph.isAnimating)
        ? target
        : EyePose.lerp(
            _from!,
            target,
            Curves.easeOutCubic.transform(_morph.value),
          );
  }

  @override
  void didUpdateWidget(EyeOrb old) {
    super.didUpdateWidget(old);
    if (old.state == widget.state) return;

    final wave = _pose.value.wave;

    // A state with an entry pop only gets one if the eye actually arrived
    // from somewhere else. Pressing again while the wave is still draining
    // means it never left, so the pop would be the second in under a second.
    final pops =
        widget.state == OrbState.listening || widget.state == OrbState.answered;
    if (pops) {
      final resuming = widget.state == OrbState.listening && wave > 0;
      _allowPop = !resuming && (_t - _lastPop) > 1.0;
      if (_allowPop) _lastPop = _t;
    } else {
      _allowPop = true;
    }

    _from = _pose.value;
    _state = widget.state;
    _since = 0;
    _morph
      ..duration = EyeMotion.transition(
        old.state,
        widget.state,
        currentWave: wave,
      )
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _morph.dispose();
    _pose.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? context.palette.accent;
    // A second orb mounting after the program has already loaded never runs
    // the load future, so it would have no shader at all without this.
    if (_shader == null && !EyeOrb.debugForceFallback) _attachShader();
    final shader = EyeOrb.debugForceFallback ? null : _shader;

    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        // The eye repaints every frame; without this the whole screen around
        // it joins in.
        child: RepaintBoundary(
          child: ValueListenableBuilder<EyePose>(
            valueListenable: _pose,
            builder: (context, pose, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: shader == null
                  ? EyeFallbackPainter(pose: pose, accent: accent)
                  : EyeShaderPainter(
                      shader: shader,
                      pose: pose,
                      accent: accent,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
