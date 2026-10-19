"""Puppets and set pieces for the Hawk launch film (painted paper-cut look).

Each builder returns the pieces that move; each key_* function writes one pose.
"""
import math
import random

import bpy

from paperlib import (M, TINY, boil, circle, clamp, closed_lid, empty, measure, move, paper, paper_multi,
                      rotate, rrect, sparkle, superellipse, text, wave_strip, word_row, _link)


# ------------------------------------------------------------------ timing
def smooth(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)


def ease_out(x):
    x = clamp(x)
    return 1 - (1 - x) ** 3


def ease_in(x):
    x = clamp(x)
    return x ** 3


def back_out(x, s=1.9):
    x = clamp(x) - 1
    return 1 + x * x * ((s + 1) * x + s)


def seg(l, l0, l1):
    return clamp((l - l0) / float(l1 - l0))


def lerp(a, b, t):
    return a + (b - a) * t


def seq_at(l, l0, seq, default=None):
    d = l - l0
    if d < 0 or d % 2 or d // 2 >= len(seq):
        return default
    return seq[d // 2]


def pop(l, *starts, seq=(1.10, 0.97, 1.03)):
    for b in starts:
        v = seq_at(l, b, list(seq))
        if v is not None:
            return v
    return 1.0


def popup(l, t0, seq=(0.3, 0.75, 1.08, 0.97)):
    """Unfold from nothing: hidden before t0, then a few overshooting steps."""
    if l < t0:
        return TINY
    v = seq_at(l, t0, list(seq))
    return 1.0 if v is None else v


def blink(l, *starts):
    """Replacement blink: half, closed, closed, half. Returns (open_y, closed)."""
    for b in starts:
        v = seq_at(l, b, [(0.45, False), (1.0, True), (1.0, True), (0.45, False)])
        if v is not None:
            return v
    return (1.0, False)


def spark(l, l0, hold=14):
    v = seq_at(l, l0, [1.35, 0.9, 1.05])
    if v is not None:
        return v
    d = l - l0
    if 6 <= d < hold:
        return 1.0
    if d == hold:
        return 0.55
    return 0.0


# ------------------------------------------------------------------ shapes
def doc_page(w, h, c=0.24):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2 - c), (w / 2 - c, h / 2), (-w / 2, h / 2)]


def tick(s):
    pts = [(-0.9, 0.05), (-0.35, -0.55), (0.95, 0.75), (0.75, 0.9), (-0.35, -0.2), (-0.7, 0.25)]
    return [(x * s, y * s) for x, y in pts]


def crumple(r, seed, n=16):
    rnd = random.Random(seed)
    return [(r * (1 + rnd.uniform(-0.2, 0.12)) * math.cos(2 * math.pi * i / n),
             r * (1 + rnd.uniform(-0.2, 0.12)) * math.sin(2 * math.pi * i / n)) for i in range(n)]


def zig(x_t, y0, y1, n, amp, seed):
    rnd = random.Random(seed)
    return [(x_t + (amp if i % 2 else -amp) * rnd.uniform(0.4, 1.0), y0 + (y1 - y0) * i / n) for i in range(n + 1)]


def brow_strip(L=0.9, th=0.09, arch=0.12, N=40):
    top, bot = [], []
    for i in range(N + 1):
        u = -1 + 2 * i / N
        x = u * L / 2
        yc = arch * (1 - u * u)
        t = th * (0.35 + 0.65 * math.sqrt(max(0.0, 1 - u * u)))
        top.append((x, yc + t / 2))
        bot.append((x, yc - t / 2))
    return bot + list(reversed(top))


def band_in_circle(R, cy, th, amp, k, ph, N=48):
    ymax = max(abs(cy + th / 2 + amp), abs(cy - th / 2 - amp))
    if ymax >= R:
        return None
    xr = math.sqrt(R * R - ymax * ymax)
    top = [(-xr + 2 * xr * i / N, cy + th / 2 + amp * math.sin(k * (-xr + 2 * xr * i / N) + ph)) for i in range(N + 1)]
    return [(x, y - th) for x, y in top] + list(reversed(top))


def hill_fn(base, waves, seed):
    rnd = random.Random(seed)
    phs = [rnd.random() * 6.283 for _ in waves]

    def f(x):
        return base + sum(a * math.sin(fr * x + ph) for (a, fr), ph in zip(waves, phs))
    return f


def peaks_fn(base, height, x0, x1, n, seed, jag=0.12):
    """Mountain ridge: straight-sided peaks at random spacing, with a little ragged cut."""
    rnd = random.Random(seed)
    xs = sorted(rnd.uniform(x0, x1) for _ in range(n))
    pts = [(x0 - 1, base)]
    for x in xs:
        pts.append((x - rnd.uniform(0.6, 1.4), base + rnd.uniform(0.0, 0.25) * height))
        pts.append((x, base + rnd.uniform(0.55, 1.0) * height))
    pts.append((x1 + 1, base))
    pts.sort()

    def f(x):
        for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
            if xa <= x <= xb:
                t = (x - xa) / (xb - xa) if xb > xa else 0
                return ya + (yb - ya) * t + jag * 0.1 * math.sin(x * 37.0 + seed)
        return base
    return f


def hills(fn, x0, x1, bottom=-6.0, step=0.08):
    xs = [x0 + step * i for i in range(int((x1 - x0) / step) + 1)]
    return [(x0, bottom), (x1, bottom)] + [(x, fn(x)) for x in reversed(xs)]


def leaf_shape(L, W, bend=0.0, N=24):
    """A leaf growing up +y from its base at the origin; bend curls the tip sideways."""
    right, left = [], []
    for i in range(N + 1):
        t = i / N
        w = W * math.sin(math.pi * t) ** 0.75 / 2
        xc = bend * L * t * t
        right.append((xc + w, L * t))
        left.append((xc - w, L * t))
    return right + list(reversed(left[1:-1]))


