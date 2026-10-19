#version 460 core
#include <flutter/runtime_effect.glsl>

// The Hawk eye — ported 1:1 from design/blender/HANDOFF_eye_orb.md.
//
// Draws in the rig's camera frame: a square box 2.6 units across, coordinates
// running -1.3..1.3. The widget reserves the whole box; nothing here may be
// clipped, because the brow reaches 1.22 and decorations 1.27.
//
// TWO TRAPS, both from the handoff, both load-bearing:
//
//  1. Never `x / (k + 0.0001)` as a "safe" denominator. At k = 0 the power
//     overflows and the mask floods to 1 — a white screen, not a missing
//     shape. Sizes are floored with `max(k, 0.02)` and the shape is gated
//     with `smoothstep(0.0, 0.05, k)` so it fades out instead.
//  2. `brow_th` is a HALF width. The stroke is twice it.
//
// Every edge is a signed-distance test softened with `fwidth`, never a fixed
// width, so a 34px render and a 236px one both get a one-pixel edge.

precision highp float;

// Packed four to a vec4, not one declaration per knob.
//
// Metal gives every uniform DECLARATION its own buffer binding and accepts
// indices 0..30 only. Forty-three scalars is forty-four bindings, and the
// device refused the program outright:
//
//   'buffer' attribute parameter is out of bounds: must be between 0 and 30
//
// The host build was green throughout, because `impellerc` validates the
// GLSL and the SkSL translation — not Metal's binding budget. So this could
// only ever have been caught by running it. Twelve vec4s is twelve bindings.
//
// Dart does not see the packing. `setFloat(i)` is a flat offset across all
// uniforms in declaration order, so `EyePose.toFloats` keeps exactly the
// order it had. u11.yzw are padding: 12 * 4 = 48 slots for 45 floats.
uniform vec4 u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11;

out vec4 fragColor;

const float PI = 3.14159265359;

// ---------------------------------------------------------------- noise ---
//
// Verbatim from `design/blender/export/orb_noise.glsl`, not reinvented here.
//
// This file previously carried a hash I made up. It compiled and it looked
// like noise — which is precisely the problem: the wobble and the wave would
// have had a different *character* from the rig with nothing on screen to
// say so. Blender's Noise Texture is Perlin; this is hash-based value noise
// with a quintic fade, which the design session matched to the scales the
// orb actually uses (wobble at 4x, wave at wave_scale). No bitwise ops and
// no integer tricks, so Impeller accepts it.

