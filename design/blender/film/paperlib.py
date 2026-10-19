"""Paper-cut toolkit for the Hawk launch film (Blender 5.1).

Every piece is a flat cut shape with a sliver of thickness, lit by one angled key light and
shot from straight above, like a rostrum camera looking down through stacked glass. Puppets
are keyed on twos with CONSTANT interpolation; cameras and multiplane slides on ones.
"""
import math
import random

import bmesh
import bpy
from bpy_extras import anim_utils

TINY = 1e-4
FONT_DIR = "/Users/karnav/Products/knowra/app/assets/fonts/"
FONT_FILES = {
    "serif": "InstrumentSerif-Regular.ttf",
    "serif_i": "InstrumentSerif-Italic.ttf",
    "sans": "Archivo-Variable.ttf",
    "mono": "MartianMono-Variable.ttf",
    "hand": __import__("os").path.join(__import__("os").path.dirname(__file__), "fonts", "Caveat.ttf"),
}

_state = {"col": None}
_mats = {}
_fonts = {}


def use_collection(col):
    _state["col"] = col


def _link(ob):
    _state["col"].objects.link(ob)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


# ------------------------------------------------------------------ paper stock
def s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexc(h):
    h = h.lstrip("#")
    return tuple(s2l(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


def _sock(node, name, typ=None, out=False):
    for s in (node.outputs if out else node.inputs):
        if s.name == name and (typ is None or s.type == typ):
            return s
    raise KeyError(name)


def paper_mat(name, rgb, alpha=1.0, fiber=0.08, mottle=0.12, rough=0.9, tint=None, streak=0.4, tex=1.0,
              angle=0.35, emit=0.0, speck=0.1):
    """Painted paper, like gouache on card:
    - broad brush strokes that pull toward a lighter tint, laid in a different direction on every piece
      (Object Info random rotates the stroke mapping), with a second, darker stroke layer across them;
    - blotchy colour, dry-brush light specks and dark grain, fibre bump.
    alpha < 1 makes a veil (tracing paper, light cones); emit > 0 makes it glow (bulbs, moon, town lights)."""
    if name in _mats:
        return _mats[name]
    if tint is None:
        tint = tuple(min(1.0, c * 1.5 + 0.015) for c in rgb)
    shade = tuple(c * 0.78 for c in rgb)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    tc = N.new("ShaderNodeTexCoord")
    oi = N.new("ShaderNodeObjectInfo")
    rnd = N.new("ShaderNodeMath")
    rnd.operation = "MULTIPLY_ADD"
    rnd.inputs[1].default_value = 6.283
    rnd.inputs[2].default_value = angle
    L.new(oi.outputs["Random"], rnd.inputs[0])

    def strokes(scale_x, scale_y, extra_rot, lo, hi, strength):
        rot = N.new("ShaderNodeCombineXYZ")
        add = N.new("ShaderNodeMath")
        add.operation = "ADD"
        add.inputs[1].default_value = extra_rot
        L.new(rnd.outputs["Value"], add.inputs[0])
        L.new(add.outputs["Value"], rot.inputs["Z"])
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale_x * tex, scale_y * tex, scale_x * tex)
        L.new(rot.outputs["Vector"], mp.inputs["Rotation"])
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        nz = N.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = 5.0
        nz.inputs["Roughness"].default_value = 0.6
        try:
            nz.inputs["Distortion"].default_value = 0.5
        except KeyError:
            pass
        L.new(mp.outputs["Vector"], nz.inputs["Vector"])
        mr_ = N.new("ShaderNodeMapRange")
        mr_.inputs["From Min"].default_value = lo
        mr_.inputs["From Max"].default_value = hi
        mr_.inputs["To Min"].default_value = 0.0
        mr_.inputs["To Max"].default_value = strength
        L.new(nz.outputs["Fac"], mr_.inputs["Value"])
        return mr_.outputs["Result"]

    def mix_to(prev, color, fac):
        mx = N.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        if prev is None:
            _sock(mx, "A", "RGBA").default_value = (*rgb, 1.0)
        else:
            L.new(prev, _sock(mx, "A", "RGBA"))
        _sock(mx, "B", "RGBA").default_value = (*color, 1.0)
        L.new(fac, _sock(mx, "Factor", "VALUE"))
        return _sock(mx, "Result", "RGBA", out=True)

    col = mix_to(None, tint, strokes(2.2, 9.0, 0.0, 0.38, 0.66, streak))          # light strokes
    col = mix_to(col, shade, strokes(1.6, 6.0, 1.1, 0.46, 0.7, streak * 0.8))      # darker strokes across them
    # blotchy colour
    mot = N.new("ShaderNodeTexNoise")
    mot.inputs["Scale"].default_value = 5.0 * tex
    mot.inputs["Detail"].default_value = 6.0
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    mr = N.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.3
    mr.inputs["From Max"].default_value = 0.7
    mr.inputs["To Min"].default_value = 1.0 - mottle
    mr.inputs["To Max"].default_value = 1.0 + mottle * 0.5
    L.new(mot.outputs["Fac"], mr.inputs["Value"])
    mul = N.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    _sock(mul, "Factor", "VALUE").default_value = 1.0
    L.new(col, _sock(mul, "A", "RGBA"))
    L.new(mr.outputs["Result"], _sock(mul, "B", "RGBA"))
    col = _sock(mul, "Result", "RGBA", out=True)
    # dry-brush specks (light) and paper grain (dark)
    for scale, lo, hi, color, amt in ((700.0, 0.66, 0.72, tint, speck), (900.0, 0.69, 0.74, tuple(c * 0.5 for c in rgb), speck * 1.3)):
        sp = N.new("ShaderNodeTexNoise")
        sp.inputs["Scale"].default_value = scale * tex
        sp.inputs["Detail"].default_value = 2.0
        L.new(tc.outputs["Object"], sp.inputs["Vector"])
        spr = N.new("ShaderNodeMapRange")
        spr.inputs["From Min"].default_value = lo
        spr.inputs["From Max"].default_value = hi
        spr.inputs["To Min"].default_value = 0.0
        spr.inputs["To Max"].default_value = amt
        L.new(sp.outputs["Fac"], spr.inputs["Value"])
        col = mix_to(col, color, spr.outputs["Result"])
    L.new(col, bsdf.inputs["Base Color"])
    fib = N.new("ShaderNodeTexNoise")
    fib.inputs["Scale"].default_value = 260.0
    fib.inputs["Detail"].default_value = 12.0
    fib.inputs["Roughness"].default_value = 0.75
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = fiber
    bump.inputs["Distance"].default_value = 0.01
    L.new(tc.outputs["Object"], fib.inputs["Vector"])
    L.new(fib.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = rough
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.05
    except KeyError:
        pass
    if emit > 0:
        L.new(col, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if alpha < 1.0:
        # Alpha blends in linear light: small values already read strongly on a dark page.
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    _mats[name] = m
    return m


def tone(hexstr, fiber=0.1):
    return paper_mat("Paper_" + hexstr.lstrip("#"), hexc(hexstr), fiber=fiber)


class M:
    """The film's paper stock: navy page, cream paper, brand blue, orange accents, painted greens."""


def _p(name, hexs, tint=None, **kw):
    return paper_mat("Paper_" + name, hexc(hexs), tint=hexc(tint) if tint else None, **kw)


def init_palette():
    _mats.clear()
    M.white = _p("Cream", "#efe6d3", "#fbf7ee", streak=0.5)
    M.cream2 = _p("CreamShade", "#d8cbb2", "#eadfca")
    M.light = _p("CreamTorso", "#e3d7c1", "#f3ebdc")
    M.black = _p("Ink", "#0e1522", "#1a2436", streak=0.2)
    M.card = _p("Page", "#0a1120", "#1b2c4a", streak=0.7, tex=0.14, fiber=0.12, speck=0.05)
    M.char1 = _p("FloorBack", "#111a2a", "#1a2740", streak=0.45, tex=0.25)
    M.char2 = _p("FloorFront", "#0a111d", "#141f33", streak=0.45, tex=0.25)
    M.blue = _p("Blue", "#59d3ff", "#b5ecff", streak=0.35)
    M.blue2 = _p("BlueMid", "#3f86c9", "#74b2ea")
    M.blue3 = _p("BlueDeep", "#1f4f8f", "#3570b8")
    M.sky1 = _p("LightBlue", "#9fcdf0", "#dff0fc")
    M.paleblue = _p("PaleBlue", "#cfe5f8", "#eef7fe")
    M.orange = _p("Orange", "#e98b3a", "#f6b872", streak=0.5)
    M.orange2 = _p("OrangeLight", "#f2b36b", "#fcdcae")
    M.yellow = _p("Yellow", "#f3c34f", "#fbe08e")
    M.teal = _p("Teal", "#2a6f6b", "#4c9a91")
    M.teal2 = _p("TealDark", "#1d4f50", "#2f6e6b")
    M.leafb = _p("LeafBlue", "#2b5e9a", "#4f86c4")
    M.leafb2 = _p("LeafBlueDark", "#1b3f6b", "#2e5b92")
    M.wood = _p("Wood", "#8a5a33", "#b27b47", streak=0.55)
    M.wood2 = _p("WoodDark", "#5e3b20", "#7b5231", streak=0.55)
    M.dark = _p("NavyCard", "#1b2638", "#28374f")
    M.slate = _p("Slate", "#3b4a63", "#56678a")
    M.grey = _p("Dim", "#5b6b82", "#71819a")
    M.mid = _p("Mist", "#7d8aa0", "#9aa6ba")
    M.mount1 = _p("Mount1", "#1f3a62", "#2f5184", streak=0.5, tex=0.4)
    M.mount2 = _p("Mount2", "#182f52", "#244270", streak=0.5, tex=0.4)
    M.mount3 = _p("Mount3", "#11223d", "#1b3458", streak=0.5, tex=0.4)
    M.pine = _p("Pine", "#0e1a2c", "#172a45")
    M.lake = _p("Lake", "#0b172a", "#152643", streak=0.5, tex=0.3)
    M.cloud1 = _p("Cloud1", "#b7c9df", "#e3ecf6", streak=0.6)
    M.cloud2 = _p("Cloud2", "#7c9fc9", "#afc8e6", streak=0.6)
    M.sky = [_p(f"Sky{i}", h, t, streak=0.6, tex=0.15) for i, (h, t) in enumerate(
        (("#172b4a", "#213a61"), ("#122441", "#1b3257"), ("#0e1c35", "#172a4a"), ("#0b162a", "#13223c"),
         ("#08101f", "#101b30")))]
    M.sunset = [_p(f"Sunset{i}", h, t, streak=0.6, tex=0.4) for i, (h, t) in enumerate(
        (("#284a6b", "#3a6288"), ("#6b5a7a", "#8c7896"), ("#c96a4a", "#e08a62"), ("#ee8a3c", "#f7ae62"),
         ("#f6c25a", "#fbdc8c")))]
    M.island = _p("Island", "#3a3f6b", "#50578a")
    M.sea = _p("Sea", "#1d3354", "#2c4a74", streak=0.6)
    M.palm = _p("Palm", "#0f1a2b", "#1a2940")
    M.bulb = _p("Bulb", "#ffe3a1", "#fff3d2", emit=10.0)
    M.town = _p("TownLight", "#ffd27a", "#ffe7b0", emit=6.0)
    M.sun = _p("SunGlow", "#ffd873", "#fff0bd", emit=3.0)
    M.moon = _p("Moon", "#f3d6ab", "#fbe9cf", emit=0.6)
    M.crater = _p("Crater", "#eccfa3", "#f6e2c2", emit=0.5)
    M.cone = paper_mat("Paper_LightCone", hexc("#f7c26a"), alpha=0.09, streak=0.2, fiber=0.0)
    M.reflect = paper_mat("Paper_Reflect", hexc("#f2b36b"), alpha=0.35, streak=0.3, fiber=0.0)
    M.trace = paper_mat("Paper_Tracing", (0.66, 0.72, 0.80), alpha=0.06, fiber=0.03, mottle=0.03, streak=0.1)


# ------------------------------------------------------------------ cut shapes (CCW point lists)
def wobble(pts, amp, seed):
    """Hand-cut edge: a smooth periodic wobble along the outline."""
    if amp <= 0:
        return pts
    rnd = random.Random(seed)
    ph = [rnd.random() * 6.283 for _ in range(3)]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    n = len(pts)
    out = []
    for i, (x, y) in enumerate(pts):
        t = i / n
        d = amp * (0.55 * math.sin(6.2832 * 3 * t + ph[0]) + 0.3 * math.sin(6.2832 * 7 * t + ph[1])
                   + 0.15 * math.sin(6.2832 * 17 * t + ph[2]))
        vx, vy = x - cx, y - cy
        ln = math.hypot(vx, vy) or 1.0
        out.append((x + vx / ln * d, y + vy / ln * d))
    return out


def superellipse(a, b, n, N=180):
    pts = []
    for i in range(N):
        t = 2 * math.pi * i / N
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / n), c), b * math.copysign(abs(s) ** (2 / n), s)))
    return pts


