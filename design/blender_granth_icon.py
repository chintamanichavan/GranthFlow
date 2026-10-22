"""The GranthFlow app icon: a granth, the traditional bound manuscript.

A pothi of long cream leaves between two teak boards rests on its opened red cloth, tied with a
cord, with ग्रंथ (Marathi: book) inlaid in gold on the top board. It sits on the app's blue tile,
tilted toward the reader so the edges of the leaves show.

    swift design/granth_lettering.swift design/granth_lettering.png    # Blender cannot shape Devanagari
    blender -b -P design/blender_granth_icon.py -- --render design/app_icon.png

Units: 1 Blender unit is 100 icon pixels. The canvas is 1024 px; the tile is 824 px, the macOS grid.
The tile, colours and shape helpers come from blender_app_icon.py, so the two icons share a ground.
"""
import math
import os
import random
import subprocess
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blender_app_icon as base  # noqa: E402  (Blender adds no path for the script's own folder)

CLOTH = "#A8232B"
CLOTH_BORDER = "#D9A441"
TEAK = "#5E3A22"
TEAK_EDGE = "#4A2C19"
LEAF = ["#F1E3C2", "#EAD9B4", "#F4E8CC", "#E6D3AA"]
GOLD = "#D9A441"
CORD = "#C8B27A"
LETTERING = os.path.join(HERE, "granth_lettering.png")

LENGTH, DEPTH = 6.2, 1.75          # a pothi is long and narrow
LEAVES, LEAF_THICK = 18, 0.045
BOARD_THICK = 0.13
TILT = 46                          # degrees toward the reader, enough to show the leaves' edges


def gold_material():
    m = bpy.data.materials.new("gold")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = base.linear(GOLD)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.32
    return m


def lettering_material():
    """Gold where the lettering is, nothing elsewhere: the image's alpha cuts the gold out. Burnished
    rather than polished, with a faint glow: polished gold reflects only the dark around the icon."""
    m = bpy.data.materials.new("lettering")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = base.linear("#E8B649")
    bsdf.inputs["Metallic"].default_value = 0.45
    bsdf.inputs["Roughness"].default_value = 0.4
    bsdf.inputs["Emission Color"].default_value = base.linear("#E8B649")
    bsdf.inputs["Emission Strength"].default_value = 0.35
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(LETTERING)
    tex.extension = "CLIP"
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return m


def box(name, w, d, h, x, y, z, material, bevel=0.02, parent=None, radius=0.0):
    """A box `w` long (x), `d` deep (y), `h` thick (z), centred on x, y, its bottom at z."""
    obj = base.slab(name, base.rect(x - w / 2, y - d / 2, w, d, radius), z + h, h, material, bevel)
    if parent:
        obj.parent = parent
    return obj


