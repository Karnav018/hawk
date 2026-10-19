"""Makes the 9:16 portrait version from a copy of the final 16:9 file, by re-aiming the camera only.

    cp hawk_film_previous_textured.blend hawk_film_portrait.blend
    Blender -b hawk_film_portrait.blend --python make_portrait.py

Nothing in the scene moves. The camera gets a longer lens (the frame is 6.4 units wide at the usual
height instead of 11), then follows the action through each scene: it pans between the person and the
eye, steps back where a scene is wide, and sits a little lower on the ground scenes so the picture fills
the upper part of the frame and the captions land in the lower third. The hawk dive keeps its own moves.
Long captions wrap onto two lines. Frame numbers are in the original timeline (the 1.2x remap stays).
"""
import math
import statistics

import bpy
from bpy_extras import anim_utils

TINY = 1e-4
LENS = 36.0 * 14.0 / 6.4                  # 6.4 units wide at the usual camera height
DIVE = (396, 470)                          # frames whose camera keys come from the dive edit
GLASS_Z = 0.7

# portrait framing stations: (original frame, x, y, z); smoothstep between neighbours
STATIONS = [
    (1, -0.2, -0.9, 13.6), (144, -0.1, -0.9, 13.4),                 # lost
    (235, 0.0, -0.3, 19.0), (288, 0.0, -0.3, 19.0),                 # the archive unfolds
    (324, -2.2, 7.0, 14.0), (384, 0.3, 7.3, 14.0), (396, 0.3, 7.3, 14.0),   # up into the sky, with the hawk
    (470, 0.3, 7.3, 14.0), (504, 15.9, -0.9, 18.5), (612, 15.9, -0.9, 18.3),  # storage
    (648, 27.7, -0.9, 17.5), (744, 27.7, -0.9, 17.4),              # filenames
    (780, 38.15, -0.9, 14.0), (880, 38.15, -0.9, 14.0),            # the ask: person, ribbon, eye
    (900, 41.9, -0.9, 14.0), (928, 41.9, -0.9, 14.0),              # the eye finds the photo on the shelf
    (955, 38.15, -0.9, 14.0), (1020, 38.15, -0.9, 14.0),           # the photo flies back; the answer
    (1047, 42.3, -0.9, 14.5), (1164, 42.3, -0.9, 14.5),            # three more finds
    (1205, 36.9, -0.9, 17.5), (1296, 36.9, -0.9, 17.2),            # the memories come close
    (1343, 35.8, 7.0, 14.0), (1440, 35.8, 7.0, 13.6),              # end card
]
LINE_MAX, LINE_GAP = 5.0, 0.4


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def framing(f):
    for (f0, *a), (f1, *b) in zip(STATIONS, STATIONS[1:]):
        if f0 <= f <= f1:
            t = smooth((f - f0) / float(f1 - f0))
            return tuple(u + (v - u) * t for u, v in zip(a, b))
    return tuple(STATIONS[-1][1:])


def fcurves(idblock):
    ad = idblock.animation_data
    if not ad or not ad.action:
        return []
    cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
    return list(cb.fcurves) if cb else []


def curve(idblock, path, index):
    return next((fc for fc in fcurves(idblock) if fc.data_path == path and fc.array_index == index), None)


def key_map(fc):
    return {round(kp.co.x): kp for kp in fc.keyframe_points}


def put(fc, f, v, keys):
    kp = keys.get(f)
    if kp is None:
        kp = fc.keyframe_points.insert(f, v, options={"FAST"})
        keys[f] = kp
    kp.co.y = kp.handle_left.y = kp.handle_right.y = v


