"""
Object-oriented design of `anyfile` as a UML-style class diagram, built in Blender.

Run headless and render:
    blender -b -P design/blender_oop_design.py -- --render design/oop_design.png
Open interactively:
    blender -P design/blender_oop_design.py

Options after `--`: --render <png>  --save <blend>  --size <w> <h>

Edit CLASSES and RELATIONS below to change the diagram. Each class is a panel with a coloured
header (colour = source package) and its members on the face. Relation notation follows UML:
hollow white triangle = inheritance, filled diamond at the owner = composition,
thin grey arrow = dependency (uses / creates).
"""
import math
import sys

import bpy
from mathutils import Vector

# ----------------------------------------------------------------------------- design data

PACKAGES = {
    "core": (0.25, 0.60, 0.95, 1),
    "handlers": (0.30, 0.80, 0.45, 1),
    "pdf": (0.80, 0.35, 0.75, 1),
    "epub": (0.90, 0.75, 0.20, 1),
}

# id, name, package, (x, z) centre, members (one string per line; "" = separator)
CLASSES = [
    ("iface", "FileHandler  «abstract»", "core", (-6, 16),
     ["# path_ : string", "", "+ kind() : string", "+ commands() : vector<Command>", "+ run(cmd, args, out, err) : Status"]),
    ("command", "Command", "core", (-16, 16), ["+ name", "+ usage", "+ help"]),
    ("status", "Status  «enum»", "core", (4, 16), ["Ok  Error", "BadUsage  Unknown"]),
    ("factory", "makeHandler()  «factory»", "core", (-16, 10),
     ["magic bytes → pdf, epub", "extension → markdown", "printable → text", "else → binary"]),

    ("byte", "ByteHandler", "handlers", (-6, 10),
     ["# data_ : string", "# loaded_ : bool", "", "+ run() : Status", "# load() / store()", "# describe(out)"]),
    ("text", "TextHandler", "handlers", (-13, 3),
     ["# lines_ : vector<string>", "# newline_ : string", "", "+ run() : Status", "# loadLines() / storeLines()"]),
    ("md", "MarkdownHandler", "handlers", (-13, -4),
     ["+ run() : Status", "- headings()", "- sectionRange(title)", "- renderInline(s)"]),
    ("pdfh", "PdfHandler", "handlers", (0, 3),
     ["- doc_ : unique_ptr<Document>", "", "+ run() : Status", "- open() / commit()", "- outputPath(args)"]),

    ("document", "Document", "pdf", (10, 3),
     ["- data_ : string", "- xref_ : map<int, XrefEntry>", "- cache_ : map<int, ObjPtr>", "- trailer_ : ObjPtr", "- updates_ : vector<Update>", "",
      "+ load(path) / save(path)", "+ object(num) / resolve(obj)", "+ pages() : vector<PageInfo>", "+ streamData(stream)", "+ allocateObject() / setObject()"]),
    ("object", "Object", "pdf", (20, 10),
     ["+ type : Type", "+ number / str / raw", "+ array : vector<ObjPtr>", "+ dict : map<string, ObjPtr>", "+ ref : Ref", "", "+ get(key) : ObjPtr", "+ has(key) : bool"]),
    ("parser", "Parser", "pdf", (10, -5),
     ["- lex_ : Lexer", "- resolver_ : Resolver", "", "+ parse() : ObjPtr", "+ parseIndirect(num, gen, out)"]),
    ("lexer", "Lexer", "pdf", (20, -5),
     ["- d_ : string_view", "- p_ : size_t", "", "+ next() / peek() : Token", "+ seek(pos)"]),
    ("pageinfo", "PageInfo", "pdf", (0, -5),
     ["+ ref : Ref", "+ dict / resources / mediaBox"]),
    ("font", "FontDecoder", "pdf", (20, 3),
     ["+ codeBytes : int", "+ toUnicode : map<int, string>", "+ encoding : string", "", "+ decode(bytes) : string"]),
    ("textfn", "text.cpp  «algorithms»", "pdf", (10, -11),
     ["extractPageText(doc, page)", "replaceTextOnPage(doc, page, …)", "buildFontDecoder(doc, font)"]),

    ("epubh", "EpubHandler", "handlers", (-6.5, -19),
     ["- book_ : unique_ptr<Book>", "", "+ run() : Status", "- open() / commit()"]),
    ("book", "Book", "epub", (3, -19),
     ["- zip_ : Archive", "- opf_ : string", "- chapters_ : vector<Chapter>", "",
      "+ load(bytes) / serialize()", "+ chapterText(i) / chapterTitle(i)", "+ setMeta(key, value)", "+ replaceText(i, from, to, all)"]),
    ("archive", "Archive  «zip»", "epub", (13, -19),
     ["- data_ : string", "- entries_ : vector<Entry>", "", "+ load(bytes) / serialize()", "+ read(name) / put(name, content)"]),
    ("xmlr", "xml::Reader", "epub", (3, -27),
     ["- s_ : string", "- pos_ : size_t", "", "+ next(Token) : bool", "decodeEntities() / escape()"]),
]

