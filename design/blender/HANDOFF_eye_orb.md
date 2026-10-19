# Handoff: the Eye Orb replaces the orb (Blender -> Flutter)

From: the Blender/design session (knowra-94 [24ea36]). For: the Flutter implementation session (knowra-94 [4c14b3]).
Date: 2026-09-22. Approved by the user after verifying the listening transformation render.
Rig (source of truth for every number): `design/blender/orb_eye_cartoon_states.blend`, README text block inside.
Previews: `design/blender/previews_toon/` (stills sheets, per-state loops, `listening_wave_sequence.mp4`).

## Decisions

1. **The cartoon eye replaces the orb.** One widget, five states plus one exit clip, at every placement 190 px and up
   (home 224, listening 236, indexing 190). It replaces both `VoiceOrb` and `HawkOrb` there. The two-circle Hawk
   mark stays a separate object for logo placements (splash, sign-in header, greeting row) and the 34 px snack glyph.
2. **Delivery: fragment shader** (`FragmentProgram`, SkSL via impellerc) **plus a test-only fallback painter**
   (widget tests have no GPU). Every unknown is closed: `fwidth` verified under Impeller, uniforms are scalar floats,
   entry point is `#version 460 core` + `#include <flutter/runtime_effect.glsl>` + `FlutterFragCoord()`, register
   under `shaders:` in pubspec, load once with a future and draw the fallback meanwhile.
3. **Listening is the wave.** Entering LISTENING morphs the eye into wave bands (radial wipe from the pupil);
   the wave's amplitude follows the mic level. Leaving: successful release is cut short by navigation (no delay);
   the silent "never mind" plays LISTENING_OUT.
4. **Non-scanning gazes.** RETRIEVING thinks (gaze up-right, held); INDEXING opens its lids with progress. The
   SEARCHING / FOUND / SHOCKED clips are NOT in this handoff (see "Later").
5. **App mark: no change now.** Revisit once the eye is on device (it will read as a small eye by association).
6. **Indexing bar:** recommendation is to drop the 8 px bar and keep the numerals, since the lids are the
   glanceable indicator. Frontend's call; not a requirement of this handoff.

## Widget contract