def reaim(scene):
    O = bpy.data.objects
    cam, glass = O["Cam"], O["Glass"]
    cd = cam.data
    cd.lens = LENS
    cc = [curve(cam, "location", i) for i in range(3)]
    gc = [curve(glass, "location", i) for i in range(3)] + [curve(glass, "scale", i) for i in range(3)]
    fd, cs = curve(cd, "dof.focus_distance", 0), curve(cd, "clip_start", 0)
    ck, gk = [key_map(c) for c in cc], [key_map(c) for c in gc]
    fk, sk = key_map(fd), key_map(cs)
    for f in range(1, 1441):
        if DIVE[0] <= f <= DIVE[1]:
            x, y, z = (ck[i][f].co.y for i in range(3))
        else:
            x, y, z = framing(f)
            for i, v in enumerate((x, y, z)):
                put(cc[i], f, v, ck[i])
            put(fd, f, max(0.01, z - 0.42), fk)
            put(cs, f, 0.1, sk)
        s = (z - GLASS_Z) / (14.0 - GLASS_Z) if z > 3.0 else TINY
        for i, v in enumerate((x, y, GLASS_Z, s, s, s)):
            put(gc[i], f, v, gk[i])
    for c in cc + gc + [fd, cs]:
        c.update()


def width_of(ob):
    """Local width of the evaluated text (an unevaluated text object reports an empty box)."""
    dg = bpy.context.evaluated_depsgraph_get()
    xs = [v[0] for v in ob.evaluated_get(dg).bound_box]
    return max(xs) - min(xs)


def base(ob, index):
    fc = curve(ob, "location", index)
    return statistics.median(kp.co.y for kp in fc.keyframe_points), fc


def rewrap_captions():
    groups = {}
    for ob in bpy.data.objects:
        if ob.type == "FONT" and ob.name.startswith("Cap") and ob.name.count("_") == 2:
            cap, s, w = ob.name.split("_")
            groups.setdefault(cap, []).append((int(s), int(w), ob))
    bpy.context.view_layer.update()
    wrapped = 0
    for cap, items in groups.items():
        items.sort()
        size = items[0][2].data.size
        sp = size * 0.3
        widths = {ob.name: width_of(ob) for _, _, ob in items}
        total = sum(widths.values()) + sp * (len(items) - 1)
        if total <= LINE_MAX:
            continue
        segs = sorted({s for s, _, _ in items})
        if len(segs) >= 3:                               # e.g. "Documents. Voice notes." / "Photos, ..."
            lines = [[it for it in items if it[0] < segs[-1]], [it for it in items if it[0] == segs[-1]]]
        elif len(segs) == 2:
            lines = [[it for it in items if it[0] == segs[0]], [it for it in items if it[0] == segs[1]]]
        else:                                            # one long segment: split where it balances
            best, cut = None, 1
            for k in range(1, len(items)):
                a = sum(widths[it[2].name] for it in items[:k])
                b = sum(widths[it[2].name] for it in items[k:])
                if best is None or abs(a - b) < best:
                    best, cut = abs(a - b), k
            lines = [items[:cut], items[cut:]]
        y0, _ = base(items[0][2], 1)
        for li, line in enumerate(lines):
            lw = sum(widths[it[2].name] for it in line) + sp * (len(line) - 1)
            x = -lw / 2
            ty = y0 + LINE_GAP / 2 - li * LINE_GAP
            for _, _, ob in line:
                w = widths[ob.name]
                tx = x + w / 2
                for idx, target in ((0, tx), (1, ty)):
                    b, fc = base(ob, idx)
                    d = target - b
                    for kp in fc.keyframe_points:
                        kp.co.y += d
                        kp.handle_left.y += d
                        kp.handle_right.y += d
                    fc.update()
                x += w + sp
        wrapped += 1
    return wrapped


def main():
    scene = bpy.context.scene
    reaim(scene)
    n = rewrap_captions()
    scene.render.resolution_x, scene.render.resolution_y = 1080, 1920
    scene.render.filepath = "//frames_portrait/hp_"
    scene.frame_set(1)
    bpy.ops.wm.save_mainfile()
    print(f"PORTRAIT lens={LENS:.1f}mm captions_wrapped={n} res=1080x1920 frames={scene.frame_start}-{scene.frame_end}")


main()
