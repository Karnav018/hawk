import 'dart:math' as math;

import 'eye_pose.dart';

/// The per-frame motion, as pure functions.
///
/// Split out from the widget for one reason: this is the part that can be
/// wrong in a way nobody sees until it ships. A shader either draws or it
/// does not, but a blink at the wrong moment, a gaze that sweeps instead of
/// rolling, or an amplitude that ignores the microphone all look *fine* in a
/// still. Here they are ordinary Dart and a test can assert them.
///
/// Every signature is from `HANDOFF_eye_orb.md` § Motion signatures.
class EyeMotion {
  const EyeMotion._();

  /// READY's loop, and the period the breathe and blink are timed against.
  static const readyLoop = 6.0;

  /// RETRIEVING's loop — the pupil's roll.
  static const retrieveLoop = 2.0;

  /// Lids to .02, three frames at 30fps.
  static const blinkDuration = 0.1;

  /// The shape the eye holds between the pop and the morph.
  ///
  /// Entering LISTENING is not a crossfade to the wave — it is a pop, a
  /// beat, and *then* the wave growing out of the pupil. This is the beat.
  static final _beforeWave = EyePose.rest(OrbState.ready);

  /// The enter's morph window, from `HANDOFF_eye_orb.md`: the pop runs
  /// 0-0.17s, then the wave grows from 0.4s to 1.0s.
  static const morphStart = 0.4;
  static const morphEnd = 1.0;

  /// A lid multiplier that dips to ~.02 at each start time and returns.
  ///
  /// Multiplicative rather than absolute so it composes with whatever the
  /// lids are already doing — INDEXING's lids are the progress bar, and a
  /// blink there has to be a blink *of that opening*, not a jump to .72.
  static double blink(double t, List<double> starts) {
    var f = 1.0;
    for (final s in starts) {
      final d = t - s;
      if (d < 0 || d >= blinkDuration) continue;
      // 0 -> 1 -> 0 across the blink: closing, then opening.
      final closed = 1 - (2 * (d / blinkDuration) - 1).abs();
      f = math.min(f, 1 - 0.98 * closed);
    }
    return f;
  }

  /// The pose for a state at a given moment.
  ///
  /// [loopT] is free-running elapsed time, for loops that should not restart
  /// when the state does. [sinceT] is time since this state was entered, for
  /// the one-shots — the listening pop, the answered sparkle.
  ///
  /// [reduceMotion] returns the rest pose untouched: no blink, no wander, no
  /// beat. It is deliberately checked once at the top rather than threaded
  /// through each branch, so a new signature cannot forget it.
  static EyePose poseFor(
    OrbState state, {
    required double loopT,
    required double sinceT,
    double level = 0,
    double progress = 0,
    bool reduceMotion = false,
    bool allowPop = true,
  }) {
    final rest = EyePose.rest(state, progress: progress);
    if (reduceMotion) return rest;

    switch (state) {
      case OrbState.ready:
        final t = loopT % readyLoop;
        // A double blink: two dips 0.15s apart, once per loop.
        final lid = blink(t, const [0.7, 0.85]);
        final look = readyWander(loopT);
        return rest.copyWith(
          eyeTop: rest.eyeTop * lid,
          eyeBot: rest.eyeBot * lid,
          lookX: look.x,
          lookZ: look.z,
          // Breathe 1.012 over the loop — the eye inhales once per cycle.
          scale:
              1 + 0.012 * (0.5 - 0.5 * math.cos(2 * math.pi * t / readyLoop)),
        );

      case OrbState.listening:
        // THE ENTER LIVES HERE, not in the transition.
        //
        // The design's rule is "blend 200ms into row 1, then play the clip",
        // because frames 1-36 of the LISTENING clip *are* the pop and the
        // morph. Taking the 200ms without the clip made the 200ms the whole
        // transformation — the eye snapped to a full wave in a fifth of a
        // second. Until clip playback lands, the schedule has to be written
        // out, and it is the handoff's: pop 0-0.17s, hold, wave grows
        // 0.4-1.0s ease-out.
        final pop = allowPop && sinceT < 0.17
            ? math.sin(math.pi * sinceT / 0.17)
            : 0.0;

        // Ease-out cubic over the morph window; hand-rolled because this
        // file stays free of the widget layer.
        final u = ((sinceT - morphStart) / (morphEnd - morphStart)).clamp(
          0.0,
          1.0,
        );
        final m = 1 - math.pow(1 - u, 3).toDouble();

        // Lids, eye_n, disc_r and wave all travel together over that window.
        final shape = EyePose.lerp(_beforeWave, rest, m);

        // The brow comes up with the pop, ahead of the morph — it is the
        // part of the pop that says "heard you" before anything else moves.
        final brow = (sinceT / 0.17).clamp(0.0, 1.0);

        return shape.copyWith(
          // .98 overshoot at the top of the pop.
          eyeTop: shape.eyeTop + 0.26 * pop,
          eyeBot: shape.eyeBot - 0.26 * pop,
          scale: 1 + 0.05 * pop,
          browShow: brow,
          browZ: 0.95 + 0.15 * brow,
          // Bands rise, and the field they are cut from drifts. Two rates,
          // so the pattern never repeats on itself.
          waveFlow: -1.0 * loopT,
          waveT: 0.35 * loopT,
          // The one knob the microphone drives.
          waveAmp: 0.5 + 0.45 * level.clamp(0.0, 1.0),
        );

      case OrbState.retrieving:
        // A roll, not a sweep. The gaze traces a small closed loop and comes
        // back; it must never look like it is reading something.
        final u = 2 * math.pi * (loopT % retrieveLoop) / retrieveLoop;
        return rest.copyWith(
          lookX: 0.35 + 0.15 * math.cos(u),
          lookZ: 0.45 + 0.12 * math.sin(u),
          browTilt: 0.24 - 0.06 * math.cos(u),
          browZ: 0.885 + 0.035 * math.sin(u),
          discR: 0.42 + 0.02 * math.sin(u),
          scale: 1 + 0.03 * (0.5 - 0.5 * math.cos(2 * math.pi * loopT / 2)),
        );

      case OrbState.answered:
        // One shot that then holds: pop, twinkle, settle, brow away, blink.
        final pop = allowPop && sinceT < 0.4
            ? math.sin(math.pi * sinceT / 0.4)
            : 0.0;
        final twinkle = sinceT >= 0.27 && sinceT < 1.7
            ? 0.5 + 0.5 * math.sin(2 * math.pi * (sinceT - 0.27) * 1.6)
            : 0.0;
        // Brow is up for the moment of the answer, then leaves by 2.2s.
        final brow = sinceT < 1.9
            ? 1.0
            : (sinceT < 2.2 ? 1 - (sinceT - 1.9) / 0.3 : 0.0);
        final lid = blink(sinceT, const [2.7]);
        return rest.copyWith(
          scale: 1 + 0.06 * pop,
          eyeTop: rest.eyeTop * lid,
          eyeBot: rest.eyeBot * lid,
          browShow: brow,
          spark: twinkle,
        );

      case OrbState.indexing:
        final t = loopT % readyLoop;
        final lid = blink(t, const [3.0]);
        return rest.copyWith(
          eyeTop: rest.eyeTop * lid,
          eyeBot: rest.eyeBot * lid,
          // A slow bob, so a long job does not look frozen even while the
          // lids are not moving.
          locZ: 0.05 * math.sin(2 * math.pi * t / readyLoop),
          scale: 1 + 0.02 * (0.5 - 0.5 * math.cos(2 * math.pi * t / readyLoop)),
          discR: rest.discR + 0.02 * math.sin(2 * math.pi * t / 3),
        );
    }
  }

