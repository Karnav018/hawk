"""Edits the textured film file in place:

1. The dive: the camera now zooms into the hawk's eye and keeps going, through the pupil, until the screen
   is black. The screen then opens like an eyelid (two black paper lids that part, riding on the camera)
   onto the Hawk eye, which itself blinks open while the camera pulls back to "Hawk".
   The hawk no longer bursts on screen; it is swapped out while the screen is black.
2. Text quality: every letter is cut from clean flat paper (no paint streaks or specks), with smoother
   curves, and the render filter is sharpened.

    Blender -b hawk_film_previous_textured.blend --python edit_dive.py

All frame numbers are in the film's original timeline (the 1.2x speed is a playback remap on top).
"""
import math
import os
import random
import sys

import bpy
from bpy_extras import anim_utils

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paperlib  # noqa: E402
from paperlib import hexc, paper, paper_mat  # noqa: E402

TINY = 1e-4
EYE_Z, EYE_S0 = 0.33, 0.11
P_E = (-0.5 + 0.79, 7.9 + 0.15)                  # the hawk's eye while it hovers
GAZE = (0.15, -0.05)                              # its stern look while on the hawk
PUPIL = (P_E[0] + GAZE[0] * EYE_S0, P_E[1] + GAZE[1] * EYE_S0)
PUPIL_TOP = EYE_Z + 0.46 * EYE_S0
B_CAM = (0.3, 7.3)
F_BLACK, F_SWAP, F_OPEN, F_END = 430, 432, 437, 468
REVEAL = (P_E[0], P_E[1] - 0.25)
D_REVEAL, D_END = 6.0, 13.17
LID_Z, LID_C, LID_W = -0.25, 0.02, 0.2
LID_OPEN = (0.006, 0.022, 0.042, 0.066, 0.095)   # how far each lid has parted on each step of the opening


def use_layout(scene):
    """A file built with its own layout (the 9:16 portrait) stores where its hawk's eye is; the lids are
    then sized to that frame, since the lids open along the frame's height."""
    global P_E, PUPIL, B_CAM, REVEAL, D_REVEAL, LID_W, LID_OPEN
    if "dive_p_e" not in scene:
        return
    P_E = tuple(scene["dive_p_e"])
    PUPIL = (P_E[0] + GAZE[0] * EYE_S0, P_E[1] + GAZE[1] * EYE_S0)
    B_CAM = tuple(scene["dive_b_cam"])
    REVEAL = tuple(scene["dive_reveal"])
    D_REVEAL = float(scene["dive_d_reveal"])
    r = scene.render
    lens = scene.camera.data.lens
    hw = -LID_Z * 36.0 / lens / 2                    # half the frame's width where the lids sit
    hh = hw * r.resolution_y / r.resolution_x
    LID_W = 2.04 * hw
    k = hh / 0.0550                                   # the landscape frame's half-height there
    LID_OPEN = tuple(v * k for v in LID_OPEN)


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def seg(f, a, b):
    return max(0.0, min(1.0, (f - a) / float(b - a)))


def lerp(a, b, t):
    return a + (b - a) * t


def pair(f):
    return f - ((f - 1) % 2)