def swoosh(L, W, bend=0.18, N=40):
    """A loaded brush stroke: curved, tapered, fatter where the brush pressed."""
    top, bot = [], []
    for i in range(N + 1):
        t = i / N
        x = (t - 0.5) * L
        yc = bend * L * (0.25 - (t - 0.5) ** 2)
        w = W * (math.sin(math.pi * t) ** 0.6) * (0.45 + 0.55 * t) / 2
        top.append((x, yc + w))
        bot.append((x, yc - w))
    return bot + list(reversed(top))


def ring_segments(rx, ry, w, n=72, rot=0.0, cx=0.0, cy=0.0, gaps=0):
    """A thin elliptical line as short quads (paper has no holes); gaps>0 dashes it."""
    quads = []
    for i in range(n):
        if gaps and i % gaps == gaps - 1:
            continue
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        o0 = (rx * math.cos(a0), ry * math.sin(a0))
        o1 = (rx * math.cos(a1), ry * math.sin(a1))
        i1 = ((rx - w) * math.cos(a1), (ry - w) * math.sin(a1))
        i0 = ((rx - w) * math.cos(a0), (ry - w) * math.sin(a0))
        quads.append(move(rotate([o0, o1, i1, i0], rot), cx, cy))
    return quads


def marks_polys(r, base_deg, n=3, spread=24, L=0.17, W=0.045):
    """Action marks: three short blue strokes radiating from something that just happened."""
    out = []
    for i in range(n):
        a = math.radians(base_deg + (i - (n - 1) / 2) * spread)
        stroke = rotate(rrect(L, W, W / 2), a)
        out.append(move(stroke, (r + L / 2) * math.cos(a), (r + L / 2) * math.sin(a)))
    return out


def palm_polys(h, lean=0.25, fronds=7, cx=0.0, cy=0.0):
    N = 16
    left, right = [], []
    for i in range(N + 1):
        t = i / N
        x = lean * h * t * t
        w = 0.045 * h * (1 - t) + 0.02 * h
        left.append((x - w, h * t))
        right.append((x + w, h * t))
    polys = [left + list(reversed(right))]
    top = (lean * h, h)
    for k in range(fronds):
        a = math.radians(15 + k * 150 / (fronds - 1))
        leaf = leaf_shape(0.5 * h, 0.12 * h, bend=(0.35 if a < math.pi / 2 else -0.35))
        polys.append(move(rotate(leaf, a - math.pi / 2), *top))
    return [move(p, cx, cy) for p in polys]


def sightline(prefix, parent, p0, p1, n, z=0.28):
    """The eye's gaze: blue paper dashes laid one by one."""
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    out = []
    for j in range(n):
        t = j / (n - 1)
        out.append(paper(f"{prefix}{j:02d}", rrect(0.13, 0.055, 0.022), M.blue, z, parent,
                         loc=(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t), rot=ang))
    return out


def key_dash(A, ob, f, l, on, off):
    if l < on or l >= off:
        s = TINY
    elif l == on:
        s = 1.3
    else:
        s = 1.0
    A.scl(ob, f, s)


# ------------------------------------------------------------------ the eye (Hawk)
EA, EB, EN = 1.0, 0.74, 2.5


def build_eye(name, parent, loc=(0, 0), z=0.0, scale=1.0, wave=False, seed=0):
    E = {"base": (loc[0], loc[1], z), "scale": scale}
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    E["root"] = root
    op = empty(name + "_Open", parent=root)
    E["open"] = op
    paper(name + "_Ring", superellipse(EA + 0.17, EB + 0.17, EN), M.white, 0.30, op, wob=0.012, seed=seed + 11)
    paper(name + "_Gap", superellipse(EA + 0.075, EB + 0.075, EN), M.black, 0.34, op, wob=0.010, seed=seed + 12)
    paper(name + "_Sclera", superellipse(EA, EB, EN), M.white, 0.38, op, wob=0.010, seed=seed + 13)
    gz = empty(name + "_Gaze", parent=op)
    E["gaze"] = gz
    paper(name + "_Disc", circle(0.40), M.blue, 0.42, gz, wob=0.008, seed=seed + 14)
    paper(name + "_Sheen", rotate(superellipse(0.22, 0.11, 2.0, 48), math.radians(40)), M.sky1, 0.44, gz,
          loc=(-0.13, 0.12))
    E["pupil"] = paper(name + "_Pupil", circle(0.19), M.black, 0.46, gz, wob=0.006, seed=seed + 15)
    paper(name + "_HL", circle(0.085), M.white, 0.50, gz, loc=(-0.14, 0.14))
    E["closed"] = paper(name + "_Closed", closed_lid(EA + 0.14), M.white, 0.38, root)
    E["spark"] = paper(name + "_Spark", sparkle(0.26), M.white, 0.55, root, loc=(1.30, 0.92))
    E["marks"] = paper_multi(name + "_Marks", marks_polys(1.42, 145), [M.blue], 0.55, root)
    E["brow"] = paper(name + "_Brow", brow_strip(), M.white, 0.40, root, loc=(0.0, 1.13))
    if wave:
        lr = empty(name + "_Listen", parent=root)
        E["listen"] = lr
        paper(name + "_LRing", circle(0.97), M.white, 0.30, lr, wob=0.01, seed=seed + 16)
        paper(name + "_LGap", circle(0.90), M.black, 0.34, lr, wob=0.008, seed=seed + 17)
        E["bands"] = []
        for p in range(4):
            g = empty(f"{name}_Wave{p}", parent=lr)
            E["bands"].append(g)
            polys = [band_in_circle(0.84, cy, 0.13, 0.045, 6.5, p * 1.5708 + b * 0.9)
                     for b, cy in enumerate((-0.56, -0.28, 0.0, 0.28, 0.56))]
            paper_multi(f"{name}_W{p}", [q for q in polys if q], [M.blue], 0.38, g)
    return E


