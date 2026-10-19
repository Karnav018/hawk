import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'eye_pose.dart';

/// The eye, drawn with ordinary canvas calls instead of the shader.
///
/// Two jobs, and the second is the one that justifies the file:
///
///  1. **Tests.** `flutter test` has no GPU, so `FragmentProgram` never
///     resolves there. Without this, every widget test touching a screen with
///     an orb on it would render nothing and assert nothing.
///  2. **The first frame.** Loading the shader is a real await. For the few
///     frames before it lands, a hole where the app's centrepiece goes is
///     worse than an approximation of it.
///
/// It is an approximation on purpose. The wobble and the wave's noise field
/// are per-pixel work that a path cannot do; the bands here are straight and
/// the outline is smooth. Everything that carries *meaning* — how open the
/// lids are, where the gaze points, whether the wave has taken the eye, the
/// brow — is exact, because that is what a test asserts and what a user
/// reads in the first 100ms.
class EyeFallbackPainter extends CustomPainter {
  const EyeFallbackPainter({required this.pose, required this.accent});

  final EyePose pose;
  final Color accent;

  /// Enough segments that the superellipse reads as a curve at 236px.
  static const _segments = 160;

  /// Box coordinate (-1.3..1.3, z up) to canvas pixel.
  Offset _px(Size size, double x, double z) => Offset(
    (x / eyeBoxUnits + 0.5) * size.width,
    (0.5 - z / eyeBoxUnits) * size.height,
  );

  /// Eye-space to box-space: the whole eye scales and shifts as one object,
  /// exactly as the shader's `x = (x - loc_x) / s` does in reverse.
  Offset _toBox(double x, double z) =>
      Offset(x * pose.scale + pose.locX, z * pose.scale + pose.locZ);