def seq_at(l, l0, seq):
    d = l - l0
    if d < 0 or d % 2 or d // 2 >= len(seq):
        return None
    return seq[d // 2]


def boil(seed, f, amt=0.006, rot_deg=0.35):
    r = random.Random(seed * 100003 + f)
    return r.uniform(-amt, amt), r.uniform(-amt, amt), math.radians(r.uniform(-rot_deg, rot_deg))


# ------------------------------------------------------------------ the new camera through the dive
def cam(f):
    if f <= F_BLACK:                                   # into the eye, through the pupil
        e = smooth(seg(f, 396, F_BLACK))
        d0, d1 = 14.0 - PUPIL_TOP, 0.03
        d = math.exp(lerp(math.log(d0), math.log(d1), e))
        sx = (PUPIL[0] - B_CAM[0]) / d0 * (1 - e)
        sy = (PUPIL[1] - B_CAM[1]) / d0 * (1 - e)
        return (PUPIL[0] - sx * d, PUPIL[1] - sy * d, PUPIL_TOP + d), PUPIL_TOP
    if f < F_SWAP:
        return (PUPIL[0], PUPIL[1], PUPIL_TOP + 0.03), PUPIL_TOP
    top = EYE_Z + 0.5                                  # the Hawk eye at full size
    e = 1 - (1 - seg(f, F_OPEN - 1, F_END)) ** 2.4    # open, then ease back to the sky
    d = math.exp(lerp(math.log(D_REVEAL), math.log(D_END), e))
    m = smooth(seg(f, F_OPEN, F_END))
    return (lerp(REVEAL[0], B_CAM[0], m), lerp(REVEAL[1], B_CAM[1], m), top + d), top


# ------------------------------------------------------------------ helpers to rewrite existing keys
def fcurves(idblock):
    ad = idblock.animation_data
    if not ad or not ad.action:
        return []
    cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
    return list(cb.fcurves) if cb else []


def set_key(idblock, path, index, f, value):
    for fc in fcurves(idblock):
        if fc.data_path == path and fc.array_index == index:
            for kp in fc.keyframe_points:
                if abs(kp.co.x - f) < 0.01:
                    kp.co.y = value
                    kp.handle_left.y = value
                    kp.handle_right.y = value
                    return True
            fc.keyframe_points.insert(f, value, options={"FAST"}).interpolation = "CONSTANT"
            return True
    return False


def set_vec(ob, path, f, vals):
    for i, v in enumerate(vals):
        if not set_key(ob, path, i, f, v):
            setattr(ob, path, vals) if path != "rotation_euler" else None
            ob.keyframe_insert(path, frame=f)
            set_key(ob, path, i, f, v)


def refresh(*ids):
    for idb in ids:
        for fc in fcurves(idb):
            fc.update()


# ------------------------------------------------------------------ 1. the dive
def edit_dive():
    O = bpy.data.objects
    camera = O["Cam"]
    cd = camera.data
    glass = O["Glass"]
    for f in range(396, F_END + 1):
        (x, y, z), fz = cam(f)
        set_vec(camera, "location", f, (x, y, z))
        set_vec(glass, "location", f, (x, y, 0.7))
        s = (z - 0.7) / 13.3 if z > 3.0 else TINY
        set_vec(glass, "scale", f, (s, s, s))
        set_key(cd, "dof.focus_distance", 0, f, max(0.005, z - fz))
        set_key(cd, "clip_start", 0, f, min(0.1, max(0.0005, 0.03 * (z - fz))))
    # crisp lids while they open: stop the lens down for the transition only
    for f, v in ((427, 1.4), (428, 16.0), (449, 16.0), (450, 1.4)):
        cd.dof.aperture_fstop = v
        cd.keyframe_insert("dof.aperture_fstop", frame=f)
    for fc in fcurves(cd):
        if fc.data_path == "dof.aperture_fstop":
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"

    # the Hawk eye: on the hawk until the screen goes black, then full size behind closed lids, then it opens
    eye = {n: O[n] for n in ("Eye", "Eye_Open", "Eye_Closed", "Eye_Spark", "Eye_Brow", "Eye_Gaze", "Eye_Pupil")}
    for f in range(424, F_END + 1):
        g = pair(f)
        jx, jy, jr = boil(3, g, 0.005 if f >= 452 else 0.0, 0.25)
        if f < F_SWAP:
            s, open_y, closed, brow, gaze, spark = EYE_S0, 1.0, False, 1.0, GAZE, 0.0
        elif f < F_OPEN + 1:
            s, open_y, closed, brow, gaze, spark = 1.0, 1.0, True, 0.0, (0.0, 0.0), 0.0
        else:
            popv = seq_at(g, F_OPEN + 4, [1.12, 0.96, 1.03])
            s = 1.0 * (popv if popv is not None else 1.0)
            half = g in (F_OPEN, F_OPEN + 2)
            bl = seq_at(g, 461, [(0.45, False), (1.0, True), (1.0, True), (0.45, False)]) or (1.0, False)
            open_y, closed = (0.45, False) if half else bl
            brow, gaze = 0.0, (0.0, 0.0)
            sp = seq_at(g, F_OPEN + 6, [1.35, 0.9, 1.05])
            d = g - (F_OPEN + 6)
            spark = sp if sp is not None else (1.0 if 6 <= d < 16 else (0.55 if d == 16 else 0.0))
        set_vec(eye["Eye"], "scale", f, (s, s, s))
        set_vec(eye["Eye_Open"], "scale", f, (1, open_y, 1) if not closed else (TINY, TINY, TINY))
        set_vec(eye["Eye_Closed"], "scale", f, (1, 1, 1) if closed else (TINY, TINY, TINY))
        sv = spark if spark > 0 else TINY
        set_vec(eye["Eye_Spark"], "scale", f, (sv, sv, sv))
        bv = brow if brow > 0 else TINY
        set_vec(eye["Eye_Brow"], "scale", f, (bv, bv, bv))
        set_key(eye["Eye_Brow"], "rotation_euler", 2, f, -0.3 if brow > 0 else 0.0)
        set_vec(eye["Eye_Gaze"], "location", f, (gaze[0], gaze[1], 0.0))
        set_vec(eye["Eye_Pupil"], "scale", f, (1, 1, 1))
        set_vec(eye["Eye"], "location", f, (P_E[0] + jx, P_E[1] + jy, EYE_Z))

    # the hawk no longer bursts on screen: its pieces stay put and it is swapped out while the screen is black
    hawk = O["B_Hawk"]
    for f in range(424, 480):
        v = TINY if f >= F_SWAP else 1.0
        if set_key(hawk, "scale", 0, f, v):
            set_key(hawk, "scale", 1, f, v)
            set_key(hawk, "scale", 2, f, v)
    for name in ("B_Hawk_Body", "B_Hawk_Tail", "B_Hawk_Head", "B_Hawk_Beak", "B_Hawk_Wing_n", "B_Hawk_Wing_f"):
        ob = O[name]
        for fc in fcurves(ob):
            if fc.data_path == "location" or (fc.data_path == "rotation_euler" and not name.startswith("B_Hawk_Wing")):
                first = min(fc.keyframe_points, key=lambda k: k.co.x)
                if first.co.x >= 424:
                    rest = first.co.y
                    for kp in fc.keyframe_points:
                        kp.co.y = kp.handle_left.y = kp.handle_right.y = rest

    # the screen's eyelids: black paper riding on the camera, closed in the dark, then parting
    paperlib.use_collection(bpy.data.collections["HawkFilm"])
    ink = bpy.data.materials.get("Paint_ink") or paper_mat("Paint_lid", hexc("#0e1522"))
    xs = [-LID_W + 2 * LID_W * i / 40 for i in range(41)]
    top_pts = [(x, LID_C * (1 - (x / LID_W) ** 2)) for x in xs] + [(LID_W, 0.3), (-LID_W, 0.3)]
    bot_pts = [(x, -LID_C * (1 - (x / LID_W) ** 2)) for x in reversed(xs)] + [(-LID_W, -0.3), (LID_W, -0.3)]
    lids = []
    for name, pts in (("Lid_Top", top_pts), ("Lid_Bottom", bot_pts)):
        if name in O:                                   # re-running the script reuses the lids
            lids.append(O[name])
            continue
        ob = paper(name, pts, ink, LID_Z, camera, thick=0.002, wob=0.0)
        ob.visible_shadow = False
        lids.append(ob)
    closed = LID_C + 0.004
    opening = {F_OPEN + 2 * i: v for i, v in enumerate(LID_OPEN)}
    for f in range(420, 452):
        g = pair(f)
        if f < 429 or g > F_OPEN + 8:
            s, off = TINY, -closed
        elif g < F_OPEN:
            s, off = 1.0, -closed
        else:
            s, off = 1.0, opening.get(g, -closed)
        for sign, ob in ((1, lids[0]), (-1, lids[1])):
            ob.location = (0.0, sign * off, LID_Z)
            ob.scale = (s, s, s)
            ob.keyframe_insert("location", frame=f)
            ob.keyframe_insert("scale", frame=f)
    for ob in lids:
        for fc in fcurves(ob):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    refresh(camera, cd, glass, hawk, *eye.values(), *[O[n] for n in ("B_Hawk_Body", "B_Hawk_Tail", "B_Hawk_Head",
                                                                    "B_Hawk_Beak", "B_Hawk_Wing_n", "B_Hawk_Wing_f")])


# ------------------------------------------------------------------ 2. crisp letters
def edit_text():
    clean = {}
    for ob in bpy.data.objects:
        if ob.type != "FONT":
            continue
        ob.data.resolution_u = 24
        for i, m in enumerate(ob.data.materials):
            if m is None or m.name.startswith("Text_"):
                continue
            key = m.name
            if key not in clean:
                src = next((n for n in m.node_tree.nodes if n.type == "MIX"), None)
                rgb = (0.8, 0.8, 0.8)
                if src is not None:
                    a = next(s for s in src.inputs if s.name == "A" and s.type == "RGBA")
                    rgb = tuple(a.default_value[:3])
                clean[key] = paper_mat("Text_" + key, rgb, streak=0.0, speck=0.0, fiber=0.0, mottle=0.02)
            ob.data.materials[i] = clean[key]
    bpy.context.scene.render.filter_size = 1.0
    for ob in bpy.data.objects:                        # printed letters cast no shadow: no doubled edges
        if ob.type == "FONT":
            ob.visible_shadow = False
    scene = bpy.context.scene
    if not scene.get("captions_raised") and not scene.get("portrait"):   # keep captions clear of the bottom edge
        for ob in bpy.data.objects:
            if ob.name.startswith("Cap") and ob.animation_data and ob.animation_data.action:
                for fc in fcurves(ob):
                    if fc.data_path == "location" and fc.array_index == 1:
                        for kp in fc.keyframe_points:
                            kp.co.y += 0.1
                            kp.handle_left.y += 0.1
                            kp.handle_right.y += 0.1
                        fc.update()
        scene["captions_raised"] = True
    return len(clean)


def main():
    paperlib._mats.clear()
    use_layout(bpy.context.scene)
    edit_dive()
    n = edit_text()
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_mainfile()
    print(f"EDITED dive + lids; clean text materials={n}")


main()