  /// How long the morph between two states runs.
  ///
  /// These are the design session's numbers, not a guess. The rule is 320ms
  /// ease-out-cubic from the current pose into the target's first pose, and
  /// the exceptions each have a reason:
  ///
  ///  * **Into LISTENING or ANSWERED — 200ms.** Short, because the state's
  ///    own pop *is* the transition. A long blend on top of it would swallow
  ///    the pop and the press would feel unacknowledged.
  ///  * **Leaving LISTENING with a result — 240ms.** The handoff calls a
  ///    successful release a cut, because in the design the result is a
  ///    different screen. Ours is not: the user asked to listen in place, so
  ///    the eye stays put and the rule for that case applies — ease the wave
  ///    out while the pose blends.
  ///  * **Leaving LISTENING in silence — the LISTENING_OUT clip.** The wave
  ///    runs back into the pupil. Approximated here at 900ms; the real clip
  ///    is 60 frames and needs clip playback to be right.
  ///  * **A flinch, not an apology — 240ms.** Releasing before the wave is
  ///    half-grown means the eye barely started; running the full exit for
  ///    something the user aborted in under a second reads as sulking.
  ///  * **ANSWERED to READY — 480ms.** A lazy settle. It is the one
  ///    transition nobody is waiting on.
  ///  * **Anything touching INDEXING — 400ms.** Calm; it is a long job.
  ///
  /// [currentWave] is the wave's value *right now*, which is what separates
  /// the flinch from the full exit. It cannot be inferred from the two
  /// states alone.
  static Duration transition(
    OrbState from,
    OrbState to, {
    double currentWave = 0,
  }) {
    if (to == OrbState.listening || to == OrbState.answered) {
      return const Duration(milliseconds: 200);
    }
    if (from == OrbState.listening) {
      // Aborted before the wave took hold.
      if (currentWave < 0.5) return const Duration(milliseconds: 240);
      // A result, rendering on this same screen.
      if (to != OrbState.ready) return const Duration(milliseconds: 240);
      return const Duration(milliseconds: 900);
    }
    if (from == OrbState.answered && to == OrbState.ready) {
      return const Duration(milliseconds: 480);
    }
    if (from == OrbState.indexing || to == OrbState.indexing) {
      return const Duration(milliseconds: 400);
    }
    return const Duration(milliseconds: 320);
  }
}
