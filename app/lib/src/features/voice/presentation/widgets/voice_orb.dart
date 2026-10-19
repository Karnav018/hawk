import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/hawk_orb.dart';
import '../bloc/voice_cubit.dart';

/// Every number the LISTENING transform is tuned by, in one place.
///
/// From `design/blender/HANDOFF_listening_orb.md`, section "Constants". They
/// live together because they are a single piece of choreography: changing the
/// squash without the halo, or the attack without the release, produces motion
/// that no longer matches the rig the frames were baked from.
abstract final class OrbListening {
  /// Widest the silhouette stretches, as a fraction. `sx = 1 + this * level`.
  static const squashMax = 0.08;

  /// How fast the smoothed level chases the microphone. Fast up, slow down —
  /// speech has sharp onsets and the orb has to catch them, but a level that
  /// fell as fast as it rose would flicker on every syllable gap.
  static const attack = Duration(milliseconds: 40);
  static const release = Duration(milliseconds: 250);

  /// Sphere frames in the amplitude strip. `level_0` is silence.
  static const frames = 5;

  /// Sphere <-> strip dissolve when listening starts and stops.
  static const crossfade = Duration(milliseconds: 220);

  /// The frames' native size. Cropped edge-to-edge at the alpha box, exactly
  /// like `orb_sphere.png`, so the resting and listening silhouettes are the
  /// same circle and no scale compensation is needed.
  static const frameExtent = 768;

  static String frame(int index) => 'assets/images/orb_listen/level_$index.png';

  /// The texture both swirls are made of — the same emission map the ambient
  /// background uses, and the same file the design points at.
  static const emission = 'assets/images/orb_emission.png';

  /// `inset:-24%` on the layer inside the sphere, and `inset:-18%` on the
  /// glow outside it. Both are larger than the circle that clips them, which
  /// is what lets a rotation move new texture through the aperture instead of
  /// spinning a disc in place.
  static const innerInset = 1.48;
  static const glowInset = 1.36;

  /// `@keyframes swirl`: scale 1.25 -> 1.45 -> 1.25 across one revolution.
  static const innerScaleMin = 1.25;
  static const innerScaleMax = 1.45;

  /// `@keyframes swirl2`: a constant scale(1.6), rotating the other way.
  static const glowScale = 1.6;

  /// The size the design's orb was drawn at, which its pixel values assume.
  static const designOrb = 214.0;

  /// `filter:blur(34px)` on the glow, as a sigma for an orb of [size].
  static double glowBlur(double size) => 34 * size / designOrb;

  /// `@keyframes breathe`: scale(1) -> scale(1.05). Applied to the sphere
  /// itself, not just to its glow — the ball inhales.
  static const breatheScale = 0.05;

  /// How much of the churn shows through the rendered sphere.
  ///
  /// The design composites its emission *under* a radial gradient inside an
  /// otherwise empty circle. Our sphere is a path-traced render with its own
  /// lighting baked in, so the texture goes over it instead, at an opacity
  /// low enough to read as light moving inside glass rather than as a decal
  /// stuck to the front.
  static const innerOpacity = 0.34;
}

