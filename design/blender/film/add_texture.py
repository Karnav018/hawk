"""Adds the reference's painted texture and colours to a copy of the previous film file.

    Blender -b hawk_film_previous_textured.blend --python add_texture.py

Nothing is moved, added or removed: every paper material is swapped for a gouache-painted one in the
reference palette (reference/enhanced_look_reference_v2.png), a few pieces that shared a grey get their
own colour, key caption words turn blue, and the frame becomes 16:9 with the captions lowered into the
bottom band.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paperlib  # noqa: E402
from paperlib import hexc, paper_mat  # noqa: E402

_made = {}


def paint(key, hexs, tint=None, **kw):
    if key not in _made:
        _made[key] = paper_mat("Paint_" + key, hexc(hexs), tint=hexc(tint) if tint else None, **kw)
    return _made[key]


CREAM = ("cream", "#efe6d3", "#fbf7ee", dict(streak=0.5))
CREAM2 = ("cream2", "#d8cbb2", "#eadfca", {})
SLATE = ("slate", "#3b4a63", "#56678a", {})
NAVY = ("navy", "#1b2638", "#28374f", {})
WOOD = ("wood", "#8a5a33", "#b27b47", dict(streak=0.55))
WOOD2 = ("wood2", "#5e3b20", "#7b5231", dict(streak=0.55))
BLUEBOOK = ("bluebook", "#2b5e9a", "#4f86c4", {})
NAVYBOOK = ("navybook", "#1b3f6b", "#2e5b92", {})
TEAL = ("teal", "#2a6f6b", "#4c9a91", {})
TEAL2 = ("teal2", "#1d4f50", "#2f6e6b", {})
ORANGE = ("orange", "#e98b3a", "#f6b872", dict(streak=0.5))
MIST = ("mist", "#7d8aa0", "#9aa6ba", {})
TAN = ("tan", "#cdb48d", "#e0cfb0", {})
PALEBLUE = ("paleblue", "#cfe5f8", "#eef7fe", {})
BLUE = ("blue", "#59d3ff", "#b5ecff", dict(streak=0.35))

# every material in the previous file -> its painted replacement
BASE = {
    "Paper_White": CREAM,
    "Paper_Black": ("ink", "#0e1522", "#1a2436", dict(streak=0.2)),
    "Paper_BlackCard": ("page", "#0a1120", "#1b2c4a", dict(streak=0.7, tex=0.14, fiber=0.12, speck=0.05)),
    "Paper_Charcoal_Back": ("floorback", "#111a2a", "#1a2740", dict(streak=0.45, tex=0.25)),
    "Paper_Charcoal_Front": ("floorfront", "#0a111d", "#141f33", dict(streak=0.45, tex=0.25)),
    "Paper_Blue": BLUE,
    "Paper_Grey": ("dim", "#5b6b82", "#71819a", {}),
    "Paper_b9b9b6": ("creamtorso", "#e3d7c1", "#f3ebdc", {}),
    "Paper_7c7c80": MIST,
    "Paper_2e2e32": NAVY,
    "Paper_1d1d21": ("backshelf", "#1a2436", "#26334a", {}),
    "Paper_3a3a3f": WOOD2,
    "Paper_141416": ("cells", "#141a22", "#1e2733", {}),
    "Paper_4a4a4f": NAVYBOOK,
    "Paper_55555a": TEAL2,
    "Paper_6a6a70": TEAL,
    "Paper_8e8e92": WOOD,
    "Paper_9a9a9e": ORANGE,
    "Paper_1b1b1f": ("hillsfar", "#1f3a62", "#2f5184", dict(streak=0.5, tex=0.4)),
    "Paper_26262b": ("hillsmid", "#182f52", "#244270", dict(streak=0.5, tex=0.4)),
    "Paper_34343a": ("fields", "#2d4f7c", "#3f669c", {}),
    "Paper_3a3a40": ("moon", "#f3d6ab", "#fbe9cf", dict(emit=0.6)),
    "Paper_2e2e33": WOOD2,
    "Paper_26262a": TEAL,
}

# pieces that shared a grey with something else get their own colour: (old material, name contains, new)
OVERRIDES = [
    ("Paper_7c7c80", "_Lines", SLATE), ("Paper_7c7c80", "_PageL", SLATE), ("Paper_7c7c80", "Crease", SLATE),
    ("Paper_7c7c80", "_f", CREAM2),                         # far-side limbs and the hawk's far wing
    ("Paper_2e2e32", "_Binders", WOOD), ("Paper_2e2e32", "_Hair", CREAM2),
    ("Paper_2e2e32", "_Title", SLATE), ("Paper_2e2e32", "_Scribble", SLATE),
    ("Paper_3a3a3f", "_ChipP", NAVY), ("Paper_3a3a3f", "E_Shelf_Binders", ORANGE),
    ("Paper_b9b9b6", "_Binders", BLUEBOOK),
    ("Paper_6a6a70", "B_Stacks", ("stacks", "#8f9bb3", "#aab4c8", {})),
    ("Paper_8e8e92", "A_Mid3_TagP", TAN), ("Paper_8e8e92", "_TagP", CREAM2), ("Paper_8e8e92", "_Small", MIST),
    ("Paper_White", "E_AnsP", PALEBLUE),
]

# caption words cut from blue paper (object names from the caption builder: Cap<i>_<segment>_<word>)
EMPHASIS = ["Cap00_1_6", "Cap01_0_1", "Cap02_1_0", "Cap02_1_1", "Cap02_1_2", "Cap03_0_2", "Cap03_0_3",
            "Cap04_1_2", "Cap04_1_3", "Cap04_1_4", "Cap05_1_0", "Cap05_1_1", "Cap06_0_4", "Cap07_0_2",
            "Cap07_0_3", "Cap07_0_4", "Cap08_1_2", "Cap08_1_3", "Cap08_1_4", "Cap09_2_4", "Cap09_2_5",
            "Cap10_1_3", "Cap10_1_4"]
CAPTION_DROP = 0.72          # 16:9 is taller: lower the captions into the bottom band


def mat_of(spec):
    key, hexs, tint, kw = spec
    return paint(key, hexs, tint, **kw)


def fix_fonts():
    """The file was first saved elsewhere, so its relative font paths broke when copied: point every font
    back at the app's font files and pack them into the .blend so the copy is self-contained."""
    for f in bpy.data.fonts:
        if f.filepath == "<builtin>":
            continue
        base = os.path.basename(bpy.path.abspath(f.filepath))
        path = os.path.join(paperlib.FONT_DIR, base)
        if os.path.exists(path):
            f.filepath = path
            if f.packed_file is None:
                f.pack()