# (from, to, kind, label)  kinds: inherit | compose | use
RELATIONS = [
    ("byte", "iface", "inherit", ""),
    ("text", "byte", "inherit", ""),
    ("md", "text", "inherit", ""),
    ("pdfh", "byte", "inherit", ""),
    ("epubh", "byte", "inherit", ""),
    ("epubh", "book", "compose", ""),
    ("book", "archive", "compose", ""),
    ("book", "xmlr", "use", "tokens"),
    ("iface", "command", "use", "describes"),
    ("iface", "status", "use", "returns"),
    ("factory", "iface", "use", "creates"),
    ("pdfh", "document", "compose", ""),
    ("document", "object", "compose", "cache, trailer"),
    ("document", "parser", "use", "creates"),
    ("document", "pageinfo", "use", "builds"),
    ("parser", "lexer", "compose", ""),
    ("parser", "object", "use", "creates"),
    ("object", "object", "self", "children"),
    ("textfn", "document", "use", ""),
    ("textfn", "parser", "use", "content ops"),
    ("textfn", "font", "use", "builds"),
    ("font", "document", "use", ""),
]

BOX_W = 7.2
BOX_D = 0.45
HEADER_H = 0.9
LINE_H = 0.52
PAD = 0.35

# ----------------------------------------------------------------------------- helpers


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"render": None, "save": None, "size": (2200, 1400)}
    i = 0
    while i < len(argv):
        if argv[i] == "--render" and i + 1 < len(argv):
            opts["render"] = argv[i + 1]; i += 2
        elif argv[i] == "--save" and i + 1 < len(argv):
            opts["save"] = argv[i + 1]; i += 2
        elif argv[i] == "--size" and i + 2 < len(argv):
            opts["size"] = (int(argv[i + 1]), int(argv[i + 2])); i += 3
        else:
            i += 1
    return opts


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


_materials = {}