def key_eye(A, E, f, gaze=(0, 0), open_y=1.0, closed=False, pop_s=1.0, squash=(1, 1), spark_s=0.0,
            spark_rot=0.0, brow=0.0, brow_rot=0.0, brow_dy=0.0, pupil=1.0, listen=False, phase=0,
            offset=(0, 0), amt=0.005, seed=3, hidden=False, pos=None, scale=None, rot=0.0, bf=None, marks=None):
    """One pose of the eye. pos/scale/rot place it anywhere (it travels); bf is the frame the boil
    is drawn from, so a travelling eye can move every frame while still shivering on twos."""
    jx, jy, jr = boil(seed, f if bf is None else bf, amt, 0.25)
    bx, by, bz = E["base"] if pos is None else (pos[0], pos[1], E["base"][2])
    s = TINY if hidden else (E["scale"] if scale is None else scale) * pop_s
    A.loc(E["root"], f, (bx + offset[0] + jx, by + offset[1] + jy, bz))
    A.rot(E["root"], f, rot + jr)
    A.scl(E["root"], f, (s * squash[0], s * squash[1], s))
    show_open = not closed and not listen
    A.scl(E["open"], f, (1, open_y, 1) if show_open else TINY)
    A.loc(E["gaze"], f, (gaze[0], gaze[1], 0))
    A.scl(E["pupil"], f, pupil)
    A.scl(E["closed"], f, 1.0 if closed else TINY)
    A.scl(E["spark"], f, spark_s if spark_s > 0 else TINY)
    A.rot(E["spark"], f, spark_rot)
    m = spark_s if marks is None else marks
    A.scl(E["marks"], f, m if m > 0 else TINY)
    A.scl(E["brow"], f, brow if brow > 0 else TINY)
    A.rot(E["brow"], f, brow_rot)
    A.loc(E["brow"], f, (0, 1.13 + brow_dy, 0))
    if "listen" in E:
        A.scl(E["listen"], f, 1.0 if listen else TINY)
        for p, g in enumerate(E["bands"]):
            A.scl(g, f, 1.0 if (listen and p == phase) else TINY)


# ------------------------------------------------------------------ the person (split-pin puppet)
POSES = {
    "stand": dict(torso=0, head=0, ua_n=6, fa_n=12, ua_f=-6, fa_f=8, th_n=3, sh_n=-3, th_f=-3, sh_f=2),
    "look": dict(torso=-2, head=-16, ua_n=18, fa_n=100, ua_f=-4, fa_f=10, th_n=3, sh_n=-3, th_f=-3, sh_f=2),
    "talk": dict(torso=1, head=4, ua_n=45, fa_n=120, ua_f=-5, fa_f=10, th_n=3, sh_n=-3, th_f=-3, sh_f=2),
    "up": dict(torso=3, head=16, ua_n=8, fa_n=24, ua_f=-6, fa_f=8, th_n=3, sh_n=-3, th_f=-3, sh_f=2),
    "sad": dict(torso=-5, head=-14, ua_n=3, fa_n=6, ua_f=-2, fa_f=4, th_n=2, sh_n=-2, th_f=-2, sh_f=1),
    "delight": dict(torso=2, head=12, ua_n=22, fa_n=96, ua_f=-38, fa_f=-24, th_n=3, sh_n=-3, th_f=-3, sh_f=2),
    "joy": dict(torso=4, head=18, ua_n=125, fa_n=25, ua_f=-125, fa_f=-25, th_n=6, sh_n=-4, th_f=-6, sh_f=3),
}
JOINTS = ("torso", "head", "ua_n", "fa_n", "ua_f", "fa_f", "th_n", "sh_n", "th_f", "sh_f")


def mix(a, b, t):
    return {k: lerp(a[k], b[k], t) for k in a}


def capsule(w, L):
    return rrect(w, L + w, w / 2, cy=-L / 2)


def _taper(pts, y0, y1, f0, f1):
    return [(x * (f0 + (f1 - f0) * clamp((y - y0) / (y1 - y0))), y) for x, y in pts]


def build_person(name, parent, loc=(0, 0), scale=0.8, z=0.18, seed=0):
    """Hips at loc. Limbs rotate at their pins and never bend; the far side is shaded cream."""
    P = {"base": (loc[0], loc[1], z), "scale": scale}
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    P["root"] = root
    for side, dx, mat, zz in (("f", -0.06, M.cream2, 0.00), ("n", 0.07, M.white, 0.01)):
        th = empty(f"{name}_Thigh_{side}", (dx, 0.0, 0), root)
        P["th_" + side] = th
        paper(f"{name}_ThighP_{side}", capsule(0.17, 0.55), mat, zz, th)
        sh = empty(f"{name}_Shin_{side}", (0, -0.55, 0), th)
        P["sh_" + side] = sh
        paper(f"{name}_ShinP_{side}", capsule(0.145, 0.52), mat, zz, sh)
        paper(f"{name}_Foot_{side}", rrect(0.30, 0.12, 0.055, cx=0.07, cy=-0.56), mat, zz, sh)
    torso = empty(name + "_Torso", (0, 0, 0), root)
    P["torso"] = torso
    paper(name + "_TorsoP", _taper(rrect(0.52, 1.06, 0.15, cy=0.45), -0.08, 0.98, 0.82, 1.0), M.light, 0.03,
          torso, wob=0.006, seed=seed + 1)
    for side, mat, zz in (("f", M.cream2, 0.015), ("n", M.white, 0.06)):
        ua = empty(f"{name}_UArm_{side}", (0.02, 0.86, 0), torso)
        P["ua_" + side] = ua
        paper(f"{name}_UArmP_{side}", capsule(0.13, 0.46), mat, zz, ua)
        fa = empty(f"{name}_FArm_{side}", (0, -0.46, 0), ua)
        P["fa_" + side] = fa
        paper(f"{name}_FArmP_{side}", capsule(0.115, 0.42), mat, zz + 0.002, fa)
        paper(f"{name}_Hand_{side}", circle(0.075, cy=-0.44), mat, zz + 0.004, fa)
    head = empty(name + "_Head", (0, 0.98, 0), torso)
    P["head"] = head
    paper(name + "_Neck", rrect(0.12, 0.2, 0.05, cy=0.02), M.white, 0.035, head)
    paper(name + "_HeadP", circle(0.26, cx=0.03, cy=0.36), M.white, 0.04, head, wob=0.006, seed=seed + 3)
    paper(name + "_EyeDot", circle(0.028, cx=0.17, cy=0.39), M.black, 0.045, head)
    ph = empty(name + "_Phone", (0.0, -0.44, 0), P["fa_n"])
    P["phone"] = ph
    paper(name + "_PhoneRim", rrect(0.17, 0.30, 0.04), M.dark, 0.066, ph)
    paper(name + "_PhoneScr", rrect(0.13, 0.25, 0.03), M.blue2, 0.07, ph)
    paper(name + "_PhoneDot", circle(0.03), M.blue, 0.074, ph)
    return P


