"""Render the voice orb model to PNG, headless.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tool/render_orb.py -- --frames 1 --size 1024

Why offline rather than at runtime: the model is a glass shell
(KHR_materials_transmission + IOR) around an emissive plasma core. Real
refraction needs a path tracer; the Flutter-side options are a WebView running
<model-viewer> (heavy, slow to first paint, unusable on a splash) or
flutter_scene (no transmission support). Baking here gives exact fidelity at
zero runtime cost, on every device.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(ROOT, "assets", "voice_orb.glb")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--frames", type=int, default=1)
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--emission", type=float, default=1.0)
    p.add_argument("--exposure", type=float, default=-0.7)
    # The mesh pinches at its poles. Leaving them on the silhouette (tilt 0)
    # hides them behind the rim; tilting brings them onto the face, where they
    # show as small dark nicks.
    p.add_argument("--tilt", type=float, default=0.0)
    # Hero angle. 0 puts the mesh's UV seam across the face of the sphere,
    # where it shows as a faint vertical line; 45 turns it out of view.
    p.add_argument("--spin", type=float, default=45.0)
    p.add_argument("--out", default=os.path.join(ROOT, "build", "orb_render"))
    return p.parse_args(argv)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model():
    bpy.ops.import_scene.gltf(filepath=MODEL)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objects):
    """World-space centre and radius of the imported meshes."""
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo[i], world[i]) for i in range(3)))
            hi = Vector((max(hi[i], world[i]) for i in range(3)))
    centre = (lo + hi) / 2
    radius = max((hi - lo)[i] for i in range(3)) / 2
    return centre, radius


def build_camera(centre, radius):
    """Orthographic, straight on.

    Orthographic because the mark has to sit inside a circle at any size — a
    perspective lens would foreshorten the sphere's silhouette differently at
    each render size and the icon would stop matching the in-app orb.
    """
    data = bpy.data.cameras.new("Cam")
    data.type = "ORTHO"
    # A little air around the sphere so the glass rim is not clipped.
    data.ortho_scale = radius * 2.12
    cam = bpy.data.objects.new("Cam", data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = centre + Vector((0, -radius * 8, 0))
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.camera = cam
    return cam


def tune_materials(emission):
    """The glTF ships the plasma at emission strength 1.0.

    That is correct for a viewer with a neutral tone map, but here it renders
    as a grey disc: the core has to out-run the studio lights for the orb to
    read as lit from within rather than lit from outside.
    """
    for material in bpy.data.materials:
        if not material.use_nodes:
            continue
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            if node.inputs["Emission Color"].is_linked:
                node.inputs["Emission Strength"].default_value = emission
                print(f"[orb] {material.name}: emission -> {emission}")
            if node.inputs["Transmission Weight"].default_value > 0:
                # Polished glass. A rough shell scatters the core into haze.
                node.inputs["Roughness"].default_value = 0.04
                print(f"[orb] {material.name}: glass roughness -> 0.04")


def build_lighting(centre, radius):
    """Studio rig.

    The plasma core lights itself, but the glass shell is only visible where it
    catches and bends something — with a black world it would vanish. A bright
    key up-left matches the design's specular highlight (CSS `radial-gradient
    at 34% 26%`), and a dim rim behind separates the silhouette from the ground.
    """
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    # Near-black world: the orb is lit from inside, and any ambient fill turns
    # the glass shell into a grey disc.
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.01, 0.02, 0.05, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    bpy.context.scene.world = world

    def area(name, loc, energy, size, rot):
        data = bpy.data.lights.new(name, type="AREA")
        # Disc, not the default square: a square source reflects as a visible
        # square patch on a polished sphere, which instantly reads as CGI.
        data.shape = "DISK"
        data.energy = energy
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = centre + Vector(loc)
        obj.rotation_euler = rot
        bpy.context.scene.collection.objects.link(obj)
        return obj

    r = radius
    # Small and bright rather than big and soft: a broad source smears into a
    # flat sheen, a tight one leaves a specular dot that reads as glass.
    area("Key", (-r * 2.6, -r * 3.2, r * 2.8), 320, r * 1.6, (math.radians(52), 0, math.radians(-40)))
    area("Rim", (r * 1.2, r * 3.8, r * 1.6), 180, r * 2.4, (math.radians(-118), 0, math.radians(18)))


def configure_render(args):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    # Refraction through the shell needs enough bounces to reach the core.
    scene.cycles.max_bounces = 12
    scene.cycles.transmission_bounces = 12
    scene.cycles.transparent_max_bounces = 12

    prefs = bpy.context.preferences.addons.get("cycles")
    if prefs is not None:
        try:
            prefs.preferences.compute_device_type = "METAL"
            prefs.preferences.get_devices()
            for device in prefs.preferences.devices:
                device.use = True
            scene.cycles.device = "GPU"
        except Exception as exc:  # noqa: BLE001 - fall back to CPU, still correct
            print(f"[orb] GPU unavailable ({exc}); rendering on CPU")

    scene.render.resolution_x = args.size
    scene.render.resolution_y = args.size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Transparent film: the orb is composited onto whatever ground the app is
    # using, so it must not carry a baked-in background.
    scene.render.film_transparent = True
    # Standard, not AgX: AgX is built to tame highlights, which is exactly
    # wrong here — it desaturates the emission and the vivid blue collapses to
    # grey. The mark's colour is authored, so it should be reproduced, not
    # re-graded.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = args.exposure


def main():
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)

    reset_scene()
    meshes = import_model()
    print(f"[orb] imported {len(meshes)} meshes: {[m.name for m in meshes]}")

    centre, radius = bounds(meshes)
    print(f"[orb] centre={tuple(round(v, 4) for v in centre)} radius={radius:.4f}")

    tune_materials(args.emission)
    build_camera(centre, radius)
    build_lighting(centre, radius)
    configure_render(args)

    # One empty at the centre, with every mesh parented to it, so a turntable
    # is a single rotation rather than N objects kept in sync.
    pivot = bpy.data.objects.new("Pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    pivot.location = centre
    for mesh in meshes:
        mesh.parent = pivot
        mesh.matrix_parent_inverse = pivot.matrix_world.inverted()

    tilt = math.radians(args.tilt)
    spin = math.radians(args.spin)
    for i in range(args.frames):
        pivot.rotation_euler = (tilt, 0, spin + 2 * math.pi * i / args.frames)
        bpy.context.scene.render.filepath = os.path.join(args.out, f"orb_{i:03d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[orb] wrote frame {i + 1}/{args.frames}")


if __name__ == "__main__":
    main()
