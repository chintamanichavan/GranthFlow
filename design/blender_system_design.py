"""
Engineering system design of `anyfile`, built as a 3D diagram in Blender.

Run headless (no UI) and render a PNG:
    blender -b -P design/blender_system_design.py -- --render design/system_design.png

Open interactively to orbit around it:
    blender -P design/blender_system_design.py

Options after `--`:
    --render <file.png>    render to this file and exit
    --save <file.blend>    save the scene to a .blend file
    --engine <name>        WORKBENCH (default, fast), BLENDER_EEVEE_NEXT, BLENDER_EEVEE or CYCLES
    --size <w> <h>         render resolution (default 1920 1080)

The diagram is data-driven: edit LAYERS, COMPONENTS and EDGES below to change the design.
Each component is a labelled block sitting on a translucent slab for its layer; arrows show
"depends on / calls" relationships flowing downward through the layers.
"""
import math
import sys

import bpy
from mathutils import Vector

# ----------------------------------------------------------------------------- design data

# Layers from top (user-facing) to bottom (external). z is the slab height, color is RGBA.
LAYERS = [
    {"id": "cli", "title": "CLI  (src/main.cpp)", "z": 17.5, "color": (0.95, 0.55, 0.20, 1)},
    {"id": "core", "title": "Core  (src/core)", "z": 14.0, "color": (0.25, 0.60, 0.95, 1)},
    {"id": "handlers", "title": "Handlers  (src/handlers)", "z": 10.5, "color": (0.30, 0.80, 0.45, 1)},
    {"id": "pdf", "title": "PDF engine  (src/pdf)", "z": 7.0, "color": (0.80, 0.35, 0.75, 1)},
    {"id": "epub", "title": "EPUB engine  (src/epub)", "z": 3.5, "color": (0.90, 0.75, 0.20, 1)},
    {"id": "ext", "title": "External", "z": 0.0, "color": (0.55, 0.55, 0.60, 1)},
]

# id, label, layer, (x, y) position on that layer's slab, optional size (w, d)
COMPONENTS = [
    ("main", "main\nargv -> file, cmd, args", "cli", (0, 0), (5.0, 2.2)),

    ("registry", "Registry\nmagic bytes + extension", "core", (-5.5, 0), (4.2, 2.0)),
    ("iface", "FileHandler\ncommands() / run()", "core", (0, 0), (4.2, 2.0)),
    ("util", "util\nread/atomic write, hex,\nline split, escapes", "core", (5.5, 0), (4.2, 2.0)),

    ("byte", "ByteHandler\ninfo hex strings patch", "handlers", (-8.6, 0), (3.8, 2.0)),
    ("text", "TextHandler\nshow grep replace\ninsert delete", "handlers", (-4.3, 0), (3.8, 2.0)),
    ("md", "MarkdownHandler\noutline section toc\nrender", "handlers", (0, 0), (3.8, 2.0)),
    ("pdfh", "PdfHandler\ntext meta set-meta\nadd-page replace", "handlers", (4.3, 0), (3.8, 2.0)),
    ("epubh", "EpubHandler\ntext chapters meta\nset-meta replace", "handlers", (8.6, 0), (3.8, 2.0)),

    ("lexer", "Lexer\ntokens", "pdf", (-8.0, 1.5), (3.2, 1.8)),
    ("parser", "Parser\nobjects, refs,\nstreams", "pdf", (-4.0, 1.5), (3.2, 1.8)),
    ("object", "Object model\n+ serialize()", "pdf", (0, 1.5), (3.2, 1.8)),
    ("filters", "Filters\nFlate, A85, AHx,\nPNG predictors", "pdf", (4.0, 1.5), (3.2, 1.8)),
    ("document", "Document\nxref tables/streams,\nObjStm, page tree,\nincremental save", "pdf", (-2.0, -2.0), (4.6, 2.0)),
    ("textx", "Text extractor\ncontent interpreter,\nToUnicode CMaps", "pdf", (3.5, -2.0), (4.2, 2.0)),

    ("archive", "Archive (zip)\nstored + deflate,\ncopy-through save", "epub", (8.2, 0), (4.2, 2.0)),
    ("xmlr", "XML Reader\ntokens with\nbyte offsets", "epub", (-3.5, 0), (3.6, 2.0)),
    ("book", "Book\npackage, spine,\nchapter text, edits", "epub", (2.5, 0), (4.2, 2.0)),

    ("zlib", "zlib", "ext", (3.0, 0), (2.6, 1.6)),
    ("fs", "filesystem\n(the file on disk)", "ext", (-3.0, 0), (3.4, 1.6)),
]