def key_person(A, P, f, pose, offset=(0, 0), flip=False, phone=True, amt=0.004, seed=5, lift=0.0, pos=None, bf=None):
    jx, jy, jr = boil(seed, f if bf is None else bf, amt, 0.2)
    bx, by, bz = P["base"] if pos is None else (pos[0], pos[1], P["base"][2])
    s = P["scale"]
    A.loc(P["root"], f, (bx + offset[0] + jx, by + offset[1] + jy + lift, bz))
    A.rot(P["root"], f, jr)
    A.scl(P["root"], f, (-s if flip else s, s, s))
    for k in JOINTS:
        A.rot(P[k], f, math.radians(pose.get(k, 0.0)))
    A.scl(P["phone"], f, 1.0 if phone else TINY)


# ------------------------------------------------------------------ the hawk
HAWK_EYE = (0.79, 0.15)
HAWK_K = 0.125
FLAP = [(1.0, 16), (0.8, 10), (0.4, 2), (-0.15, -6), (-0.55, -10), (-0.35, -6), (0.2, 4), (0.7, 12)]


def build_hawk(name, parent, loc, scale=1.0, z=0.3, eye=True):
    """eye=False leaves the eye socket empty: the film puts the real Hawk eye on the hawk's head,
    so the hawk can burst apart and the eye it leaves behind is the product's eye.
    The wings carry painted bands of orange and blue, like the reference's brushed feathers."""
    H = {"base": (loc[0], loc[1], z), "scale": scale, "parts": []}
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    H["root"] = root
    inner = [(0.12, -0.04), (0.1, 0.3), (0.08, 0.62), (-0.02, 0.66), (-0.1, 0.6), (-0.16, 0.63), (-0.22, 0.55),
             (-0.28, 0.57), (-0.32, 0.45), (-0.36, 0.46), (-0.38, 0.3), (-0.36, 0.12), (-0.3, -0.04)]
    outer = [(0.08, -0.02), (0.07, 0.35), (0.03, 0.72), (-0.04, 0.6), (-0.08, 0.7), (-0.13, 0.55), (-0.18, 0.63),
             (-0.22, 0.47), (-0.27, 0.52), (-0.3, 0.34), (-0.33, 0.36), (-0.34, 0.12), (-0.3, -0.02)]
    for side, mat, zz, band in (("f", M.cream2, 0.0, M.blue2), ("n", M.white, 0.07, M.orange)):
        w = empty(f"{name}_Wing_{side}", (0.12, 0.08, 0), root)
        paper(f"{name}_WingP_{side}", inner, mat, zz, w, wob=0.004, seed=3)
        paper(f"{name}_WingBand_{side}", rrect(0.07, 0.46, 0.03, cx=-0.29, cy=0.3), M.blue3, zz + 0.001, w)
        wo = empty(f"{name}_WingO_{side}", (0.0, 0.6, 0), w)
        paper(f"{name}_WingOP_{side}", outer, mat, zz + 0.002, wo, wob=0.004, seed=4)
        paper_multi(f"{name}_WingPaint_{side}", [rrect(0.085, 0.4, 0.04, cx=-0.1, cy=0.34),
                                                 rrect(0.07, 0.3, 0.035, cx=-0.23, cy=0.3)],
                    [band, M.sky1], 0.0, wo, mat_index=[0, 1], zs=[zz + 0.003, zz + 0.0035])
        H["w" + side] = w
        H["wo" + side] = wo
    body = []
    for i in range(64):
        t = 2 * math.pi * i / 64
        x = 0.75 * math.cos(t)
        body.append((x, 0.21 * math.sin(t) * (0.62 + 0.38 * (x + 0.75) / 1.5)))
    H["parts"].append((paper(name + "_Body", body, M.white, 0.02, root, wob=0.006, seed=5), (-1.0, -0.35)))
    H["parts"].append((paper(name + "_BodyPaint", move(swoosh(0.9, 0.07, 0.06), -0.1, -0.07), M.sky1, 0.021, root),
                       (-0.8, -0.8)))
    H["parts"].append((paper(name + "_Tail", [(-0.62, 0.08), (-1.22, 0.16), (-1.28, 0.02), (-1.22, -0.12),
                                              (-0.62, -0.06)], M.white, 0.015, root), (-1.0, 0.1)))
    H["parts"].append((paper(name + "_TailPaint", [(-1.05, 0.12), (-1.22, 0.16), (-1.28, 0.02), (-1.08, 0.02)],
                             M.orange, 0.016, root), (-1.0, 0.3)))
    H["parts"].append((paper(name + "_Head", circle(0.2, cx=0.72, cy=0.1), M.white, 0.03, root, wob=0.004, seed=6),
                       (0.35, -1.0)))
    H["parts"].append((paper(name + "_Beak", [(0.86, 0.17), (1.02, 0.13), (1.08, 0.05), (1.03, 0.0), (1.0, 0.06),
                                              (0.88, 0.05)], M.cream2, 0.035, root), (1.0, -0.2)))
    H["parts"].append((H["wn"], (-0.5, 1.0)))
    H["parts"].append((H["wf"], (0.2, 1.0)))
    if not eye:
        return H
    ex, ey = HAWK_EYE
    paper(name + "_EyeW", circle(0.075, cx=ex, cy=ey), M.white, 0.045, root)
    paper(name + "_EyeRing", circle(0.066, cx=ex, cy=ey), M.black, 0.047, root)
    paper(name + "_EyeDisc", circle(0.40 * HAWK_K, cx=ex, cy=ey), M.blue, 0.05, root)
    H["pupil"] = paper(name + "_EyePupil", circle(0.19 * HAWK_K, cx=ex, cy=ey), M.black, 0.055, root)
    return H