def main():
    fix_fonts()
    if "--fonts-only" in sys.argv:
        bpy.ops.wm.save_mainfile()
        print("FONTS fixed:", [(f.name, bool(f.packed_file)) for f in bpy.data.fonts])
        return
    paperlib._mats.clear()
    old = {m.name: m for m in bpy.data.materials}
    n_over = 0
    for ob in bpy.data.objects:
        for slot in ob.material_slots:
            if slot.material is None:
                continue
            for oname, pat, spec in OVERRIDES:
                if slot.material.name == oname and pat in ob.name:
                    slot.material = mat_of(spec)
                    n_over += 1
                    break
    n_remap = 0
    for oname, spec in BASE.items():
        if oname in old:
            old[oname].user_remap(mat_of(spec))
            n_remap += 1
    if "Paper_Tracing" in old:
        old["Paper_Tracing"].user_remap(paper_mat("Paint_tracing", (0.66, 0.72, 0.80), alpha=0.05, fiber=0.03,
                                                  mottle=0.03, streak=0.1))
    blue = mat_of(BLUE)
    missing = []
    for name in EMPHASIS:
        ob = bpy.data.objects.get(name)
        if ob is None:
            missing.append(name)
            continue
        ob.data.materials[0] = blue
    scene = bpy.context.scene
    portrait = bool(scene.get("portrait"))            # the 9:16 build already places its captions
    moved = 0
    for ob in bpy.data.objects if not portrait else ():
        if ob.name.startswith("Cap") and ob.animation_data and ob.animation_data.action:
            from bpy_extras import anim_utils
            ad = ob.animation_data
            cb = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)
            for fc in cb.fcurves:
                if fc.data_path == "location" and fc.array_index == 1:
                    for kp in fc.keyframe_points:
                        kp.co.y -= CAPTION_DROP
                        kp.handle_left.y -= CAPTION_DROP
                        kp.handle_right.y -= CAPTION_DROP
                    fc.update()
                    moved += 1
    if not portrait:
        scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    w = scene.world
    if w and w.node_tree:
        bg = next((n for n in w.node_tree.nodes if n.type == "BACKGROUND"), None)
        if bg:
            bg.inputs["Color"].default_value = (0.003, 0.005, 0.012, 1)
    for scr in bpy.data.screens:
        for area in scr.areas:
            for sp in area.spaces:
                if sp.type == "VIEW_3D":
                    sp.region_3d.view_perspective = "CAMERA"
                    sp.shading.type = "RENDERED"
                    ov = sp.overlay
                    ov.show_relationship_lines = ov.show_extras = ov.show_floor = False
                    ov.show_axis_x = ov.show_axis_y = False
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    scene.frame_set(1)
    bpy.ops.wm.save_mainfile()
    print(f"TEXTURED overrides={n_over} remapped={n_remap} captions_lowered={moved} "
          f"emphasis_missing={missing} materials={len(bpy.data.materials)}")


main()
