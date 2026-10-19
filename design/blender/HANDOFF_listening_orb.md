# Handoff: LISTENING orb transform (Blender -> Flutter)

From: the Blender/design session (knowra-df). For: the Flutter implementation session.
Date: 2026-09-11. Rig: design/blender/voice_orb_states.blend (README text block inside).

## What to build

In `VoicePhase.listening` the orb reacts to the mic level, live:

1. **Silhouette squash.** Screen-aligned non-uniform scale on the whole orb stack (halo + sphere), driven by the smoothed level. Nothing else changes shape.
2. **Interior.** The sphere image switches from `orb_sphere.png` to a 5-frame amplitude strip (core swell + glass ripple + brightness, baked in Blender). Frame chosen by the same level.
3. **Other three phases: unchanged**, pixel-identical to today.

Motion target: `design/blender/previews/listening_loud_loop.gif` (or `.mp4`).
**Note on the motion target (revision 2):** in the original render the sphere rotated because the Blender rig swirls the whole orb as a stand-in for the app's ring. The app's sphere must NOT rotate. Judge the squash, core swell, ripple and glow spikes against the loop, not the rotation. `listening_loud_loop.gif` / `.mp4` are now rendered WITHOUT that rotation and show what the sphere should do; the original rotating loop is kept as `listening_loud_loop_rigswirl.gif` / `.mp4` for reference only.
Frame reference: `design/blender/previews/listening_strip_sheet.png`.

## Assets (copy into the app, register in pubspec)

- `design/blender/export/orb_listen/level_0.png` ... `level_4.png` — 768x768, transparent, cropped edge-to-edge at the alpha > 0 box exactly like `orb_sphere.png` (soft 1 px rim, sphere touches all four edges, fill 1.000). Same camera, lighting and exposure. `level_i` = mic level i/4. Uncropped 1024 masters: `export/orb_listen_1024/`.
- Decoded, five 768 frames are ~11.8 MB. If that matters on low-end devices, pass `cacheWidth` = display pixels to `Image.asset`.
- Copy to `app/assets/images/orb_listen/level_0..4.png` and add `- assets/images/orb_listen/` under `flutter: assets:` in `pubspec.yaml`. A directory entry does not include its subdirectories.
- Do not ship the previews.

## Inputs already in the app

- `lib/src/features/voice/data/speech_recogniser.dart:126` `onSoundLevelChange` -> `_level = (level / 10).clamp(0.0, 1.0)`.
- `VoiceState.level` (`voice_cubit.dart:82`), updated at `:299`, reset to 0 at `:324`, `:339`, `:353`.
- `VoiceOrb` is built at `voice_home_page.dart:139` with `phase:`. Add `level: state.level`.

**KNOWN GAP.** The `/10` normaliser fits Android's roughly -2..10 range. The same comment says iOS reports 0..1, so on iOS the orb would never pass level 0.1. Use a per-platform scale (iOS: `level.clamp(0, 1)`; Android: `level / 10`) or an adaptive range (running max with slow decay). Verify on both platforms with real speech. The transform is only as good as this number.

## Behaviour spec

Let `raw` = `VoiceState.level` (0..1).

- **Smooth.** `level` follows `raw` with fast attack, slow release. attack tau ~ 40 ms, release tau ~ 250 ms:
  `level += (raw - level) * (1 - exp(-dt / tau))` with tau picked by sign of `(raw - level)`.
  Do it in the existing ticker in `_VoiceOrbState` (`voice_orb.dart`) as one more accumulator next to `_breathe` / `_swirl`, exposed as a `ValueNotifier<double>`. The cubit already emits on every level tick; read it into the notifier, do not rebuild the tree from it.
- **Squash.** `sx = 1 + 0.08 * level`, `sy = 1 / (1 + 0.08 * level)`.
  `Transform.scale(scaleX: sx, scaleY: sy, alignment: Alignment.center)` wrapping the WHOLE stack (halo + rotated sphere), i.e. OUTSIDE the swirl `Transform.rotate`. The `ClipOval` lives inside, so the clip stretches with it. No change to `KnowraOrb` needed.