def cord(parent, x):
    """A cord wound once around the boards and leaves, its loose end trailing onto the cloth."""
    total = 2 * BOARD_THICK + LEAVES * LEAF_THICK
    half_d, r = DEPTH / 2 + 0.06, 0.035
    loop = [(x, -half_d, 0.04), (x, -half_d, total + 0.04), (x, half_d, total + 0.04), (x, half_d, 0.04)]
    tail = [(x, -half_d, 0.04), (x + 0.25, -half_d - 0.35, 0.03), (x + 0.75, -half_d - 0.55, 0.02), (x + 1.25, -half_d - 0.5, 0.02)]
    for name, pts, cyclic in (("cord loop", loop, True), ("cord tail", tail, False)):
        curve = bpy.data.curves.new(name, "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = r
        curve.bevel_resolution = 4
        spline = curve.splines.new("POLY")
        spline.points.add(len(pts) - 1)
        for p, (px, py, pz) in zip(spline.points, pts):
            p.co = (px, py, pz, 1)
        spline.use_cyclic_u = cyclic
        obj = bpy.data.objects.new(name, curve)
        obj.data.materials.append(base.matte(CORD, 0.7))
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent


def build():
    scene = bpy.context.scene
    for obj in list(scene.objects):
        bpy.data.objects.remove(obj)

    tile = base.slab("tile", base.superellipse(base.TILE, base.TILE), 0.0, 0.3, base.gradient_material(), 0.06)
    catcher = base.slab("floor", base.rect(-6, -6, 12, 12), -0.6, 0.01, base.matte("#FFFFFF"), 0)
    catcher.is_shadow_catcher = True

    # Everything on the tile turns together, tilted toward the reader and a little across.
    group = bpy.data.objects.new("granth", None)
    scene.collection.objects.link(group)
    group.location = (0, -0.3, 0.55)                        # tilting lifts the pothi; this re-centres it
    group.scale = (1.08, 1.08, 1.08)
    group.rotation_euler = (math.radians(-TILT), 0, math.radians(-7))

    # The opened cloth, a square laid as a diamond, with a gold border woven in.
    side = 5.4
    cloth = base.slab("cloth", base.rect(-side / 2, -side / 2, side, side, 0.08), 0.0, 0.025, base.matte(CLOTH, 0.85), 0.01)
    cloth.parent = group
    cloth.rotation_euler = (0, 0, math.radians(45))
    for k in range(4):
        inset, t = 0.28, 0.07
        edges = [base.rect(-side / 2 + inset, -side / 2 + inset, side - 2 * inset, t),
                 base.rect(-side / 2 + inset, side / 2 - inset - t, side - 2 * inset, t),
                 base.rect(-side / 2 + inset, -side / 2 + inset, t, side - 2 * inset),
                 base.rect(side / 2 - inset - t, -side / 2 + inset, t, side - 2 * inset)]
        stripe = base.slab("cloth border", edges[k], 0.03, 0.006, base.matte(CLOTH_BORDER, 0.6), 0)
        stripe.parent = cloth

    # The pothi: bottom board, leaves, top board.
    pothi = bpy.data.objects.new("pothi", None)
    scene.collection.objects.link(pothi)
    pothi.parent = group
    pothi.location = (0, 0, 0.03)
    box("bottom board", LENGTH + 0.2, DEPTH + 0.12, BOARD_THICK, 0, 0, 0, base.matte(TEAK, 0.45), 0.035, pothi, 0.12)
    rng = random.Random(7)                                   # the same leaves every render
    z = BOARD_THICK
    for i in range(LEAVES):
        dx, dy = rng.uniform(-0.04, 0.04), rng.uniform(-0.025, 0.025)
        box(f"leaf {i}", LENGTH - 0.05, DEPTH - 0.04, LEAF_THICK, dx, dy, z, base.matte(LEAF[i % len(LEAF)], 0.8), 0.006, pothi, 0.3)
        z += LEAF_THICK
    top = box("top board", LENGTH + 0.2, DEPTH + 0.12, BOARD_THICK, 0, 0, z, base.matte(TEAK, 0.45), 0.035, pothi, 0.12)
    top_z = z + BOARD_THICK

    # A fine gold border on the top board, and the name inlaid in gold.
    gold = gold_material()
    bw, bd, t, inset = LENGTH + 0.2 - 0.36, DEPTH + 0.12 - 0.3, 0.035, 0.0
    for outline in (base.rect(-bw / 2, -bd / 2, bw, t), base.rect(-bw / 2, bd / 2 - t, bw, t),
                    base.rect(-bw / 2, -bd / 2, t, bd), base.rect(bw / 2 - t, -bd / 2, t, bd)):
        line = base.slab("gold border", outline, top_z + 0.006, 0.006, gold, 0)
        line.parent = pothi
    h = 1.3
    w = h * 478 / 358                                        # the lettering image's own proportions
    bpy.ops.mesh.primitive_plane_add(size=1, location=(-0.95, 0, top_z + 0.008))
    plate = bpy.context.active_object
    plate.name = "lettering"
    plate.scale = (w, h, 1)
    plate.data.materials.append(lettering_material())
    plate.parent = pothi

    cord(pothi, 1.85)

    # Camera, lights and render settings as for the first icon.
    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 10.24
    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, loc, energy, size in (("key", (-3.5, 6, 14), 2000, 12), ("fill", (6, -4, 10), 350, 12)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = size
        obj = bpy.data.objects.new(name, light)
        obj.location = loc
        scene.collection.objects.link(obj)
        track = obj.constraints.new("TRACK_TO")
        track.target = tile
        track.track_axis = "TRACK_NEGATIVE_Z"
        track.up_axis = "UP_Y"
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.2
    scene.world = world

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 192
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"


if __name__ == "__main__":
    if not os.path.exists(LETTERING):
        subprocess.run(["swift", os.path.join(HERE, "granth_lettering.swift"), LETTERING], check=True)
    build()
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--render" in args:
        out = os.path.abspath(args[args.index("--render") + 1])
        bpy.context.scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(out)[0] + ".blend")
        print("rendered", out)
