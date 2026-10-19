# Eye orb export

- `orb_eye_clips.json` — every clip at 30 fps, one row per frame. **Rows are in the order of the `knobs` array in the
  file, NOT in shader-uniform order**: `scale, loc_x, loc_z` are the LAST three (indices 37/38/39) while the shader
  declares them right after `wobble`. Map by name via `knobs`; never splice a row straight into setFloat().
- **The exported data wins over the prose table in HANDOFF_eye_orb.md** wherever they differ (READY brow_arch is
  -0.25, wave_amp rests at 0.6, drop_z rests at 0.45). The table is descriptive.
- `orb_noise.glsl` — hash-based value noise with wobbleNoise() / waveNoise(); Impeller-safe.
- `stills/eye_<state>_<px>.png` — READY, LISTENING mid-wave, RETRIEVING at 224 / 236 / 190 on #0c0c0d. Reference to
  eyeball device output against; NOT golden fixtures (different renderer).
- `eye_listening_enter_224.mp4` — the LISTENING enter (pop + morph) and the first second of wave, at device size.

## Transition durations (widget blends between the current pose row and the target clip's first row)
Default 320 ms ease-out-cubic. Exceptions:
- into LISTENING: blend 200 ms into the clip's row 1, then play the clip (its own pop + morph, 1.2 s).
- out of LISTENING, silent: LISTENING_OUT clip (starts at the row whose `wave` matches the current value).
  out of LISTENING, successful release: no exit, navigation cuts it. If the next state renders on the same screen,
  ease `wave` 1 -> 0 over 240 ms (radial wipe collapses) while blending the pose.
- into ANSWERED: blend 200 ms into row 1, then play (the pop is the transition).
- ANSWERED -> READY: 480 ms (lazy settle). Into or out of INDEXING: 400 ms (calm). READY/INDEXING -> RETRIEVING: 320 ms.

## Interrupt policy
- Release during LISTENING's enter: if `wave` < 0.5, do not play LISTENING_OUT; blend to READY in 240 ms (a flinch).
  If `wave` >= 0.5, play LISTENING_OUT starting at its first row whose `wave` <= current.
- Re-press during LISTENING_OUT: if `wave` > 0, resume the LISTENING enter at the row whose `wave` matches
  (no second pop); if `wave` == 0 (already in the glance/blink tail), play the enter from row 1, the pop is the
  press feedback. Never two pops within 1 s.
- Reduce motion: every blend is a snap; `wave` snaps.

## INDEXING composition
Progress replaces ONLY eye_top / eye_bot: lid = rest_lid(progress) * (clip_lid / clip_rest_lid), i.e. the clip's
blink MULTIPLIES the progress opening (a blink at 20% dips from the 20% opening, never flashes wide). Every other
column (bob loc_z, disc_r breathe, gaze 0, brow hidden) comes from the clip as-is.
