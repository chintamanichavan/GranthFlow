"""The Anyfile app icon: every file has a face.

Three of the app's covers stand fanned on a deep blue tile: a program's byte map at the back
(computed from /bin/zsh with the app's own rule), a document page, and a cloth-bound book in front.
Text is drawn as bars, not letters, so the icon still reads at 32 pixels.

    blender -b -P design/blender_app_icon.py -- --render design/app_icon.png

Units: 1 Blender unit is 100 icon pixels. The canvas is 1024 px; the tile is 824 px, the macOS grid.
"""
import math
import os
import sys

import bmesh
import bpy

# Colours from design/blender_ui_design.py
TILE_TOP, TILE_BOTTOM = "#4654E6", "#1D2C73"
PAPER, INK, SECONDARY = "#F7F0E1", "#32291C", "#AA9C86"
CLOTH, CLOTH_INK = "#6E1E24", "#F1E4C6"
NIGHT = "#0E1330"
BYTES = ["#0E1330", "#1D2C73", "#3B49DF", "#27B5A6", "#F2C14E", "#F26A4B", "#F5F4F0"]
ACCENT_RED = "#E8553A"

CARD_W, CARD_H = 3.0, 4.2          # the app's covers are 120 x 168
TILE = 8.24


def linear(hex_colour):
    """sRGB hex to the linear RGBA Blender's shaders take."""
    h = hex_colour.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


_materials = {}


def matte(hex_colour, roughness=0.55):
    key = (hex_colour, roughness)
    if key not in _materials:
        m = bpy.data.materials.new(hex_colour)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = linear(hex_colour)
        bsdf.inputs["Roughness"].default_value = roughness
        _materials[key] = m
    return _materials[key]


def gradient_material():
    """The tile: lighter accent blue at the top falling to deep blue, lit from the top left."""
    m = bpy.data.materials.new("tile")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.35
    coords = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = linear(TILE_BOTTOM)
    ramp.color_ramp.elements[1].color = linear(TILE_TOP)
    links.new(coords.outputs["Generated"], sep.inputs[0])
    links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def superellipse(width, height, n=5.0, steps=256):
    """The macOS tile outline: a superellipse, smoother at the corners than a rounded rectangle."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = (width / 2) * math.copysign(abs(c) ** (2 / n), c)
        y = (height / 2) * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    return pts


def slab(name, outline, z, depth, material, bevel=0.02):
    """A flat shape with thickness and softened edges, its top at height z."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new((x, y, z - depth)) for x, y in outline]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z += depth
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    return obj


def rect(x, y, w, h, r=0.0):
    """A rectangle outline from its lower-left corner, with corners rounded by r."""
    if r <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for k in range(7):
            a = math.radians(a0 + k * 15)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


class Card:
    """A cover standing on the tile. Parts are drawn in the card's own coordinates, from its
    lower-left corner, and the whole card is turned and moved as one."""

    def __init__(self, name, ground, x, y, z, angle):
        self.parent = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(self.parent)
        self.parent.location = (x, y, z)
        self.parent.rotation_euler = (0, 0, math.radians(angle))
        self.z = 0.0
        body = slab(name + " body", rect(-CARD_W / 2, -CARD_H / 2, CARD_W, CARD_H, 0.12), 0.0, 0.08, matte(ground), 0.025)
        body.parent = self.parent

    def part(self, outline, colour, lift=0.004):
        shifted = [(px - CARD_W / 2, py - CARD_H / 2) for px, py in outline]
        obj = slab("part", shifted, lift, 0.004, matte(colour, 0.6), 0)
        obj.parent = self.parent
        return obj