def key_hawk(A, H, f, flap=(1.0, 10), offset=(0, 0), rot=0.0, amt=0.005, seed=9):
    jx, jy, jr = boil(seed, f, amt, 0.3) if amt > 0 else (0, 0, 0)
    bx, by, bz = H["base"]
    s = H["scale"]
    A.loc(H["root"], f, (bx + offset[0] + jx, by + offset[1] + jy, bz))
    A.rot(H["root"], f, math.radians(rot) + jr)
    A.scl(H["root"], f, s)
    sy, rd = flap
    A.scl(H["wn"], f, (1, sy, 1))
    A.rot(H["wn"], f, math.radians(rd))
    A.rot(H["won"], f, math.radians(rd * 0.6))
    A.scl(H["wf"], f, (1, sy * 0.92, 1))
    A.rot(H["wf"], f, math.radians(rd + 6))
    A.rot(H["wof"], f, math.radians(rd * 0.6))


# ------------------------------------------------------------------ memory cards
CARD_WH = {"photo": (1.45, 1.75), "doc": (1.3, 1.7), "voice": (1.7, 1.0), "board": (1.7, 1.2)}


def landscape_pic(name, g, w, h, cx, cy, z):
    """Blue sky, two yellow suns, teal and blue mountains: the reference's photo."""
    paper(name + "_Sky", rrect(w, h, 0.02, cx=cx, cy=cy), M.sky1, z, g)
    paper_multi(name + "_Suns", [circle(0.1 * w, cx=cx - 0.18 * w, cy=cy + 0.22 * h),
                                 circle(0.1 * w, cx=cx + 0.2 * w, cy=cy + 0.22 * h)], [M.yellow], z + 0.01, g)
    paper_multi(name + "_Mounts", [[(cx - w / 2, cy - h / 2), (cx - 0.08 * w, cy + 0.12 * h), (cx + 0.3 * w, cy - h / 2)],
                                   [(cx - 0.1 * w, cy - h / 2), (cx + 0.26 * w, cy + 0.02 * h),
                                    (cx + w / 2, cy - 0.16 * h), (cx + w / 2, cy - h / 2)]],
                [M.teal, M.leafb], z + 0.02, g, mat_index=[0, 1], zs=[0.0, 0.004])


def sunset_pic(name, g, w, h, cx, cy, z):
    """Goa: an orange sky, the sun on the sea, two palms."""
    paper(name + "_SkyTop", rrect(w, h, 0.02, cx=cx, cy=cy), M.sunset[3], z, g)
    paper(name + "_SkyLow", rrect(w, 0.3 * h, 0.0, cx=cx, cy=cy - 0.02 * h), M.sunset[4], z + 0.004, g)
    paper(name + "_Sun", circle(0.16 * w, cx=cx, cy=cy - 0.08 * h), M.sun, z + 0.008, g)
    paper(name + "_Sea", rrect(w, 0.42 * h, 0.02, cx=cx, cy=cy - 0.29 * h), M.sea, z + 0.012, g)
    paper_multi(name + "_Glints", [rrect(0.3 * w * (1 - 0.25 * i), 0.018 * h, 0.005, cx=cx, cy=cy - (0.14 + 0.07 * i) * h)
                                   for i in range(4)], [M.reflect], z + 0.016, g)
    palms = palm_polys(0.5 * h, 0.25, cx=cx - 0.36 * w, cy=cy - 0.45 * h) + \
        [[(-x + 2 * cx, y) for x, y in p] for p in palm_polys(0.42 * h, 0.25, cx=cx - 0.38 * w, cy=cy - 0.45 * h)]
    paper_multi(name + "_Palms", palms, [M.palm], z + 0.02, g)


def _photo(name, g, C, variant):
    paper(name + "_Frame", rrect(1.45, 1.75, 0.05), M.white, 0.0, g, wob=0.006, seed=21)
    (sunset_pic if variant == "sunset" else landscape_pic)(name, g, 1.22, 1.22, 0.0, 0.16, 0.03)


def _doc(name, g, C, variant):
    w, h = CARD_WH["doc"]
    paper(name + "_Page", doc_page(w, h), M.white, 0.0, g, wob=0.004, seed=31)
    paper(name + "_Fold", [(w / 2 - 0.24, h / 2), (w / 2 - 0.24, h / 2 - 0.24), (w / 2, h / 2 - 0.24)], M.cream2, 0.02, g)
    paper(name + "_Title", rrect(0.62, 0.08, 0.03, cx=-w / 2 + 0.45, cy=0.6), M.slate, 0.03, g)
    rnd = random.Random(5)
    lines = []
    for i, y in enumerate((0.36, 0.22, 0.08, -0.06, -0.2, -0.34, -0.48, -0.62)):
        ln = (w - 0.3) * (0.86 if i == 4 else rnd.uniform(0.6, 1.0))
        lines.append(rrect(ln, 0.045, 0.02, cx=-w / 2 + 0.15 + ln / 2, cy=y))
    paper_multi(name + "_Lines", lines, [M.slate], 0.03, g)
    ln = (w - 0.3) * 0.86 + 0.08
    C["hl"] = paper(name + "_HL", rrect(ln, 0.11, 0.03, cx=ln / 2), M.blue, 0.02, g, loc=(-w / 2 + 0.11, -0.2))


def _voice(name, g, C, variant):
    w, h = CARD_WH["voice"]
    paper(name + "_Card", rrect(w, h, 0.12), M.dark, 0.0, g, wob=0.004, seed=41)
    paper(name + "_Play", circle(0.15, cx=-0.6), M.blue, 0.03, g)
    paper(name + "_Tri", [(-0.645, -0.07), (-0.525, 0.0), (-0.645, 0.07)], M.white, 0.05, g)
    rnd = random.Random(7)
    bars = []
    C["played"] = []
    n, x0, x1 = 18, -0.33, 0.7
    for j in range(n):
        x = x0 + (x1 - x0) * j / (n - 1)
        hh = 0.08 + 0.5 * abs(math.sin(j * 0.9 + 0.4)) * rnd.uniform(0.5, 1.0)
        bars.append(rrect(0.035, hh, 0.017, cx=x))
        C["played"].append(paper(f"{name}_P{j:02d}", rrect(0.038, hh + 0.006, 0.018), M.blue, 0.035, g, loc=(x, 0)))
    paper_multi(name + "_Bars", bars, [M.blue3], 0.03, g)