float hash3(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float n000 = hash3(i + vec3(0, 0, 0)), n100 = hash3(i + vec3(1, 0, 0));
  float n010 = hash3(i + vec3(0, 1, 0)), n110 = hash3(i + vec3(1, 1, 0));
  float n001 = hash3(i + vec3(0, 0, 1)), n101 = hash3(i + vec3(1, 0, 1));
  float n011 = hash3(i + vec3(0, 1, 1)), n111 = hash3(i + vec3(1, 1, 1));
  float x00 = mix(n000, n100, u.x), x10 = mix(n010, n110, u.x);
  float x01 = mix(n001, n101, u.x), x11 = mix(n011, n111, u.x);
  return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

/// Two channels, for x and z — Blender used the noise's R and G.
vec2 wobbleNoise(vec2 xz) {
  return vec2(vnoise3(vec3(xz * 4.0, 0.0)),
              vnoise3(vec3(xz * 4.0, 7.31))) - 0.5;
}

/// Blender's 4D noise (x, z, 0; W = wave_t), with time folded into z.
float waveNoise(vec2 xz, float scale, float t) {
  return vnoise3(vec3(xz * scale, t));
}

/// `inside(f)` where f is a normalised implicit ( < 1 is inside ), softened
/// by the screen-space derivative so the edge is one pixel at any size.
float inside(float f) {
  float w = max(fwidth(f), 1e-5);
  return 1.0 - smoothstep(1.0 - w, 1.0 + w, f);
}

/// A shape that vanishes rather than floods when its size goes to zero.
float gate(float k) { return smoothstep(0.0, 0.05, k); }

void main() {
  // Unpacked in `EyePose.toFloats` order. Read this against that list; the
  // two are the contract, and a test pins the count and the binding budget.
  vec2  uSize     = u0.xy;
  float eye_w     = u0.z,  eye_top   = u0.w;
  float eye_bot   = u1.x,  eye_n     = u1.y,  ring_gap  = u1.z, ring_w = u1.w;
  float wobble    = u2.x,  scale     = u2.y,  loc_x     = u2.z, loc_z  = u2.w;
  float look_x    = u3.x,  look_z    = u3.y,  disc_r    = u3.z, pupil_f = u3.w;
  float notch_r   = u4.x,  notch_off = u4.y,  brow_show = u4.z, brow_z = u4.w;
  float brow_tilt = u5.x,  brow_arch = u5.y,  brow_th   = u5.z, brow_len = u5.w;
  float wave      = u6.x,  wave_bands = u6.y, wave_fill = u6.z, wave_amp = u6.w;
  float wave_flow = u7.x,  wave_t    = u7.y,  wave_scale = u7.z, dash   = u7.w;
  float dash_w    = u8.x,  spark     = u8.y,  spark_x   = u8.z, spark_z = u8.w;
  float spark_size = u9.x, lines     = u9.y,  lines_w   = u9.z, drop   = u9.w;
  float drop_x    = u10.x, drop_z    = u10.y;
  float accent_r  = u10.z, accent_g  = u10.w, accent_b  = u11.x;

  // Box coordinates: -1.3 .. 1.3, z up.
  vec2 uv = FlutterFragCoord().xy / uSize;
  float half_box = 0.5 * 2.6;
  float x = (uv.x - 0.5) * 2.6;
  float z = (0.5 - uv.y) * 2.6;

  // The whole eye breathes and bobs as one object.
  float s = max(scale, 0.05);
  x = (x - loc_x) / s;
  z = (z - loc_z) / s;

  // Hand-drawn wobble, on the eye shapes only.
  // Not `n`: that name is the superellipse exponent forty lines down, and
  // shadowing it here compiles into a very confusing eye.
  vec2 wob = wobbleNoise(vec2(x, z));
  float X = x + wobble * wob.x;
  float Z = z + wobble * wob.y;

  // ------------------------------------------------------ eye and ring ---
  // Asymmetric superellipse: eye_top above the axis, -eye_bot below.
  float b = Z >= 0.0 ? eye_top : -eye_bot;
  float n = max(eye_n, 0.5);

  float S0 = pow(abs(X) / max(eye_w, 0.02), n)
           + pow(abs(Z) / max(b, 0.003), n);
  float S1 = pow(abs(X) / max(eye_w + ring_gap, 0.02), n)
           + pow(abs(Z) / max(b + ring_gap, 0.003), n);
  float S2 = pow(abs(X) / max(eye_w + ring_gap + ring_w, 0.02), n)
           + pow(abs(Z) / max(b + ring_gap + ring_w, 0.003), n);

  float lids = gate(b);
  float sclera = inside(S0) * lids;
  float ring = max(0.0, inside(S2) - inside(S1)) * lids;

  // ------------------------------------------------------- accent disc ---
  // Foreshortened with the gaze, so looking aside squashes it.
  // Two scalars, not a vec2. The handoff writes this as `c = (look_x*.38,
  // look_z*.22)` and then reads `c.z`, because it is thinking in the rig's
  // (x, z) box coordinates where z is up. GLSL only has `.x` and `.y` on a
  // vec2, so `c.z` is a compile error — and naming the second component `y`
  // would put the one axis this file calls `z` under a different letter for
  // six lines. Scalars keep the handoff's names and remove the trap.
  float c_x = look_x * 0.38;
  float c_z = look_z * 0.22;
  float rr = max(disc_r, 0.02);
  float rx = rr * (1.0 - 0.3 * abs(look_x));
  float rz = rr * (1.0 - 0.3 * abs(look_z));
  float dxn = (X - c_x) / max(rx, 0.02);
  float dzn = (Z - c_z) / max(rz, 0.02);
  float dd = dxn * dxn + dzn * dzn;

  float disc0 = sclera * inside(dd) * gate(disc_r);
  float pf = max(pupil_f * pupil_f, 0.0004);
  float pupil = disc0 * inside(dd / pf);

  float nx = X - (c_x - notch_off * disc_r);
  float nz = Z - (c_z + notch_off * disc_r * 0.8);
  float nrad = max(notch_r * disc_r, 0.005);
  float notch0 = disc0 * inside((nx * nx + nz * nz) / (nrad * nrad))
               * gate(notch_r * disc_r);

  // -------------------------------------------------------------- wave ---
  // The first orb's bands, wiped radially out from the pupil.
  float w4 = (waveNoise(vec2(x, z), wave_scale, wave_t) - 0.5) * wave_amp;
  float u = z * wave_bands * 0.5 + w4 + wave_flow;
  float sv = sin(2.0 * PI * u);
  float thresh = cos(PI * wave_fill);
  float band = smoothstep(thresh - 0.08, thresh + 0.08, sv);

  float r = length(vec2(x, z));
  float wave_eff = 1.0 - smoothstep(wave * 1.45 - 0.12, wave * 1.45 + 0.12, r);
  wave_eff *= step(0.001, wave);

  float sclera_w = sclera * ((1.0 - wave_eff) + wave_eff * band);
  float disc = disc0 * (1.0 - wave_eff);
  float notch = notch0 * (1.0 - wave_eff);
  pupil *= (1.0 - wave_eff);

  // -------------------------------------------------------------- brow ---
  // A tapered stroke on a parabola, rotated about (0, brow_z).
  float ct = cos(-brow_tilt);
  float st = sin(-brow_tilt);
  float bx = X * ct - (Z - brow_z) * st;
  float bz = X * st + (Z - brow_z) * ct;
  float dv = abs(bz - brow_arch * bx * bx);
  float taper = 1.0 - (bx / max(brow_len, 0.02)) * (bx / max(brow_len, 0.02));
  float th = brow_th * brow_show * sqrt(max(0.0, taper));
  float brow = (1.0 - smoothstep(th - max(fwidth(dv), 1e-5),
                                 th + max(fwidth(dv), 1e-5), dv))
             * step(0.001, brow_show) * step(0.0, taper);

  // ------------------------------------------------------- decorations ---
  float ang = atan(z, x);
  float ring_r = r;

  // Three dashes at 32 / 58 / 84 degrees, r 1.05..1.25.
  float dashes = 0.0;
  for (int i = 0; i < 3; i++) {
    float a = radians(32.0 + 26.0 * float(i));
    float da = abs(ang - a);
    float band_w = max(dash_w * dash, 0.0005);
    float hit = (1.0 - smoothstep(band_w * 0.5, band_w, abs(sin(da))* ring_r))
              * step(1.05, ring_r) * (1.0 - step(1.25, ring_r));
    dashes = max(dashes, hit);
  }
  dashes *= step(0.001, dash);

  // Astroid sparkle.
  float ss = max(spark_size * spark, 0.02);
  float sdx = abs((x - spark_x) / ss);
  float sdz = abs((z - spark_z) / ss);
  float astro = pow(sdx, 0.6667) + pow(sdz, 0.6667);
  float sparkle = inside(astro) * step(0.001, spark);

  // Eight-stroke burst every 45 degrees, r 1.08..1.25.
  float burst = 0.0;
  for (int i = 0; i < 8; i++) {
    float a = radians(45.0 * float(i));
    float da = abs(ang - a);
    float band_w = max(lines_w * lines, 0.0005);
    float hit = (1.0 - smoothstep(band_w * 0.5, band_w, abs(sin(da)) * ring_r))
              * step(1.08, ring_r) * (1.0 - step(1.25, ring_r));
    burst = max(burst, hit);
  }
  burst *= step(0.001, lines);

  // A drop: circle plus a cone above it.
  float drad = max(0.10 * drop, 0.02);
  float ddx = (x - drop_x) / drad;
  float ddz = (z - drop_z) / drad;
  float dropm = inside(ddx * ddx + ddz * ddz) * step(0.001, drop);

  // ------------------------------------------------------- composition ---
  float white = min(1.0,
      max(0.0, sclera_w - disc) + notch + ring + brow
    + dashes + sparkle + burst + dropm);
  float accentmask = disc * (1.0 - pupil) * (1.0 - notch);

  float alpha = min(1.0, white + accentmask);
  vec3 colour = mix(vec3(1.0), vec3(accent_r, accent_g, accent_b), accentmask);

  // Premultiplied: Flutter composites shader output as premultiplied alpha,
  // and un-premultiplied colour fringes every soft edge against the ground.
  fragColor = vec4(colour * alpha, alpha);
}