def material(name, rgba):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (rgba[0], rgba[1], rgba[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.5
    _materials[name] = mat
    return mat


def add_box(name, center, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.data.materials.append(mat)
    return obj


def add_text(name, body, location, size, mat, align="LEFT"):
    curve = bpy.data.curves.new(name, type="FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.align_y = "TOP"
    curve.extrude = 0.004
    obj = bpy.data.objects.new(name, curve)
    obj.location = location
    obj.rotation_euler = (math.radians(90), 0, 0)   # stand upright, face -Y (the camera)
    bpy.context.scene.collection.objects.link(obj)
    curve.materials.append(mat)
    return obj


def add_line(name, start, end, radius, mat):
    start, end = Vector(start), Vector(end)
    d = end - start
    if d.length < 1e-6:
        return None
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=d.length, location=(start + end) / 2)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")
    obj.data.materials.append(mat)
    return obj


def add_cone(name, tip, direction, length, radius, mat):
    direction = Vector(direction).normalized()
    bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0, depth=length, location=Vector(tip) - direction * (length / 2))
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.data.materials.append(mat)
    return obj


def add_diamond(name, center, direction, size, mat):
    direction = Vector(direction).normalized()
    bpy.ops.mesh.primitive_cube_add(size=size, location=Vector(center) + direction * (size * 0.7))
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.rotation_mode = "XYZ"
    obj.rotation_euler.rotate_axis("Z", math.radians(45))
    obj.scale = (0.7, 0.7, 1.4)
    obj.data.materials.append(mat)
    return obj


# ----------------------------------------------------------------------------- scene


def build():
    clear_scene()
    scene = bpy.context.scene
    body_mat = material("Body", (0.96, 0.96, 0.97, 1))
    text_mat = material("Text", (0.08, 0.08, 0.1, 1))
    header_text_mat = material("HeaderText", (1, 1, 1, 1))
    line_mat = material("Line", (0.2, 0.2, 0.24, 1))
    use_mat = material("Use", (0.45, 0.45, 0.5, 1))
    inherit_head = material("InheritHead", (1, 1, 1, 1))
    label_mat = material("Label", (0.35, 0.35, 0.4, 1))
    board_mat = material("Board", (0.16, 0.17, 0.2, 1))

    boxes = {}
    for cid, name, pkg, (x, z), members in CLASSES:
        body_h = PAD + len(members) * LINE_H + PAD
        total_h = HEADER_H + body_h
        top = z + total_h / 2
        # header band
        add_box("hdr_" + cid, (x, 0, top - HEADER_H / 2), (BOX_W, BOX_D, HEADER_H), material("Pkg_" + pkg, PACKAGES[pkg]))
        # body
        add_box("body_" + cid, (x, 0, top - HEADER_H - body_h / 2), (BOX_W, BOX_D * 0.9, body_h), body_mat)
        add_text("hname_" + cid, name, (x, -BOX_D / 2 - 0.01, top - 0.22), 0.46, header_text_mat, align="CENTER")
        add_text("members_" + cid, "\n".join(m if m else " " for m in members),
                 (x - BOX_W / 2 + 0.3, -BOX_D * 0.45 - 0.01, top - HEADER_H - PAD + 0.05), 0.36, text_mat)
        boxes[cid] = {"x": x, "top": top, "bottom": top - total_h, "left": x - BOX_W / 2, "right": x + BOX_W / 2,
                      "cy": top - total_h / 2}

    def anchor(a, b):
        """Pick start/end points on the box borders facing each other."""
        dx = b["x"] - a["x"]
        dz = b["cy"] - a["cy"]
        if abs(dz) * 1.2 > abs(dx):
            # Spread vertical arrows along the facing edge so several children do not share one tip.
            ax = min(max(b["x"], a["left"] + 1.2), a["right"] - 1.2)
            bx = min(max(a["x"], b["left"] + 1.2), b["right"] - 1.2)
            if dz > 0:
                return Vector((ax, 0, a["top"])), Vector((bx, 0, b["bottom"]))
            return Vector((ax, 0, a["bottom"])), Vector((bx, 0, b["top"]))
        if dx > 0:
            return Vector((a["right"], 0, a["cy"])), Vector((b["left"], 0, b["cy"]))
        return Vector((a["left"], 0, a["cy"])), Vector((b["right"], 0, b["cy"]))

    for i, (src, dst, kind, label) in enumerate(RELATIONS):
        tag = "rel_%02d_%s_%s" % (i, src, dst)
        if kind == "self":
            b = boxes[src]
            p1 = Vector((b["right"], 0, b["cy"] + 0.6))
            p2 = p1 + Vector((1.2, 0, 0))
            p3 = p2 + Vector((0, 0, -1.2))
            p4 = Vector((b["right"], 0, b["cy"] - 0.6))
            add_line(tag + "a", p1, p2, 0.035, use_mat)
            add_line(tag + "b", p2, p3, 0.035, use_mat)
            add_line(tag + "c", p3, p4, 0.035, use_mat)
            add_cone(tag + "h", p4, p4 - p3, 0.35, 0.14, use_mat)
            add_text(tag + "l", label, (p2.x + 0.15, -0.01, p2.z + 0.1), 0.3, label_mat)
            continue
        start, end = anchor(boxes[src], boxes[dst])
        direction = (end - start).normalized()
        if kind == "inherit":
            add_line(tag, start, end - direction * 0.55, 0.045, line_mat)
            add_cone(tag + "h", end, direction, 0.6, 0.32, inherit_head)
        elif kind == "compose":
            add_diamond(tag + "d", start, direction, 0.32, line_mat)
            add_line(tag, start + direction * 0.4, end - direction * 0.35, 0.045, line_mat)
            add_cone(tag + "h", end, direction, 0.4, 0.15, line_mat)
        else:
            add_line(tag, start, end - direction * 0.35, 0.03, use_mat)
            add_cone(tag + "h", end, direction, 0.4, 0.15, use_mat)
        if label:
            mid = (start + end) / 2
            add_text(tag + "l", label, (mid.x + 0.2, -0.01, mid.z + 0.35), 0.3, label_mat)

    # Backboard, title and legend.
    xs = [b["left"] for b in boxes.values()] + [b["right"] for b in boxes.values()]
    zs = [b["bottom"] for b in boxes.values()] + [b["top"] for b in boxes.values()]
    minx, maxx, minz, maxz = min(xs) - 2, max(xs) + 2, min(zs) - 2.5, max(zs) + 3.5
    add_box("board", ((minx + maxx) / 2, 0.6, (minz + maxz) / 2), (maxx - minx, 0.2, maxz - minz), board_mat)
    add_text("title", "anyfile  -  object-oriented design", (minx + 0.8, -0.01, maxz - 0.5), 1.0, header_text_mat)
    add_text("legend", "white triangle = inherits      diamond = owns (composition)      grey arrow = uses / creates      "
             "blue = core   green = handlers   magenta = pdf engine   yellow = epub engine",
             (minx + 0.8, -0.01, minz + 1.3), 0.36, label_mat)

    # Orthographic camera, straight on with a slight tilt so the panels read as solid.
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(maxx - minx, (maxz - minz) * (2200 / 1400)) * 1.02
    cam = bpy.data.objects.new("Camera", cam_data)
    cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
    cam.location = (cx - 3.0, -60.0, cz + 4.0)
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector((cx, 0, cz)) - Vector(cam.location)).to_track_quat("-Z", "Y")
    scene.collection.objects.link(cam)
    scene.camera = cam

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(60), math.radians(10), math.radians(25))
    scene.collection.objects.link(sun)
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    if hasattr(world, "use_nodes"):
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background") if world.node_tree else None
    if bg is not None:
        bg.inputs[0].default_value = (0.10, 0.11, 0.14, 1.0)


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
    build()
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = opts["size"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "FLAT"
    shading.color_type = "MATERIAL"
    shading.show_cavity = True
    shading.cavity_type = "SCREEN"
    shading.show_shadows = False
    if opts["save"]:
        frame_viewports_on_camera()
        bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(opts["save"]))
        print("saved", opts["save"])
    if opts["render"]:
        scene.render.filepath = bpy.path.abspath(opts["render"])
        bpy.ops.render.render(write_still=True)
        print("rendered", opts["render"])


if __name__ == "__main__":
    main()