def _board(name, g, C, variant):
    w, h = CARD_WH["board"]
    paper(name + "_Frame", rrect(w, h, 0.06), M.cream2, 0.0, g, wob=0.004, seed=51)
    paper(name + "_Board", rrect(w - 0.14, h - 0.14, 0.04), M.white, 0.02, g)
    scr = []
    for i, (x0, y, ln) in enumerate(((-0.62, 0.36, 0.7), (-0.62, 0.14, 1.0), (-0.62, -0.08, 0.55), (-0.62, -0.3, 0.85))):
        scr.append(move(wave_strip(ln, 0.035, 0.018, 14, i * 1.3, cy=y), x0 + ln / 2, 0))
    paper_multi(name + "_Scribble", scr, [M.slate], 0.04, g)
    bx0, bx1, by0, by1, t = -0.7, 0.46, 0.03, 0.26, 0.03
    box = [rrect(bx1 - bx0, t, 0.01, cx=(bx0 + bx1) / 2, cy=by1), rrect(bx1 - bx0, t, 0.01, cx=(bx0 + bx1) / 2, cy=by0),
           rrect(t, by1 - by0, 0.01, cx=bx0, cy=(by0 + by1) / 2), rrect(t, by1 - by0, 0.01, cx=bx1, cy=(by0 + by1) / 2)]
    C["hl"] = paper_multi(name + "_Box", box, [M.blue], 0.05, g)


def _ghosts(kind):
    if kind == "photo":
        return [circle(0.2, cx=0.26, cy=0.44), [(-0.6, -0.44), (-0.1, 0.25), (0.35, -0.44)]]
    if kind == "doc":
        return [rrect(0.9, 0.05, 0.02, cx=-0.1, cy=y) for y in (0.3, 0.1, -0.1)]
    if kind == "voice":
        return [rrect(0.04, 0.15 + 0.3 * abs(math.sin(j)), 0.02, cx=-0.3 + 0.18 * j) for j in range(6)]
    return [move(wave_strip(0.9, 0.04, 0.02, 12, j, cy=y), -0.1, 0) for j, y in enumerate((0.2, -0.1))]


def _perforation(name, w, h, parent, z, spacing=0.2):
    W, H = w + 0.2, h + 0.2
    per = 2 * (W + H)
    n = max(8, int(per / spacing))
    polys = []
    for i in range(n):
        s = per * i / n
        if s < W:
            x, y, a = -W / 2 + s, H / 2, 0
        elif s < W + H:
            x, y, a = W / 2, H / 2 - (s - W), 90
        elif s < 2 * W + H:
            x, y, a = W / 2 - (s - W - H), -H / 2, 0
        else:
            x, y, a = -W / 2, -H / 2 + (s - 2 * W - H), 90
        polys.append(move(rotate(rrect(0.10, 0.032, 0.012), math.radians(a)), x, y))
    return paper_multi(name, polys, [M.grey], z, parent)


def _chip(name, g, label, size=0.11, light=False):
    """A file chip: doc icon, the filename in mono, a blue folder."""
    fg, bg = (M.black, M.white) if light else (M.white, M.dark)
    t = text(name + "_ChipT", label, "mono", size, fg, 0.05, g, loc=(0.0, -size * 0.36))
    tw = measure([t])[0]
    paper(name + "_ChipP", rrect(tw + 0.62, size * 2.4, size * 0.5), bg, 0.04, g, wob=0.003)
    paper(name + "_ChipDoc", doc_page(size * 0.8, size * 1.05, size * 0.3), M.cream2 if light else M.white, 0.05, g,
          loc=(-tw / 2 - size * 1.2, 0))
    paper_multi(name + "_ChipFolder", [rrect(size * 1.0, size * 0.72, size * 0.12, cy=-size * 0.06),
                                       rrect(size * 0.45, size * 0.2, size * 0.06, cx=-size * 0.27, cy=size * 0.32)],
                [M.blue], 0.05, g, loc=(tw / 2 + size * 1.2, 0))


def build_card(name, parent, kind, loc=(0, 0), z=0.0, scale=0.5, rot=0.0, trace=True, solid=True, chip=None,
               variant="land"):
    """A memory. 'solid' is found (painted paper, colour); 'trace' is lost (tracing paper, perforated edge)."""
    C = {"kind": kind, "solid": None, "trace": None, "chip": None, "scale": scale}
    root = empty(name, (loc[0], loc[1], z), parent, rot=math.radians(rot), scale=scale)
    C["root"] = root
    w, h = CARD_WH[kind]
    if solid:
        g = empty(name + "_Solid", parent=root)
        C["solid"] = g
        {"photo": _photo, "doc": _doc, "voice": _voice, "board": _board}[kind](name, g, C, variant)
    if trace:
        g = empty(name + "_Trace", parent=root)
        C["trace"] = g
        outline = doc_page(w, h) if kind == "doc" else rrect(w, h, 0.06)
        paper(name + "_TCard", outline, M.trace, 0.0, g)
        paper_multi(name + "_TGhost", _ghosts(kind), [M.trace], 0.02, g)
        _perforation(name + "_Perf", w, h, g, 0.01)
    if chip:
        g = empty(name + "_ChipG", (0, -h / 2 - 0.3, 0), root)
        C["chip"] = g
        _chip(name, g, chip)
    return C


def key_card(A, C, f, x, y, z, rot, scale, state="solid", pop_s=1.0, seed=0, amt=0.005, chip=False):
    jx, jy, jr = boil(seed, f, amt, 0.35)
    A.loc(C["root"], f, (x + jx, y + jy, z))
    A.rot(C["root"], f, math.radians(rot) + jr)
    A.scl(C["root"], f, TINY if state == "hidden" else scale * pop_s)
    if C["solid"] is not None:
        A.scl(C["solid"], f, 1.0 if state == "solid" else TINY)
    if C["trace"] is not None:
        A.scl(C["trace"], f, 1.0 if state == "trace" else TINY)
    if C["chip"] is not None:
        A.scl(C["chip"], f, 1.0 if chip else TINY)