def circle(r, N=72, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(2 * math.pi * i / N), cy + r * math.sin(2 * math.pi * i / N)) for i in range(N)]


def rrect(w, h, r, cx=0.0, cy=0.0, seg_n=5):
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    pts = []
    for (x, y, a0) in [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]:
        for j in range(seg_n + 1):
            a = math.radians(a0 + 90 * j / seg_n)
            pts.append((cx + x + r * math.cos(a), cy + y + r * math.sin(a)))
    return pts


def sparkle(r, p=2.6, N=96):
    pts = []
    for i in range(N):
        t = 2 * math.pi * i / N
        c, s = math.cos(t), math.sin(t)
        pts.append((r * math.copysign(abs(c) ** p, c), r * math.copysign(abs(s) ** p, s)))
    return pts


def wave_strip(w, th, amp, k, ph, cy=0.0, N=60):
    top = [(-w / 2 + w * i / N, cy + amp * math.sin(k * (-w / 2 + w * i / N) + ph)) for i in range(N + 1)]
    return [(x, y - th) for x, y in top] + list(reversed(top))


def closed_lid(A, N=60):
    top, bot = [], []
    for i in range(N + 1):
        x = -A + 2 * A * i / N
        u = x / A
        yc = -0.10 * (1 - u * u)
        th = 0.13 * math.sqrt(max(0.0, 1 - u * u)) + 0.025
        top.append((x, yc + th / 2))
        bot.append((x, yc - th / 2))
    return bot + list(reversed(top))