- **Frame.** `f = level * 4`. Draw `level_floor(f)` at opacity 1 with `level_ceil(f)` on top at opacity `frac(f)` (crossfade, no popping). `gaplessPlayback: true`; `precacheImage` all five in `didChangeDependencies`.
- **Halo in listening.** Replace the breathe modulation with level: alpha factor `phase.glow * (0.6 + 0.6 * level)`. Keep breathe for the other phases untouched.
- **Swirl.** The sphere image does not rotate in any phase today; only the ring does. Draw the strip exactly where `KnowraOrb` is drawn, unrotated. Do not rotate it, neither by delta nor absolute: the specular highlight and the off-centre core are lighting, and lighting does not turn with the orb. The rotation in the Blender loop is the rig's stand-in for the ring. Ring behaviour unchanged.
- **Enter/leave listening.** Crossfade `orb_sphere.png` <-> `level_0.png` over 220 ms (same as the bars' fade at `voice_orb.dart:263`). Level starts at 0 on enter so the core visibly shrinks (the "inhale"); the cubit already resets level to 0 on leave.
- **VoiceBars.** Keep for this iteration. Decision pending: once the transform is on device, judge whether the bars are redundant.

## Constants (keep in one place)

squashMax 0.08 | attack 40 ms | release 250 ms | frames 5 | halo 0.6 + 0.6*level | crossfade 220 ms

## Acceptance (for QA)

1. Speaking loudly widens the orb visibly (6-8%) and it springs back within ~250 ms of silence.
2. In silence while listening, the core is visibly smaller than in READY; on loud speech it nearly fills the glass and the glass shows faint rings.
3. No popping between strip frames; no jump in swirl angle when entering or leaving listening.
4. READY, RETRIEVING, ANSWERED are pixel-identical to before.
5. 60 fps on a mid-range Android during listening; no full-page rebuilds per level tick (DevTools rebuild counter).
6. iOS reaches level > 0.5 on normal speech (the normaliser gap above).

## Not in this handoff

- Churn (internal plasma drift loop) and the one-shot transitions (wake / dive / settle). Later, once the loop-length decision is made.
- Any change to `VoicePhase` values (swirl / breathe / glow). The rig mirrors the current numbers.

## Re-rendering the strip

Open the blend, mute all NLA tracks, set `Orb_Pivot` `core` (-1..1), `ripple`, `breathe`, `glow` 0.72, `squash` 0, render a still at 50%. Details in the README text block, section "EXPORT FOR FLUTTER".

## Widget layering (added after QA review; this is the LO-3 / LO-4 invariant)

```
Semantics
└─ Transform.scale(scaleX: sx, scaleY: sy)          squash. OUTSIDE everything. 1/1 unless listening.
   └─ Stack
      ├─ halo (ValueListenableBuilder)              alpha from breathe, or from level when listening
      ├─ Transform.rotate(angle: swirl * 2π)        the ring only, as today. Unchanged.
      │   └─ ring
      └─ crossfade, unrotated, in KnowraOrb's place
         ├─ KnowraOrb(orb_sphere.png)               ready / retrieving / answered
         └─ strip: floor frame + ceil frame         listening
                   at opacity frac(level * 4)
```

Invariants:
1. `_swirl` and `_breathe` accumulate in `_VoiceOrbState` and survive phase changes. Do not give `VoiceOrb` a phase-dependent key, and do not move the ticker into a subtree that gets swapped.
2. The strip is never rotated. The ring's rotate is untouched. The squash is outside the whole stack (halo, ring, sphere) so the ring stays attached to the squashed sphere. A rotated strip breaks LO-3 on enter or leave.
3. Squash reads the smoothed level only; the level is 0 outside listening (cubit resets it), so the other phases render at scale 1/1 and stay pixel-identical (LO-4).

QA (knowra-c2) can verify LO-1..5 on the physical Android. LO-6 (iOS reaches level > 0.5) needs a real iOS device with a mic. Owner: whoever holds one.

## Revision 2 (after the Flutter landing, 2026-09-11)

Findings from the Flutter session and the resolutions:
1. Crop mismatch: the first strip had a 14 px transparent margin at 512 px (fill 0.945) while `orb_sphere.png` is edge-to-edge. Fixed at the source: re-rendered at 1024, cropped at the alpha > 0 box, sized to 768. Re-copy the five files and delete the `stripZoom` constant.
2. "Rotation is safe because the rings are centred" was wrong, and the instruction to rotate was wrong too: the app never rotated the sphere, only the ring. The strip must not rotate.
3. The delta-from-entry rotation workaround becomes unnecessary with 2, and with it the 220 ms orientation dissolve on leave.