# ------------------------------------------------------------------ set dressing
def build_leaves(name, parent, loc, z, n=6, spread=(-55, 55), length=(0.8, 1.4), width=0.3, mats=None,
                 seed=0, scale=1.0, rot=0.0, rib=None):
    """A clump of paper leaves fanning up from one point, each on its own layer."""
    mats = mats or [M.teal, M.teal2]
    root = empty(name, (loc[0], loc[1], z), parent, rot=math.radians(rot), scale=scale)
    rnd = random.Random(seed)
    polys, idx, zs, ribs = [], [], [], []
    for i in range(n):
        a = lerp(spread[0], spread[1], i / max(1, n - 1)) + rnd.uniform(-8, 8)
        L = rnd.uniform(*length)
        W = width * rnd.uniform(0.8, 1.2)
        bend = rnd.uniform(-0.1, 0.1) + (0.18 if a > 0 else -0.18)
        polys.append(rotate(leaf_shape(L, W, bend), math.radians(-a)))
        idx.append(i % len(mats))
        zs.append(0.004 * ((i * 3) % n))
        ribs.append(rotate(leaf_shape(L * 0.88, W * 0.07, bend), math.radians(-a)))
    paper_multi(name + "_Leaves", polys, mats, 0.0, root, mat_index=idx, zs=zs, wob=0.004, seed=seed)
    if rib is not None:
        paper_multi(name + "_Ribs", ribs, [rib], 0.0, root, zs=[zz + 0.0015 for zz in zs])
    return root


def build_plant(name, parent, loc, z, scale=1.0, mats=None, seed=0, n=8, pot=None):
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    potmat = pot or M.orange
    paper(name + "_Pot", [(-0.26, -0.5), (0.26, -0.5), (0.34, 0.0), (-0.34, 0.0)], potmat, 0.03, root, wob=0.004)
    paper(name + "_Rim", rrect(0.8, 0.12, 0.03, cy=0.02), M.orange2, 0.032, root)
    build_leaves(name + "_Clump", root, (0, 0.04), 0.0, n=n, spread=(-62, 62), length=(0.9, 1.7), width=0.3,
                 mats=mats or [M.teal, M.teal2], seed=seed, rib=M.teal2)
    return root


def build_books(name, parent, loc, z, n=4, seed=0, w=0.9, scale=1.0):
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    rnd = random.Random(seed)
    mats = [M.orange, M.white, M.leafb, M.orange2, M.teal]
    polys, idx, zs = [], [], []
    y = 0.0
    for i in range(n):
        bw, bh = w * rnd.uniform(0.78, 1.0), rnd.uniform(0.11, 0.16)
        polys.append(rrect(bw, bh, 0.02, cx=rnd.uniform(-0.05, 0.05), cy=y + bh / 2))
        idx.append(rnd.randrange(len(mats)))
        zs.append(0.002 * i)
        y += bh + 0.004
    paper_multi(name + "_Books", polys, mats, 0.0, root, mat_index=idx, zs=zs, wob=0.003)
    return root


def build_box(name, parent, loc, z, w=1.1, h=0.7, drawers=2):
    """A little wooden cabinet: body, drawers, knobs, legs."""
    root = empty(name, (loc[0], loc[1], z), parent)
    paper(name + "_Body", rrect(w, h, 0.04, cy=h / 2), M.wood, 0.0, root, wob=0.004)
    dr, kn = [], []
    for i in range(drawers):
        cy = h * (i + 0.5) / drawers
        dr.append(rrect(w - 0.14, h / drawers - 0.08, 0.02, cy=cy))
        kn.append(rrect(0.14, 0.035, 0.015, cy=cy))
    paper_multi(name + "_Drawers", dr, [M.wood2], 0.004, root)
    paper_multi(name + "_Knobs", kn, [M.black], 0.008, root)
    paper_multi(name + "_Legs", [rrect(0.06, 0.1, 0.02, cx=-w / 2 + 0.1, cy=-0.04),
                                 rrect(0.06, 0.1, 0.02, cx=w / 2 - 0.1, cy=-0.04)], [M.wood2], -0.002, root)
    return root


def build_podium(name, parent, loc, z, w=2.2, h=1.05):
    root = empty(name, (loc[0], loc[1], z), parent)
    paper(name + "_Front", rrect(w, h, 0.03, cy=h / 2), M.wood, 0.0, root, wob=0.004)
    paper(name + "_Top", rrect(w + 0.2, 0.12, 0.03, cy=h + 0.04), M.wood2, 0.004, root)
    paper_multi(name + "_Grain", [rrect(0.03, h - 0.2, 0.01, cx=x, cy=h / 2) for x in (-w / 4, w / 4)],
                [M.wood2], 0.003, root)
    return root


def build_lamp(name, parent, loc, cord_top=1.6, cone_to=-3.8, energy=180.0, z=0.3):
    """A pendant lamp: cord, dark shade, glowing bulb, a veil of warm light, and a real warm light."""
    root = empty(name, (loc[0], loc[1], 0), parent)
    paper(name + "_Cord", rrect(0.025, cord_top, 0.01, cy=cord_top / 2 + 0.3), M.black, 0.02, root)
    paper(name + "_Shade", [(-0.46, 0.0), (0.46, 0.0), (0.3, 0.22), (0.12, 0.36), (-0.12, 0.36), (-0.3, 0.22)],
          M.dark, z, root, wob=0.004)
    paper(name + "_Rim", rrect(0.94, 0.05, 0.02, cy=0.0), M.slate, z + 0.002, root)
    paper(name + "_Bulb", circle(0.11, cy=-0.05), M.bulb, z + 0.004, root)
    paper(name + "_Cone", [(-0.38, -0.02), (0.38, -0.02), (1.8, cone_to), (-1.8, cone_to)], M.cone, 0.035, root)
    ld = bpy.data.lights.new(name + "_Warm", "POINT")
    ld.color = (1.0, 0.76, 0.45)
    ld.energy = energy
    ld.shadow_soft_size = 0.3
    if hasattr(ld, "use_custom_distance"):
        ld.use_custom_distance = True
        ld.cutoff_distance = 7.0
    lo = bpy.data.objects.new(name + "_Warm", ld)
    _link(lo)
    lo.parent = root
    lo.location = (0.0, -0.4, 1.3)
    return root