/// The home screen's orb: the rendered sphere, plus the motion that says what
/// the app is doing.
///
/// Three layers, and they animate independently on purpose — locking them to
/// one controller made the whole thing pulse in lockstep, which reads as a
/// loading spinner rather than something alive.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    required this.phase,
    required this.size,
    this.level = 0,
    this.hasMatches = false,
    this.onTap,
    super.key,
  });

  final VoicePhase phase;
  final double size;

  /// There are matches on screen, so the orb may emit rings.
  ///
  /// `<sc-if value="{{ v2HasMatches }}">` in the design: the pulse ring is
  /// not an idle animation, it is the orb reporting a find.
  final bool hasMatches;

  /// Raw microphone level, 0-1, straight from the cubit.
  ///
  /// Smoothed inside, not outside: the cubit emits on every level tick, and
  /// the smoothing has to run on the ticker's clock to have a `dt` at all.
  final double level;

  final VoidCallback? onTap;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  /// One ticker, two accumulated phases — deliberately not two
  /// `AnimationController`s.
  ///
  /// A controller's period *is* its cycle, so changing it means calling
  /// `repeat()` again, which restarts from the beginning. The orb changes
  /// phase whenever the user starts typing, and a visible jump back to the
  /// start of the swirl every time reads as a glitch on the app's
  /// centrepiece.
  ///
  /// Accumulating phase instead — `phase += dt / period` — makes the period a
  /// *rate*. Changing it changes how fast the orb moves from wherever it
  /// currently is, with no discontinuity in position at all. It also removes
  /// the class of bug that took this screen down once already: there is no
  /// controller left that can be started before it has a duration.
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// 0–1, driving the glow's breathe.
  final _breathe = ValueNotifier<double>(0);

  /// 0–1, one full revolution of the travelling ring.
  final _swirl = ValueNotifier<double>(0);

  /// The smoothed microphone level, 0–1. Drives the squash and the frame.
  final _level = ValueNotifier<double>(0);

  /// 0 = resting sphere, 1 = amplitude strip. The enter/leave dissolve.
  final _strip = ValueNotifier<double>(0);

  /// 0–1, one revolution of the counter-rotating glow. Design: `swirl2`.
  final _glowSpin = ValueNotifier<double>(0);

  /// 0–1, one emitted ring. Design: `pulseRing`.
  final _ring = ValueNotifier<double>(0);

  /// Physical pixels the strip frames are decoded at.
  ///
  /// The orb is drawn at `widget.size` logical points, so this is that times
  /// the device pixel ratio — capped at the frames' native size, since
  /// asking for more than exists would upscale five PNGs for nothing.
  int _decodeWidth = OrbListening.frameExtent;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _decodeWidth = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, OrbListening.frameExtent);

    // The emission map feeds both swirls and is on screen from the first
    // frame, so a late decode would show as a pop-in on the home screen.
    precacheImage(const AssetImage(OrbListening.emission), context);

    // Decoded before they are needed. Five PNGs arriving mid-utterance would
    // each drop a frame on first use, which is exactly when the orb is being
    // watched.
    for (var i = 0; i < OrbListening.frames; i++) {
      precacheImage(
        ResizeImage(AssetImage(OrbListening.frame(i)), width: _decodeWidth),
        context,
      );
    }
  }

  void _tick(Duration elapsed) {
    // Clamped: coming back from the background delivers one enormous delta,
    // which would fling both phases forward by an arbitrary amount.
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;

    // ValueNotifier rather than setState: the sphere below is a decoded
    // image, and rebuilding it sixty times a second to move a glow would be
    // the most expensive thing on the screen.
    _breathe.value = (_breathe.value + dt / widget.phase.breatheSeconds) % 1.0;
    _swirl.value = (_swirl.value + dt / widget.phase.swirlSeconds) % 1.0;
    _glowSpin.value =
        (_glowSpin.value + dt / widget.phase.glowSpinSeconds) % 1.0;
    _ring.value = (_ring.value + dt / widget.phase.ringSeconds) % 1.0;

    // One-pole smoothing, with the time constant chosen by direction.
    //
    // `1 - exp(-dt/tau)` rather than a fixed per-frame fraction, so the
    // motion is the same on a 60Hz and a 120Hz screen — a plain lerp per
    // frame is twice as fast on a 120Hz device, which is how animations end
    // up feeling different on different phones.
    final target = widget.phase == VoicePhase.listening ? widget.level : 0.0;
    final tau = target > _level.value
        ? OrbListening.attack.inMicroseconds / 1e6
        : OrbListening.release.inMicroseconds / 1e6;
    _level.value += (target - _level.value) * (1 - math.exp(-dt / tau));

    // The dissolve runs on the same clock, linearly over its own duration.
    final stripTarget = widget.phase == VoicePhase.listening ? 1.0 : 0.0;
    final step = dt / (OrbListening.crossfade.inMicroseconds / 1e6);
    _strip.value = stripTarget > _strip.value
        ? math.min(stripTarget, _strip.value + step)
        : math.max(stripTarget, _strip.value - step);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _level.dispose();
    _strip.dispose();
    _glowSpin.dispose();
    _ring.dispose();
    _breathe.dispose();
    _swirl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: widget.onTap != null,
      label: 'Ask Hawk. ${widget.phase.hint}',
      child: GestureDetector(
        onTap: widget.onTap,
        // The squash, outside everything.
        //
        // Wrapping the whole stack — halo, ring and sphere — is what makes it
        // read as the orb itself deforming rather than a picture inside it
        // being stretched. It is also outside the swirl rotation on purpose:
        // a non-uniform scale inside a rotation is sheared by that rotation,
        // so the orb would squash along whatever axis the swirl happened to
        // be pointing at instead of along the screen.
        //
        // `child:` rather than building the stack in the closure, so a level
        // tick rebuilds one Transform and not the subtree under it.
        child: ValueListenableBuilder<double>(
          valueListenable: _level,
          child: SizedBox.square(
            dimension: widget.size * 1.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The glow. Behind the sphere and scaling past it, so the orb
                // appears to light its surroundings rather than be lit.
                AnimatedBuilder(
                  animation: Listenable.merge([_breathe, _level]),
                  builder: (context, _) {
                    // Triangle wave, eased: a sine would spend most of its time
                    // near the extremes, which reads as a pulse rather than a
                    // breath.
                    final phase = _breathe.value;
                    final breath = Curves.easeInOut.transform(
                      phase < 0.5 ? phase * 2 : (1 - phase) * 2,
                    );

                    // While listening, the halo follows the voice instead of
                    // the breath. A breathing halo over a level-driven
                    // silhouette would be two different rhythms on one
                    // object, which reads as the animation being out of sync
                    // with itself rather than as an orb that is listening.
                    final listening = _strip.value > 0;
                    final t = listening
                        ? (0.6 + 0.6 * _level.value).clamp(0.0, 1.0)
                        : breath;
                    return Container(
                      width: widget.size * (1.18 + 0.16 * t),
                      height: widget.size * (1.18 + 0.16 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Three offset glows, not one — and in v3 all three
                        // are the accent.
                        //
                        // v2 built this halo out of a violet and a teal
                        // offset behind the brand colour, so the blurs
                        // overlapped into hues neither one was. v3 has one
                        // accent and no hue wheel, so that spectrum is gone:
                        // `p.hue(Hue.violet)` now resolves to white through
                        // the compatibility shim, which was quietly washing
                        // the halo out rather than colouring it.
                        //
                        // The three offsets stay, because the *geometry* is
                        // what makes the glow read as light with a direction
                        // rather than a ring around a ball. Only the spectrum
                        // is collapsed.
                        boxShadow: [
                          BoxShadow(
                            color: p.accent.withValues(
                              alpha: widget.phase.glow * (0.34 + 0.30 * t),
                            ),
                            blurRadius: widget.size * 0.50,
                            spreadRadius: widget.size * 0.05,
                            offset: Offset(
                              -widget.size * 0.05,
                              widget.size * 0.03,
                            ),
                          ),
                          BoxShadow(
                            color: p.accent.withValues(
                              alpha: widget.phase.glow * (0.26 + 0.24 * t),
                            ),
                            blurRadius: widget.size * 0.46,
                            spreadRadius: widget.size * 0.03,
                            offset: Offset(
                              widget.size * 0.06,
                              -widget.size * 0.02,
                            ),
                          ),
                          // Brightest last, so the halo has a core.
                          BoxShadow(
                            color: p.accent.withValues(
                              alpha: widget.phase.glow * (0.55 + 0.45 * t),
                            ),
                            blurRadius: widget.size * 0.42,
                            spreadRadius: widget.size * 0.04,
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // The outer glow: the emission texture, heavily blurred,
                // turning anticlockwise. Design: `inset:-18%`,
                // `filter:blur(34px)`, `animation:swirl2 {{orbGlowSpin}}`.
                //
                // This replaced a sweep gradient I had used for the same
                // slot. The gradient rotated correctly and still looked
                // wrong, because the design's glow is not a gradient — it is
                // the same emission map as the core, blurred until only its
                // large-scale structure survives. A gradient has no
                // structure to blur, so it read as a faint tint sliding
                // round rather than as light coming off a textured body.
                ValueListenableBuilder<double>(
                  valueListenable: _glowSpin,
                  builder: (context, turns, child) => Transform.rotate(
                    angle: -turns * 2 * math.pi,
                    child: child,
                  ),
                  // Built once and rotated, inside a RepaintBoundary. That
                  // saves re-recording the image draw every frame — but not
                  // the blur: Impeller applies an image filter at composite
                  // time, so a filtered layer under a changing transform is
                  // re-blurred each frame. On the GPU at this size that is
                  // cheap, and it is the first thing to bake into the asset
                  // if LO-5 (60fps during listening) ever fails. The glow's
                  // scale is constant, so a pre-blurred emission map would be
                  // visually exact.
                  child: RepaintBoundary(
                    child: Opacity(
                      opacity: widget.phase.glow,
                      child: Transform.scale(
                        scale: OrbListening.glowScale,
                        child: ImageFiltered(
                          // The design's `filter:blur(34px)`, scaled to this
                          // orb. A CSS blur length *is* the standard
                          // deviation, and it was authored on a 214px orb,
                          // so on 168px it is 34 * 168/214 ~= 27.
                          //
                          // This was 17, which left the emission map's large
                          // blobs visible, so the glow read as a bright
                          // textured sheet behind the orb rather than light
                          // coming off it. Inside the 1.6x scale, as in CSS,
                          // where a filter is applied before a transform.
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: OrbListening.glowBlur(widget.size),
                            sigmaY: OrbListening.glowBlur(widget.size),
                            tileMode: TileMode.decal,
                          ),
                          // Clipped to a circle *inside* the blur, so the
                          // blur softens a round edge.
                          //
                          // Without the clip this was the emission image
                          // drawn into a square box — and a blurred square
                          // turning at 1.6x still shows its corners sweeping
                          // round behind the orb. The design's glow carries
                          // `border-radius:50%`; the clip is that. Inside
                          // the filter rather than outside it, because
                          // clipping after the blur would cut the soft falloff
                          // off into a hard disc.
                          child: ClipOval(
                            child: SizedBox.square(
                              dimension: widget.size * OrbListening.glowInset,
                              child: const _Emission(saturation: 1.2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // The emitted ring. Design: `@keyframes pulseRing` —
                // opacity .55 to 0 while scaling .94 to 1.22, then held at
                // zero.
                //
                // The hold is what makes it a *pulse*: without the dead
                // last third the rings run continuously and read as a
                // static halo, which is the one thing a pulse must not look
                // like.
                ValueListenableBuilder<double>(
                  valueListenable: _ring,
                  builder: (context, t, _) {
                    // `<sc-if value="{{ v2HasMatches }}">` — the design emits
                    // rings only once there is something to show for them,
                    // so the ring means "found", not "awake".
                    if (!widget.hasMatches || t >= 0.7) {
                      return const SizedBox.shrink();
                    }
                    final progress = t / 0.7;
                    return Opacity(
                      opacity: 0.55 * (1 - progress),
                      child: Container(
                        width: widget.size * (0.94 + 0.28 * progress),
                        height: widget.size * (0.94 + 0.28 * progress),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.accent, width: 1.2),
                        ),
                      ),
                    );
                  },
                ),

                // The travelling ring. One revolution per swirl period, so its
                // speed is the phase readout you can read from across a room.
                ValueListenableBuilder<double>(
                  valueListenable: _swirl,
                  builder: (context, phase, _) => Transform.rotate(
                    angle: phase * 2 * math.pi,
                    child: CustomPaint(
                      size: Size.square(widget.size * 1.24),
                      painter: _RingPainter(
                        // The accent with a white highlight travelling
                        // through it — the mark's own two colours, moving.
                        // v2 swept three hues here; v3 has one accent, and
                        // the highlight is what keeps the ring from reading
                        // as a flat circle.
                        colors: [p.accent, p.textPrimary, p.accent],
                      ),
                    ),
                  ),
                ),

                // The sphere.
                //
                // At rest this is the same rendered artwork as the launcher
                // icon and the splash, so the mark is one thing everywhere.
                // While listening it becomes the amplitude strip, dissolving
                // across the two whenever the phase changes.
                //
                // Drawn unrotated, exactly where the resting sphere is
                // drawn. The specular highlight and the off-centre core are
                // lighting, and lighting does not turn with the object — a
                // rotating sphere would read as a spinning marble. Only the
                // ring rotates, as it always has.
                AnimatedBuilder(
                  animation: Listenable.merge([_level, _strip]),
                  builder: (context, _) => _Sphere(
                    size: widget.size,
                    strip: _strip.value,
                    level: _level.value,
                    decodeWidth: _decodeWidth,
                    swirl: _swirl,
                    breathe: _breathe,
                  ),
                ),
              ],
            ),
          ),
          builder: (context, level, child) {
            final sx = 1 + OrbListening.squashMax * level;
            return Transform.scale(
              scaleX: sx,
              // The reciprocal, not `2 - sx`: volume-preserving, so the orb
              // reads as an incompressible thing being squeezed rather than
              // a rectangle being resized.
              scaleY: 1 / sx,
              alignment: Alignment.center,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// The emission texture, saturated the way the design saturates it.
///
/// One widget for both swirls because they are the same file at different
/// blurs — which is the whole reason the orb's inside and its glow look like
/// the same object lit from within rather than two effects stacked.
class _Emission extends StatelessWidget {
  const _Emission({required this.saturation});

  final double saturation;

  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: ColorFilter.matrix(_saturate(saturation)),
    child: Image.asset(
      OrbListening.emission,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
  );

  /// A saturation matrix, as CSS `filter: saturate(n)` defines it.
  static List<double> _saturate(double s) {
    const lr = 0.213, lg = 0.715, lb = 0.072;
    return <double>[
      lr + s * (1 - lr), lg * (1 - s), lb * (1 - s), 0, 0, //
      lr * (1 - s), lg + s * (1 - lg), lb * (1 - s), 0, 0, //
      lr * (1 - s), lg * (1 - s), lb + s * (1 - lb), 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}

/// The sphere layer: resting artwork, amplitude strip, or a blend of both.
class _Sphere extends StatelessWidget {
  const _Sphere({
    required this.size,
    required this.strip,
    required this.level,
    required this.decodeWidth,
    required this.swirl,
    required this.breathe,
  });

  final double size;

  /// 0 = resting sphere only, 1 = strip only, between = dissolving.
  final double strip;

  /// Smoothed microphone level, 0-1.
  final double level;

  /// Physical pixels to decode the strip frames at.
  final int decodeWidth;

  /// The accumulators themselves, not their values.
  ///
  /// Passed as listenables so the swirl and the breathe rebuild only their
  /// own layers. Handing in `swirl.value` would force this whole widget —
  /// resting sphere, five strip frames and all — to rebuild on the swirl's
  /// clock, sixty times a second.
  final ValueListenable<double> swirl;
  final ValueListenable<double> breathe;

  @override
  Widget build(BuildContext context) {
    // `level * 4` over five frames: 0 lands on level_0, 1 on level_4.
    final position = level.clamp(0.0, 1.0) * (OrbListening.frames - 1);
    final lower = position.floor();
    final upper = position.ceil();
    final blend = position - lower;

    // The breathe, on the sphere itself. Design: `animation:breathe` on the
    // sphere body, scale(1) -> scale(1.05). The app used to breathe only the
    // glow, so the halo pulsed around a ball that never moved.
    return ValueListenableBuilder<double>(
      valueListenable: breathe,
      builder: (context, phase, child) {
        final t = Curves.easeInOut.transform(
          phase < 0.5 ? phase * 2 : (1 - phase) * 2,
        );
        return Transform.scale(
          scale: 1 + OrbListening.breatheScale * t,
          child: child,
        );
      },
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (strip < 1)
                Opacity(
                  opacity: 1 - strip,
                  child: HawkOrb(size: size, semanticLabel: null),
                ),
              if (strip > 0)
                Opacity(
                  opacity: strip,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Frame(index: lower, decodeWidth: decodeWidth),
                      // The neighbour on top at the fractional part. Five
                      // frames stepped without this would pop four times
                      // across a single loud syllable.
                      if (upper != lower && blend > 0)
                        Opacity(
                          opacity: blend,
                          child: _Frame(index: upper, decodeWidth: decodeWidth),
                        ),
                    ],
                  ),
                ),

              // The swirl: the thing that actually makes the orb move.
              //
              // Design: `inset:-24%`, `filter:blur(3px) saturate(1.25)`,
              // `animation:swirl` — clockwise, scaling 1.25 -> 1.45 -> 1.25
              // over one revolution, clipped by the sphere. The layer is far
              // larger than the circle, so turning it drags fresh texture
              // across the aperture: the inside of the ball churns rather
              // than a disc spinning in place.
              //
              // This was the missing piece. The sphere is a static render, and
              // every motion layer the app had sat *around* it — an arc, a
              // glow, a ring — so the ball itself never moved at all.
              IgnorePointer(
                child: Opacity(
                  opacity: OrbListening.innerOpacity,
                  child: ValueListenableBuilder<double>(
                    valueListenable: swirl,
                    builder: (context, turns, child) {
                      // Scale rides the same clock as the rotation, peaking
                      // half way round, exactly as the keyframes place it.
                      final wave = Curves.easeInOut.transform(
                        turns < 0.5 ? turns * 2 : (1 - turns) * 2,
                      );
                      final scale =
                          OrbListening.innerScaleMin +
                          (OrbListening.innerScaleMax -
                                  OrbListening.innerScaleMin) *
                              wave;
                      return Transform.rotate(
                        angle: turns * 2 * math.pi,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    // A RepaintBoundary so the image draw is recorded once.
                    // The 1.5-sigma blur is still applied per frame at
                    // composite time; at this radius that is negligible.
                    child: RepaintBoundary(
                      child: OverflowBox(
                        maxWidth: size * OrbListening.innerInset,
                        maxHeight: size * OrbListening.innerInset,
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 1.5,
                            sigmaY: 1.5,
                            tileMode: TileMode.decal,
                          ),
                          child: SizedBox.square(
                            dimension: size * OrbListening.innerInset,
                            child: const _Emission(saturation: 1.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One strip frame.
class _Frame extends StatelessWidget {
  const _Frame({required this.index, required this.decodeWidth});

  final int index;

  /// Physical pixels to decode at. See `_VoiceOrbState._decodeWidth`.
  final int decodeWidth;

  @override
  Widget build(BuildContext context) => Image(
    // `ResizeImage`, not the raw asset: five 768px frames decode to about
    // 11.8 MB held for the whole session, and the orb is ~170 logical
    // points. Decoding at the size actually drawn cuts that by roughly the
    // square of the ratio.
    //
    // The width has to match the one `precacheImage` used, because it is
    // part of the provider's cache key — a mismatch decodes twice and
    // precaches nothing.
    image: ResizeImage(
      AssetImage(OrbListening.frame(index)),
      width: decodeWidth,
    ),
    fit: BoxFit.cover,
    // Same as the resting sphere: low-quality sampling bands badly across a
    // smooth gradient.
    filterQuality: FilterQuality.medium,
    // No blink when the frame index changes mid-utterance.
    gaplessPlayback: true,
    excludeFromSemantics: true,
  );
}

/// A single arc, not a full circle: a closed ring reads as a progress
/// indicator, and this is not measuring anything.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.colors});

  /// Tail to head. The arc fades in as it goes, so the last colour is the
  /// one that reads — which is why the brightest hue goes last.
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sweep = math.pi * 0.42;

    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + sweep,
          colors: [
            colors.first.withValues(alpha: 0),
            for (final c in colors.skip(1)) c.withValues(alpha: 0.55),
            colors.last.withValues(alpha: 0.95),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => !listEquals(old.colors, colors);
}

/// The seven bars under the orb while listening.
class VoiceBars extends StatefulWidget {
  const VoiceBars({required this.active, this.level = 0, super.key});

  final bool active;

  /// 0–1 from the microphone. Scales the bars' travel, so they respond to
  /// how loudly somebody is actually speaking rather than animating a fixed
  /// loop that looks the same in silence.
  final double level;

  @override
  State<VoiceBars> createState() => _VoiceBarsState();
}

class _VoiceBarsState extends State<VoiceBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  /// The design's own bar heights, in the design's own order.
  ///
  /// `14 · 26 · 38 · 20 · 32 · 12 · 22`, straight off screen 1N. They are not
  /// a curve and not symmetrical, which is the point — a meter whose bars
  /// rise and fall in a neat arc reads as an equaliser graphic, and this is
  /// meant to read as somebody's voice.
  static const _heights = [14.0, 26.0, 38.0, 20.0, 32.0, 12.0, 22.0];

  /// Which bars are lit.
  ///
  /// The design accents the four in the middle and leaves the outer three in
  /// [AppPalette.border]. So the meter spends the accent the way the rest of
  /// v3 does: on the live part, once, with the quiet part still visible
  /// rather than hidden.
  static const _lit = [false, true, true, true, true, false, false];

  /// Fixed offsets rather than random: `Math.random` per frame makes the bars
  /// jitter incoherently, which looks like noise instead of a voice.
  static const _phase = [0.0, 0.35, 0.7, 0.15, 0.85, 0.5, 0.25];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // How far the bars travel. Silence still breathes a little — a meter
    // frozen flat while a microphone is open looks like a meter that has
    // stopped working, not like a room that has gone quiet.
    final amplitude = 0.42 + 0.58 * widget.level.clamp(0.0, 1.0);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.active ? 1 : 0,
      child: SizedBox(
        // `height:44` on 1N. Fixed, so the orb above never moves when the
        // bars do.
        height: 44,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final (i, offset) in _phase.indexed)
                Padding(
                  // `gap:4` between 3px bars.
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 3,
                    height:
                        _heights[i] *
                        (1 -
                            amplitude *
                                0.5 *
                                (1 -
                                    math.sin(
                                      (_c.value + offset) * 2 * math.pi,
                                    ))),
                    decoration: BoxDecoration(
                      color: _lit[i] ? p.accent : p.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