def byte_map(path, cols, rows):
    """The app's Cover.classify, in Python: 0 empty, 4 text, 1-3, 5, 6 by rising entropy."""
    try:
        data = open(path, "rb").read()
    except OSError:
        data = bytes(range(256)) * 64
    cells = cols * rows
    block = max(1, -(-len(data) // cells))
    out = []
    for start in range(0, len(data), block):
        chunk = data[start:start + block]
        step = max(1, len(chunk) // 4096)
        sample = chunk[::step]
        n = len(sample)
        zeros = sample.count(0)
        printable = sum(1 for b in sample if 0x20 <= b < 0x7F or b in (9, 10, 13))
        if zeros * 10 >= n * 9:
            out.append(0)
            continue
        if printable * 100 >= n * 85:
            out.append(4)
            continue
        counts = {}
        for b in sample:
            counts[b] = counts.get(b, 0) + 1
        entropy = -sum(c / n * math.log2(c / n) for c in counts.values())
        entropy = min(8, entropy + (len(counts) - 1) / (2 * n * math.log(2)))
        frac = entropy / min(8, math.log2(max(n, 2)))
        out.append(1 if frac < 0.25 else 2 if frac < 0.55 else 3 if frac < 0.8 else 5 if frac < 0.95 else 6)
    return out[:cells]


def build():
    scene = bpy.context.scene
    for obj in list(scene.objects):
        bpy.data.objects.remove(obj)

    # The tile, and a shadow catcher under it so the icon keeps its soft drop shadow on transparency.
    tile = slab("tile", superellipse(TILE, TILE), 0.0, 0.3, gradient_material(), 0.06)
    catcher = slab("floor", rect(-6, -6, 12, 12), -0.6, 0.01, matte("#FFFFFF"), 0)    # low, so the shadow shows below
    catcher.is_shadow_catcher = True

    # Back: a program, its face the byte map of a real program.
    prog = Card("program", NIGHT, -1.45, 0.35, 0.5, 13)
    cols, rows = 9, 13
    cells = byte_map("/bin/zsh", cols, rows)
    inset, gap = 0.26, 0.035
    cw, ch = (CARD_W - 2 * inset) / cols, (CARD_H - 2 * inset) / rows
    for i, v in enumerate(cells):
        if v == 0:
            continue
        c, r = i % cols, i // cols
        prog.part(rect(inset + c * cw + gap / 2, CARD_H - inset - (r + 1) * ch + gap / 2, cw - gap, ch - gap, 0.02), BYTES[v])

    # Middle: a document page with a heading, lines and a small chart.
    page = Card("page", "#FFFFFF", 1.35, 0.55, 0.7, -10)
    page.part(rect(0.32, CARD_H - 0.48, 0.62, 0.09, 0.04), ACCENT_RED)
    page.part(rect(0.32, CARD_H - 0.82, 1.7, 0.16, 0.07), INK)
    for k in range(3):
        page.part(rect(0.32, CARD_H - 1.15 - k * 0.2, 2.36 if k < 2 else 1.5, 0.07, 0.035), "#D9D9DE")
    page.part(rect(0.32, 0.95, 2.36, 1.55, 0.1), "#F1F3F8")
    for k, hgt in enumerate((0.45, 0.7, 0.55, 0.95, 1.2)):
        page.part(rect(0.55 + k * 0.42, 1.12, 0.26, hgt, 0.06), "#3B49DF" if k == 4 else "#AEB8F0", 0.008)
    for k in range(2):
        page.part(rect(0.32, 0.6 - k * 0.2, 2.36 if k == 0 else 1.3, 0.07, 0.035), "#D9D9DE")

    # Front: a cloth-bound book, titled in bars, with the app's three-diamond ornament.
    book = Card("book", CLOTH, 0.0, -0.55, 0.9, -2)
    book.part(rect(0.0, 0.0, 0.16, CARD_H, 0.0), "#4E1419")                      # the shade of the spine
    frame = (0.34, 0.3, CARD_W - 0.6, CARD_H - 0.6)
    t = 0.035
    fx, fy, fw, fh = frame
    for outline in (rect(fx, fy, fw, t), rect(fx, fy + fh - t, fw, t), rect(fx, fy, t, fh), rect(fx + fw - t, fy, t, fh)):
        book.part(outline, CLOTH_INK)
    cx = CARD_W / 2 + 0.06
    book.part(rect(cx - 0.85, CARD_H - 1.05, 1.7, 0.22, 0.11), CLOTH_INK)        # title, two lines
    book.part(rect(cx - 0.6, CARD_H - 1.45, 1.2, 0.22, 0.11), CLOTH_INK)
    for k, r in enumerate((0.11, 0.19, 0.11)):
        dx = cx + (k - 1) * 0.5
        dy = CARD_H - 2.15
        book.part([(dx, dy + r * 1.4), (dx + r, dy), (dx, dy - r * 1.4), (dx - r, dy)], CLOTH_INK)
    book.part(rect(cx - 0.55, CARD_H - 2.62, 1.1, 0.03), CLOTH_INK)
    book.part(rect(cx - 0.5, 0.62, 1.0, 0.09, 0.045), CLOTH_INK)                 # the author

    # Camera straight down, orthographic, framing the 1024 px canvas.
    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 10.24
    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam

    # One large soft light from the upper left, as macOS icons are lit, and a dim fill.
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
    scene.cycles.samples = 160
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"


if __name__ == "__main__":
    build()
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--render" in args:
        out = os.path.abspath(args[args.index("--render") + 1])
        bpy.context.scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(out)[0] + ".blend")
        print("rendered", out)
