"""Builds the 60-second Hawk launch film: ONE painted paper world, ONE camera move, 16:9.

    Blender -b --factory-startup --python design/blender/film/hawk_film.py

There are no cuts. The camera starts on the person under a warm lamp (A), pulls back as the wooden
archive unfolds, tilts up into the night sky over the lake (B) where the hawk flies, dives in and holds
on its head for the title, then the hawk bursts into paper and leaves the Hawk eye behind. From then on
the eye is the guide: it glides down to your storage (C), on to the filenames and the Goa sunset (D),
and to the person again (E), and the camera follows it. At the end the camera tilts up for the end card.

Look: painted paper (gouache streaks), navy + cream + brand blue + orange, warm lamps, painted leaves.
Paper moves on twos (poses held for two frames); the camera, the travelling eye and the walking
person's path move on ones. Captions sit on a "top glass" that rides with the camera.
Art direction: reference/enhanced_look_reference_v2.png (and v1).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from paperlib import (M, TINY, Anim, boil, circle, empty, init_palette, measure, move, paper,  # noqa: E402
                      paper_multi, rotate, rrect, sparkle, text, tone, torn_strip, use_collection, wave_strip,
                      word_row)
from puppets import (FLAP, HAWK_EYE, POSES, _chip, back_out, blink, build_blob, build_books,  # noqa: E402
                     build_box, build_card, build_eye, build_hawk, build_lamp, build_leaves, build_moon,
                     build_person, build_plant, build_podium, build_shelf, build_swoosh, build_thought, caption,
                     clamp, crumple, doc_page, ease_in, ease_out, hill_fn, hills, key_card, key_dash, key_eye,
                     key_hawk, key_person, landscape_pic, lerp, mix, palm_polys, peaks_fn, pop, popup,
                     ring_segments, seg, seq_at, sightline, smooth, spark, sunset_pic, swoosh, tick, zig)

LAST = 1440
EYE_Z = 0.33                    # the guide eye's layer height (above the hawk's head)
HAWK_S = 1.3                    # the hawk, drawn larger as in the reference
EYE_S0 = 0.11 * HAWK_S          # the Hawk eye's size while it sits on the hawk
HAWK_Y = 7.9
P_E = (-0.5 + HAWK_S * HAWK_EYE[0], HAWK_Y + HAWK_S * HAWK_EYE[1])     # where the hawk hovers its eye
B_CAM = (0.3, 7.3)                                    # camera centre over the sky
HOLD_T = (P_E[0] + 0.36 * HAWK_S, P_E[1] - 0.03 * HAWK_S)   # title hold: eye on the left, words on the right
HOLD_D0, HOLD_D1 = 1.35 * HAWK_S, 1.22 * HAWK_S
C0, D0, E0 = (15.5, 0.0), (27.0, 0.0), (39.5, 0.0)   # region origins along the one sheet
C_EYE = (C0[0] + 3.9, 1.2)
D_EYE = (D0[0] + 4.1, -0.45)
E_EYE = (E0[0] + 1.9, 0.95)
E3_EYE = (E0[0] + 0.9, 1.55)
END_C = (E0[0] - 3.7, 7.0)
END_EYE = (END_C[0], END_C[1] + 0.85)
PERSON_A, PERSON_PARK, PERSON_E = (-0.4, -0.62), (E0[0] - 6.2, -0.62), (E0[0] - 3.7, -0.62)


def pair(f):
    """The pose frame: poses change on odd frames and hold for two (animation on twos)."""
    return f - ((f - 1) % 2)


def region(name, x, y, parent):
    return empty(name, (x, y, 0), parent)


def steps(S):
    return range(0, S["length"], 2)


def F(S, l):
    return S["start"] + l


def sink(fn, x_end=9.3, floor=3.0, width=3.0):
    """Slope a ridge down behind the last shelf so it never ends in a hard edge."""
    return lambda xx: floor + (fn(xx) - floor) * smooth(seg(xx, x_end, x_end - width))


# ------------------------------------------------------------------ the one camera
def eye_top(s):
    return EYE_Z + 0.5 * s


def eye_grow(f):
    """After the burst the eye grows while the camera pulls back."""
    if f <= 446:
        return EYE_S0
    return lerp(EYE_S0, 1.0, smooth(seg(f, 446, 468)))


def cam_path(f):
    if f <= 144:
        t = (f - 1) / 143.0
        return (0.1 * t, 0.0, 13.6 - 0.2 * smooth(t))
    if f <= 288:                                               # pull back: the archive unfolds
        t = smooth(seg(f, 144, 235))
        return (lerp(0.1, 0.0, t), lerp(0.0, 0.6, t), lerp(13.4, 19.0, t))
    if f <= 324:                                               # tilt up past the shelves into the sky
        t = smooth(seg(f, 288, 324))
        return (lerp(0.0, -0.5, t), lerp(0.6, B_CAM[1], t), lerp(19.0, 14.0, t))
    if f <= 396:                                               # drift with the hawk
        t = smooth(seg(f, 324, 396))
        return (lerp(-0.5, B_CAM[0], t), B_CAM[1], 14.0)
    if f <= 418:                                               # dive to the hawk's head
        e = smooth(seg(f, 396, 418))
        top = eye_top(EYE_S0)
        d0 = 14.0 - top
        d = math.exp(lerp(math.log(d0), math.log(HOLD_D0), e))
        sx = (HOLD_T[0] - B_CAM[0]) / d0 * (1 - e)
        sy = (HOLD_T[1] - B_CAM[1]) / d0 * (1 - e)
        return (HOLD_T[0] - sx * d, HOLD_T[1] - sy * d, top + d)
    if f <= 446:                                               # hold for the title, easing in
        d = lerp(HOLD_D0, HOLD_D1, smooth(seg(f, 418, 446)))
        return (HOLD_T[0], HOLD_T[1], eye_top(EYE_S0) + d)
    if f <= 474:                                               # the hawk bursts; pull back as the eye grows
        e = smooth(seg(f, 446, 474))
        d = math.exp(lerp(math.log(HOLD_D1), math.log(13.17), e))
        m = smooth(seg(f, 450, 474))
        return (lerp(HOLD_T[0], B_CAM[0], m), lerp(HOLD_T[1], B_CAM[1], m), eye_top(eye_grow(f)) + d)
    if f <= 504:                                               # follow the eye down to storage
        t = smooth(seg(f, 474, 504))
        return (lerp(B_CAM[0], C0[0], t), lerp(B_CAM[1], 0.0, t), 14.0)
    if f <= 612:
        t = smooth(seg(f, 504, 612))
        return (C0[0], 0.0, lerp(14.0, 13.8, t))
    if f <= 648:
        t = smooth(seg(f, 612, 648))
        return (lerp(C0[0], D0[0], t), 0.0, lerp(13.8, 14.0, t))
    if f <= 744:
        t = smooth(seg(f, 648, 744))
        return (D0[0], 0.0, lerp(14.0, 13.85, t))
    if f <= 780:
        t = smooth(seg(f, 744, 780))
        return (lerp(D0[0], E0[0], t), 0.0, lerp(13.85, 14.0, t))
    if f <= 1020:
        t = smooth(seg(f, 780, 1020))
        return (lerp(E0[0], E0[0] - 0.1, t), 0.0, lerp(14.0, 13.85, t))
    if f <= 1164:
        t = smooth(seg(f, 1020, 1047))
        return (lerp(E0[0] - 0.1, E0[0] + 1.2, t), 0.0, lerp(13.85, 14.2, t))
    if f <= 1296:
        t = smooth(seg(f, 1164, 1205))
        u = smooth(seg(f, 1205, 1296))
        return (lerp(E0[0] + 1.2, PERSON_E[0], t), 0.0, lerp(14.2, 14.4, t) - 0.3 * u)
    t = smooth(seg(f, 1296, 1343))                             # tilt up into the sky for the end card
    u = smooth(seg(f, 1343, 1440))
    return (PERSON_E[0], lerp(0.0, END_C[1], t), lerp(14.1, 14.0, t) - 0.4 * u)


def focus_z(f):
    return eye_top(eye_grow(f)) if 390 <= f <= 476 else 0.42


# ------------------------------------------------------------------ the hawk's flight
def hawk_root(f):
    g = pair(f)
    if f < 289:
        x, y = -9.5, HAWK_Y
    elif f < 384:
        x = lerp(-9.5, -0.5, ease_out(seg(f, 289, 384)))
        y = HAWK_Y + 0.07 * math.sin(f * 0.2) * (1 - seg(f, 364, 384))
    else:
        x, y = -0.5, HAWK_Y
    rot = math.radians(-6) if 357 <= g < 384 else 0.0
    jx, jy, jr = boil(9, g, 0.005, 0.3) if g < 384 else (0.0, 0.0, 0.0)
    return x + jx, y + jy, rot + jr


# ------------------------------------------------------------------ D: the crumpled filename's roll
def ball_state(l):
    g, floor, x0, y0, l0 = 9.0, -1.15, -0.4, 1.05, 28
    if l < l0:
        return None
    t = (l - l0) / 24.0
    t1 = math.sqrt(2 * (y0 - floor) / g)
    if t < t1:
        return (x0, y0 - 0.5 * g * t * t, -60 * t)
    u = t - t1
    return (x0 + 5.0 * u, floor + 0.35 * abs(math.sin(math.pi * u / 0.32)) * math.exp(-4 * u), -60 * t1 - 520 * u)


# ------------------------------------------------------------------ E: the found photo's flight
PH0, PH1 = (4.3, 0.35, -7.0, 0.44), (-0.55, 1.2, 5.0, 0.5)


def photo_path(l):
    """E-local pose of the photo during the ask (l = frame - 781)."""
    if l < 136:
        return PH0[0], PH0[1] + 0.02 * math.sin(l * 0.1), 0.2, PH0[2], PH0[3], 1.0, "trace", 0.0
    t = seg(l, 146, 172)
    tt = smooth(t)
    pull = 0.15 * math.sin(math.pi * seg(l, 138, 150)) if l < 150 else 0.0
    x = lerp(PH0[0], PH1[0], tt) + pull
    y = lerp(PH0[1], PH1[1], tt) + 0.85 * math.sin(math.pi * tt)
    if l >= 180:
        y += 0.025 * math.sin((l - 180) * 0.12)
    z = 0.2 + 0.8 * ease_out(seg(l, 136, 144)) - 0.55 * ease_in(seg(l, 172, 178))
    p = pop(l, 136, seq=(1.16, 0.96, 1.03)) * pop(l, 178, seq=(1.035, 0.99))
    return x, y, z, lerp(PH0[2], PH1[2], back_out(t, 2.2)), lerp(PH0[3], PH1[3], tt), p, "solid", tt


# ------------------------------------------------------------------ the guide eye, every frame
def travel(f, f0, f1, a, b, sa, sb, arc=0.6):
    t = seg(f, f0, f1)
    e = smooth(t)
    lean = -0.14 * math.sin(math.pi * t) * (1 if b[0] > a[0] else -1)
    return (lerp(a[0], b[0], e), lerp(a[1], b[1], e) + arc * math.sin(math.pi * t)), lerp(sa, sb, e), lean


def guide(f):
    g = pair(f)
    st = dict(gaze=(0.0, 0.0), open_y=1.0, closed=False, pop_s=1.0, squash=(1, 1), spark_s=0.0, brow=0.0,
              brow_rot=0.0, pupil=1.0, listen=False, phase=(g // 2) % 4, amt=0.005, rot=0.0)
    if f <= 446:                                   # riding on the hawk's head, with a stern brow
        hx, hy, hr = hawk_root(f)
        ex, ey = HAWK_S * HAWK_EYE[0], HAWK_S * HAWK_EYE[1]
        pos = (hx + math.cos(hr) * ex - math.sin(hr) * ey, hy + math.sin(hr) * ex + math.cos(hr) * ey)
        st.update(pos=pos, scale=EYE_S0, rot=hr, amt=0.0, brow=1.0, brow_rot=-0.3,
                  gaze=(0.2, -0.3) if 357 <= g < 384 else (0.15, -0.05))
        st["open_y"], st["closed"] = blink(g, 335, 435)
        st["spark_s"] = spark(g, 423, 14)
        return st
    if f <= 474:                                   # left behind as the hawk bursts, growing
        st.update(pos=P_E, scale=eye_grow(f), amt=0.0 if f < 468 else 0.005)
        st["pop_s"] = pop(g, 469)
        st["spark_s"] = spark(g, 469, 12)
        return st
    if f <= 504:
        pos, sc, lean = travel(f, 474, 504, P_E, C_EYE, 1.0, 0.6, arc=0.8)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(0.3, -0.2))
        return st
    if f <= 612:                                   # C: looks into your storage
        st.update(pos=C_EYE, scale=0.6, gaze=(-0.32, -0.14) if g >= 515 else (0.0, 0.0))
        st["open_y"], st["closed"] = blink(g, 519, 589)
        st["pop_s"] = pop(g, 603)
        st["spark_s"] = spark(g, 603, 12)
        return st
    if f <= 648:
        pos, sc, lean = travel(f, 612, 648, C_EYE, D_EYE, 0.6, 0.45, arc=0.5)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(0.3, -0.1))
        return st
    if f <= 744:                                   # D: unimpressed by filenames
        st.update(pos=D_EYE, scale=0.45)
        if g < 701:
            st["open_y"] = 0.55
            b = ball_state(g - 641)
            st["gaze"] = (-0.35, 0.3) if (g < 669 or b is None) else (clamp((b[0] - 4.1) / 3.0, -1, 1) * 0.34, -0.2)
        else:
            st["open_y"], st["closed"] = blink(g, 719)
            st["gaze"] = (-0.3, 0.25)
            st["pop_s"] = pop(g, 701)
            st["spark_s"] = spark(g, 701, 16)
        return st
    if f <= 780:
        pos, sc, lean = travel(f, 744, 780, D_EYE, E_EYE, 0.45, 0.72, arc=1.8)   # swoops over the walker
        st.update(pos=pos, scale=sc, rot=lean, gaze=(0.3, 0.0))
        return st
    if f <= 1020:                                  # E1: listens, thinks, looks, finds
        l = g - 781
        st.update(pos=E_EYE, scale=0.72)
        st["open_y"], st["closed"] = blink(l, 12, 198, 226)
        st["listen"] = 32 <= l < 92
        st["squash"] = (1.1, 0.85) if l == 30 else ((0.9, 1.1) if l == 92 else (1, 1))
        st["gaze"] = (-0.33, -0.1)
        if 94 <= l < 114:
            st.update(gaze=(0.22, 0.24), brow=1.0, brow_rot=math.radians(-8), pupil=0.9)
        elif 114 <= l < 146:
            st["gaze"] = (0.34, -0.1)
        elif 146 <= l < 178:
            pp = photo_path(l)
            st["gaze"] = (clamp((pp[0] - 1.9) / 3.0, -1, 1) * 0.34, 0.03 + 0.1 * math.sin(math.pi * pp[7]))
        elif l >= 178:
            st.update(gaze=(-0.33, 0.0), pupil=1.25 if l < 212 else 1.0)
        st["pop_s"] = pop(l, 32, seq=(1.08, 1.0)) * pop(l, 182)
        st["spark_s"] = spark(l, 184, 18)
        return st
    if f <= 1164:                                  # E2: three more asks
        l = g - 1021
        k = min(2, l // 40)
        b = 40 * k
        d = l - b
        think = 18 <= d < 22
        st.update(pos=E_EYE, scale=0.72, listen=6 <= d < 16, brow=1.0 if think else 0.0,
                  brow_rot=math.radians(-8))
        if l >= 120:
            st["gaze"] = (0.3, -0.05)
        elif think:
            st["gaze"] = (0.22, 0.24)
        elif d >= 16:
            st["gaze"] = (0.34, -0.05)
        elif d < 6 and k > 0:
            st["gaze"] = (0.3, 0.0)
        st["squash"] = (0.9, 1.1) if d == 16 else (1, 1)
        st["pop_s"] = pop(l, b + 32) * pop(l, b + 6, seq=(1.08, 1.0))
        st["spark_s"] = spark(l, b + 32, 12)
        st["open_y"], st["closed"] = blink(l, 128)
        return st
    if f <= 1205:
        pos, sc, lean = travel(f, 1164, 1205, E_EYE, E3_EYE, 0.72, 0.4, arc=0.4)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(-0.2, -0.1))
        return st
    if f <= 1296:                                  # E3: watches the memories come close
        st.update(pos=E3_EYE, scale=0.4, gaze=(-0.3, -0.1))
        st["spark_s"] = spark(g, 1231, 14)
        st["open_y"], st["closed"] = blink(g, 1261)
        return st
    if f <= 1343:
        pos, sc, lean = travel(f, 1296, 1343, E3_EYE, END_EYE, 0.4, 0.8, arc=0.3)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(-0.1, 0.2))
        return st
    st.update(pos=END_EYE, scale=0.8)
    st["pop_s"] = pop(g, 1345)
    st["spark_s"] = spark(g, 1367, 16)
    st["open_y"], st["closed"] = blink(g, 1401)
    return st


# ------------------------------------------------------------------ the person, every frame
def walk_pose(phase):
    a = 2 * math.pi * phase
    s = math.sin(a)
    return dict(torso=-3, head=0, ua_n=-20 * s, fa_n=18, ua_f=20 * s, fa_f=18,
                th_n=24 * s, sh_n=-22 * max(0.0, -math.cos(a)) - 4,
                th_f=-24 * s, sh_f=-22 * max(0.0, math.cos(a)) - 4)


def person(f):
    """Returns (pos, pose, flip, lift)."""
    g = pair(f)
    if f < 330:
        if g <= 144:
            l = g - 1
            if l < 56:
                pose = POSES["look"]
            elif l < 66:
                pose = mix(POSES["look"], POSES["up"], smooth(seg(l, 56, 66)))
            elif l < 116:
                pose = POSES["up"]
            else:
                pose = mix(POSES["up"], POSES["sad"], smooth(seg(l, 116, 128)))
            return PERSON_A, pose, False, 0.0
        l = g - 145
        return PERSON_A, POSES["up"], 84 <= l < 108, 0.0
    if f < 745:
        return PERSON_PARK, POSES["stand"], False, 0.0
    if f <= 800:                                   # walks in while the camera arrives
        t = seg(f, 745, 800)
        x = lerp(PERSON_PARK[0], PERSON_E[0], 1 - (1 - t) ** 1.6)
        if g < 799:
            phase = ((g - 745) / 12.0) % 1.0
            return (x, PERSON_E[1]), walk_pose(phase), False, 0.03 * abs(math.cos(2 * math.pi * phase))
        return (x, PERSON_E[1]), POSES["look"], False, 0.0
    if f <= 1020:
        l = g - 781
        if l < 20:
            pose = POSES["look"]
        elif l < 30:
            pose = mix(POSES["look"], POSES["talk"], smooth(seg(l, 20, 30)))
        elif l < 92:
            pose = POSES["talk"]
        elif l < 104:
            pose = mix(POSES["talk"], POSES["look"], smooth(seg(l, 92, 104)))
        elif l < 176:
            pose = POSES["look"]
        else:
            pose = mix(POSES["look"], POSES["delight"], smooth(seg(l, 176, 188)))
        return PERSON_E, pose, False, 0.03 if l in (180, 182) else 0.0
    if f <= 1164:
        return PERSON_E, mix(POSES["delight"], POSES["up"], smooth(seg(g - 1021, 0, 12))), False, 0.0
    if f <= 1296:
        l = g - 1165
        pose = POSES["up"] if l < 40 else mix(POSES["up"], POSES["joy"], smooth(seg(l, 40, 48)))
        return PERSON_E, pose, False, 0.04 if l in (48, 50) else 0.0
    return PERSON_E, POSES["joy"], False, 0.0


# ------------------------------------------------------------------ the sheet: page, floor, sky, stars
def build_world(W):
    paper("Page", rrect(92, 42, 0.1, cx=17, cy=4), M.card, 0.0, W, thick=0.02)
    paper("GroundBack", torn_strip(-1.45, -14, 3, x0=-18, x1=56), M.char1, 0.05, W)
    paper("GroundFront", torn_strip(-1.78, -14, 7, x0=-18, x1=56), M.char2, 0.10, W)
    for i, mat in enumerate(M.sky):                           # painted bands that deepen upward
        yb = 3.6 + 1.6 * i
        rnd = random.Random(40 + i)
        ph = rnd.random() * 6.28
        xs = [-18 + 0.12 * k for k in range(int(74 / 0.12) + 1)]
        edge = [(x, yb + 0.14 * math.sin(0.45 * x + ph) + 0.05 * math.sin(1.7 * x + 2 * ph)) for x in xs]
        paper(f"Sky{i}", [(-18, 15.0), (56, 15.0)] + list(reversed(edge)), mat, 0.004 + 0.0006 * i, W)
    rnd = random.Random(3)
    clear = [(END_C[0] - 3.4, END_C[0] + 3.4, 4.6, 6.9), (P_E[0] - 0.4, P_E[0] + 1.8, P_E[1] - 0.6, P_E[1] + 0.6)]
    dots, sparks = [], []
    while len(dots) < 190:
        sx, sy = rnd.uniform(-14, 48), rnd.uniform(4.6, 12.5)
        if not any(a <= sx <= b and c <= sy <= d for a, b, c, d in clear):
            dots.append(circle(rnd.uniform(0.012, 0.03), N=12, cx=sx, cy=sy))
    while len(sparks) < 34:
        sx, sy = rnd.uniform(-14, 48), rnd.uniform(5.2, 12.5)
        if not any(a <= sx <= b and c <= sy <= d for a, b, c, d in clear):
            sparks.append(move(sparkle(rnd.uniform(0.05, 0.1), N=48), sx, sy))
    paper_multi("Stars", dots + sparks, [M.white], 0.008, W)


# ------------------------------------------------------------------ A: lost, then the archive
def build_A(A, W):
    RA = region("A_Region", 0.0, 0.0, W)
    S1 = dict(root=RA, start=1, length=144)
    S2 = dict(root=RA, start=145, length=144)
    # the room: painted shapes behind, a lamp, a plant, a cabinet with books, an orange bush
    paper("A_Wash", rrect(2.4, 3.4, 0.6, cx=-4.9, cy=1.1), tone("#1c2a40"), 0.012, RA, wob=0.05, seed=7)
    paper("A_Door", rrect(2.3, 4.4, 0.25, cx=1.5, cy=0.8), tone("#142035"), 0.014, RA, wob=0.04, seed=8)
    paper("A_Door2", rrect(1.3, 3.2, 0.2, cx=2.9, cy=0.1), tone("#1a2b46"), 0.016, RA, wob=0.04, seed=9)
    build_lamp("A_Lamp", RA, (-3.7, 2.2), cord_top=1.6, cone_to=-3.6)
    build_plant("A_Plant", RA, (-4.75, -1.25), 0.2, scale=1.0, seed=4)
    build_box("A_Box", RA, (-3.45, -1.72), 0.16, w=1.0, h=0.62)
    build_books("A_Books", RA, (-3.45, -1.08), 0.17, n=3, seed=5)
    build_leaves("A_Sprout", RA, (-1.55, -1.72), 0.2, n=5, length=(0.4, 0.75), width=0.22,
                 mats=[M.teal, M.leafb], seed=6, rib=M.teal2)
    build_blob("A_Bush", RA, (4.9, -1.75), 0.15, r=0.9, mats=[M.orange, M.orange2, M.white], seed=3)
    specs = [("photo", (1.35, 1.2), -6, 40, (0.55, 0.85)),
             ("doc", (-2.3, 1.0), 8, 52, (-0.7, 0.75)),
             ("voice", (2.7, 0.05), 5, 64, (0.9, 0.35)),
             ("board", (-2.9, -0.2), -4, 76, (-0.9, 0.3))]
    cards = [(build_card(f"A_{k}", RA, k), p, r, ls, d) for k, p, r, ls, d in specs]
    for l in steps(S1):
        f = F(S1, l)
        for k, (C, p, r, ls, d) in enumerate(cards):
            bob = 0.04 * math.sin(l * 0.13 + k * 1.7)
            if l < ls:
                key_card(A, C, f, p[0], p[1] + bob, 0.55, r + 2 * math.sin(l * 0.07 + k), 0.5, "solid", seed=20 + k)
            else:
                t = ease_in(seg(l, ls + 8, ls + 72))
                z = lerp(0.55, 0.14, ease_out(seg(l, ls, ls + 6)))
                key_card(A, C, f, p[0] + d[0] * 7 * t, p[1] + bob + d[1] * 7 * t, z, r + 40 * t * (1 if k % 2 else -1),
                         0.5, "hidden" if l > ls + 72 else "trace", pop_s=pop(l, ls, seq=(1.12, 0.95, 1.02)),
                         seed=20 + k)

    # the archive: wooden shelves of coloured books that unfold around the person
    arch = empty("A_Archive", (0, -1.45, 0), RA, scale=1.35)
    rnd = random.Random(2)
    units = []
    for k in range(7):
        units.append((build_shelf(f"A_Back{k}", arch, -6.0 + 2.0 * k, 0.05, 1.9, 4.0 + rnd.uniform(-0.3, 0.3), 0.03,
                                  tone("#1a2436")), 4 + 2 * k))
    mid_tags = ["untitled.m4a", "backup_2021", None, "misc_old", None, "Copy of Copy"]
    for k, x in enumerate((-5.0, -3.1, -1.2, 1.2, 3.1, 5.0)):
        units.append((build_shelf(f"A_Mid{k}", arch, x, 0.0, 1.75, 3.3 + rnd.uniform(-0.25, 0.25), 0.07,
                                  M.wood2, tone("#141a22"), [M.leafb2, M.teal2, M.wood, tone("#243f66"), M.orange],
                                  tag=mid_tags[k], tag_mat=tone("#cdb48d") if k == 3 else M.cream2, seed=k,
                                  max_binders=4), 12 + 2 * k))
    for k, (x, tag) in enumerate(((-4.5, "IMG_4829.jpg"), (-2.7, "Final_v3_REAL.docx"), (2.7, "New Folder (7)"),
                                  (4.5, "Scan_0032.pdf"))):
        units.append((build_shelf(f"A_Front{k}", arch, x, -0.05, 1.6, 2.7 + rnd.uniform(-0.2, 0.2), 0.12,
                                  M.wood, M.black, [M.white, M.leafb, M.orange, M.teal, M.cream2, M.orange2],
                                  tag=tag, tag_mat=M.white, seed=10 + k), 22 + 4 * k))
    lamp2 = build_lamp("A_Lamp2", RA, (5.4, 3.35), cord_top=1.4, cone_to=-4.6)
    warm2 = bpy.data.objects["A_Lamp2_Warm"].data              # its light switches on when it drops in
    for fr, e in ((1, 0.0), (167, 0.0), (171, 180.0)):
        warm2.energy = e
        warm2.keyframe_insert("energy", frame=fr)
    fg = build_leaves("A_FgLeaves", RA, (-6.4, -3.5), 0.5, n=5, spread=(-15, 60), length=(1.6, 2.5), width=0.55,
                      mats=[M.teal, M.leafb, M.teal2], seed=12, rib=M.teal2)
    T = build_thought("A_Thought", RA, (0.9, 1.9), 1.0)
    for l in steps(S2):
        f = F(S2, l)
        for u, t0 in units:
            A.scl(u, f, (1, popup(l, t0, seq=(0.25, 0.7, 1.08, 0.97)), 1))
        A.scl(lamp2, f, (1, popup(l, 24, seq=(0.4, 1.1)), 1))
        A.scl(fg, f, popup(l, 30, seq=(0.5, 1.08)))
        gone = l >= 138
        for i, b in enumerate(T["bubbles"]):
            A.scl(b, f, TINY if gone else (0.55 if l == 136 else popup(l, 46 + 4 * i, seq=(1.3, 0.9))))
        A.scl(T["cloud"], f, TINY if gone else (0.55 if l == 136 else popup(l, 58)))
        key_card(A, T["card"], f, 0, 0.03, 0.03, 0, 0.5, "hidden" if gone else "solid",
                 pop_s=0.55 if l == 136 else popup(l, 64), seed=22)
    for l in steps(S1):
        f = F(S1, l)
        A.scl(lamp2, f, TINY)
        A.scl(fg, f, TINY)


# ------------------------------------------------------------------ B: the night sky over the lake, the hawk
def build_B(A, W):
    build_blob("B_CloudL", W, (-5.3, 6.5), 0.010, r=0.95, mats=[M.cloud2, M.cloud1], seed=21, base=(2.6, 0.45),
               puffs=[(-0.8, 0.05, 0.42), (-0.25, 0.3, 0.55), (0.35, 0.18, 0.5), (0.85, 0.02, 0.38)])
    build_blob("B_CloudR", W, (5.8, 6.9), 0.010, r=1.0, mats=[M.cloud1, M.cloud2], seed=22, base=(2.4, 0.42),
               puffs=[(-0.75, 0.02, 0.4), (-0.15, 0.28, 0.56), (0.5, 0.12, 0.48), (0.95, -0.02, 0.34)])
    build_moon("B_Moon", W, (4.3, 9.3), 0.012, r=0.7)
    far = sink(peaks_fn(5.1, 1.35, -14, 11, 10, 41))
    mid = sink(peaks_fn(4.85, 0.95, -14, 11, 12, 42))
    near = sink(hill_fn(4.78, [(0.18, 0.6), (0.08, 1.9)], 43))
    paper("B_FarMounts", hills(far, -16, 11, bottom=3.0), M.mount1, 0.014, W)
    paper("B_MidMounts", hills(mid, -16, 11, bottom=3.0), M.mount2, 0.017, W)
    paper("B_NearHills", hills(near, -16, 11, bottom=3.0), M.mount3, 0.020, W)
    lake_top = sink(lambda xx: 4.72, x_end=9.3, floor=3.3, width=2.0)
    paper("B_Lake", hills(lake_top, -16, 11, bottom=3.0), M.lake, 0.022, W)
    rnd = random.Random(44)
    lights = [rrect(rnd.uniform(0.04, 0.07), rnd.uniform(0.04, 0.07), 0.01, cx=rnd.uniform(2.4, 6.2),
                    cy=4.76 + rnd.uniform(0.0, 0.2)) for _ in range(16)]
    paper_multi("B_TownLights", lights, [M.town], 0.0235, W)
    refl = [rrect(rnd.uniform(0.15, 0.55), 0.022, 0.01, cx=rnd.uniform(2.2, 6.4), cy=rnd.uniform(3.95, 4.62))
            for _ in range(12)]
    refl += [rrect(0.35 - 0.04 * i, 0.03, 0.012, cx=4.3 + rnd.uniform(-0.05, 0.05), cy=4.6 - 0.12 * i) for i in range(6)]
    paper_multi("B_Reflections", refl, [M.reflect], 0.024, W)
    pines = []
    for gx, n in ((-6.3, 4), (5.3, 4)):
        for i in range(n):
            x, h = gx + i * 0.45 + rnd.uniform(-0.1, 0.1), rnd.uniform(1.0, 1.8)
            for tier in range(3):
                w = h * (0.34 - tier * 0.08)
                yb = 4.1 + h * tier * 0.28
                pines.append([(x - w, yb), (x + w, yb), (x, yb + h * 0.5)])
            pines.append(rrect(0.06, 0.25, 0.01, cx=x, cy=4.05))
    paper_multi("B_Pines", pines, [M.pine], 0.026, W)
    glint = paper("B_Glint", circle(0.045), M.blue, 0.027, W, loc=(2.6, 4.35))
    gspark = paper("B_GlintSpark", rotate(sparkle(0.12), 0.3), M.white, 0.028, W, loc=(2.72, 4.47))

    H = build_hawk("B_Hawk", W, (0, 0), HAWK_S, 0.3, eye=False)
    for f in range(1, 477):
        g = pair(f)
        hx, hy, hr = hawk_root(f)
        if g < 350:
            flap = FLAP[((g - 289) // 2) % 8] if g >= 289 else FLAP[0]
        elif g < 384:
            flap = (0.9, 8)
        else:
            flap = (0.85, 6) if (g // 8) % 2 else (0.9, 8)
        key_hawk(A, H, f, flap, offset=(hx, hy), rot=math.degrees(hr), amt=0.0)
        if g >= 463:
            A.scl(H["root"], f, TINY)
        if f >= 447:                                  # the hawk bursts into its paper pieces
            u = seg(g, 447, 463) ** 0.85
            for i, (ob, (dx, dy)) in enumerate(H["parts"]):
                wing = ob in (H["wn"], H["wf"])
                rest = (0.12, 0.08, 0.0) if wing else (0.0, 0.0, ob.location.z)
                A.loc(ob, f, (rest[0] + dx * 3.4 * u, rest[1] + dy * 3.4 * u, rest[2]))
                if not wing:
                    A.rot(ob, f, math.radians((380 if i % 2 else -380) * u))
    for f in range(289, 401, 2):
        A.scl(glint, f, 1.5 if f in (357, 365) else 1.0)
        sp = spark(f, 359, 12)
        A.scl(gspark, f, sp if sp > 0 else TINY)

    # the title card, held on the hawk's head: painted strokes behind, words on the right
    T = dict(root=W, start=419, length=40)
    K = HAWK_S
    paints = [build_swoosh("B_PaintA", W, (P_E[0] - 0.28 * K, P_E[1] + 0.2 * K), 0.26, 0.75 * K, 0.1 * K, 0.2, 28, M.orange),
              build_swoosh("B_PaintB", W, (P_E[0] - 0.36 * K, P_E[1] + 0.05 * K), 0.25, 0.85 * K, 0.11 * K, 0.2, 22, M.sky1),
              build_swoosh("B_PaintC", W, (P_E[0] - 0.2 * K, P_E[1] - 0.22 * K), 0.255, 0.6 * K, 0.07 * K, 0.25, 18, M.blue3)]
    under = build_swoosh("B_TitleLine", W, (P_E[0] + 0.66 * K, P_E[1] - 0.14 * K), 0.42, 0.22 * K, 0.012 * K, 0.1, 2, M.blue)
    for l in steps(T):
        f = F(T, l)
        for i, pnt in enumerate(paints):
            A.scl(pnt, f, 0.55 if l == 26 else (TINY if l > 26 else popup(l, 2 * i, seq=(0.4, 1.08))))
        A.scl(under, f, 0.55 if l == 24 else (TINY if l > 24 else popup(l, 12, seq=(0.4, 1.1))))
    for f in range(1, 419, 2):
        for pnt in paints:
            A.scl(pnt, f, TINY)
        A.scl(under, f, TINY)
    caption(A, T, "B_Title", [("Hawk", 2)], 24, y=P_E[1], x=P_E[0] + 0.66 * K, size=0.16 * K, z=0.42, seed=31)
    caption(A, T, "B_Tag", [("Your second memory.", 8)], 24, y=P_E[1] - 0.09 * K, x=P_E[0] + 0.66 * K, size=0.05 * K,
            z=0.42, seed=33, stagger=0)


# ------------------------------------------------------------------ C: your storage
def icon_doc(name, g):
    paper(name + "_P", doc_page(0.5, 0.64, 0.14), M.white, 0.0, g, wob=0.004)
    paper_multi(name + "_L", [rrect(0.3, 0.035, 0.015, cy=y) for y in (0.12, 0.02, -0.08, -0.18)], [M.slate], 0.004, g)


def icon_voice(name, g):
    paper(name + "_C", rrect(0.8, 0.52, 0.1), M.dark, 0.0, g, wob=0.004)
    rnd = random.Random(9)
    paper_multi(name + "_B", [rrect(0.03, 0.06 + 0.3 * abs(math.sin(j * 1.1)) * rnd.uniform(0.5, 1), 0.015,
                                    cx=-0.3 + 0.06 * j) for j in range(11)], [M.blue], 0.004, g)


def icon_shot(name, g):
    paper(name + "_F", rrect(0.74, 0.56, 0.05), M.white, 0.0, g, wob=0.004)
    landscape_pic(name, g, 0.62, 0.44, 0.0, 0.0, 0.004)


def icon_cam(name, g):
    paper_multi(name + "_Body", [rrect(0.72, 0.5, 0.1, cy=-0.03), rrect(0.26, 0.12, 0.04, cy=0.25)], [M.white], 0.0,
                g, wob=0.004)
    paper(name + "_Ring", circle(0.18, cy=-0.04), M.black, 0.004, g)
    paper(name + "_Lens", circle(0.135, cy=-0.04), M.blue, 0.006, g)
    paper(name + "_Glint", circle(0.04, cx=-0.05, cy=0.0), M.white, 0.008, g)
    paper(name + "_Flash", circle(0.035, cx=0.25, cy=0.13), M.orange, 0.004, g)


def build_C(A, W):
    RC = region("C_Region", C0[0], C0[1], W)
    S = dict(root=RC, start=489, length=124)
    cloud = build_blob("C_Cloud", RC, (-0.4, 1.2), 0.2, r=1.0, mats=[M.white, M.sky1, M.cloud1, M.orange2], seed=5,
                       base=(3.0, 0.5), puffs=[(-0.95, -0.02, 0.48), (-0.35, 0.3, 0.66), (0.4, 0.24, 0.6),
                                               (1.0, -0.04, 0.44), (0.05, 0.02, 0.5)])
    rx, ry, rot, ocx, ocy = 3.3, 0.95, math.radians(-5), -0.4, 1.0
    orbit = empty("C_Orbit", (ocx, ocy, 0.19), RC)
    paper_multi("C_OrbitLine", ring_segments(rx, ry, 0.022, n=110, rot=rot), [M.cream2], 0.0, orbit)
    dots = [(paper(f"C_Dot{i}", circle(r), m, 0.0, RC), ph) for i, (r, m, ph) in
            enumerate(((0.11, M.orange, 0.4), (0.08, M.orange2, 2.6), (0.05, M.blue, 4.4)))]
    icons, badges = [], []
    for i, (label, fn) in enumerate((("Documents", icon_doc), ("Voice notes", icon_voice), ("Screenshots", icon_shot),
                                     ("Camera roll", icon_cam))):
        g = empty(f"C_Icon{i}", (-2.95 + 1.7 * i, -0.5, 0.22), RC, scale=1.25)
        fn(f"C_Icon{i}", g)
        t = text(f"C_IconT{i}", label, "mono", 0.12, M.white, 0.02, g, loc=(0, -0.63))
        paper(f"C_IconChip{i}", rrect(measure([t])[0] + 0.24, 0.25, 0.08, cy=-0.59), M.dark, 0.012, g)
        b = empty(f"C_Badge{i}", (0.34, 0.24, 0.02), g)
        paper(f"C_BadgeD{i}", circle(0.1), M.blue, 0.0, b)
        paper(f"C_BadgeT{i}", tick(0.06), M.white, 0.004, b)
        icons.append(g)
        badges.append(b)
    to_cloud = sightline("C_SC", RC, (3.18, 1.2), (1.25, 1.2), 7)
    to_icons = sightline("C_SI", RC, (3.3, 0.72), (2.55, 0.1), 4)
    blob = build_blob("C_Blob", RC, (-5.0, -2.2), 0.12, r=1.0, mats=[M.orange, M.orange2], seed=8)
    leaves = build_leaves("C_Leaves", RC, (5.2, -2.9), 0.45, n=6, spread=(-70, 20), length=(1.0, 1.8), width=0.4,
                          mats=[M.leafb, M.leafb2, M.teal], seed=9, rib=M.leafb2)
    twinkles = paper_multi("C_Twinkles", [move(sparkle(r, N=48), x, y) for x, y, r in
                                          ((-2.6, 2.2, 0.07), (1.9, 2.4, 0.06), (-3.9, 0.6, 0.05), (2.8, 0.2, 0.05))],
                           [M.white], 0.2, RC)
    for l in steps(S):
        f = F(S, l)
        A.scl(cloud, f, popup(l, 10))
        A.scl(orbit, f, popup(l, 14, seq=(0.5, 1.05)))
        for i, (d, ph) in enumerate(dots):
            a = ph + 0.05 * l
            x, y = rx * math.cos(a), ry * math.sin(a)
            x, y = x * math.cos(rot) - y * math.sin(rot), x * math.sin(rot) + y * math.cos(rot)
            A.loc(d, f, (ocx + x, ocy + y, 0.21 if math.sin(a) < 0 else 0.185))
            A.scl(d, f, popup(l, 16 + 2 * i, seq=(1.3, 0.9)))
        for i, g in enumerate(icons):
            jx, jy, _ = boil(41 + i, f)
            A.loc(g, f, (-2.95 + 1.7 * i + jx, -0.5 + jy, 0.22))
            A.scl(g, f, 1.25 * popup(l, 40 + 4 * i))
            A.scl(badges[i], f, popup(l, 72 + 6 * i, seq=(1.4, 0.9)))
        for j, d in enumerate(to_cloud):
            key_dash(A, d, f, l, 26 + 2 * j, 70 + 2 * j)
        for j, d in enumerate(to_icons):
            key_dash(A, d, f, l, 58 + 2 * j, 92 + 2 * j)
        A.scl(blob, f, popup(l, 6))
        A.scl(leaves, f, popup(l, 8, seq=(0.5, 1.08)))
        A.scl(twinkles, f, popup(l, 20, seq=(1.3, 0.9)))


# ------------------------------------------------------------------ D: forget the filenames; remember the sunset
def build_sunset_panel(RD):
    P = empty("D_Sunset", (0.4, -1.5, 0.02), RD)
    for i, mat in enumerate(M.sunset[::-1]):                 # yellow at the horizon up to navy-teal
        yb = 1.1 + 0.8 * i
        ph = i * 1.3
        xs = [-6.8 + 0.1 * k for k in range(137)]
        edge = [(x, yb + 0.1 * math.sin(0.6 * x + ph) + 0.04 * math.sin(2.1 * x + ph)) for x in xs]
        paper(f"D_SunsetSky{i}", [(-6.8, 5.6), (6.8, 5.6)] + list(reversed(edge)), mat, 0.002 * i, P)
    paper("D_SunsetSun", circle(0.62, N=96, cx=0.4, cy=1.25), M.sun, 0.012, P, wob=0.01)
    paper_multi("D_SunsetClouds", [move(swoosh(2.2, 0.16, 0.05), -3.4, 2.6), move(swoosh(1.8, 0.12, 0.04), 2.9, 2.9),
                                   move(swoosh(1.4, 0.1, 0.05), -0.6, 3.4), move(swoosh(2.4, 0.14, 0.03), 3.6, 2.2)],
                [M.orange2, M.sunset[2]], 0.013, P, mat_index=[0, 1, 1, 0])
    isl_l = hill_fn(1.25, [(0.25, 0.9), (0.08, 2.5)], 51)
    isl_r = hill_fn(1.2, [(0.3, 0.7), (0.1, 2.2)], 52)
    paper("D_IslandL", [(-6.8, 1.0), (-1.6, 1.0)] + [(x, max(1.0, isl_l(x) + 0.25 * math.sin((x + 6.8) / 5.2 * math.pi)))
                                                    for x in [(-1.6 - 0.1 * k) for k in range(53)]], M.island, 0.014, P)
    paper("D_IslandR", [(2.4, 1.0), (6.8, 1.0)] + [(x, max(1.0, isl_r(x) + 0.3 * math.sin((x - 2.4) / 4.4 * math.pi)))
                                                  for x in [(6.8 - 0.1 * k) for k in range(45)]], M.island, 0.014, P)
    paper("D_SunsetSea", rrect(13.6, 1.25, 0.0, cy=0.6), M.sea, 0.016, P)
    paper_multi("D_SunsetGlints", [rrect(1.3 - 0.18 * i, 0.04, 0.015, cx=0.4, cy=1.05 - 0.13 * i) for i in range(7)],
                [M.reflect], 0.018, P)
    palms = palm_polys(2.7, 0.25, cx=-5.6, cy=0.2) + [[(-x - 0.6, y) for x, y in p] for p in palm_polys(2.3, 0.25, cx=-6.3, cy=0.2)]
    paper_multi("D_SunsetPalms", palms, [M.palm], 0.02, P)
    return P


def build_D(A, W):
    RD = region("D_Region", D0[0], D0[1], W)
    S = dict(root=RD, start=641, length=104)
    g_ = 9.0
    sunset = build_sunset_panel(RD)
    ga = empty("D_StripA", (-0.4, 1.05, 0.22), RD, rot=math.radians(-3))
    ta = text("D_StripAT", "IMG_20230814_183022.jpg", "mono", 0.2, M.black, 0.03, ga, loc=(0, -0.07))
    wa = measure([ta])[0]
    paper("D_StripAP", rrect(wa + 0.5, 0.46, 0.04), M.white, 0.0, ga, wob=0.004, seed=51)
    ball = empty("D_Ball", (-0.4, 1.05, 0.3), RD)
    paper("D_BallP", crumple(0.33, 5), M.white, 0.0, ball, wob=0.01, seed=52)
    tangle = []
    for k in range(3):
        tangle += ring_segments(0.2, 0.09, 0.02, n=40, rot=k * 1.05)
    paper_multi("D_BallTangle", tangle, [M.blue], 0.012, ball)
    gb = empty("D_StripB", (0.2, 0.05, 0.22), RD, rot=math.radians(2))
    tl = text("D_StripBTL", "Drive / 2023 / Trips /", "mono", 0.2, M.black, 0.03, gb, align="RIGHT")
    tr_ = text("D_StripBTR", "misc / final", "mono", 0.2, M.black, 0.03, gb, align="LEFT")
    probe = text("D_Probe", "0", "mono", 0.2, M.black, 0.03, gb)
    wl, wr, w0 = measure([tl, tr_, probe])
    bpy.data.objects.remove(probe, do_unlink=True)
    Wd, hh = wl + w0 + wr + 0.5, 0.23
    x_t = -Wd / 2 + 0.25 + wl + w0 / 2
    zz = zig(x_t, -hh, hh, 8, 0.05, 54)
    gl = empty("D_HalfL", (-Wd / 2, 0, 0), gb)
    gr = empty("D_HalfR", (Wd / 2, 0, 0), gb)
    paper("D_HalfLP", move([(-Wd / 2, -hh)] + zz + [(-Wd / 2, hh)], Wd / 2, 0), M.white, 0.0, gl)
    paper("D_HalfRP", move([zz[0], (Wd / 2, -hh), (Wd / 2, hh), zz[-1]] + list(reversed(zz[1:-1])), -Wd / 2, 0),
          M.white, 0.0, gr)
    tl.parent, tr_.parent = gl, gr
    tl.location = (x_t - w0 / 2 + Wd / 2, -0.07, 0.027)
    tr_.location = (x_t + w0 / 2 - Wd / 2, -0.07, 0.027)
    # paper scraps burst from the tear
    rnd = random.Random(55)
    tear = (0.2 + x_t, 0.05)
    scraps = []
    for i in range(14):
        s_ = rnd.uniform(0.07, 0.15)
        shape = [(0, s_), (-s_ * 0.8, -s_ * 0.6), (s_ * 0.9, -s_ * 0.4)] if i % 2 else rrect(s_ * 1.4, s_ * 0.8, 0.01)
        ob = paper(f"D_Scrap{i}", shape, [M.blue2, M.orange, M.white, M.sky1, M.orange2][i % 5], 0.32, RD)
        scraps.append((ob, rnd.uniform(-2.6, 2.6), rnd.uniform(0.6, 2.8), rnd.uniform(-420, 420)))
    # remembered words, handwritten, strung on a thin line
    wg = empty("D_Words", (0, 0, 0.3), RD)
    words = [("the sunset…", (-3.3, 2.15), -6, 64), ("my sister laughing", (-0.1, 2.5), -4, 70), ("Goa?", (2.7, 2.2), 6, 76)]
    floaters = [text(f"D_Float{i}", w, "hand", 0.46, M.white, 0.0, wg, loc=p, rot=math.radians(r))
                for i, (w, p, r, _) in enumerate(words)]
    strings = [paper_multi("D_String0", [move(wave_strip(1.0, 0.02, 0.05, 3.0, 0.4), -1.65, 2.3),
                                         rrect(0.022, 0.13, 0.01, cx=-2.15, cy=2.3), rrect(0.022, 0.13, 0.01, cx=-1.15, cy=2.3)],
                           [M.white], 0.0, wg),
               paper_multi("D_String1", [move(wave_strip(0.9, 0.02, 0.05, 3.0, 1.4), 1.75, 2.4),
                                         rrect(0.022, 0.13, 0.01, cx=1.3, cy=2.4), rrect(0.022, 0.13, 0.01, cx=2.2, cy=2.4)],
                           [M.white], 0.0, wg)]
    leaves = build_leaves("D_Leaves", RD, (-5.4, -2.9), 0.45, n=6, spread=(-20, 70), length=(1.1, 1.9), width=0.42,
                          mats=[M.leafb, M.orange, M.leafb2], seed=14, rib=M.leafb2)
    for l in steps(S):
        f = F(S, l)
        fold = seq_at(l, 96, [0.7, 0.3], None)
        A.scl(sunset, f, (1, fold if fold is not None else (TINY if l > 98 else popup(l, 58, seq=(0.3, 0.75, 1.06, 0.98))), 1))
        jx, jy, jr = boil(55, f)
        sca = popup(l, 2) if l < 24 else ((0.92, 1.08, 1) if l == 24 else ((0.6, 1.25, 1) if l == 26 else TINY))
        A.scl(ga, f, sca)
        A.loc(ga, f, (-0.4 + jx, 1.05 + jy, 0.22))
        A.rot(ga, f, math.radians(-3) + jr)
        b = ball_state(l)
        if b is None or b[0] > 6.1:
            A.scl(ball, f, TINY)
            A.loc(ball, f, (-0.4, 1.05, 0.3) if b is None else (b[0], b[1], 0.3))
        else:
            A.loc(ball, f, (b[0], b[1], 0.3))
            A.rot(ball, f, math.radians(b[2]))
            A.scl(ball, f, pop(l, 28, seq=(1.25, 0.95)))
        jx, jy, _ = boil(58, f)
        A.scl(gb, f, popup(l, 8))
        A.loc(gb, f, (0.2 + jx, 0.05 + jy, 0.22))
        if l < 40:
            A.rot(gl, f, 0.0)
            A.rot(gr, f, 0.0)
            A.loc(gl, f, (-Wd / 2, 0, 0))
            A.loc(gr, f, (Wd / 2, 0, 0))
        else:
            t = (l - 40) / 24.0
            A.rot(gl, f, math.radians(-(10 + 60 * t)))
            A.loc(gl, f, (-Wd / 2 - 0.3 * t, -0.5 * g_ * t * t, 0))
            A.rot(gr, f, math.radians(14 + 80 * t))
            A.loc(gr, f, (Wd / 2 + 0.4 * t, -0.55 * g_ * t * t, 0))
        for ob, vx, vy, spin in scraps:
            t = max(0.0, (l - 40) / 24.0)
            A.loc(ob, f, (tear[0] + vx * t, tear[1] + vy * t - 1.5 * t * t, 0.32))
            A.rot(ob, f, math.radians(spin * t))
            A.scl(ob, f, TINY if (l < 40 or l > 96) else (1.3 if l == 40 else 1.0))
        A.loc(wg, f, (0, 0.012 * max(0, (l - 64) / 2), 0.3))
        for i, (ob, (w, p, r, t0)) in enumerate(zip(floaters, words)):
            s = TINY if (l < t0 or l > 98) else (0.55 if l == 98 else (seq_at(l, t0, [1.2, 0.95]) or 1.0))
            A.scl(ob, f, s)
            A.rot(ob, f, math.radians(r) + boil(57 + i, f, 0.0, 1.5)[2])
        for i, st_ in enumerate(strings):
            A.scl(st_, f, TINY if (l < words[i + 1][3] or l > 98) else (0.55 if l == 98 else 1.0))
        A.scl(leaves, f, popup(l, 6, seq=(0.5, 1.08)))


# ------------------------------------------------------------------ E: ask, find, everything, close
def build_E(A, W):
    RE = region("E_Region", E0[0], E0[1], W)
    S1 = dict(root=RE, start=781, length=240)
    S2 = dict(root=RE, start=1021, length=144)
    S3 = dict(root=RE, start=1165, length=132)
    back = hill_fn(-0.2, [(0.3, 0.45), (0.12, 1.4)], 61)
    front = hill_fn(-0.65, [(0.25, 0.6), (0.1, 1.9)], 62)
    paper("E_HillsBack", hills(back, -11, 9, bottom=-1.6), tone("#17284a"), 0.015, RE)
    paper("E_HillsFront", hills(front, -11, 9, bottom=-1.6), tone("#111f38"), 0.02, RE)
    shelf_b = build_shelf("E_ShelfBack", RE, 3.3, -1.45, 1.9, 3.7, 0.04, tone("#1a2436"))
    shelf = build_shelf("E_Shelf", RE, 4.45, -1.45, 1.65, 3.1, 0.1, M.wood2, tone("#141a22"),
                        [M.leafb2, M.teal2, M.wood, M.orange, tone("#243f66")], seed=61)
    build_podium("E_Podium", RE, (-3.5, -1.72), 0.3, w=2.3, h=1.3)
    build_leaves("E_LeavesL", RE, (-5.6, -3.0), 0.45, n=6, spread=(-10, 60), length=(1.2, 2.0), width=0.45,
                 mats=[M.teal, M.teal2, M.leafb], seed=15, rib=M.teal2)
    build_leaves("E_LeavesR", RE, (5.4, -3.0), 0.45, n=6, spread=(-70, 10), length=(1.1, 1.9), width=0.42,
                 mats=[M.orange, M.leafb, M.orange2], seed=16, rib=M.wood2)
    photo = build_card("E_Photo", RE, "photo", variant="sunset")

    # the ask: a speech bubble that types itself, then feeds into the eye
    B0 = (-1.2, 1.6)
    bub = empty("E_Bubble", (B0[0], B0[1], 0.36), RE)
    paper("E_BubbleP", rrect(3.9, 1.0, 0.28), M.white, 0.0, bub, wob=0.006)
    paper("E_BubbleTail", [(-1.45, -0.45), (-1.02, -0.45), (-1.85, -0.92)], M.white, 0.0, bub)
    paper_multi("E_BubbleMarks", [rrect(0.26, 0.03, 0.014, cx=-2.2), rrect(0.26, 0.03, 0.014, cx=2.2)],
                [M.white], 0.0, bub)
    line1 = word_row("E_Say1", [("“that sunset with my sister,", 0)], "mono", 0.18, M.black, 0.02, (0, 0.12), bub)
    line2 = word_row("E_Say2", [("in Goa", 0)], "mono", 0.18, M.black, 0.02, (0, -0.26), bub)
    for line in (line1, line2):
        w0, w1 = measure([line[0][0], line[-1][0]])
        left = line[0][0].location.x - w0 / 2
        for ob, _ in line:
            ob.location.x += -1.7 - left
    endx = line2[-1][0].location.x + measure([line2[-1][0]])[0] / 2
    wave = paper_multi("E_BubbleWave", [rrect(0.034, 0.06 + 0.16 * abs(math.sin(j * 1.3)), 0.014, cx=0.075 * j)
                                        for j in range(7)], [M.blue], 0.02, bub, loc=(endx + 0.25, -0.2))
    typed = [ob for ob, _ in line1 + line2]
    dashes = sightline("E_Sight", RE, (2.78, 0.85), (3.95, 0.45), 4)

    # the answer: a pale-blue card with the place, the date and the photo, and the file chip under it
    ans = empty("E_Answer", (-0.3, -0.33, 0.32), RE)
    paper("E_AnsP", rrect(3.7, 1.15, 0.16), M.paleblue, 0.0, ans, wob=0.006)
    text("E_AnsTitle", "Palolem Beach, Goa", "serif", 0.29, M.black, 0.02, ans, loc=(-1.66, 0.04), align="LEFT")
    text("E_AnsDate", "26 Dec 2023", "sans", 0.16, M.slate, 0.02, ans, loc=(-1.66, -0.33), align="LEFT")
    paper("E_AnsThumbF", rrect(0.86, 0.86, 0.06), M.white, 0.01, ans, loc=(1.3, 0.0))
    th = empty("E_AnsThumb", (1.3, 0.0, 0.0), ans)
    sunset_pic("E_AnsThumbPic", th, 0.74, 0.74, 0.0, 0.0, 0.014)
    chip = empty("E_AnsChip", (-0.3, -1.2, 0.32), RE)
    _chip("E_Ans", chip, "IMG_4829.JPG  ·  PHONE / CAMERA ROLL", size=0.1)

    for l in steps(S1):
        f = F(S1, l)
        jx, jy, _ = boil(64, f, 0.004)
        if l < 32:
            A.scl(bub, f, TINY)
            A.loc(bub, f, (B0[0], B0[1], 0.36))
        elif l < 80:
            A.scl(bub, f, popup(l, 32, seq=(0.3, 0.8, 1.08, 0.97)))
            A.loc(bub, f, (B0[0] + jx, B0[1] + jy, 0.36))
        else:
            t = smooth(seg(l, 80, 92))
            A.scl(bub, f, max(TINY, 1 - t))
            A.loc(bub, f, (lerp(B0[0], 1.9, t), lerp(B0[1], 0.95, t), 0.36))
        for k, ob in enumerate(typed):
            A.scl(ob, f, TINY if l < 36 + 4 * k else (1.2 if l == 36 + 4 * k else 1.0))
        A.scl(wave, f, popup(l, 36 + 4 * len(typed), seq=(1.3, 0.9)))
        x, y, z, r, sc, p, state, _ = photo_path(l)
        key_card(A, photo, f, x, y, z, r, sc, state, pop_s=p, seed=62)
        for j, d in enumerate(dashes):
            key_dash(A, d, f, l, 118 + 3 * j, 142 + 3 * j)
        A.scl(ans, f, popup(l, 180, seq=(0.5, 1.15, 0.96)))
        A.scl(chip, f, popup(l, 186, seq=(0.5, 1.15, 0.96)))

    # everything you keep: three more asks, three more finds
    items = [("doc", (3.35, 0.35, -6.0, 0.72), "lease-renewal.pdf  ·  PAGE 2", "“When does my lease renew?”"),
             ("voice", (4.75, -0.4, 4.0, 0.72), "call-with-mum.m4a  ·  FROM 01:12", "“What did Mum say about the recipe?”"),
             ("board", (5.5, 0.95, -3.0, 0.66), "whiteboard.jpg  ·  TEXT IN IMAGE", "“What did we write on the whiteboard?”")]
    mcards = []
    for k, (kind, tgt, chip_label, q) in enumerate(items):
        mcards.append((build_card(f"E_{kind}", RE, kind, trace=False, chip=chip_label), tgt, kind))
        b = 40 * k
        caption(A, S2, f"E_Q{k}", [(q, b + 4)], (b + 38) if k < 2 else 140, y=-0.2, x=1.9, size=0.15,
                fkey="serif_i", z=0.3, seed=70 + 10 * k)
    for l in steps(S2):
        f = F(S2, l)
        A.scl(ans, f, 0.55 if l == 0 else TINY)
        A.scl(chip, f, 0.55 if l == 0 else TINY)
        fold = seq_at(l, 2, [1.06, 0.7, 0.3]) or (1.0 if l < 2 else TINY)
        A.scl(shelf, f, (1, fold, 1))
        A.scl(shelf_b, f, (1, fold, 1))
        for k, (C, (tx, ty, tr, ts), kind) in enumerate(mcards):
            b = 40 * k
            if l < b + 20:
                key_card(A, C, f, 8.5, 3.3, 1.0, 25, ts, "hidden", seed=71 + k)
            else:
                t = seg(l, b + 20, b + 32)
                z = 1.0 - (0.8 - 0.08 * k) * ease_in(seg(l, b + 30, b + 34))
                chip_on = (b + 32 <= l < b + 72) if k < 2 else (l >= b + 32)
                key_card(A, C, f, lerp(8.5, tx, ease_out(t)), lerp(3.3, ty, ease_out(t)) + 0.3 * math.sin(math.pi * t),
                         z, lerp(25, tr, back_out(t, 2.0)), ts, "solid", pop_s=pop(l, b + 32, seq=(1.04, 0.99)),
                         seed=71 + k, chip=chip_on)
            if kind == "doc":
                A.scl(C["hl"], f, (clamp((l - (b + 32)) / 10.0), 1, 1) if l >= b + 34 else TINY)
            elif kind == "voice":
                for j, bar in enumerate(C["played"]):
                    A.scl(bar, f, 1.0 if l >= b + 34 + 2 * (j // 2) else TINY)
            else:
                A.scl(C["hl"], f, popup(l, b + 34, seq=(1.2, 0.95)))

    # the memories you already have, close again; painted strokes bloom around them
    x1, y1, z1, r1, s1, _, _, _ = photo_path(238)
    starts = [(photo, (x1, y1, z1, r1, s1))] + [(C, (tx, ty, 0.2 + 0.08 * k, tr, ts))
                                               for k, (C, (tx, ty, tr, ts), _) in enumerate(mcards)]
    targets = [(-6.1, 1.35, -8, 0.46), (-1.6, 1.5, 7, 0.42), (-6.2, -0.05, 5, 0.45), (-1.25, 0.15, -5, 0.45)]
    blooms = [build_swoosh("E_BloomA", RE, (-8.1, 2.3), 0.03, 2.8, 0.38, 0.2, -18, M.orange),
              build_swoosh("E_BloomB", RE, (-7.5, 2.75), 0.032, 2.3, 0.26, 0.2, -12, M.sky1),
              build_swoosh("E_BloomC", RE, (0.7, 2.5), 0.03, 2.2, 0.3, 0.22, 20, M.blue2),
              build_swoosh("E_BloomD", RE, (1.1, -2.3), 0.12, 2.4, 0.3, 0.2, 24, M.orange2)]
    for l in steps(S3):
        f = F(S3, l)
        for k, ((C, a0), b1) in enumerate(zip(starts, targets)):
            t = seg(l, 4 + 4 * k, 28 + 4 * k)
            e = smooth(t)
            z = lerp(a0[2], 0.6, ease_out(t))
            bob = 0.03 * math.sin(l * 0.14 + k) * seg(l, 28, 40)
            key_card(A, C, f, lerp(a0[0], b1[0], e), lerp(a0[1], b1[1], e) + 0.35 * math.sin(math.pi * t) + bob, z,
                     lerp(a0[3], b1[2], e), lerp(a0[4], b1[3], e), "solid",
                     pop_s=pop(l, 28 + 4 * k, seq=(1.06, 0.98)), seed=81 + k, chip=False)
        for i, bl in enumerate(blooms):
            A.scl(bl, f, popup(l, 30 + 4 * i, seq=(0.35, 1.1)))
    for f in range(1, 1165, 2):
        for bl in blooms:
            A.scl(bl, f, TINY)


# ------------------------------------------------------------------ END: the sky above E
def build_END(A, W):
    RN = region("END_Region", END_C[0], END_C[1], W)
    S = dict(root=RN, start=1297, length=144)
    strokes = [build_swoosh("END_SwA", RN, (-4.7, 2.3), 0.03, 3.2, 0.5, 0.2, -24, M.orange),
               build_swoosh("END_SwB", RN, (-5.0, 1.7), 0.032, 2.8, 0.34, 0.2, -18, M.sky1),
               build_swoosh("END_SwC", RN, (4.8, -2.3), 0.03, 3.2, 0.46, 0.2, 18, M.blue2),
               build_swoosh("END_SwD", RN, (5.0, -1.7), 0.032, 2.6, 0.3, 0.2, 22, M.orange2)]
    leaves = build_leaves("END_Leaves", RN, (-5.3, -3.1), 0.45, n=5, spread=(-10, 60), length=(1.1, 1.8), width=0.42,
                          mats=[M.leafb, M.leafb2, M.teal], seed=17, rib=M.leafb2)
    for l in steps(S):
        f = F(S, l)
        for i, s_ in enumerate(strokes):
            A.scl(s_, f, popup(l, 30 + 3 * i, seq=(0.35, 1.1)))
        A.scl(leaves, f, popup(l, 36, seq=(0.5, 1.08)))
    for f in range(1, 1297, 2):
        for s_ in strokes:
            A.scl(s_, f, TINY)
        A.scl(leaves, f, TINY)
    caption(A, S, "END_Word", [("Hawk", 50)], 999, y=-0.85, size=1.0, seed=92)
    caption(A, S, "END_Small1", [("INDEXED ON YOUR DEVICE", 66)], 999, y=-1.45, size=0.11, fkey="sans", stagger=0,
            seed=94)
    caption(A, S, "END_Small2", [("FILES NEVER LEAVE WITHOUT YOU", 70)], 999, y=-1.68, size=0.11, fkey="sans",
            stagger=0, seed=95)


# ------------------------------------------------------------------ the top glass: captions ride with the camera
GLASS_Z = 0.7
CAPTIONS = [
    ([("We keep so much of our lives", 11), ("in places we can no longer *see.*", 41)], 137),
    ([("We *remember* the moment.", 165), ("Not where we put it.", 209)], 281),
    ([("A hawk sees what is almost invisible,", 333), ("*from far away.*", 359)], 391),
    ([("Bring your *own storage.*", 507)], 551),
    ([("Originals stay where they live.", 555), ("Hawk keeps *only the index.*", 579)], 607),
    ([("No filenames.", 669), ("*No folders.*", 681)], 699),
    ([("Just remember what you *remember.*", 703)], 741),
    ([("Ask in *your own words.*", 789)], 869),
    ([("Get the answer,", 963), ("and the *file behind it.*", 983)], 1017),
    ([("Documents.", 1055), ("Voice notes.", 1095), ("Photos, even the words *inside them.*", 1135)], 1161),
    ([("You remember it.", 1177), ("Hawk helps you *see it.*", 1215)], 1291),
]


def build_glass(A, W):
    glass = empty("Glass", (0, 0, GLASS_Z), W)
    for f in range(1, LAST + 1):
        cx, cy, cz = cam_path(f)
        A.loc(glass, f, (cx, cy, GLASS_Z))
        A.scl(glass, f, (cz - GLASS_Z) / (14.0 - GLASS_Z) if cz > 3.0 else TINY)
    A.smooth(glass)
    G = dict(root=glass, start=1, length=LAST)
    for i, (segs, out_f) in enumerate(CAPTIONS):
        items = caption(A, G, f"Cap{i:02d}", [(t, f_in - 1) for t, f_in in segs], out_f - 1, y=-2.72, size=0.27,
                        z=0.0, seed=200 + 10 * i)
        for ob, _ in items:
            ob.visible_shadow = False


def main():
    scene = bpy.context.scene
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.materials,
                 bpy.data.actions):
        for b in list(coll):
            coll.remove(b)
    scene.timeline_markers.clear()
    init_palette()
    col = bpy.data.collections.new("HawkFilm")
    scene.collection.children.link(col)
    use_collection(col)

    w = scene.world or bpy.data.worlds.new("World")
    scene.world = w
    if w.node_tree is None:
        w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.003, 0.005, 0.012, 1)
    bg.inputs["Strength"].default_value = 1.0

    W = empty("World_Root", (0, 0, 0))
    build_world(W)

    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 3.6
    sd.color = (0.94, 0.96, 1.0)
    sd.angle = math.radians(14)
    if hasattr(sd, "use_shadow_jitter"):
        sd.use_shadow_jitter = True
    sun = bpy.data.objects.new("Sun", sd)
    col.objects.link(sun)
    sun.rotation_euler = Vector((5.0, -4.5, -11.0)).to_track_quat("-Z", "Y").to_euler()

    cd = bpy.data.cameras.new("Cam")
    cd.lens, cd.sensor_width, cd.sensor_fit = 46, 36, "HORIZONTAL"
    cd.clip_end = 80
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = 1.4
    cam = bpy.data.objects.new("Cam", cd)
    col.objects.link(cam)
    scene.camera = cam

    A = Anim()
    build_A(A, W)
    build_B(A, W)
    build_C(A, W)
    build_D(A, W)
    build_E(A, W)
    build_END(A, W)
    build_glass(A, W)

    E = build_eye("Eye", W, (0, 0), EYE_Z, 1.0, wave=True)
    P = build_person("Person", W, PERSON_A, 0.78)
    for f in range(1, LAST + 1):
        st = guide(f)
        key_eye(A, E, f, bf=pair(f), seed=3, **st)
        pos, pose, flip, lift = person(f)
        key_person(A, P, f, pose, flip=flip, lift=lift, pos=pos, bf=pair(f), seed=11)
        x, y, z = cam_path(f)
        A.loc(cam, f, (x, y, z))
        fz = focus_z(f)
        cd.dof.focus_distance = max(0.01, z - fz)
        cd.keyframe_insert("dof.focus_distance", frame=f)
        cd.clip_start = min(0.1, max(0.001, 0.03 * (z - fz)))
        cd.keyframe_insert("clip_start", frame=f)
    A.smooth(cam)
    n = A.flush()
    print(f"keyframes: {n}, objects: {len(bpy.data.objects)}")

    r = scene.render
    r.resolution_x, r.resolution_y, r.resolution_percentage = 1920, 1080, 100
    r.fps = 24
    scene.frame_start, scene.frame_end = 1, LAST
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.filepath = "//frames/hf_"
    scene.eevee.taa_render_samples = 32
    if hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = "Standard"
    for scr in bpy.data.screens:                               # open looking through the camera, rendered
        for area in scr.areas:
            for sp in area.spaces:
                if sp.type == "VIEW_3D":
                    sp.region_3d.view_perspective = "CAMERA"
                    sp.shading.type = "RENDERED"
                    ov = sp.overlay
                    ov.show_relationship_lines = ov.show_extras = ov.show_floor = False
                    ov.show_axis_x = ov.show_axis_y = False
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "hawk_film.blend"))
    print("saved", bpy.data.filepath)


if __name__ == "__main__":
    main()