```dart
enum OrbState { ready, listening, retrieving, answered, indexing }
// VoicePhase maps 1:1 onto the first four; screen 1J asks for indexing directly.
EyeOrb({ required OrbState state, required double size, double level = 0, double progress = 0,
         bool reduceMotion = false, Color accent })
```
- `level` 0..1 from `VoiceState.level` (already per-frame off the recogniser).
- `progress` 0..1 from `IndexProgressState.job.fraction` (indexing only).
- `accent` = the theme accent (six options, default #59d3ff). Everything else is white on transparency.
- Transitions are the widget's job: AnimationControllers ease the uniforms between poses. The shader infers nothing.
- Reduce motion: pin every knob to the state's rest pose (no blink, no wander, no beat) and SNAP `wave` 0->1 / 1->0.

## Layout

The shader draws in a square box = the rig's camera frame, 2.6 units across (coordinates -1.3..1.3). Reserve the
whole box; the eye's outline ring is 1.16 x 0.88 units at rest (77% of the box width), the brow reaches 1.22 when
shown, decorations reach 1.27, pops scale the eye by up to 1.08. Ground behind it: #0c0c0d. Nothing else is drawn
behind the eye (no halo, no ring, no shadow).

## Uniforms (all floats; pack accent as three)

Shape: `eye_w eye_top eye_bot eye_n ring_gap ring_w wobble scale loc_x loc_z`
Gaze/disc: `look_x look_z disc_r pupil_f notch_r notch_off`
Brow: `brow_show brow_z brow_tilt brow_arch brow_th brow_len`
Wave: `wave wave_bands wave_fill wave_amp wave_flow wave_t wave_scale`
Decorations: `dash dash_w spark spark_x spark_z spark_size lines lines_w drop drop_x drop_z`
Colour: `accent_r accent_g accent_b`. Plus `u_size` for fwidth-independent scaling if needed.

## The formula (port 1:1; x, z are box coordinates in -1.3..1.3)

```
// hand-drawn wobble on the eye shapes only
n   = noise3(4*(x,z)) - 0.5                     // two channels
X   = x + wobble*n.r ;  Z = z + wobble*n.g
// eye: asymmetric superellipse, b = eye_top above the axis, -eye_bot below
b   = Z >= 0 ? eye_top : -eye_bot
S(e)= (|X|/(eye_w+e))^eye_n + (|Z|/(max(b+e, 0.003)))^eye_n
sclera = inside(S(0));  ring = inside(S(ring_gap+ring_w)) - inside(S(ring_gap))     // inside(f) = 1 - step(f, 1)
// accent disc (iris+pupil in one), foreshortened with the gaze
c   = (look_x*0.38, look_z*0.22)
rx  = max(disc_r,.02)*(1-0.3*|look_x|) ; rz = max(disc_r,.02)*(1-0.3*|look_z|)
dd  = ((X-c.x)/rx)^2 + ((Z-c.z)/rz)^2
disc0 = sclera * inside(dd)
pupil = disc0 * inside(dd / max(pupil_f^2, .0004))
notch0= disc0 * inside( ((X - (c.x - notch_off*disc_r))^2 + (Z - (c.z + notch_off*disc_r*0.8))^2) / max(notch_r*disc_r,.005)^2 )
// wave layer (the first orb's bands), radial wipe from the pupil
w   = (noise4(wave_scale*(x,z), wave_t) - 0.5) * wave_amp
u   = z*wave_bands/2 + w + wave_flow ;  band = sin(2*pi*u) > cos(pi*wave_fill)        // soft edge +-0.08
wave_eff = 1 - smoothstep(wave*1.45-0.12, wave*1.45+0.12, length(x,z))
sclera_w = sclera * ((1-wave_eff) + wave_eff*band)
disc = disc0*(1-wave_eff) ; notch = notch0*(1-wave_eff)
// eyebrow: tapered stroke on a parabola, rotated by brow_tilt about (0, brow_z); brow_th is a HALF width
(u,v) = rotate(X, Z-brow_z, -brow_tilt) ; dv = |v - brow_arch*u^2|
th  = brow_th*brow_show*sqrt(max(0, 1-(u/brow_len)^2)) ; brow = (dv < th) * step(brow_show > 0)
// decorations (see README): dashes = 3 strokes at 32/58/84 deg, r 1.05..1.25, width dash_w*dash
//   spark = astroid |dx/s|^(2/3)+|dz/s|^(2/3) < 1, s = max(spark_size*spark,.02), gated by spark>0
//   burst = 8 strokes every 45 deg, r 1.08..1.25, width lines_w*lines ; drop = circle + cone at (drop_x, drop_z)
// composition
white = min(1, (sclera_w - disc) + notch + ring + brow + dashes + spark + burst + drop)
accentmask = disc*(1-pupil)*(1-notch)
alpha = min(1, white + accentmask) ; colour = mix(white, accent, accentmask)
```
Edges: every `inside`/`<` above is a signed-distance test with `fwidth` softness, never a fixed width.
Never use `x/(k+0.0001)` as a "safe" denominator: at k=0 the power overflows and the mask floods to 1. Floor sizes
with `max(k, 0.02)` and gate the shape with `smoothstep(0, 0.05, k)`.

## Rest poses per state (the values the widget eases between)

| knob | READY | LISTENING (wave) | RETRIEVING | ANSWERED | INDEXING |
|---|---|---|---|---|---|
| eye_top / eye_bot | .72 / -.72 | 1.0 / -1.0 | .32 / -.55 | .74 / -.74 | .3+.42*progress / mirror |
| eye_n | 2.3 | 2.0 | 2.4 | 2.3 | 2.3 |
| disc_r | .48 | .06 (hidden by wave) | .40-.44 | .50 | .44-.48 |
| pupil_f / notch_r / notch_off | .5 / .32 / .55 | - | .5 / .30 / .55 | .5 / .36 / .55 | .5 / .30 / .55 |
| look_x, look_z | wander +-.2 | 0 | (.35..0.5, .45..0.57) rolling | 0, 0 | 0, 0 |
| brow_show / brow_z / tilt / arch | 0 | 1 / 1.10 / 0 / -.3 | 1 / .85-.92 / .3-.18 / -.1 | 1 then 0 / 1.10 / 0 / -.35 | 0 |
| wave | 0 | 1 | 0 | 0 | 0 |
| wave_amp | - | 0.5 + 0.45*level | - | - | - |
| wave_flow / wave_t | - | -1.0/s, +0.35/s | - | - | - |
| scale breathe | 1.012 / 6 s | 1.0 | 1.03 / 2 s | 1.0 | 1.02 / 4 s + bob z +-.05 |
Constants: eye_w 1.0, ring_gap .06, ring_w .10, wobble .012, brow_th .12, brow_len .6, wave_bands 5, wave_fill .42,
wave_scale 1.1, dash_w .07, lines_w .06, spark_size .22 at (.98, .8), drop at x 1.12.

## Motion signatures (timings at 30 fps; all are knob keyframes, see the rig for exact curves)

- READY (6 s loop): double blink at 0.7 s (lids to .02 twice, 3 frames each), then look left (hold 1 s), centre,
  right (hold 1 s), centre; slow breathe.
- LISTENING enter (one-shot, 1.0 s): 0-0.17 s pop (eye_top .98 overshoot, brow_show 0->1, brow_z .95->1.10,
  scale 1.05); 0.4-1.0 s morph: `wave` 0->1 ease-out, disc_r .48->.06, lids -> 1.0, eye_n -> 2.0. Then loop:
  bands rise (wave_flow -1/s), shape drifts (wave_t +0.35/s), wave_amp from `level`. No blink, no dashes.
- LISTENING_OUT, the silent exit (one-shot, 0.5 s + blink): wave 1->0 over 0.4 s (ripple runs back into the pupil),
  disc_r .06->.48, lids -> .72, eye_n -> 2.3, brow lowers then hides (0.5 s), small glance down, one soft blink at
  0.7 s, gaze back to centre by 1.8 s. Successful release: no exit animation, navigation cuts it.
- RETRIEVING (2 s loop): pupil rolls a small circle (look_x .5->.2->.5, look_z .45->.57->.33), brow bounces
  (tilt .3->.18, z .85->.92), disc pulses .40-.44.
- ANSWERED (one-shot): pop to .96 (scale 1.06) at 0.2 s, brow up, sparkle twinkles 0.27-1.7 s, settle to .74 at 2 s,
  brow fades by 2.2 s, one blink at 2.7 s, then holds.
- INDEXING: lids = .3 + .42*progress (top) mirrored below, treat progress >= .98 as fully open; slow bob (loc_z
  +-.05 over 6 s), disc breathe, one blink midway.

## Acceptance (for QA)

1. READY at rest is a still white oval with an accent disc; it double-blinks and looks around; never a bare
   circle, never a halo.
2. Hold to listen: the eye pops within 0.2 s, then the wave ripples out from the pupil and fills the eye by 1 s;
   bands visibly move and their amplitude follows speech.
3. Release with a transcript: the result screen appears immediately (no 400 ms wait).
4. Release with an empty transcript: the wave runs back into the pupil, the eye relaxes, blinks once, and home stays.
5. RETRIEVING never tracks content: the gaze rolls, it does not sweep or read.
6. INDEXING lids open with the job fraction; at 0 they are at .3, at >= .98 fully open.
7. Reduce motion: no blink, no wander, no beat; entering listening snaps to the wave, leaving snaps back.
8. The other four states are white + accent only; the accent follows the theme on all six options.
9. Nothing draws outside the widget box; the brow never clips at the top.
10. Widget tests pass with the fallback painter; `flutter build bundle` compiles the shader.

## Later (not in this handoff)

- SEARCHING / FOUND / SHOCKED expression clips (FOUND as a first-answer moment, SHOCKED as an error state).
- Riso grain on the sclera; the app mark; dropping the indexing bar.