# (from, to, label)  -- "from" uses "to"
EDGES = [
    ("main", "registry", "detect type"),
    ("main", "iface", "run(cmd)"),
    ("registry", "byte", ""), ("registry", "text", ""), ("registry", "md", ""), ("registry", "pdfh", ""), ("registry", "epubh", ""),
    ("text", "byte", "inherits"), ("md", "text", "inherits"), ("pdfh", "byte", "inherits"), ("epubh", "byte", "inherits"),
    ("byte", "util", ""), ("text", "util", ""), ("md", "util", ""),
    ("pdfh", "document", "load/save"), ("pdfh", "textx", "extract/replace"),
    ("document", "parser", ""), ("document", "filters", ""), ("document", "object", ""),
    ("parser", "lexer", ""), ("parser", "object", ""),
    ("textx", "document", "pages, streams"), ("textx", "parser", "content ops"),
    ("epubh", "book", "load/save"), ("book", "archive", "entries"), ("book", "xmlr", "parse, splice"),
    ("filters", "zlib", "inflate/deflate"), ("archive", "zlib", "inflate/deflate"),
    ("util", "fs", "read / atomic write"), ("document", "fs", "append update"),
]

BLOCK_HEIGHT = 1.0
SLAB_THICKNESS = 0.18
SLAB_SIZE = (22.0, 8.0)

# ----------------------------------------------------------------------------- helpers


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"render": None, "save": None, "engine": "WORKBENCH", "size": (1920, 1080)}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--render" and i + 1 < len(argv):
            opts["render"] = argv[i + 1]; i += 2
        elif a == "--save" and i + 1 < len(argv):
            opts["save"] = argv[i + 1]; i += 2
        elif a == "--engine" and i + 1 < len(argv):
            opts["engine"] = argv[i + 1]; i += 2
        elif a == "--size" and i + 2 < len(argv):
            opts["size"] = (int(argv[i + 1]), int(argv[i + 2])); i += 3
        else:
            i += 1
    return opts


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


_materials = {}