def build_swoosh(name, parent, loc, z, L, W, bend=0.18, rot=0.0, mat=None):
    return paper(name, swoosh(L, W, bend), mat or M.orange, z, parent, loc=loc, rot=math.radians(rot), wob=0.006)


def build_blob(name, parent, loc, z, r=1.0, mats=None, seed=0, scale=1.0, puffs=None, base=None):
    """A soft painted mass (bush, cloud, orange blob) made of overlapping puffs; base=(w, h) gives it the
    flat bottom of a paper cloud."""
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    mats = mats or [M.orange, M.orange2]
    puffs = puffs or [(-0.5, -0.1, 0.55), (0.1, 0.2, 0.7), (0.65, -0.05, 0.5), (0.0, -0.3, 0.6)]
    polys = [circle(pr * r, cx=px * r, cy=py * r) for px, py, pr in puffs]
    idx = [i % len(mats) for i in range(len(puffs))]
    zs = [0.003 * (i + 1) for i in range(len(puffs))]
    if base:
        polys.append(rrect(base[0] * r, base[1] * r, base[1] * r * 0.5, cy=-0.12 * r - base[1] * r / 2))
        idx.append(0)
        zs.append(0.0)
    paper_multi(name + "_Puffs", polys, mats, 0.0, root, mat_index=idx, zs=zs, wob=0.02, seed=seed)
    return root


def build_moon(name, parent, loc, z, r=0.75):
    root = empty(name, (loc[0], loc[1], z), parent)
    paper(name + "_Disc", circle(r, N=96), M.moon, 0.0, root, wob=0.01)
    paper_multi(name + "_Craters", [circle(r * s, cx=r * x, cy=r * y) for x, y, s in
                                    ((0.25, 0.3, 0.22), (-0.3, -0.1, 0.16), (0.1, -0.4, 0.12), (-0.05, 0.45, 0.08))],
                [M.crater], 0.004, root, wob=0.004)
    return root


def build_shelf(name, parent, x, base_y, w, h, z, frame_mat, cell_mat=None, binder_mats=None, cols=2, rows=4,
                tag=None, tag_mat=None, seed=0, max_binders=6):
    """A shelf unit whose pin is its bottom edge, so scaling y unfolds it like a pop-up."""
    root = empty(name, (x, base_y, z), parent)
    paper(name + "_Frame", rrect(w, h, 0.04, cy=h / 2), frame_mat, 0.0, root, wob=0.004, seed=seed)
    rnd = random.Random(seed)
    if cols and cell_mat is not None:
        m = 0.08
        cw = (w - m * (cols + 1)) / cols
        ch = (h - m * (rows + 1) - 0.12) / rows
        cells, binders, bidx = [], [], []
        for r in range(rows):
            for c in range(cols):
                cx = -w / 2 + m + cw / 2 + c * (cw + m)
                cy = 0.12 + m + ch / 2 + r * (ch + m)
                cells.append(rrect(cw, ch, 0.02, cx=cx, cy=cy))
                xx, nb = cx - cw / 2 + 0.04, 0
                while nb < max_binders:
                    bw, bh = rnd.uniform(0.07, 0.13), ch * rnd.uniform(0.5, 0.88)
                    if xx + bw > cx + cw / 2 - 0.03:
                        break
                    binders.append(rrect(bw, bh, 0.015, cx=xx + bw / 2, cy=cy - ch / 2 + bh / 2 + 0.01))
                    bidx.append(rnd.randrange(len(binder_mats)))
                    xx += bw + rnd.uniform(0.012, 0.05)
                    nb += 1
        paper_multi(name + "_Cells", cells, [cell_mat], 0.012, root)
        paper_multi(name + "_Binders", binders, list(binder_mats), 0.022, root, mat_index=bidx)
    if tag:
        tg = empty(name + "_Tag", (0, h * 0.52, 0), root, rot=math.radians(rnd.uniform(-5, 5)))
        t = text(name + "_TagT", tag, "mono", 0.075, M.black, 0.04, tg, loc=(0, -0.027))
        tw = measure([t])[0]
        paper(name + "_TagP", rrect(tw + 0.12, 0.15, 0.03), tag_mat, 0.034, tg)
    return root


def build_thought(name, parent, loc, scale=1.0, z=0.26):
    T = {}
    root = empty(name, (loc[0], loc[1], z), parent, scale=scale)
    T["root"] = root
    cloud = empty(name + "_Cloud", parent=root)
    T["cloud"] = cloud
    for i, (cx, cy, r) in enumerate(((0, 0.05, 0.5), (-0.6, -0.08, 0.38), (0.62, -0.06, 0.4), (-0.3, 0.35, 0.36),
                                     (0.32, 0.36, 0.38), (0, -0.25, 0.42))):
        paper(f"{name}_C{i}", circle(r, cx=cx, cy=cy), M.white, 0.003 * i, cloud, wob=0.01, seed=i)
    T["bubbles"] = [paper(f"{name}_B{i}", circle(r), M.white, 0.0, root, loc=p)
                    for i, (p, r) in enumerate((((-0.75, -0.95), 0.06), ((-0.6, -0.72), 0.09), ((-0.38, -0.48), 0.12)))]
    T["card"] = build_card(name + "_Photo", root, "photo", loc=(0, 0.03), z=0.03, scale=0.5, trace=False)
    return T


def caption(A, S, prefix, segments, out_l, y=-2.08, size=0.25, fkey="serif", mat=None, x=0.0, z=0.14,
            stagger=2, seed=50, gap=None, emph_mat=None):
    """Cut-paper words that pop in one per step (on twos) and pop out together."""
    items = word_row(prefix, segments, fkey, size, mat or M.white, z, (x, y), S["root"], gap=gap,
                     emph_mat=emph_mat or M.blue)
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
