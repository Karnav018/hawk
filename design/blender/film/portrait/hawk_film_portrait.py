"""Builds the 9:16 PORTRAIT version of the Hawk launch film: the same one-take story, motion and pieces as
the landscape cut, re-laid out so every scene fits a tall phone frame without anything being cut off.

    Blender -b --factory-startup --python design/blender/film/portrait/hawk_film_portrait.py

This is the landscape film's original scene script with its positions re-arranged for 9:16: what sat side
by side in landscape is stacked or tightened vertically. The finishing passes are the same as the
landscape cut (painted texture, the dive into the pupil with the eyelid opening, crisp text, 1.2x speed);
see the "Portrait (9:16)" section of design/blender/film/README.md for the full pipeline.

The camera lens gives a frame 6.2 units wide (11 tall) at the usual camera height; content is kept inside
x +-2.85 so nothing touches the edges. Captions sit in the lower third, clear of phone app buttons.
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
from puppets import (FLAP, HAWK_EYE, POSES, _chip, back_out, blink, build_card, build_eye, build_hawk,  # noqa: E402
                     build_person, build_shelf, build_thought, caption, clamp, crumple, doc_page, ease_in,
                     ease_out, hill_fn, hills, key_card, key_dash, key_eye, key_hawk, key_person, lerp, mix,
                     pop, popup, seg, seq_at, sightline, smooth, spark, tick, zig)

LAST = 1440
FRAME_W = 6.2                                   # frame width at the usual camera height (z 14)
LENS = 36.0 * 14.0 / FRAME_W
EYE_Z = 0.33
EYE_S0 = 0.11
D_MIN = 0.55
HAWK_Y = 11.9                                   # the sky sits higher: the portrait archive is taller
B_CAM = (0.3, 11.3)
P_E = (-0.5 + HAWK_EYE[0], HAWK_Y + HAWK_EYE[1])
GROUND_Y = 0.9                                  # camera height over the ground scenes
C0, D0, E0 = (15.5, 0.0), (27.0, 0.0), (39.5, 0.0)
C_EYE = (C0[0], 3.6)
D_EYE = (D0[0] + 1.6, 4.0)
E_EYE = (E0[0] + 1.0, 3.3)
PERSON_A, PERSON_PARK, PERSON_E = (0.0, -0.62), (E0[0] - 4.8, -0.62), (E0[0] - 1.6, -0.62)
E3_EYE = (PERSON_E[0] + 1.9, 4.2)
END_C = (PERSON_E[0], 11.0)
END_EYE = (END_C[0], END_C[1] + 0.85)
CAP_Y, CAP_SIZE, CAP_MAX = -2.9, 0.28, 5.2


def pair(f):
    """The pose frame: poses change on odd frames and hold for two (animation on twos)."""
    return f - ((f - 1) % 2)


def region(name, x, y, parent):
    return empty(name, (x, y, 0), parent)


def steps(S):
    return range(0, S["length"], 2)


def F(S, l):
    return S["start"] + l


# ------------------------------------------------------------------ the one camera
def eye_top(s):
    return EYE_Z + 0.5 * s


def d_pull(f):
    e = smooth(seg(f, 424, 468))
    return math.exp(lerp(math.log(D_MIN), math.log(13.17), e))


def eye_grow(f):
    if f <= 424:
        return EYE_S0
    if f >= 468:
        return 1.0
    return min(1.0, EYE_S0 * d_pull(f) / D_MIN)


def cam_path(f):
    if f <= 144:
        t = (f - 1) / 143.0
        return (0.0, 0.6, 13.6 - 0.2 * smooth(t))
    if f <= 288:                                               # pull back: the tall archive unfolds
        t = smooth(seg(f, 144, 235))
        return (0.0, lerp(0.6, 2.2, t), lerp(13.4, 19.0, t))
    if f <= 324:                                               # tilt up past the shelves into the sky
        t = smooth(seg(f, 288, 324))
        return (lerp(0.0, -0.5, t), lerp(2.2, B_CAM[1], t), lerp(19.0, 14.0, t))
    if f <= 396:                                               # drift with the hawk
        t = smooth(seg(f, 324, 396))
        return (lerp(-0.5, B_CAM[0], t), B_CAM[1], 14.0)
    if f <= 424:                                               # dive (replaced by the dive pass)
        e = smooth(seg(f, 396, 424))
        top = eye_top(EYE_S0)
        d0 = 14.0 - top
        d = math.exp(lerp(math.log(d0), math.log(D_MIN), e))
        sx, sy = (P_E[0] - B_CAM[0]) / d0 * (1 - e), (P_E[1] - B_CAM[1]) / d0 * (1 - e)
        return (P_E[0] - sx * d, P_E[1] - sy * d, top + d)
    if f <= 468:
        m = smooth(seg(f, 436, 468))
        return (lerp(P_E[0], B_CAM[0], m), lerp(P_E[1], B_CAM[1], m), eye_top(eye_grow(f)) + d_pull(f))
    if f <= 504:                                               # follow the eye down to storage
        t = smooth(seg(f, 468, 504))
        return (lerp(B_CAM[0], C0[0], t), lerp(B_CAM[1], GROUND_Y, t), 14.0)
    if f <= 612:
        t = smooth(seg(f, 504, 612))
        return (C0[0], GROUND_Y, lerp(14.0, 13.8, t))
    if f <= 648:
        t = smooth(seg(f, 612, 648))
        return (lerp(C0[0], D0[0], t), GROUND_Y, lerp(13.8, 14.0, t))
    if f <= 744:
        t = smooth(seg(f, 648, 744))
        return (D0[0], GROUND_Y, lerp(14.0, 13.85, t))
    if f <= 780:
        t = smooth(seg(f, 744, 780))
        return (lerp(D0[0], E0[0], t), GROUND_Y, lerp(13.85, 14.0, t))
    if f <= 1020:
        t = smooth(seg(f, 780, 1020))
        return (E0[0], GROUND_Y, lerp(14.0, 13.85, t))
    if f <= 1164:
        t = smooth(seg(f, 1020, 1047))
        return (lerp(E0[0], E0[0] + 0.25, t), GROUND_Y, lerp(13.85, 14.1, t))
    if f <= 1296:
        t = smooth(seg(f, 1164, 1205))
        u = smooth(seg(f, 1205, 1296))
        return (lerp(E0[0] + 0.25, PERSON_E[0], t), GROUND_Y, lerp(14.1, 14.3, t) - 0.3 * u)
    t = smooth(seg(f, 1296, 1343))                             # tilt up into the sky for the end card
    u = smooth(seg(f, 1343, 1440))
    return (PERSON_E[0], lerp(GROUND_Y, END_C[1], t), lerp(14.0, 14.0, t) - 0.4 * u)


def focus_z(f):
    return eye_top(eye_grow(f)) if 390 <= f <= 470 else 0.42


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
STRIP_A = (0.0, 2.4)
STRIP_B = (0.0, 1.0)


def ball_state(l):
    g, floor, x0, y0, l0 = 9.0, -1.15, STRIP_A[0], STRIP_A[1], 28
    if l < l0:
        return None
    t = (l - l0) / 24.0
    t1 = math.sqrt(2 * (y0 - floor) / g)
    if t < t1:
        return (x0, y0 - 0.5 * g * t * t, -60 * t)
    u = t - t1
    return (x0 + 5.0 * u, floor + 0.35 * abs(math.sin(math.pi * u / 0.32)) * math.exp(-4 * u), -60 * t1 - 520 * u)


# ------------------------------------------------------------------ E: the found photo's flight
PH0, PH1 = (2.0, 0.35, -7.0, 0.44), (-0.9, 2.15, 5.0, 0.56)


def photo_path(l):
    """E-local pose of the photo during the ask (l = frame - 781)."""
    if l < 136:
        return PH0[0], PH0[1] + 0.02 * math.sin(l * 0.1), 0.2, PH0[2], PH0[3], 1.0, "trace", 0.0
    t = seg(l, 146, 172)
    tt = smooth(t)
    pull = 0.12 * math.sin(math.pi * seg(l, 138, 150)) if l < 150 else 0.0
    x = lerp(PH0[0], PH1[0], tt) + pull
    y = lerp(PH0[1], PH1[1], tt) + 0.7 * math.sin(math.pi * tt)
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
    if f <= 424:
        hx, hy, hr = hawk_root(f)
        ex, ey = HAWK_EYE
        pos = (hx + math.cos(hr) * ex - math.sin(hr) * ey, hy + math.sin(hr) * ex + math.cos(hr) * ey)
        st.update(pos=pos, scale=EYE_S0, rot=hr, amt=0.0, brow=1.0, brow_rot=-0.3,
                  gaze=(0.2, -0.3) if 357 <= g < 384 else (0.15, -0.05))
        st["open_y"], st["closed"] = blink(g, 335)
        return st
    if f <= 468:
        st.update(pos=P_E, scale=eye_grow(f), amt=0.0 if f < 452 else 0.005)
        st["pop_s"] = pop(g, 453)
        st["spark_s"] = spark(g, 455, 12)
        st["open_y"], st["closed"] = blink(g, 461)
        return st
    if f <= 504:
        pos, sc, lean = travel(f, 468, 504, P_E, C_EYE, 1.0, 0.6, arc=0.8)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(0.2, -0.3))
        return st
    if f <= 612:                                   # C: looks down into your storage
        st.update(pos=C_EYE, scale=0.6, gaze=(-0.05, -0.32) if g >= 515 else (0.0, 0.0))
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
            st["gaze"] = (-0.3, -0.3) if (g < 669 or b is None) else (clamp((b[0] - 1.6) / 3.0, -1, 1) * 0.34, -0.34)
        else:
            st["open_y"], st["closed"] = blink(g, 719)
            st["gaze"] = (-0.2, -0.25)
            st["pop_s"] = pop(g, 701)
            st["spark_s"] = spark(g, 731, 12)
        return st
    if f <= 780:
        pos, sc, lean = travel(f, 744, 780, D_EYE, E_EYE, 0.45, 0.72, arc=0.6)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(0.3, 0.0))
        return st
    if f <= 1020:                                  # E1: listens, thinks, looks, finds
        l = g - 781
        st.update(pos=E_EYE, scale=0.72)
        st["open_y"], st["closed"] = blink(l, 12, 198, 226)
        st["listen"] = 32 <= l < 92
        st["squash"] = (1.1, 0.85) if l == 30 else ((0.9, 1.1) if l == 92 else (1, 1))
        st["gaze"] = (-0.3, -0.25)
        if 94 <= l < 114:
            st.update(gaze=(0.22, 0.24), brow=1.0, brow_rot=math.radians(-8), pupil=0.9)
        elif 114 <= l < 146:
            st["gaze"] = (0.22, -0.32)
        elif 146 <= l < 178:
            pp = photo_path(l)
            st["gaze"] = (clamp((pp[0] - 1.0) / 2.5, -1, 1) * 0.34, -0.2 + 0.2 * math.sin(math.pi * pp[7]))
        elif l >= 178:
            st.update(gaze=(-0.3, -0.2), pupil=1.25 if l < 212 else 1.0)
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
            st["gaze"] = (0.2, -0.3)
        elif think:
            st["gaze"] = (0.22, 0.24)
        elif d >= 16:
            st["gaze"] = (0.2, -0.3)
        elif d < 6 and k > 0:
            st["gaze"] = (0.2, -0.25)
        st["squash"] = (0.9, 1.1) if d == 16 else (1, 1)
        st["pop_s"] = pop(l, b + 32) * pop(l, b + 6, seq=(1.08, 1.0))
        st["spark_s"] = spark(l, b + 32, 12)
        st["open_y"], st["closed"] = blink(l, 128)
        return st
    if f <= 1205:
        pos, sc, lean = travel(f, 1164, 1205, E_EYE, E3_EYE, 0.72, 0.4, arc=0.4)
        st.update(pos=pos, scale=sc, rot=lean, gaze=(-0.2, -0.2))
        return st
    if f <= 1296:                                  # E3: watches the memories come close
        st.update(pos=E3_EYE, scale=0.4, gaze=(-0.3, -0.3))
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


# ------------------------------------------------------------------ A: lost, then the archive (tall)
def build_A(A, W):
    RA = region("A_Region", 0.0, 0.0, W)
    S1 = dict(root=RA, start=1, length=144)
    S2 = dict(root=RA, start=145, length=144)
    specs = [("photo", (1.35, 2.35), -6, 40, (0.55, 0.85)),       # memories float above and around the head
             ("doc", (-1.5, 2.05), 8, 52, (-0.7, 0.75)),
             ("voice", (1.75, 0.6), 5, 64, (0.9, 0.35)),
             ("board", (-1.85, 0.35), -4, 76, (-0.9, 0.3))]
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

    arch = empty("A_Archive", (0, -1.45, 0), RA)
    rnd = random.Random(2)
    units = []
    for k, x in enumerate((-3.8, -1.9, 0.0, 1.9, 3.8)):              # tall back stacks
        units.append((build_shelf(f"A_Back{k}", arch, x, 0.05, 1.9, 8.0 + rnd.uniform(-0.4, 0.4), 0.03,
                                  tone("#1d1d21")), 4 + 2 * k))
    mid_tags = ["untitled.m4a", "Final_v3_REAL.docx", "misc_old", "New Folder (7)"]
    for k, x in enumerate((-3.0, -1.05, 1.05, 3.0)):
        h = 5.8 + rnd.uniform(-0.3, 0.3)
        units.append((build_shelf(f"A_Mid{k}", arch, x, 0.0, 1.75, h, 0.07,
                                  tone("#3a3a3f"), tone("#141416"), [tone("#4a4a4f"), tone("#55555a"), tone("#2e2e32")],
                                  rows=7, tag=mid_tags[k], tag_mat=tone("#8e8e92"), seed=k, max_binders=4), 12 + 2 * k))
    for k, (x, tag) in enumerate(((-2.45, "IMG_4829.jpg"), (2.45, "Scan_0032.pdf"))):
        units.append((build_shelf(f"A_Front{k}", arch, x, -0.05, 1.6, 4.2 + rnd.uniform(-0.2, 0.2), 0.12,
                                  tone("#8e8e92"), M.black, [M.white, M.light, tone("#9a9a9e"), tone("#6a6a70")],
                                  rows=5, tag=tag, tag_mat=M.white, seed=10 + k), 22 + 4 * k))
    T = build_thought("A_Thought", RA, (0.35, 2.3), 1.0)
    for l in steps(S2):
        f = F(S2, l)
        for u, t0 in units:
            A.scl(u, f, (1, popup(l, t0, seq=(0.25, 0.7, 1.08, 0.97)), 1))
        gone = l >= 138
        for i, b in enumerate(T["bubbles"]):
            A.scl(b, f, TINY if gone else (0.55 if l == 136 else popup(l, 46 + 4 * i, seq=(1.3, 0.9))))
        A.scl(T["cloud"], f, TINY if gone else (0.55 if l == 136 else popup(l, 58)))
        key_card(A, T["card"], f, 0, 0.03, 0.03, 0, 0.5, "hidden" if gone else "solid",
                 pop_s=0.55 if l == 136 else popup(l, 64), seed=22)


# ------------------------------------------------------------------ B: the sky, the hills, the hawk (raised)
def build_B(A, W):
    rnd = random.Random(3)
    clear = [(P_E[0] - 1.6, P_E[0] + 1.6, P_E[1] - 2.8, P_E[1] - 1.5),
             (END_C[0] - 2.3, END_C[0] + 2.3, END_C[1] - 2.3, END_C[1] - 0.4)]
    stars = []
    while len(stars) < 200:
        sx, sy = rnd.uniform(-6, 45), rnd.uniform(7.6, 17.0)
        if not any(a <= sx <= b and c <= sy <= d for a, b, c, d in clear):
            stars.append(circle(rnd.uniform(0.012, 0.03), N=12, cx=sx, cy=sy))
    paper_multi("B_Stars", stars, [M.light], 0.01, W)
    paper("B_Moon", circle(0.55), tone("#3a3a40"), 0.012, W, loc=(2.0, 15.0), wob=0.01, seed=2)
    raw_far = hill_fn(9.85, [(0.4, 0.45), (0.18, 1.3)], 31)
    raw_mid = hill_fn(9.3, [(0.25, 0.8), (0.1, 2.1)], 32)

    def sink(fn):                                   # slope down behind the last shelf instead of a hard edge
        return lambda xx: 6.2 + (fn(xx) - 6.2) * smooth(seg(xx, 9.3, 6.3))
    fn_far, fn_mid = sink(raw_far), sink(raw_mid)
    paper("B_FarHills", hills(fn_far, -12, 10, bottom=6.2), tone("#1b1b1f"), 0.012, W)
    paper("B_MidHills", hills(fn_mid, -12, 10, bottom=6.2), tone("#26262b"), 0.022, W)
    fields, x = [], -11.0
    while x < 9.3:
        for j in range(rnd.randint(2, 4)):
            fx = x + j * 0.24
            fy = fn_mid(fx) - 0.22 - rnd.uniform(0, 0.25)
            fields.append(rrect(0.2, 0.13, 0.02, cx=fx, cy=fy))
            fields.append(rrect(0.09, 0.05, 0.015, cx=fx - 0.05, cy=fy + 0.08))
        x += rnd.uniform(1.0, 1.6)
    paper_multi("B_Fields", fields, [tone("#34343a")], 0.026, W)
    stacks = []
    for sx in (-8.0, -2.4, 1.6, 5.5, 8.8):
        by = fn_mid(sx) - 0.45
        for j in range(4):
            stacks.append(rrect(0.42 - 0.04 * (j % 2), 0.05, 0.015, cx=sx + 0.02 * ((j * 7) % 3 - 1), cy=by + 0.065 * j))
    paper_multi("B_Stacks", stacks, [tone("#6a6a70")], 0.028, W)

    gx = max((0.6 + 0.1 * i for i in range(20)), key=lambda xx: fn_far(xx) - fn_mid(xx))
    gy = fn_far(gx) - 0.2
    glint = paper("B_Glint", circle(0.045), M.blue, 0.016, W, loc=(gx, gy))
    gspark = paper("B_GlintSpark", rotate(sparkle(0.12), 0.3), M.white, 0.018, W, loc=(gx + 0.12, gy + 0.12))

    H = build_hawk("B_Hawk", W, (0, 0), 1.0, 0.3, eye=False)
    for f in range(1, 471):
        g = pair(f)
        hx, hy, hr = hawk_root(f)
        if g < 350:
            flap = FLAP[((g - 289) // 2) % 8] if g >= 289 else FLAP[0]
        elif g < 384:
            flap = (0.9, 8)
        else:
            flap = (0.85, 6)
        key_hawk(A, H, f, flap, offset=(hx, hy), rot=math.degrees(hr), amt=0.0)
        if g >= 443:
            A.scl(H["root"], f, TINY)
        if f >= 425:
            u = seg(g, 425, 441) ** 0.85
            for i, (ob, (dx, dy)) in enumerate(H["parts"]):
                rest = (0.12, 0.08, 0.0) if ob in (H["wn"], H["wf"]) else (0.0, 0.0, ob.location.z)
                A.loc(ob, f, (rest[0] + dx * 3.4 * u, rest[1] + dy * 3.4 * u, rest[2]))
                if ob not in (H["wn"], H["wf"]):
                    A.rot(ob, f, math.radians((380 if i % 2 else -380) * u))
    for f in range(289, 401, 2):
        A.scl(glint, f, 1.5 if f in (357, 365) else 1.0)
        sp = spark(f, 359, 12)
        A.scl(gspark, f, sp if sp > 0 else TINY)
    S_B = dict(root=W, start=289, length=190)
    caption(A, S_B, "B_Word", [("H a w k", 162)], 180, y=P_E[1] - 2.25, x=P_E[0], size=0.9, gap=0.03, seed=32)


# ------------------------------------------------------------------ C: your storage (stacked: eye above, storage below)
def build_C(A, W):
    RC = region("C_Region", C0[0], C0[1], W)
    S = dict(root=RC, start=489, length=124)
    cx, cy, rx, ry = 0.0, 0.55, 2.65, 1.95
    perf = []
    for k in range(46):
        a = 2 * math.pi * k / 46
        tang = math.atan2(ry * math.cos(a), -rx * math.sin(a))
        perf.append(paper(f"C_Perf{k:02d}", rrect(0.17, 0.045, 0.018), M.grey, 0.12, RC,
                          loc=(cx + rx * math.cos(a), cy + ry * math.sin(a)), rot=tang))
    cloud = empty("C_Cloud", (-1.2, 1.45, 0.2), RC)
    for i, (x, y, r) in enumerate(((-0.45, -0.02, 0.4), (0.08, 0.2, 0.52), (0.6, 0.0, 0.36), (0.0, -0.18, 0.4))):
        paper(f"C_CloudC{i}", circle(r, cx=x, cy=y), M.white, 0.03 + 0.003 * i, cloud, wob=0.01, seed=60 + i)
    paper("C_CloudBase", rrect(1.6, 0.46, 0.22, cy=-0.18), M.white, 0.045, cloud, wob=0.006)
    text("C_DriveT", "DRIVE", "sans", 0.16, M.black, 0.06, cloud, loc=(0.05, -0.2))
    pages, page_dots = [], []
    for i, (x, r) in enumerate(((-0.42, 8), (0.0, -3), (0.42, -10))):
        pg = empty(f"C_Page{i}", (x, -0.62, 0), cloud, rot=math.radians(r))
        paper(f"C_PageP{i}", doc_page(0.36, 0.46, 0.1), M.white, 0.0, pg)
        paper_multi(f"C_PageL{i}", [rrect(0.22, 0.025, 0.01, cy=yy) for yy in (0.08, 0.0, -0.08)], [M.mid], 0.01, pg)
        pages.append(pg)
        page_dots.append(paper(f"C_PageDot{i}", circle(0.05), M.blue, 0.02, pg, loc=(0.1, 0.16)))
    PH = (1.2, 1.05)
    phone = empty("C_Phone", (PH[0], PH[1], 0.2), RC)
    paper("C_PhoneRim", rrect(0.8, 1.36, 0.13), M.white, 0.0, phone, wob=0.004)
    paper("C_PhoneScr", rrect(0.68, 1.2, 0.09), M.black, 0.02, phone)
    paper("C_PhoneSpk", rrect(0.16, 0.03, 0.015, cy=0.54), M.dark, 0.03, phone)
    paper_multi("C_Icons", [move(doc_page(0.13, 0.17, 0.04), -0.2 + 0.2 * c_, 0.3 - 0.3 * r_)
                            for r_ in range(3) for c_ in range(3)], [M.light], 0.03, phone)
    icon_dots = [paper(f"C_IconDot{j}", circle(0.032), M.blue, 0.04, phone,
                       loc=(-0.2 + 0.2 * c_ + 0.05, 0.3 - 0.3 * r_ + 0.07))
                 for j, (c_, r_) in enumerate(((0, 0), (2, 0), (1, 1), (0, 2), (2, 1), (1, 2)))]
    to_phone = sightline("C_SP", RC, (0.3, 3.05), (1.1, 1.85), 5)
    to_cloud = sightline("C_SC", RC, (-0.3, 3.05), (-1.05, 2.05), 5)
    labels = ["Documents", "Voice notes", "Screenshots", "Camera roll"]
    texts = [text(f"C_ChipT{i}", lab, "sans", 0.13, M.black, 0.05, RC) for i, lab in enumerate(labels)]
    widths = measure(texts)
    pw = [w + 0.46 for w in widths]
    grid = [(-1.05, -0.2), (1.05, -0.2), (-1.05, -0.7), (1.05, -0.7)]    # two by two inside the ellipse
    chips = []
    for i, (tob, w, p) in enumerate(zip(texts, widths, pw)):
        gx, gy = grid[i]
        g = empty(f"C_Chip{i}", (gx, gy, 0.2), RC)
        tob.parent = g
        tob.location = (0.1, -0.045, 0.047)
        paper(f"C_ChipP{i}", rrect(p, 0.32, 0.16), M.white, 0.03, g, wob=0.003)
        off = paper(f"C_ChipOff{i}", circle(0.07), M.grey, 0.04, g, loc=(-p / 2 + 0.17, 0))
        on = empty(f"C_ChipOn{i}", (-p / 2 + 0.17, 0, 0), g)
        paper(f"C_ChipOnD{i}", circle(0.075), M.blue, 0.042, on)
        paper(f"C_ChipTick{i}", tick(0.05), M.white, 0.046, on)
        chips.append((g, off, on))
    for l in steps(S):
        f = F(S, l)
        for k, d in enumerate(perf):
            A.scl(d, f, popup(l, 6 + 2 * (k // 4), seq=(0.5, 1.15)))
        jx, jy, _ = boil(41, f)
        A.loc(cloud, f, (-1.2 + jx, 1.45 + jy, 0.2))
        A.scl(cloud, f, popup(l, 14))
        for i, pg in enumerate(pages):
            A.scl(pg, f, popup(l, 18 + 2 * i, seq=(0.5, 1.1)))
        jx, jy, _ = boil(42, f)
        A.loc(phone, f, (PH[0] + jx, PH[1] + jy, 0.2))
        A.scl(phone, f, popup(l, 20))
        for j, d in enumerate(to_phone):
            key_dash(A, d, f, l, 36 + 2 * j, 84 + 2 * j)
        for j, d in enumerate(to_cloud):
            key_dash(A, d, f, l, 40 + 2 * j, 88 + 2 * j)
        for j, d in enumerate(icon_dots):
            A.scl(d, f, popup(l, 52 + 4 * j, seq=(1.4, 0.9)))
        for i, d in enumerate(page_dots):
            A.scl(d, f, popup(l, 70 + 4 * i, seq=(1.4, 0.9)))
        for i, (g, off, on) in enumerate(chips):
            A.scl(g, f, popup(l, 92 + 4 * i))
            ton = 102 + 4 * i
            A.scl(off, f, 1.0 if l < ton else TINY)
            A.scl(on, f, popup(l, ton, seq=(1.35, 0.9)))


# ------------------------------------------------------------------ D: forget the filenames (strips stacked)
def build_D(A, W):
    RD = region("D_Region", D0[0], D0[1], W)
    S = dict(root=RD, start=641, length=104)
    g_ = 9.0
    ga = empty("D_StripA", (STRIP_A[0], STRIP_A[1], 0.22), RD, rot=math.radians(-3))
    ta = text("D_StripAT", "IMG_20230814_183022.jpg", "mono", 0.2, M.black, 0.03, ga, loc=(0, -0.07))
    wa = measure([ta])[0]
    paper("D_StripAP", rrect(wa + 0.5, 0.46, 0.04), M.white, 0.0, ga, wob=0.004, seed=51)
    ball = empty("D_Ball", (STRIP_A[0], STRIP_A[1], 0.3), RD)
    paper("D_BallP", crumple(0.33, 5), M.white, 0.0, ball, wob=0.01, seed=52)
    rnd = random.Random(53)
    paper_multi("D_BallCrease", [move(rotate(rrect(rnd.uniform(0.2, 0.4), 0.018, 0.009), rnd.uniform(0, 3.14)),
                                      rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12)) for _ in range(5)],
                [M.mid], 0.012, ball)
    gb = empty("D_StripB", (STRIP_B[0], STRIP_B[1], 0.22), RD, rot=math.radians(2))
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
    words = [("the sunset…", (-1.35, 0.35), 66), ("my sister laughing", (0.75, -0.15), 74), ("Goa?", (-0.5, -0.75), 82)]
    floaters = [text(f"D_Float{i}", w, "serif_i", 0.24, M.white, 0.3, RD, loc=p) for i, (w, p, _) in enumerate(words)]
    for l in steps(S):
        f = F(S, l)
        jx, jy, jr = boil(55, f)
        sca = popup(l, 2) if l < 24 else ((0.92, 1.08, 1) if l == 24 else ((0.6, 1.25, 1) if l == 26 else TINY))
        A.scl(ga, f, sca)
        A.loc(ga, f, (STRIP_A[0] + jx, STRIP_A[1] + jy, 0.22))
        A.rot(ga, f, math.radians(-3) + jr)
        b = ball_state(l)
        if b is None or b[0] > 3.5:
            A.scl(ball, f, TINY)
            A.loc(ball, f, (STRIP_A[0], STRIP_A[1], 0.3) if b is None else (b[0], b[1], 0.3))
        else:
            A.loc(ball, f, (b[0], b[1], 0.3))
            A.rot(ball, f, math.radians(b[2]))
            A.scl(ball, f, pop(l, 28, seq=(1.25, 0.95)))
        jx, jy, _ = boil(58, f)
        A.scl(gb, f, popup(l, 8))
        A.loc(gb, f, (STRIP_B[0] + jx, STRIP_B[1] + jy, 0.22))
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
        for i, (ob, (w, p, t0)) in enumerate(zip(floaters, words)):
            s = TINY if (l < t0 or l > 100) else (0.55 if l == 100 else (seq_at(l, t0, [1.2, 0.95]) or 1.0))
            fx, fy, fr = boil(57 + i, f, 0.004, 1.5)
            A.loc(ob, f, (p[0] + fx, p[1] + 0.035 * max(0, (l - t0) / 2), 0.297))
            A.rot(ob, f, fr + 0.06 * math.sin(l * 0.1 + i))
            A.scl(ob, f, s)


# ------------------------------------------------------------------ E: ask, find, everything, close (stacked)
def build_E(A, W):
    RE = region("E_Region", E0[0], E0[1], W)
    S1 = dict(root=RE, start=781, length=240)
    S2 = dict(root=RE, start=1021, length=144)
    S3 = dict(root=RE, start=1165, length=132)
    shelf_b = build_shelf("E_ShelfBack", RE, 1.1, -1.45, 1.9, 3.9, 0.04, tone("#1d1d21"))
    shelf = build_shelf("E_Shelf", RE, 2.0, -1.45, 1.65, 3.1, 0.1, tone("#2e2e33"), M.black,
                        [tone("#3a3a3f"), tone("#4a4a4f"), tone("#26262a")], seed=61)
    photo = build_card("E_Photo", RE, "photo")

    rib_y, x_left = 2.2, -2.75
    words = word_row("E_Say", [("“that sunset with my sister, in Goa…”", 0)], "serif_i", 0.16, M.black, 0.34,
                     (0, rib_y - 0.055), RE)
    w_first, w_last = measure([words[0][0], words[-1][0]])
    left_edge = words[0][0].location.x - w_first / 2
    total = words[-1][0].location.x + w_last / 2 - left_edge
    for ob, _ in words:
        ob.location.x += (x_left + 0.15) - left_edge
    L = total + 0.3
    rib = empty("E_Ribbon", (x_left, rib_y, 0.3), RE)
    paper("E_RibbonP", move(wave_strip(L, 0.3, 0.025, 2.4, 0.4, cy=0.15), L / 2, 0), M.white, 0.0, rib, wob=0.003)
    word_c = [(ob, ob.location.x - x_left, tuple(ob.location)) for ob, _ in words]
    dashes = sightline("E_Sight", RE, (1.55, 2.75), (2.0, 0.85), 6)
    ans = empty("E_Answer", (0.15, 0.9, 0.25), RE)
    t1 = text("E_AnsT", "Palolem beach, Goa  ·  26 Dec 2023", "sans", 0.13, M.black, 0.04, ans, loc=(0, -0.045))
    paper("E_AnsP", rrect(measure([t1])[0] + 0.5, 0.5, 0.08), M.white, 0.0, ans, wob=0.004)
    chip = empty("E_AnsChip", (0.15, 0.35, 0.25), RE)
    _chip("E_Ans", chip, "IMG_4829.JPG  ·  PHONE / CAMERA ROLL", size=0.085)

    # E1: the ask
    for l in steps(S1):
        f = F(S1, l)
        jx, jy, _ = boil(64, f, 0.004)
        if l < 36:
            s_r, lx = TINY, x_left
        elif l < 80:
            s_r, lx = max(TINY, seg(l, 36, 74)), x_left
        else:
            sf = 1 - seg(l, 80, 92)
            s_r, lx = max(TINY, sf), x_left + (1 - sf) * L
        A.scl(rib, f, (s_r, 1, 1) if s_r > TINY else TINY)
        A.loc(rib, f, (lx + jx, rib_y + jy, 0.3))
        for ob, c, base in word_c:
            l_vis = 36 + 2 * math.ceil(19 * c / L)
            l_hide = 80 + 2 * math.ceil(6 * c / L)
            s = TINY if (l < l_vis or l >= l_hide) else (1.2 if l == l_vis else 1.0)
            A.scl(ob, f, s)
            A.loc(ob, f, (base[0] + jx, base[1] + jy, base[2]))
        x, y, z, r, sc, p, state, _ = photo_path(l)
        key_card(A, photo, f, x, y, z, r, sc, state, pop_s=p, seed=62)
        for j, d in enumerate(dashes):
            key_dash(A, d, f, l, 118 + 2 * j, 142 + 2 * j)
        A.scl(ans, f, popup(l, 180, seq=(0.5, 1.15, 0.96)))
        A.scl(chip, f, popup(l, 186, seq=(0.5, 1.15, 0.96)))

    # E2: everything you keep -- the three finds stack in a column on the right
    items = [("doc", (1.55, 1.85, -6.0, 0.6), "lease-renewal.pdf  ·  PAGE 2", "“When does my lease renew?”"),
             ("voice", (1.75, 0.7, 4.0, 0.6), "call-with-mum.m4a  ·  FROM 01:12", "“What did Mum say about the recipe?”"),
             ("board", (1.55, -0.35, -3.0, 0.58), "whiteboard.jpg  ·  TEXT IN IMAGE", "“What did we write on the whiteboard?”")]
    mcards = []
    for k, (kind, tgt, chip_label, q) in enumerate(items):
        mcards.append((build_card(f"E_{kind}", RE, kind, trace=False, chip=chip_label), tgt, kind))
        b = 40 * k
        caption(A, S2, f"E_Q{k}", [(q, b + 4)], (b + 38) if k < 2 else 140, y=4.45, x=0.25, size=0.15,
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
                key_card(A, C, f, 4.6, 6.2, 1.0, 25, ts, "hidden", seed=71 + k)
            else:
                t = seg(l, b + 20, b + 32)
                z = 1.0 - (0.8 - 0.08 * k) * ease_in(seg(l, b + 30, b + 34))
                chip_on = (b + 32 <= l < b + 72) if k < 2 else (l >= b + 32)
                key_card(A, C, f, lerp(4.6, tx, ease_out(t)), lerp(6.2, ty, ease_out(t)) + 0.3 * math.sin(math.pi * t),
                         z, lerp(25, tr, back_out(t, 2.0)), ts, "solid", pop_s=pop(l, b + 32, seq=(1.04, 0.99)),
                         seed=71 + k, chip=chip_on)
            if kind == "doc":
                A.scl(C["hl"], f, (clamp((l - (b + 32)) / 10.0), 1, 1) if l >= b + 34 else TINY)
            elif kind == "voice":
                for j, bar in enumerate(C["played"]):
                    A.scl(bar, f, 1.0 if l >= b + 34 + 2 * (j // 2) else TINY)
            else:
                A.scl(C["hl"], f, popup(l, b + 34, seq=(1.2, 0.95)))

    # E3: the memories you already have, close again, gathered around the person inside the frame
    x1, y1, z1, r1, s1, _, _, _ = photo_path(238)
    starts = [(photo, (x1, y1, z1, r1, s1))] + [(C, (tx, ty, 0.2 + 0.08 * k, tr, ts))
                                               for k, (C, (tx, ty, tr, ts), _) in enumerate(mcards)]
    px = PERSON_E[0] - E0[0]
    targets = [(px - 1.55, 2.4, -8, 0.46), (px + 1.5, 2.55, 7, 0.42), (px - 1.75, 0.85, 5, 0.45),
               (px + 1.6, 0.95, -5, 0.45)]
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


# ------------------------------------------------------------------ END: the sky above E
def build_END(A, W):
    RN = region("END_Region", END_C[0], END_C[1], W)
    S = dict(root=RN, start=1297, length=144)
    caption(A, S, "END_Word", [("H a w k", 50)], 999, y=-0.78, size=1.0, gap=0.035, seed=92)
    caption(A, S, "END_Tag", [("Your second memory.", 68)], 999, y=-1.38, size=0.3, fkey="serif_i", seed=93)
    caption(A, S, "END_Small", [("INDEXED ON YOUR DEVICE  ·  FILES NEVER LEAVE WITHOUT YOU", 86)], 999, y=-1.9,
            size=0.1, fkey="sans", mat=tone("#8e8e92"), stagger=0, seed=94)


# ------------------------------------------------------------------ the top glass: captions ride with the camera
GLASS_Z = 0.7
CAPTIONS = [
    ([("We keep so much of our lives", 11), ("in places we can no longer see.", 41)], 137),
    ([("We remember the moment.", 165), ("Not where we put it.", 209)], 281),
    ([("A hawk sees what is almost invisible,", 333), ("from far away.", 359)], 391),
    ([("Bring your own storage.", 507)], 551),
    ([("Originals stay where they live.", 555), ("Hawk keeps only the index.", 579)], 607),
    ([("No filenames.", 669), ("No folders.", 681)], 699),
    ([("Just remember what you remember.", 703)], 741),
    ([("Ask in your own words.", 789)], 869),
    ([("Get the answer,", 963), ("and the file behind it.", 983)], 1017),
    ([("Documents.", 1055), ("Voice notes.", 1095), ("Photos, even the words inside them.", 1135)], 1161),
    ([("You remember it.", 1177), ("Hawk helps you see it.", 1215)], 1291),
]


def wrap_caption(items, size):
    """Put a caption that is wider than the portrait frame allows on two centred lines, splitting between
    its segments (the last segment of three goes alone on the second line)."""
    widths = measure([ob for ob, _ in items])
    sp = size * 0.3
    total = sum(widths) + sp * (len(items) - 1)
    if total <= CAP_MAX:
        return
    segs = sorted({int(ob.name.split("_")[1]) for ob, _ in items})
    cut_seg = segs[-1] if len(segs) >= 2 else None
    rows = [[], []]
    for (ob, _), w in zip(items, widths):
        s = int(ob.name.split("_")[1])
        rows[1 if (cut_seg is not None and s >= cut_seg) else 0].append((ob, w))
    if cut_seg is None:                                  # one long segment: split where the halves balance
        half = total / 2
        run = 0.0
        rows = [[], []]
        for (ob, _), w in zip(items, widths):
            rows[0 if run + w / 2 < half else 1].append((ob, w))
            run += w + sp
    for r, row in enumerate(rows):
        lw = sum(w for _, w in row) + sp * (len(row) - 1)
        x = -lw / 2
        for ob, w in row:
            ob.location.x = x + w / 2
            ob.location.y = CAP_Y + 0.21 - 0.42 * r
            x += w + sp


def build_glass(A, W):
    glass = empty("Glass", (0, 0, GLASS_Z), W)
    for f in range(1, LAST + 1):
        cx, cy, cz = cam_path(f)
        A.loc(glass, f, (cx, cy, GLASS_Z))
        A.scl(glass, f, (cz - GLASS_Z) / (14.0 - GLASS_Z) if cz > 3.0 else TINY)
    A.smooth(glass)
    G = dict(root=glass, start=1, length=LAST)
    for i, (segs, out_f) in enumerate(CAPTIONS):
        segments = [(t, f_in - 1) for t, f_in in segs]
        probe = word_row(f"Probe{i:02d}", segments, "serif", CAP_SIZE, M.white, 0.0, (0, CAP_Y), glass)
        widths = measure([ob for ob, _ in probe])
        needs_wrap = sum(widths) + CAP_SIZE * 0.3 * (len(probe) - 1) > CAP_MAX
        for ob, _ in probe:
            bpy.data.objects.remove(ob, do_unlink=True)
        items = caption(A, G, f"Cap{i:02d}", segments, out_f - 1, y=CAP_Y, size=CAP_SIZE, z=0.0, seed=200 + 10 * i) \
            if not needs_wrap else None
        if needs_wrap:
            # lay the words out on two lines first, then key them where they now sit
            words = word_row(f"Cap{i:02d}", segments, "serif", CAP_SIZE, M.white, 0.0, (0, CAP_Y), glass)
            wrap_caption(words, CAP_SIZE)
            items = _key_caption(A, G, words, out_f - 1, seed=200 + 10 * i)
        for ob, _ in items:
            ob.visible_shadow = False


def _key_caption(A, S, items, out_l, seed=50, stagger=2):
    """The caption keyer from puppets.caption, for words already laid out."""
    counts = {}
    for n, (ob, l_in) in enumerate(items):
        k = counts.get(l_in, 0)
        counts[l_in] = k + 1
        t0 = l_in + stagger * k
        base = tuple(ob.location)
        for l in range(0, S["length"], 2):
            f = S["start"] + l
            if l < t0 or l > out_l:
                s = TINY
            elif l == t0:
                s = 1.22
            elif l == t0 + 2:
                s = 0.94
            elif l < out_l:
                s = 1.0
            else:
                s = 0.55
            jx, jy, jr = boil(seed + n, f, 0.003, 0.4)
            A.loc(ob, f, (base[0] + jx, base[1] + jy, base[2]))
            A.rot(ob, f, jr)
            A.scl(ob, f, s)
    return items


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
    bg.inputs["Color"].default_value = (0.004, 0.004, 0.005, 1)
    bg.inputs["Strength"].default_value = 1.0

    W = empty("World_Root", (0, 0, 0))
    paper("Page", rrect(90, 44, 0.1, cx=17, cy=5), M.card, 0.0, W, thick=0.02)
    paper("GroundBack", torn_strip(-1.45, -14, 3, x0=-16, x1=54), M.char1, 0.05, W)
    paper("GroundFront", torn_strip(-1.78, -14, 7, x0=-16, x1=54), M.char2, 0.10, W)

    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 3.8
    sd.angle = math.radians(14)
    if hasattr(sd, "use_shadow_jitter"):
        sd.use_shadow_jitter = True
    sun = bpy.data.objects.new("Sun", sd)
    col.objects.link(sun)
    sun.rotation_euler = Vector((5.0, -4.5, -11.0)).to_track_quat("-Z", "Y").to_euler()

    cd = bpy.data.cameras.new("Cam")
    cd.lens, cd.sensor_width, cd.sensor_fit = LENS, 36, "HORIZONTAL"
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
    r.resolution_x, r.resolution_y, r.resolution_percentage = 1080, 1920, 100
    r.fps = 24
    scene.frame_start, scene.frame_end = 1, LAST
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.filepath = "//frames_portrait/hp_"
    scene.eevee.taa_render_samples = 32
    if hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = "Standard"
    # parameters the shared finishing passes read (dive geometry for this layout)
    scene["dive_p_e"] = P_E
    scene["dive_b_cam"] = B_CAM
    scene["dive_reveal"] = (P_E[0], P_E[1] - 0.35)
    scene["dive_d_reveal"] = 6.0
    scene["portrait"] = True
    scene.frame_set(1)
    out = os.path.join(os.path.dirname(HERE), "hawk_film_portrait.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("saved", bpy.data.filepath)


if __name__ == "__main__":
    main()
