import 'dart:math' as math;
import 'dart:ui';

/// What the eye is doing. Owned by the orb, not by the voice layer.
///
/// `VoicePhase` maps 1:1 onto the first four; screen 1J asks for [indexing]
/// directly. Putting a fifth value on `VoicePhase` would have given
/// `VoiceCubit` a state it can never enter — 1J has no microphone anywhere
/// near it.
enum OrbState { ready, listening, retrieving, answered, indexing }

/// Every knob the eye has, at one instant.
///
/// A plain value type rather than uniforms scattered through the widget,
/// because the animation is **interpolation between poses**: each state is a
/// rest pose, transitions are [lerp] over a controller, and the shader is
/// handed the result. That split is what lets the whole thing be tested
/// without a GPU — the poses and the easing are ordinary Dart, and only the
/// drawing needs a device.
///
/// The field order here **is** the uniform order in `eye_orb.frag`. They are
/// written once, in [toFloats], against the same index list the shader
/// declares. Getting them out of step produces a plausible-looking eye with
/// the wrong proportions rather than an error, so the two are kept adjacent
/// and there is a test that pins the count.
class EyePose {
  const EyePose({
    this.eyeW = 1.0,
    this.eyeTop = 0.72,
    this.eyeBot = -0.72,
    this.eyeN = 2.3,
    this.ringGap = 0.06,
    this.ringW = 0.10,
    this.wobble = 0.012,
    this.scale = 1.0,
    this.locX = 0,
    this.locZ = 0,
    this.lookX = 0,
    this.lookZ = 0,
    this.discR = 0.48,
    this.pupilF = 0.5,
    this.notchR = 0.32,
    this.notchOff = 0.55,
    this.browShow = 0,
    this.browZ = 1.10,
    this.browTilt = 0,
    this.browArch = -0.3,
    this.browTh = 0.12,
    this.browLen = 0.6,
    this.wave = 0,
    this.waveBands = 5,
    this.waveFill = 0.42,
    this.waveAmp = 0.5,
    this.waveFlow = 0,
    this.waveT = 0,
    this.waveScale = 1.1,
    this.dash = 0,
    this.dashW = 0.07,
    this.spark = 0,
    this.sparkX = 0.98,
    this.sparkZ = 0.8,
    this.sparkSize = 0.22,
    this.lines = 0,
    this.linesW = 0.06,
    this.drop = 0,
    this.dropX = 1.12,
    this.dropZ = 0,
  });

  // Shape.
  final double eyeW, eyeTop, eyeBot, eyeN, ringGap, ringW, wobble, scale;
  final double locX, locZ;

  // Gaze and disc.
  final double lookX, lookZ, discR, pupilF, notchR, notchOff;

  // Brow. `browTh` is a HALF width — the stroke is twice this thick.
  final double browShow, browZ, browTilt, browArch, browTh, browLen;

  // Wave.
  final double wave, waveBands, waveFill, waveAmp, waveFlow, waveT, waveScale;

  // Decorations.
  final double dash, dashW, spark, sparkX, sparkZ, sparkSize;
  final double lines, linesW, drop, dropX, dropZ;

  /// The rest pose for a state, before any per-frame motion is layered on.
  ///
  /// [progress] only matters to [OrbState.indexing], where the lids *are* the
  /// progress indicator: `.3 + .42 * progress`, with anything from .98 read as
  /// fully open. The job sits at 0 through its whole `enumerating` phase — the
  /// longest part on a large Drive — which is why the floor is .3 and not 0.
  static EyePose rest(OrbState state, {double progress = 0}) {
    switch (state) {
      case OrbState.ready:
        return const EyePose(
          eyeTop: 0.72,
          eyeBot: -0.72,
          eyeN: 2.3,
          discR: 0.48,
          notchR: 0.32,
        );

      case OrbState.listening:
        // The lids round to a full circle and the disc all but vanishes: the
        // wave has taken the eye over, and a visible pupil under the bands
        // would read as a second object.
        return const EyePose(
          eyeTop: 1.0,
          eyeBot: -1.0,
          eyeN: 2.0,
          discR: 0.06,
          wave: 1,
          browShow: 1,
          browZ: 1.10,
          browArch: -0.3,
        );

      case OrbState.retrieving:
        // A squint with the gaze held up-right. It thinks; it does not read.
        return const EyePose(
          eyeTop: 0.32,
          eyeBot: -0.55,
          eyeN: 2.4,
          discR: 0.42,
          notchR: 0.30,
          lookX: 0.42,
          lookZ: 0.51,
          browShow: 1,
          browZ: 0.885,
          browTilt: 0.24,
          browArch: -0.1,
        );

      case OrbState.answered:
        return const EyePose(
          eyeTop: 0.74,
          eyeBot: -0.74,
          discR: 0.50,
          notchR: 0.36,
          browShow: 1,
          browArch: -0.35,
        );

      case OrbState.indexing:
        final open = progress >= 0.98 ? 1.0 : 0.3 + 0.42 * progress.clamp(0, 1);
        return EyePose(eyeTop: open, eyeBot: -open, discR: 0.46, notchR: 0.30);
    }
  }