def material(name, rgba, alpha=1.0, emission=0.0):
    key = (name, rgba, alpha, emission)
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (rgba[0], rgba[1], rgba[2], alpha)   # used by Workbench
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (rgba[0], rgba[1], rgba[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.45
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emission > 0 and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (rgba[0], rgba[1], rgba[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
    if alpha < 1.0:
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    _materials[key] = mat
    return mat


def add_box(name, center, size, mat, bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.use_clamp_overlap = True
    return obj


def add_label(name, text, location, size=0.42, rotation=(math.radians(90), 0, 0), mat=None, align="CENTER", extrude=0.0):
    curve = bpy.data.curves.new(name, type="FONT")
    curve.body = text
    curve.size = size
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.extrude = extrude
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.scene.collection.objects.link(obj)
    if mat is not None:
        curve.materials.append(mat)
    return obj


def add_arrow(name, start, end, mat, radius=0.05):
    start, end = Vector(start), Vector(end)
    direction = end - start
    length = direction.length
    if length < 1e-6:
        return None
    head_len = min(0.45, length * 0.3)
    shaft_len = length - head_len
    axis = direction.normalized()
    quat = axis.to_track_quat("Z", "Y")

    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=shaft_len, location=start + axis * (shaft_len / 2))
    shaft = bpy.context.active_object
    shaft.name = name + "_shaft"
    shaft.rotation_mode = "QUATERNION"
    shaft.rotation_quaternion = quat
    shaft.data.materials.append(mat)

    bpy.ops.mesh.primitive_cone_add(radius1=radius * 3.2, radius2=0, depth=head_len, location=start + axis * (shaft_len + head_len / 2))
    head = bpy.context.active_object
    head.name = name + "_head"
    head.rotation_mode = "QUATERNION"
    head.rotation_quaternion = quat
    head.data.materials.append(mat)
    return shaft, head


# ----------------------------------------------------------------------------- scene


def build():
    clear_scene()
    scene = bpy.context.scene
    layer_by_id = {layer["id"]: layer for layer in LAYERS}
    text_mat = material("Label", (0.08, 0.08, 0.1, 1))
    slab_label_mat = material("SlabLabel", (0.95, 0.95, 0.97, 1), emission=0.4)
    arrow_mat = material("Arrow", (0.15, 0.15, 0.18, 1))
    inherit_mat = material("ArrowInherit", (0.85, 0.25, 0.25, 1))

    # Slabs with their titles along the front edge.
    for layer in LAYERS:
        z = layer["z"]
        add_box("slab_" + layer["id"], (0, 0, z - SLAB_THICKNESS / 2), (SLAB_SIZE[0], SLAB_SIZE[1], SLAB_THICKNESS),
                material("Slab_" + layer["id"], layer["color"], alpha=0.16), bevel=0.0)
        add_label("slabtitle_" + layer["id"], layer["title"], (-SLAB_SIZE[0] / 2 + 0.2, -SLAB_SIZE[1] / 2 - 0.05, z + 0.45),
                  size=0.6, mat=slab_label_mat, align="LEFT", extrude=0.02)

    # Component blocks and their anchor points for arrows.
    anchors = {}
    for comp_id, label, layer_id, (x, y), size in COMPONENTS:
        layer = layer_by_id[layer_id]
        z = layer["z"]
        center = (x, y, z + BLOCK_HEIGHT / 2)
        add_box("block_" + comp_id, center, (size[0], size[1], BLOCK_HEIGHT), material("Block_" + layer_id, layer["color"]))
        lines = label.count("\n") + 1
        add_label("label_" + comp_id, label, (x, y - size[1] / 2 - 0.02, z + BLOCK_HEIGHT / 2),
                  size=0.30 if lines <= 2 else 0.26, mat=text_mat, extrude=0.005)
        anchors[comp_id] = {
            "top": Vector((x, y, z + BLOCK_HEIGHT)),
            "bottom": Vector((x, y, z)),
            "left": Vector((x - size[0] / 2, y, z + BLOCK_HEIGHT / 2)),
            "right": Vector((x + size[0] / 2, y, z + BLOCK_HEIGHT / 2)),
            "layer": layer_id,
        }

    # Arrows: downward between layers, sideways within a layer.
    for i, (src, dst, label) in enumerate(EDGES):
        a, b = anchors[src], anchors[dst]
        inherit = label == "inherits"
        if a["layer"] == b["layer"]:
            start, end = (a["left"], b["right"]) if a["top"].x > b["top"].x else (a["right"], b["left"])
            start = start + Vector((0, 0, 0.25 if inherit else -0.25))
            end = end + Vector((0, 0, 0.25 if inherit else -0.25))
        else:
            start, end = a["bottom"], b["top"]
            if start.z < end.z:
                start, end = a["top"], b["bottom"]
        add_arrow("edge_%02d_%s_%s" % (i, src, dst), start, end, inherit_mat if inherit else arrow_mat)
        if label and not inherit:
            mid = (start + end) / 2
            add_label("edgelabel_%02d" % i, label, (mid.x + 0.15, mid.y - 0.05, mid.z), size=0.22, mat=text_mat, align="LEFT")

    # Title card.
    add_label("title", "anyfile  -  system design", (-SLAB_SIZE[0] / 2 + 0.2, -SLAB_SIZE[1] / 2 - 0.05, LAYERS[0]["z"] + 3.2),
              size=1.1, mat=slab_label_mat, align="LEFT", extrude=0.03)
    add_label("subtitle", "C++20 file reader / editor for PDF, EPUB, Markdown, text and binary files\n"
              "arrows point from a module to the module it depends on; red arrows mark inheritance",
              (-SLAB_SIZE[0] / 2 + 0.2, -SLAB_SIZE[1] / 2 - 0.05, LAYERS[0]["z"] + 2.2),
              size=0.42, mat=slab_label_mat, align="LEFT")

    # Camera: elevated three-quarter view looking at the middle of the stack.
    mid_z = (LAYERS[0]["z"] + LAYERS[-1]["z"]) / 2
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 36
    cam = bpy.data.objects.new("Camera", cam_data)
    cam.location = (-14.0, -40.0, mid_z + 15.0)
    scene.collection.objects.link(cam)
    target = Vector((0.0, 0.5, mid_z - 0.3))
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (target - Vector(cam.location)).to_track_quat("-Z", "Y")
    scene.camera = cam

    # Lights.
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.location = (6, -10, 25)
    sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(20))
    scene.collection.objects.link(sun)
    fill_data = bpy.data.lights.new("Fill", type="AREA")
    fill_data.energy = 800
    fill_data.size = 12
    fill = bpy.data.objects.new("Fill", fill_data)
    fill.location = (-12, -6, 14)
    fill.rotation_euler = (math.radians(55), 0, math.radians(-40))
    scene.collection.objects.link(fill)

    # World background.
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    if hasattr(world, "use_nodes"):
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background") if world.node_tree else None
    if bg is not None:
        bg.inputs[0].default_value = (0.10, 0.11, 0.14, 1.0)
        bg.inputs[1].default_value = 1.0


def configure_render(opts):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = opts["size"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    engine = opts["engine"]
    try:
        scene.render.engine = engine
    except TypeError:
        if engine.startswith("BLENDER_EEVEE"):
            # Blender 4.2 renamed Eevee; try the other spelling, then fall back to Workbench.
            try:
                scene.render.engine = "BLENDER_EEVEE" if engine == "BLENDER_EEVEE_NEXT" else "BLENDER_EEVEE_NEXT"
            except TypeError:
                scene.render.engine = "BLENDER_WORKBENCH"
        else:
            scene.render.engine = "BLENDER_WORKBENCH"
    if scene.render.engine == "BLENDER_WORKBENCH":
        shading = scene.display.shading
        shading.light = "STUDIO"
        shading.color_type = "MATERIAL"
        shading.show_cavity = True
        shading.show_shadows = True
        shading.show_xray = False
    elif scene.render.engine == "CYCLES":
        scene.cycles.samples = 128


def frame_viewports_on_camera():
    """Make every 3D viewport in the saved file open looking through the camera with material colours."""
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                space.region_3d.view_perspective = "CAMERA"
                space.shading.type = "SOLID"
                space.shading.color_type = "MATERIAL"
                space.shading.light = "FLAT"
                space.shading.show_cavity = True
                space.overlay.show_floor = False
                space.overlay.show_axis_x = False
                space.overlay.show_axis_y = False
                space.overlay.show_relationship_lines = False


def main():
    opts = parse_args()
    if opts["engine"] == "WORKBENCH":
        opts["engine"] = "BLENDER_WORKBENCH"
    build()
    configure_render(opts)
    if opts["save"]:
        frame_viewports_on_camera()
        bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(opts["save"]))
        print("saved", opts["save"])
    if opts["render"]:
        bpy.context.scene.render.filepath = bpy.path.abspath(opts["render"])
        bpy.ops.render.render(write_still=True)
        print("rendered", opts["render"])


if __name__ == "__main__":
    main()