def torn_strip(y_top, y_bot, seed, x0=-9.0, x1=9.0, step=0.05):
    rnd = random.Random(seed)
    ph = [rnd.random() * 6.283 for _ in range(3)]
    top = []
    xs = [x0 + step * i for i in range(int((x1 - x0) / step) + 1)]
    for x in xs:
        y = (y_top + 0.06 * math.sin(0.9 * x + ph[0]) + 0.025 * math.sin(3.1 * x + ph[1])
             + 0.012 * math.sin(9.7 * x + ph[2]) + rnd.uniform(-0.008, 0.008))
        top.append((x, y))
    return [(x0, y_bot), (x1, y_bot)] + list(reversed(top))


def move(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


def rotate(pts, a):
    c, s = math.cos(a), math.sin(a)
    return [(x * c - y * s, x * s + y * c) for x, y in pts]


# ------------------------------------------------------------------ objects
def empty(name, loc=(0, 0, 0), parent=None, rot=0.0, scale=1.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.2
    _link(e)
    if parent is not None:
        e.parent = parent
    e.location = loc
    e.rotation_euler.z = rot
    e.scale = scale if isinstance(scale, tuple) else (scale, scale, scale)
    return e


def paper_multi(name, polys, mats, z, parent=None, loc=(0, 0), thick=0.01, wob=0.0, seed=1, rot=0.0,
                mat_index=None, zs=None):
    """Several cut pieces in one mesh (one draw call); each polygon is one piece. zs lifts pieces that
    overlap (leaves, cloud puffs) onto their own layers so they do not z-fight."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for i, pts in enumerate(polys):
        pts = wobble(pts, wob, seed + i)
        zz = zs[i] if zs else 0.0
        f = bm.faces.new([bm.verts.new((x, y, zz)) for x, y in pts])
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        f.material_index = mat_index[i] if mat_index else 0
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    _link(ob)
    sol = ob.modifiers.new("Paper", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1.0
    if parent is not None:
        ob.parent = parent
    ob.location = (loc[0], loc[1], z)
    ob.rotation_euler.z = rot
    return ob


def paper(name, pts, mat, z, parent=None, loc=(0, 0), thick=0.01, wob=0.0, seed=1, rot=0.0):
    return paper_multi(name, [pts], [mat], z, parent, loc, thick, wob, seed, rot)


def font(key):
    if key not in _fonts:
        path = FONT_FILES[key] if FONT_FILES[key].startswith("/") else FONT_DIR + FONT_FILES[key]
        _fonts[key] = bpy.data.fonts.load(path, check_existing=True)
    return _fonts[key]


def text(name, body, fkey, size, mat, z, parent=None, loc=(0, 0), align="CENTER", thick=0.006, rot=0.0):
    """Cut-paper lettering: an extruded text curve whose top face sits at z."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.font = font(fkey)
    cu.size = size
    cu.align_x = align
    cu.extrude = thick / 2
    ob = bpy.data.objects.new(name, cu)
    _link(ob)
    cu.materials.append(mat)
    if parent is not None:
        ob.parent = parent
    ob.location = (loc[0], loc[1], z - thick / 2)
    ob.rotation_euler.z = rot
    return ob


def measure(obs):
    """Width in the object's own space. Object.dimensions folds in the parents' scale, so it lies
    for text sitting on a scaled card; the local bounding box does not."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    for ob in obs:
        xs = [v[0] for v in ob.evaluated_get(dg).bound_box]
        out.append((max(xs) - min(xs)) * ob.scale.x)
    return out


def word_row(prefix, segments, fkey, size, mat, z, center, parent, gap=None, emph_mat=None):
    """Lay words out on one centred line; each word is its own piece so it can pop in.
    Words wrapped in *stars* (one word or a run of words) are cut from emph_mat instead."""
    obs, tags = [], []
    emph = False
    for si, (txt, tag) in enumerate(segments):
        for wi, w in enumerate(txt.split()):
            on = emph or w.startswith("*")
            end = len(w) > 1 and w.endswith("*")
            m = emph_mat if (on and emph_mat is not None) else mat
            obs.append(text(f"{prefix}_{si}_{wi}", w.strip("*"), fkey, size, m, z, parent))
            tags.append(tag)
            emph = on and not end
    widths = measure(obs)
    sp = size * 0.3 if gap is None else gap
    total = sum(widths) + sp * (len(obs) - 1)
    x = center[0] - total / 2
    out = []
    for ob, w, tag in zip(obs, widths, tags):
        ob.location.x = x + w / 2
        ob.location.y = center[1]
        out.append((ob, tag))
        x += w + sp
    return out


# ------------------------------------------------------------------ keys
def boil(seed, f, amt=0.006, rot_deg=0.35):
    """The hand-placed shiver: a new tiny offset every step."""
    r = random.Random(seed * 100003 + f)
    return r.uniform(-amt, amt), r.uniform(-amt, amt), math.radians(r.uniform(-rot_deg, rot_deg))


class Anim:
    """Collects poses, then writes them as keyframes in one pass (fast bulk insert)."""

    def __init__(self):
        self.k = {}
        self.interp = {}

    def _ch(self, ob, ch):
        return self.k.setdefault(ob.name, {}).setdefault(ch, {})

    def loc(self, ob, f, v):
        self._ch(ob, "loc")[f] = (float(v[0]), float(v[1]), float(v[2]))

    def rot(self, ob, f, r):
        self._ch(ob, "rot")[f] = float(r)

    def scl(self, ob, f, s):
        if not isinstance(s, (tuple, list)):
            s = (s, s, s)
        self._ch(ob, "scl")[f] = tuple(float(v) for v in s)

    def smooth(self, ob):
        self.interp[ob.name] = "LINEAR"

    def flush(self):
        n = 0
        for name, chans in self.k.items():
            ob = bpy.data.objects[name]
            interp = self.interp.get(name, "CONSTANT")
            for ch, path, idxs in (("loc", "location", (0, 1, 2)), ("rot", "rotation_euler", (2,)),
                                   ("scl", "scale", (0, 1, 2))):
                data = chans.get(ch)
                if not data:
                    continue
                frames = sorted(data)
                f0 = frames[0]
                if ch == "rot":
                    ob.rotation_euler[2] = data[f0]
                    ob.keyframe_insert(path, index=2, frame=f0)
                else:
                    setattr(ob, path, data[f0])
                    ob.keyframe_insert(path, frame=f0)
                ad = ob.animation_data
                cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
                for fc in cb.fcurves:
                    if fc.data_path != path or fc.array_index not in idxs:
                        continue
                    i = fc.array_index
                    co = []
                    for f in frames:
                        v = data[f]
                        co += [f, v if ch == "rot" else v[i]]
                    kps = fc.keyframe_points
                    kps.add(len(frames) - len(kps))
                    kps.foreach_set("co", co)
                    for kp in kps:
                        kp.interpolation = interp
                    fc.update()
                    n += len(frames)
        return n