  /// Linear blend, knob by knob. `t` is the controller's value.
  ///
  /// Every knob eases, including `wave` — except when reduce-motion is on,
  /// where the widget snaps rather than calling this.
  static EyePose lerp(EyePose a, EyePose b, double t) {
    double v(double x, double y) => x + (y - x) * t;
    return EyePose(
      eyeW: v(a.eyeW, b.eyeW),
      eyeTop: v(a.eyeTop, b.eyeTop),
      eyeBot: v(a.eyeBot, b.eyeBot),
      eyeN: v(a.eyeN, b.eyeN),
      ringGap: v(a.ringGap, b.ringGap),
      ringW: v(a.ringW, b.ringW),
      wobble: v(a.wobble, b.wobble),
      scale: v(a.scale, b.scale),
      locX: v(a.locX, b.locX),
      locZ: v(a.locZ, b.locZ),
      lookX: v(a.lookX, b.lookX),
      lookZ: v(a.lookZ, b.lookZ),
      discR: v(a.discR, b.discR),
      pupilF: v(a.pupilF, b.pupilF),
      notchR: v(a.notchR, b.notchR),
      notchOff: v(a.notchOff, b.notchOff),
      browShow: v(a.browShow, b.browShow),
      browZ: v(a.browZ, b.browZ),
      browTilt: v(a.browTilt, b.browTilt),
      browArch: v(a.browArch, b.browArch),
      browTh: v(a.browTh, b.browTh),
      browLen: v(a.browLen, b.browLen),
      wave: v(a.wave, b.wave),
      waveBands: v(a.waveBands, b.waveBands),
      waveFill: v(a.waveFill, b.waveFill),
      waveAmp: v(a.waveAmp, b.waveAmp),
      waveFlow: v(a.waveFlow, b.waveFlow),
      waveT: v(a.waveT, b.waveT),
      waveScale: v(a.waveScale, b.waveScale),
      dash: v(a.dash, b.dash),
      dashW: v(a.dashW, b.dashW),
      spark: v(a.spark, b.spark),
      sparkX: v(a.sparkX, b.sparkX),
      sparkZ: v(a.sparkZ, b.sparkZ),
      sparkSize: v(a.sparkSize, b.sparkSize),
      lines: v(a.lines, b.lines),
      linesW: v(a.linesW, b.linesW),
      drop: v(a.drop, b.drop),
      dropX: v(a.dropX, b.dropX),
      dropZ: v(a.dropZ, b.dropZ),
    );
  }

  EyePose copyWith({
    double? eyeTop,
    double? eyeBot,
    double? scale,
    double? locZ,
    double? lookX,
    double? lookZ,
    double? discR,
    double? browShow,
    double? browZ,
    double? browTilt,
    double? wave,
    double? waveAmp,
    double? waveFlow,
    double? waveT,
    double? spark,
  }) => EyePose(
    eyeW: eyeW,
    eyeTop: eyeTop ?? this.eyeTop,
    eyeBot: eyeBot ?? this.eyeBot,
    eyeN: eyeN,
    ringGap: ringGap,
    ringW: ringW,
    wobble: wobble,
    scale: scale ?? this.scale,
    locX: locX,
    locZ: locZ ?? this.locZ,
    lookX: lookX ?? this.lookX,
    lookZ: lookZ ?? this.lookZ,
    discR: discR ?? this.discR,
    pupilF: pupilF,
    notchR: notchR,
    notchOff: notchOff,
    browShow: browShow ?? this.browShow,
    browZ: browZ ?? this.browZ,
    browTilt: browTilt ?? this.browTilt,
    browArch: browArch,
    browTh: browTh,
    browLen: browLen,
    wave: wave ?? this.wave,
    waveBands: waveBands,
    waveFill: waveFill,
    waveAmp: waveAmp ?? this.waveAmp,
    waveFlow: waveFlow ?? this.waveFlow,
    waveT: waveT ?? this.waveT,
    waveScale: waveScale,
    dash: dash,
    dashW: dashW,
    spark: spark ?? this.spark,
    sparkX: sparkX,
    sparkZ: sparkZ,
    sparkSize: sparkSize,
    lines: lines,
    linesW: linesW,
    drop: drop,
    dropX: dropX,
    dropZ: dropZ,
  );

  /// The uniform payload, in the order `eye_orb.frag` declares.
  ///
  /// Index 0 and 1 are the widget size, which the shader needs for
  /// `FlutterFragCoord`. Everything after is this pose, then the accent.
  List<double> toFloats(Size size, Color accent) => <double>[
    size.width, size.height,
    // shape
    eyeW, eyeTop, eyeBot, eyeN, ringGap, ringW, wobble, scale, locX, locZ,
    // gaze and disc
    lookX, lookZ, discR, pupilF, notchR, notchOff,
    // brow
    browShow, browZ, browTilt, browArch, browTh, browLen,
    // wave
    wave, waveBands, waveFill, waveAmp, waveFlow, waveT, waveScale,
    // decorations
    dash, dashW, spark, sparkX, sparkZ, sparkSize,
    lines, linesW, drop, dropX, dropZ,
    // colour
    accent.r, accent.g, accent.b,
  ];

  /// How many floats [toFloats] produces. Pinned by a test, because a shader
  /// reading one index out of step renders a plausible eye with the wrong
  /// proportions rather than failing.
  static const uniformCount = 45;
}

/// The design's box: 2.6 units across, coordinates in -1.3..1.3.
///
/// Everything is reserved, not just the eye: the ring is 1.16 x 0.88 at rest
/// (77% of the width), the brow reaches 1.22, decorations 1.27, and a pop
/// scales by up to 1.08. Nothing may clip.
const double eyeBoxUnits = 2.6;

/// A small deterministic wander, so READY does not look frozen.
///
/// Derived from elapsed time rather than a random source: two orbs on screen
/// would otherwise drift apart, and a golden would never repeat.
({double x, double z}) readyWander(double seconds) =>
    (x: 0.2 * math.sin(seconds * 0.9), z: 0.06 * math.sin(seconds * 0.6 + 1.1));