  /// The asymmetric superellipse `(|x|/a)^n + (|z|/b)^n = 1`, sampled.
  ///
  /// `b` differs above and below the axis — that asymmetry is the whole
  /// expression system. A squint is not a smaller eye, it is a lower lid.
  Path _lids(Size size, double grow) {
    final a = math.max(pose.eyeW + grow, 0.02);
    final top = math.max(pose.eyeTop + grow, 0.003);
    final bot = math.max(-pose.eyeBot + grow, 0.003);
    final e = 2 / math.max(pose.eyeN, 0.5);

    final path = Path();
    for (var i = 0; i <= _segments; i++) {
      final t = 2 * math.pi * i / _segments;
      final c = math.cos(t);
      final s = math.sin(t);
      final x = a * (c.isNegative ? -1 : 1) * math.pow(c.abs(), e);
      final z = (s.isNegative ? -bot : top) * math.pow(s.abs(), e);
      final b = _toBox(x.toDouble(), z.toDouble());
      final p = _px(size, b.dx, b.dy);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// The accent disc's centre and radii, foreshortened by the gaze.
  ({Offset c, double rx, double rz}) _disc(Size size) {
    final unit = size.width / eyeBoxUnits;
    final cx = pose.lookX * 0.38;
    final cz = pose.lookZ * 0.22;
    final r = math.max(pose.discR, 0.02);
    final b = _toBox(cx, cz);
    return (
      c: _px(size, b.dx, b.dy),
      rx: r * (1 - 0.3 * pose.lookX.abs()) * pose.scale * unit,
      rz: r * (1 - 0.3 * pose.lookZ.abs()) * pose.scale * unit,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    // One layer for the whole eye, because the pupil is a *hole*: in the
    // shader the pupil region ends up with alpha 0, which on the app's ground
    // reads as black. Clearing without a layer would punch through to
    // whatever is behind the widget instead.
    canvas.saveLayer(Offset.zero & size, Paint());

    final sclera = _lids(size, 0);

    // Outline ring: the gap-sized shape subtracted from the full one.
    if (pose.ringW > 0.001) {
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          _lids(size, pose.ringGap + pose.ringW),
          _lids(size, pose.ringGap),
        ),
        white,
      );
    }

    canvas.drawPath(sclera, white);

    // The wave wipes radially out from the pupil, so it is a circle that
    // grows with `wave` rather than a crossfade.
    final unit = size.width / eyeBoxUnits;
    final wipe = pose.wave > 0.001 ? pose.wave * 1.45 * unit : 0.0;

    if (wipe > 0) {
      canvas.save();
      canvas.clipPath(sclera);
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: _px(size, 0, 0), radius: wipe)),
      );
      // Erase the troughs, leaving the bands. Straight lines here; the
      // shader bends them through a noise field.
      final period = eyeBoxUnits / math.max(pose.waveBands, 1) * unit;
      final clear = Paint()..blendMode = BlendMode.clear;
      final offset = (pose.waveFlow % 1.0) * period;
      for (var y = -period; y < size.height + period; y += period) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            y + offset,
            size.width,
            period * (1 - pose.waveFill),
          ),
          clear,
        );
      }
      canvas.restore();
    }

    // Disc, pupil and notch. All three vanish under the wave — a visible
    // pupil beneath moving bands reads as a second object.
    if (pose.discR > 0.02 && wipe <= 0) {
      final d = _disc(size);
      canvas.save();
      canvas.clipPath(sclera);

      canvas.drawOval(
        Rect.fromCenter(center: d.c, width: d.rx * 2, height: d.rz * 2),
        Paint()..color = accent,
      );

      // The pupil is cleared, not painted: see the saveLayer above.
      final pf = math.max(pose.pupilF, 0.02);
      canvas.drawOval(
        Rect.fromCenter(
          center: d.c,
          width: d.rx * 2 * pf,
          height: d.rz * 2 * pf,
        ),
        Paint()..blendMode = BlendMode.clear,
      );

      if (pose.notchR > 0.001) {
        final nb = _toBox(
          pose.lookX * 0.38 - pose.notchOff * pose.discR,
          pose.lookZ * 0.22 + pose.notchOff * pose.discR * 0.8,
        );
        canvas.drawCircle(
          _px(size, nb.dx, nb.dy),
          pose.notchR * pose.discR * pose.scale * unit,
          white,
        );
      }
      canvas.restore();
    }

    if (pose.browShow > 0.001) _brow(canvas, size, white);

    if (pose.spark > 0.001) _sparkle(canvas, size, white);

    canvas.restore();
  }

  /// A tapered stroke on a parabola, rotated about (0, brow_z).
  ///
  /// `browTh` is a HALF width — the trap called out in the handoff. The
  /// stroke is built as two edges offset by ±th, not one line of width th.
  void _brow(Canvas canvas, Size size, Paint white) {
    final ct = math.cos(pose.browTilt);
    final st = math.sin(pose.browTilt);
    final len = math.max(pose.browLen, 0.02);

    Offset at(double u, double sign) {
      final taper = 1 - (u / len) * (u / len);
      final th = pose.browTh * pose.browShow * math.sqrt(math.max(0, taper));
      final v = pose.browArch * u * u + sign * th;
      // Rotate back out of brow space, then lift to brow_z.
      final x = u * ct - v * st;
      final z = u * st + v * ct + pose.browZ;
      final b = _toBox(x, z);
      return _px(size, b.dx, b.dy);
    }

    final path = Path();
    const n = 40;
    for (var i = 0; i <= n; i++) {
      final p = at(-len + 2 * len * i / n, 1);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (var i = n; i >= 0; i--) {
      final p = at(-len + 2 * len * i / n, -1);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), white);
  }

  /// The astroid twinkle, upper right.
  void _sparkle(Canvas canvas, Size size, Paint white) {
    final unit = size.width / eyeBoxUnits;
    final s = math.max(pose.sparkSize * pose.spark, 0.02) * unit;
    final c = _px(size, pose.sparkX, pose.sparkZ);
    final path = Path();
    const n = 64;
    for (var i = 0; i <= n; i++) {
      final t = 2 * math.pi * i / n;
      // |x|^(2/3) + |z|^(2/3) = 1 in parametric form.
      final x =
          s *
          math.pow(math.cos(t).abs(), 3) *
          (math.cos(t).isNegative ? -1 : 1);
      final z =
          s *
          math.pow(math.sin(t).abs(), 3) *
          (math.sin(t).isNegative ? -1 : 1);
      final p = Offset(c.dx + x.toDouble(), c.dy - z.toDouble());
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), white);
  }

  @override
  bool shouldRepaint(EyeFallbackPainter old) =>
      old.pose != pose || old.accent != accent;
}

/// Draws the compiled shader, one `drawRect` with 45 uniforms.
///
/// **The shader is owned by the widget, not created here.** This painter used
/// to call `program.fragmentShader()` per frame and `dispose()` it on the
/// next line, which drew nothing at all on device — a blank 224px hole where
/// the app's centrepiece goes, with no error anywhere.
///
/// `paint` does not draw. It *records* into a display list, and the raster
/// thread replays that list later. Disposing the shader at the end of `paint`
/// frees the native object before the rasterizer has touched it, so the
/// `drawRect` resolves to nothing. Tests never caught it because tests run
/// the fallback painter — there is no GPU to hand the program to.
///
/// So: one shader per widget, created when the program resolves, uniforms
/// rewritten each frame, disposed in `State.dispose`.
class EyeShaderPainter extends CustomPainter {
  const EyeShaderPainter({
    required this.shader,
    required this.pose,
    required this.accent,
  });

  final ui.FragmentShader shader;
  final EyePose pose;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final floats = pose.toFloats(size, accent);
    // Index order is the shader's *declaration* order. `toFloats` is written
    // against the same list; `uniformCount` is pinned by a test because a
    // one-index slip renders a plausible eye with the wrong proportions
    // rather than failing.
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(EyeShaderPainter old) =>
      old.pose != pose || old.accent != accent || old.shader != shader;
}
