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


def paper_mat(name, rgb, alpha=1.0, fiber=0.08, mottle=0.08, rough=0.9):
    """Diffuse paper: fibre bump, faint mottling, optional see-through (tracing paper)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    for n in list(N):
        N.remove(n)
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    tc = N.new("ShaderNodeTexCoord")
    fib = N.new("ShaderNodeTexNoise")
    fib.inputs["Scale"].default_value = 260.0
    fib.inputs["Detail"].default_value = 12.0
    fib.inputs["Roughness"].default_value = 0.75
    mot = N.new("ShaderNodeTexNoise")
    mot.inputs["Scale"].default_value = 3.5
    mot.inputs["Detail"].default_value = 6.0
    mr = N.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.3
    mr.inputs["From Max"].default_value = 0.7
    mr.inputs["To Min"].default_value = 1.0 - mottle
    mr.inputs["To Max"].default_value = 1.0
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    _sock(mix, "Factor", "VALUE").default_value = 1.0
    _sock(mix, "A", "RGBA").default_value = (*rgb, 1.0)
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = fiber
    bump.inputs["Distance"].default_value = 0.01
    L.new(tc.outputs["Object"], fib.inputs["Vector"])
    L.new(tc.outputs["Object"], mot.inputs["Vector"])
    L.new(mot.outputs["Fac"], mr.inputs["Value"])
    L.new(mr.outputs["Result"], _sock(mix, "B", "RGBA"))
    L.new(_sock(mix, "Result", "RGBA", out=True), bsdf.inputs["Base Color"])
    L.new(fib.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = rough
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    except KeyError:
        pass
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if alpha < 1.0:
        # Alpha blends in linear light: 0.05 already reads as faint vellum on black.
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    _mats[name] = m
    return m


def tone(hexstr, fiber=0.1):
    return paper_mat("Paper_" + hexstr.lstrip("#"), hexc(hexstr), fiber=fiber)


class M:
    """The film's paper stock. Blue is the only colour, and it means found."""


def init_palette():
    _mats.clear()
    M.white = paper_mat("Paper_White", (0.80, 0.80, 0.78))
    M.black = paper_mat("Paper_Black", hexc("#0c0c0d"))
    M.card = paper_mat("Paper_BlackCard", hexc("#121214"), fiber=0.12)
    M.char1 = paper_mat("Paper_Charcoal_Back", hexc("#18181b"), fiber=0.12)
    M.char2 = paper_mat("Paper_Charcoal_Front", hexc("#222226"), fiber=0.12)
    M.blue = paper_mat("Paper_Blue", hexc("#59d3ff"))
    M.grey = paper_mat("Paper_Grey", hexc("#5a5a5e"))
    M.light = tone("#b9b9b6")
    M.mid = tone("#7c7c80")
    M.dark = tone("#2e2e32")
    M.trace = paper_mat("Paper_Tracing", (0.62, 0.66, 0.70), alpha=0.05, fiber=0.03, mottle=0.03)


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
                mat_index=None):
    """Several cut pieces in one mesh (one draw call); each polygon is one piece."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for i, pts in enumerate(polys):
        pts = wobble(pts, wob, seed + i)
        f = bm.faces.new([bm.verts.new((x, y, 0.0)) for x, y in pts])
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
        _fonts[key] = bpy.data.fonts.load(FONT_DIR + FONT_FILES[key], check_existing=True)
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


def word_row(prefix, segments, fkey, size, mat, z, center, parent, gap=None):
    """Lay words out on one centred line; each word is its own piece so it can pop in."""
    obs, tags = [], []
    for si, (txt, tag) in enumerate(segments):
        for wi, w in enumerate(txt.split()):
            obs.append(text(f"{prefix}_{si}_{wi}", w, fkey, size, mat, z, parent))
            tags.append(tag)
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
