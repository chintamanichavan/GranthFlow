"""
UI/UX design of the Anyfile Mac app, rendered in Blender with real light and real glass.

The idea: every file has a face. A book, a document, a note and a program all live in one
library, each shown by a cover made from what is inside it. The cover is not decoration:
its colours tint the window when the file is open, and for a program the cover doubles as
the map you scroll by. Opening any file gives the same window and the same five actions.

Run headless and render:
    blender -b -P design/blender_ui_design.py -- --render design/ui_design.png
Open interactively:
    blender -P design/blender_ui_design.py

Options after `--`: --render <png>  --save <blend>  --scale <pixels per point>  --samples <n>

Everything is specified in points with y running down, as a Mac window is. Surfaces are
stacked at different heights ("lift") above the desktop, so shadows and the blur behind
glass come from the renderer, not from painted fakes.
"""
import math
import random
import sys

import bpy
from mathutils import Vector

# ----------------------------------------------------------------------------- design tokens

LIBRARY = {   # the library window: warm white, ink, one accent
    "window": "#F5F4F0", "label": "#1C1C1E", "secondary": "#6B6B70", "tertiary": "#A5A5AA",
    "accent": "#3B49DF", "hairline": "#E2E0DA",
}
NIGHT = {     # a program open: the window takes the dark ground of the file's own cover
    "window": "#0E1330", "label": "#E9EBFA", "secondary": "#8D94C4", "tertiary": "#565E96",
    "accent": "#8FA0FF", "hairline": "#252C5E",
}
PAPER = {     # the reading window: the page colour of a printed book
    "window": "#F7F0E1", "label": "#32291C", "secondary": "#7B6D58", "tertiary": "#AA9C86",
    "accent": "#3B49DF", "hairline": "#E6DCC8",
}
MARK = "#FFDD6B"                       # a highlight the reader made
TRAFFIC = ("#FF5F57", "#FEBC2E", "#28C840")
# Colours of a byte map, from empty to dense. A program's cover is drawn from its own bytes.
BYTES = ["#0E1330", "#1D2C73", "#3B49DF", "#27B5A6", "#F2C14E", "#F26A4B", "#F5F4F0"]

FONTS = {
    "ui": "/System/Library/Fonts/SFNS.ttf",           # SF Pro: the app
    "serif": "/System/Library/Fonts/NewYork.ttf",     # New York: anything you read
    "mono": "/System/Library/Fonts/SFNSMono.ttf",     # SF Mono: bytes and source
}

BOARD_W, BOARD_H = 2000, 1240          # the whole picture, in points
PT = 0.1                               # scene units per point
STEP = 0.0004                          # how far each newly drawn shape sits above the previous one

# ----------------------------------------------------------------------------- materials


def linear(hex_color):
    """Hex sRGB to the linear values Blender stores, so the render shows the colour as written."""
    def channel(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    h = hex_color.lstrip("#")
    return tuple(channel(int(h[i:i + 2], 16)) for i in (0, 2, 4))


_materials, _fonts, _widths = {}, {}, {}


def matte(hex_color, alpha=1.0):
    key = (hex_color, alpha)
    if key not in _materials:
        mat = bpy.data.materials.new("matte_%s_%d" % (hex_color, int(alpha * 100)))
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*linear(hex_color), 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        bsdf.inputs["Alpha"].default_value = alpha
        mat.diffuse_color = (*linear(hex_color), alpha)
        _materials[key] = mat
    return _materials[key]


def glass(tint="#FFFFFF", frost=0.30, body=0.22):
    """Frosted glass: what lies beneath shows through, blurred by its distance from the pane.
    `body` is how much of the pane's own colour is mixed in, so text on it stays readable."""
    key = ("glass", tint, frost, body)
    if key not in _materials:
        mat = bpy.data.materials.new("glass")
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        nodes.clear()
        out = nodes.new("ShaderNodeOutputMaterial")
        refract = nodes.new("ShaderNodeBsdfGlass")
        refract.inputs["Roughness"].default_value = frost
        refract.inputs["IOR"].default_value = 1.15
        solid = nodes.new("ShaderNodeBsdfDiffuse")
        solid.inputs["Color"].default_value = (*linear(tint), 1.0)
        pane = nodes.new("ShaderNodeMixShader")
        pane.inputs[0].default_value = body
        links.new(refract.outputs[0], pane.inputs[1])
        links.new(solid.outputs[0], pane.inputs[2])
        # Light must still reach what is under the pane, or it would sit in a black shadow.
        clear = nodes.new("ShaderNodeBsdfTransparent")
        clear.inputs["Color"].default_value = (0.86, 0.86, 0.86, 1.0)
        path = nodes.new("ShaderNodeLightPath")
        final = nodes.new("ShaderNodeMixShader")
        links.new(path.outputs["Is Shadow Ray"], final.inputs[0])
        links.new(pane.outputs[0], final.inputs[1])
        links.new(clear.outputs[0], final.inputs[2])
        links.new(final.outputs[0], out.inputs["Surface"])
        _materials[key] = mat
    return _materials[key]


def font(name):
    if name not in _fonts:
        try:
            _fonts[name] = bpy.data.fonts.load(FONTS[name])
        except RuntimeError:
            _fonts[name] = None        # fall back to Blender's built-in font on other systems
    return _fonts[name]


# ----------------------------------------------------------------------------- drawing primitives


class Surface:
    """One flat thing floating `lift` points above the desktop: a window, a cover, a pane of glass.
    Draws in points from its own top-left corner; later shapes sit a hair above earlier ones."""

    def __init__(self, left, top, lift, theme=None, k=1.0):
        self.left, self.top, self.lift = left, top, lift
        self.t = theme or {}
        self.k = k          # everything drawn here is scaled by k, so a cover can be shown at any size
        self.n = 0

    def child(self, x, y, rise, scale=1.0, theme=None):
        """A surface positioned relative to this one and raised above it."""
        return Surface(self.left + x * self.k, self.top + y * self.k, self.lift + rise + self.n * STEP / PT,
                       theme or self.t, self.k * scale)

    def color(self, name):
        return self.t.get(name, name)      # a token of the theme, or a literal hex colour

    def _place(self, pts):
        self.n += 1
        depth = -(self.lift * PT + self.n * STEP)
        return [((self.left + px * self.k) * PT, depth, -(self.top + py * self.k) * PT) for px, py in pts]

    def _mesh(self, pts, faces, materials, indices=None):
        mesh = bpy.data.meshes.new("shape")
        mesh.from_pydata(self._place(pts), [], faces)
        for m in materials:
            mesh.materials.append(m)
        if indices:
            mesh.polygons.foreach_set("material_index", indices)
        bpy.context.scene.collection.objects.link(bpy.data.objects.new("shape", mesh))

    @staticmethod
    def _outline(x, y, w, h, radius):
        radius = max(0.0, min(radius, w / 2, h / 2))
        steps = 10 if radius > 0 else 1
        pts = []
        for cx, cy, start in ((x + w - radius, y + radius, -90), (x + w - radius, y + h - radius, 0),
                              (x + radius, y + h - radius, 90), (x + radius, y + radius, 180)):
            for i in range(steps + 1):
                a = math.radians(start + 90 * i / steps)
                pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
        return pts

    def rect(self, x, y, w, h, color, radius=0.0, alpha=1.0, material=None):
        """Rounded rectangle. A radius of half the side gives a circle."""
        pts = self._outline(x, y, w, h, radius)
        self._mesh(pts, [list(range(len(pts)))], [material or matte(self.color(color), alpha)])

    def poly(self, pts, color, alpha=1.0):
        """Any closed outline, for the few shapes that are drawings and not controls."""
        self._mesh(list(pts), [list(range(len(pts)))], [matte(self.color(color), alpha)])

    def frame(self, x, y, w, h, color, radius, width=1.0, alpha=1.0):
        """The outline of a rounded rectangle."""
        outer = self._outline(x, y, w, h, radius)
        inner = self._outline(x + width, y + width, w - 2 * width, h - 2 * width, radius - width)
        n = len(outer)
        self._mesh(outer + inner, [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)], [matte(self.color(color), alpha)])

    def ring(self, cx, cy, r, width, color):
        self.frame(cx - r, cy - r, 2 * r, 2 * r, color, r, width)

    def line(self, x1, y1, x2, y2, width, color):
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        nx, ny = -dy / length * width / 2, dx / length * width / 2
        self._mesh([(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)], [[0, 1, 2, 3]], [matte(self.color(color))])

    def mosaic(self, x, y, w, h, cols, rows, palette, cell):
        """A grid of coloured squares in one mesh; cell(col, row) returns an index into the palette."""
        pts, faces, indices = [], [], []
        cw, chh = w / cols, h / rows
        for r in range(rows):
            for c in range(cols):
                base = len(pts)
                pts += [(x + c * cw, y + r * chh), (x + (c + 1) * cw, y + r * chh), (x + (c + 1) * cw, y + (r + 1) * chh), (x + c * cw, y + (r + 1) * chh)]
                faces.append([base, base + 1, base + 2, base + 3])
                indices.append(cell(c, r))
        self._mesh(pts, faces, [matte(p) for p in palette], indices)

    def text(self, x, y, body, size=13, color="label", face="ui", align="LEFT", weight=0.0):
        """One line of text; y is the top of the line. `weight` thickens the glyphs (0.5 reads as semibold)."""
        self.n += 1
        curve = bpy.data.curves.new("text", type="FONT")
        curve.body = body
        curve.size = size * self.k * PT
        curve.align_x = align
        curve.align_y = "TOP"
        curve.offset = weight * size * self.k * PT * 0.012
        if font(face) is not None:
            curve.font = font(face)
        obj = bpy.data.objects.new("text", curve)
        obj.location = ((self.left + x * self.k) * PT, -(self.lift * PT + self.n * STEP), -(self.top + y * self.k) * PT)
        obj.rotation_euler = (math.radians(90), 0, 0)
        curve.materials.append(matte(self.color(color)))
        bpy.context.scene.collection.objects.link(obj)

    def lines(self, x, y, rows, size=13, pitch=None, **style):
        pitch = pitch or size * 1.5
        for i, row in enumerate(rows):
            if row:
                self.text(x, y + i * pitch, row, size, **style)

    @staticmethod
    def _extent(body, size, face):
        curve = bpy.data.curves.new("measure", type="FONT")
        curve.body = body
        curve.size = size
        if font(face) is not None:
            curve.font = font(face)
        obj = bpy.data.objects.new("measure", curve)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.update()
        extent = obj.dimensions.x
        bpy.data.objects.remove(obj)
        bpy.data.curves.remove(curve)
        return extent

    def width(self, body, size=13, face="ui"):
        """Width of a run of text in points. Bars on both sides make leading and trailing spaces count."""
        key = (body, size, face)
        if key not in _widths:
            _widths[key] = self._extent("|" + body + "|", size, face) - self._extent("||", size, face)
        return _widths[key]

    def run(self, x, y, pieces, size=13, face="ui"):
        """Text in several styles on one line. Each piece is (text, colour) or (text, colour, highlight colour)."""
        for piece in pieces:
            w = self.width(piece[0], size, face)
            if len(piece) > 2:
                self.rect(x - 2, y - 2, w + 4, size * 1.45, piece[2], 3)
            self.text(x, y, piece[0], size, piece[1], face)
            x += w
        return x

    def pane(self, x, y, w, h, radius, rise=14, tint="#FFFFFF", frost=0.30, body=0.22, rim=0.75):
        """A pane of glass floating above this surface, with the bright rim that catches the light.
        Returns the surface to draw the pane's own controls on."""
        top = self.child(x, y, rise)
        top.rect(0, 0, w, h, "", radius, material=glass(tint, frost, body))
        top.frame(0, 0, w, h, "#FFFFFF", radius, 1.0, rim)
        return top


# ----------------------------------------------------------------------------- icons (18 pt box)


def icon(s, name, x, y, color="label"):
    if name == "contents":
        for k in range(3):
            s.rect(x + 1, y + 3 + k * 5, 2.2, 2.2, color, 1.1)
            s.rect(x + 6, y + 3.2 + k * 5, 11, 1.8, color, 0.9)
    elif name == "find":
        s.ring(x + 7.5, y + 7.5, 5.6, 1.7, color)
        s.line(x + 11.7, y + 11.7, x + 16.4, y + 16.4, 2.0, color)
    elif name == "edit":
        s.line(x + 3.6, y + 14.4, x + 12.6, y + 5.4, 3.4, color)
        s.line(x + 13.6, y + 4.4, x + 15.4, y + 2.6, 3.4, color)
        s.line(x + 1.6, y + 16.4, x + 3.0, y + 15.0, 1.4, color)
    elif name == "mark":
        s.line(x + 4.5, y + 11.5, x + 12.5, y + 3.5, 5.0, color)
        s.rect(x + 2, y + 15, 14, 1.9, color, 0.9)
    elif name == "info":
        s.ring(x + 9, y + 9, 7.6, 1.6, color)
        s.rect(x + 8.1, y + 7.8, 1.8, 5.6, color, 0.9)
        s.rect(x + 7.9, y + 4.1, 2.2, 2.2, color, 1.1)
    elif name == "plus":
        s.rect(x + 3, y + 8.1, 12, 1.8, color, 0.9)
        s.rect(x + 8.1, y + 3, 1.8, 12, color, 0.9)
    elif name == "back":
        s.line(x + 11, y + 3.5, x + 5.5, y + 9.3, 1.9, color)
        s.line(x + 5.5, y + 8.7, x + 11, y + 14.5, 1.9, color)


# ----------------------------------------------------------------------------- covers: every file has a face


def whale_tail(s, cx, top, size, color, alpha=1.0):
    """A whale's flukes rising from the water: the one drawing in the app, shared by the cover and the hero."""
    half = [(-7, 54), (-4, 29), (-13, 16), (-27, 8), (-41, 6), (-49, 2), (-37, 1), (-23, 3), (-11, 8), (0, 14)]
    pts = half + [(-x, y) for x, y in reversed(half[:-1])]
    s.poly([(cx + x * size, top + y * size) for x, y in pts], color, alpha)


def cover_book(s, w, h, title, author, cloth, ink, art=None):
    s.rect(0, 0, w, h, cloth, 4)
    s.rect(0, 0, 7, h, "#000000", 2, 0.16)                       # the shade of the spine
    s.frame(14, 12, w - 24, h - 24, ink, 2, 0.8, 0.55)
    for k, word in enumerate(title):
        s.text(w / 2 + 3, 34 + k * 26, word, 21, ink, face="serif", align="CENTER")
    s.text(w / 2 + 3, h - 34, author, 8.5, ink, face="serif", align="CENTER")
    if art == "whale":
        whale_tail(s, w / 2 + 3, 100, 1.0, ink)
        for k in range(5):
            s.rect(28 + (k % 2) * 12, 152 + k * 7.5, w - 62 - (k % 3) * 10, 1.5, "#5C7BCB", 0.75)
    elif art == "diamonds":
        cy = 34 + len(title) * 26 + 34
        for k, r in enumerate((5, 9, 5)):
            cx = w / 2 + 3 + (k - 1) * 24
            s.poly([(cx, cy - r), (cx + r * 0.7, cy), (cx, cy + r), (cx - r * 0.7, cy)], ink, 0.9)
        s.rect(w / 2 - 33, cy + 20, 72, 0.8, ink)


def cover_pdf(s, w, h, title, bars):
    s.rect(0, 0, w, h, "#FFFFFF", 3)
    s.rect(16, 18, 26, 3, "#E8553A", 1.5)
    s.text(16, 28, title, 12, "#1C1C1E", face="serif")
    for k in range(3):
        s.rect(16, 52 + k * 7, (w - 32) if k < 2 else 70, 2.4, "#D9D9DE", 1.2)
    if bars:
        s.rect(16, 82, w - 32, 78, "#F1F3F8", 4)
        for k, bar in enumerate(bars):
            s.rect(26 + k * 19, 152 - bar, 12, bar, "#3B49DF" if k == len(bars) - 1 else "#AEB8F0", 2)
    else:
        for k in range(5):                                       # an invoice: rows and amounts
            s.rect(16, 86 + k * 15, 74, 2.4, "#D9D9DE", 1.2)
            s.rect(w - 44, 86 + k * 15, 28, 2.4, "#BFC1C9", 1.2)
            s.rect(16, 94 + k * 15, w - 32, 0.6, "#ECECF0")
        s.rect(w - 60, 170, 44, 3.4, "#1C1C1E", 1.7)
    for k in range(4):
        s.rect(16, 176 + k * 7 + (0 if bars else 10), (w - 32) if k != 3 else 58, 2.4, "#D9D9DE", 1.2)


def cover_note(s, w, h, heading, rows):
    s.rect(0, 0, w, h, "#FFFBEF", 9)
    s.text(16, 18, heading, 14, "#32291C", weight=0.5)
    for k, row in enumerate(rows):
        if row.startswith("- "):
            s.rect(17, 53.5 + k * 15, 3, 3, "#7B6D58", 1.5)
            s.text(26, 48 + k * 15, row[2:], 8.5, "#32291C")
        elif row.startswith("# "):
            s.text(16, 47 + k * 15, row[2:], 10, "#32291C", weight=0.5)
        else:
            s.text(16, 48 + k * 15, row, 8.5, "#5E513E")


def cover_text(s, w, h, rows):
    s.rect(0, 0, w, h, "#FFFFFF", 3)
    s.rect(0, 0, 26, h, "#F3F3F6", 3)
    for k, row in enumerate(rows):
        s.text(20, 19 + k * 18.5, str(k + 1), 7.5, "#8E8E93", face="mono", align="RIGHT")
        s.text(33, 18 + k * 18.5, row, 9.5, "#3B49DF" if row.startswith("#") else "#1C1C1E", face="mono", weight=0.5)


def cover_bytes(s, w, h, seed, palette):
    """A program has no title page, so its cover is a map of its own bytes: dark where it is empty,
    warm where it holds text, bright where it is dense code. No two files look alike."""
    rng = random.Random(seed)
    cols, rows = 30, 42
    grid = []
    mode, left = "code", 0
    for r in range(rows):
        if left == 0:
            mode = rng.choice(["zero", "zero", "code", "code", "code", "text", "table"])
            left = rng.randint(2, 6)
        left -= 1
        row = []
        for c in range(cols):
            if r < 2:
                v = rng.choice([2, 3, 4, 5, 6])                  # the header: every value in use
            elif mode == "zero":
                v = 0 if rng.random() < 0.93 else 1
            elif mode == "text":
                v = rng.choice([4, 4, 5, 4, 6, 1])
            elif mode == "table":
                v = [2, 0, 0, 1][c % 4] if rng.random() < 0.9 else 3
            else:
                v = rng.choice([1, 2, 2, 3, 3, 1, 0, 5])
            row.append(v)
        grid.append(row)
    s.rect(0, 0, w, h, palette[0], 6)
    s.mosaic(9, 9, w - 18, h - 18, cols, rows, palette, lambda c, r: grid[r][c])


# ----------------------------------------------------------------------------- the library window


def traffic(s, x, y):
    for i, light in enumerate(TRAFFIC):
        s.rect(x + i * 20, y, 12, 12, light, 6)


def draw_library(desk, x, y):
    W, H = 1200, 800
    win = Surface(x, y, 50, LIBRARY)
    win.rect(0, 0, W, H, "window", 22)

    # The hero: the book you are in the middle of. Its cover colours and its drawing fill the top of the
    # window, and run on beneath the glass of the sidebar.
    hero_h = 322
    win.rect(0, 0, W, hero_h + 30, "#16264F", 22)
    win.rect(0, hero_h, W, 40, "window")
    whale_tail(win, 985, 58, 3.5, "#263E8A")
    for k in range(7):
        win.rect(742 + (k % 2) * 40, 250 + k * 10, 400 - (k % 3) * 56, 2.0, "#3A56A6", 1.0)

    side = win.pane(10, 10, 222, H - 20, 16, rise=12, tint="#F4F5FB", body=0.42, frost=0.45)
    traffic(side, 16, 16)
    for i, (name, count) in enumerate((("Library", "7"), ("Continue reading", "2"), ("Marks", "14"))):
        ry = 62 + i * 34
        if i == 0:
            side.rect(10, ry - 8, 202, 32, "accent", 9, 0.14)
        side.rect(22, ry + 2, 11, 11, "accent" if i == 0 else "secondary", 3.5)
        side.text(44, ry, name, 13, "accent" if i == 0 else "label", weight=0.5 if i == 0 else 0.2)
        side.text(200, ry + 1, count, 12, "accent" if i == 0 else "secondary", align="RIGHT")
    side.text(22, 186, "SHELVES", 10.5, "secondary", weight=0.5)
    for i, (name, tint) in enumerate((("Reading", "#E8553A"), ("Work", "#27B5A6"), ("Home", "#F2C14E"))):
        side.rect(22, 214 + i * 32, 11, 11, tint, 5.5)
        side.text(44, 211 + i * 32, name, 13, "label", weight=0.2)

    cx = 272
    cover_book(win.child(cx, 52, 12, scale=1.0), 160, 224, ["Moby-", "Dick"], "HERMAN MELVILLE", "#1B2F63", "#E9DFC6", "whale")
    tx = cx + 196
    win.text(tx, 70, "CONTINUE READING", 10.5, "#93A5E6", weight=0.5)
    win.text(tx, 92, "Moby-Dick", 40, "#FFFFFF", face="serif")
    win.text(tx, 146, "Herman Melville", 15, "#C5CEF2")
    win.rect(tx, 190, 250, 4, "#34498F", 2)
    win.rect(tx, 190, 12, 4, "#FFFFFF", 2)
    win.text(tx, 204, "Chapter 4 of 135   ·   6 minutes left in this chapter", 11.5, "#93A5E6")
    resume = win.pane(tx, 238, 112, 38, 19, rise=8, tint="#FFFFFF", body=0.86, frost=0.4)
    resume.text(56, 11, "Resume", 13.5, "#16264F", align="CENTER", weight=0.5)
    search = win.pane(W - 322, 26, 232, 38, 19, rise=10, tint="#C9D3FF", body=0.20, frost=0.5, rim=0.45)
    icon(search, "find", 14, 10, "#FFFFFF")
    search.text(40, 11, "Search every file", 13, "#DCE2FF")
    add = win.pane(W - 76, 26, 38, 38, 19, rise=10, tint="#C9D3FF", body=0.20, frost=0.5, rim=0.45)
    icon(add, "plus", 10, 10, "#FFFFFF")

    # One row of whatever was opened lately. Kinds are mixed on purpose.
    win.text(cx, hero_h + 30, "Recently opened", 17, "label", weight=0.6)
    faces = [
        ("Q3 Report", "Document  ·  12 pages", lambda s: cover_pdf(s, 160, 224, "Quarterly Report", (22, 34, 26, 48, 40, 60))),
        ("Project notes", "Note  ·  edited today", lambda s: cover_note(s, 160, 224, "Project notes", [
            "Reader and editor both work.", "", "# Status", "- Books and documents open", "- Every edit can be undone",
            "- Programs show their bytes", "", "# Next steps", "- Marks in every file", "- One search for all of it"])),
        ("firmware", "Program  ·  50 MB", lambda s: cover_bytes(s, 160, 224, 7, BYTES)),
        ("Pride and Prejudice", "Book  ·  finished", lambda s: cover_book(s, 160, 224, ["Pride", "and", "Prejudice"], "JANE AUSTEN", "#6B1F2B", "#F0E2C4", "diamonds")),
        ("Server settings", "Text  ·  10 lines", lambda s: cover_text(s, 160, 224, [
            "# server settings", "host=localhost", "port=8080", "debug=false", "log=/var/log/app.log", "", "# limits",
            "max_clients=200", "timeout=30", "retry=3"])),
        ("photos", "Database  ·  26 MB", lambda s: cover_bytes(s, 160, 224, 21, ["#18122B", "#443C68", "#635985", "#B15E7C", "#F29F58", "#F2D0A4", "#FFF5E4"])),
    ]
    cw, scale = 132, 132 / 160
    gap = (W - cx - 36 - 6 * cw) / 5
    for i, (name, detail, draw) in enumerate(faces):
        fx, fy = cx + i * (cw + gap), hero_h + 66
        draw(win.child(fx, fy, 7, scale=scale))
        win.text(fx, fy + 185 + 12, name, 12.5, "label", weight=0.5)
        win.text(fx, fy + 185 + 30, detail, 10.5, "secondary")

    # Marks: what you highlighted, gathered from every file. A line from a novel sits beside a line of bytes.
    my = hero_h + 318
    win.text(cx, my, "Your marks", 17, "label", weight=0.6)
    marks = [("serif", ["“…see the watery part", "of the world.”"], "#1B2F63", "Moby-Dick  ·  chapter 1"),
             ("mono", ["7f 45 4c 46", "File signature"], "#3B49DF", "firmware  ·  first 4 bytes"),
             ("serif", ["“Costs held flat for the", "third quarter in a row.”"], "#E8553A", "Q3 Report  ·  page 3")]
    mw = (W - cx - 36 - 2 * 18) / 3
    for i, (face, quote, tint, source) in enumerate(marks):
        card = win.child(cx + i * (mw + 18), my + 34, 5)
        card.rect(0, 0, mw, 100, "#FFFFFF", 12)
        card.rect(16, 16, 3, 40, MARK, 1.5)
        card.lines(30, 15, quote, 13 if face == "serif" else 12, 20, color="label", face=face, weight=0.0 if face == "serif" else 0.5)
        card.rect(16, 73, 10, 10, tint, 3)
        card.text(33, 71, source, 10.5, "secondary")


# ----------------------------------------------------------------------------- one window for any file


def action_bar(win, W, H, active, tint, body, ink, rim=0.75):
    """The five actions, on glass, floating over the content. Identical in every file."""
    actions = ["contents", "find", "edit", "mark", "info"]
    cell = 88
    bw = len(actions) * cell + 20
    bar = win.pane((W - bw) / 2, H - 80, bw, 54, 27, rise=34, tint=tint, frost=0.55, body=body, rim=rim)
    for i, name in enumerate(actions):
        ax = 10 + i * cell
        on = name == active
        if on:
            bar.rect(ax + 3, 8, cell - 6, 38, MARK, 19, 0.9)
        label = name.capitalize()
        start = ax + (cell - (18 + 7 + bar.width(label, 12.5))) / 2
        icon(bar, name, start, 18, "#32291C" if on else ink)
        bar.text(start + 25, 19.5, label, 12.5, "#32291C" if on else ink, weight=0.3)


def draw_reading(desk, x, y):
    W, H = 660, 700
    win = Surface(x, y, 130, PAPER)
    win.rect(0, 0, W, H, "window", 22)
    traffic(win, 22, 22)
    back = win.pane(96, 12, 96, 34, 17, rise=8, tint="#FFF9EC", body=0.6)
    icon(back, "back", 8, 8, "label")
    back.text(30, 9, "Library", 12.5, "label")
    win.text(W / 2, 20, "Moby-Dick", 12.5, "secondary", align="CENTER", weight=0.4)
    aa = win.pane(W - 60, 12, 40, 34, 17, rise=8, tint="#FFF9EC", body=0.6)
    aa.text(20, 8, "Aa", 13.5, "label", face="serif", align="CENTER")

    col_w, col = 452, 62
    mid = col + col_w / 2
    win.text(mid, 88, "CHAPTER 1", 10.5, "tertiary", align="CENTER", weight=0.5)
    win.text(mid, 108, "Loomings", 34, "label", face="serif", align="CENTER")
    whale_tail(win, mid, 162, 0.42, "tertiary")
    ty, pitch = 214, 27.5
    text = ["Call me Ishmael. Some years ago—never mind how long",
            "precisely—having little or no money in my purse, and nothing",
            "particular to interest me on shore, I thought I would sail about",
            None,
            "of driving off the spleen and regulating the circulation.",
            "Whenever I find myself growing grim about the mouth;",
            "whenever it is a damp, drizzly November in my soul; whenever",
            "I find myself involuntarily pausing before coffin warehouses,",
            "and bringing up the rear of every funeral I meet; and especially",
            "whenever my hypos get such an upper hand of me, that it",
            "requires a strong moral principle to prevent me from",
            "deliberately stepping into the street, and methodically",
            "knocking people’s hats off—then, I account it high time to get",
            "to sea as soon as I can. This is my substitute for pistol and ball.",
            "With a philosophical flourish Cato throws himself upon his",
            "sword; I quietly take to the ship. There is nothing surprising",
            "in this. If they but knew it, almost all men in their degree,"]
    for i, row in enumerate(text):
        if row:
            win.text(col, ty + i * pitch, row, 15.5, "label", face="serif")
    # A mark the reader made, with the note beside it.
    win.run(col, ty + 3 * pitch, [("a little and ", "label"), ("see the watery part of the world", "label", MARK), (". It is a way I have", "label")], 15.5, "serif")
    win.rect(col + col_w + 26, ty + 3 * pitch - 6, 3, 40, MARK, 1.5)
    win.lines(col + col_w + 38, ty + 3 * pitch - 4, ["The whole book", "in nine words."], 10.5, 15, color="secondary")
    action_bar(win, W, H, "mark", "#FFF9EC", 0.42, "label")


def byte_color(b):
    """The same scale the cover is painted in, so the page and the cover visibly belong together."""
    if b == 0x00:
        return "#49518A"
    if b == 0xFF:
        return "#F5F4F0"
    if 0x20 <= b < 0x7F:
        return "#F2C14E"
    return "#27B5A6" if b < 0x20 else "#F26A4B"


def draw_program(desk, x, y):
    W, H = 640, 520
    win = Surface(x, y, 130, NIGHT)
    win.rect(0, 0, W, H, "window", 22)
    traffic(win, 22, 22)
    back = win.pane(96, 12, 96, 34, 17, rise=8, tint="#2A3270", body=0.55, rim=0.30)
    icon(back, "back", 8, 8, "label")
    back.text(30, 9, "Library", 12.5, "label")
    win.text(W / 2, 20, "firmware", 12.5, "secondary", align="CENTER", weight=0.4)

    rows = ["7f454c4602010100" "0000000000000000", "02003e0001000000" "4010400000000000", "4000000000000000" "68656c6c6f000000",
            "0000000040003800" "090040001e001d00", "0600000004000000" "4000000000000000", "2f6c69622f6c642d" "6c696e75782e736f",
            "f801000000000000" "f801000000000000", "0800000000000000" "0300000004000000", "474e5500ffffffff" "3802400000000000",
            "6c6962632e736f2e" "3600707574730000", "1c00000000000000" "0100000000000000", "0100000005000000" "0000000000000000"]
    size, ch = 11.5, 11.5 * 0.602
    gx, top, pitch = 34, 104, 27
    # The reader's mark on the first four bytes, and the note that goes with it.
    win.rect(gx + 10 * ch - 5, top - 6, 11 * ch + 10, 25, MARK, 6, 0.22)
    win.rect(gx + 10 * ch - 5, top - 40, 3, 24, MARK, 1.5)
    win.text(gx + 10 * ch + 6, top - 35, "File signature: this is a Linux program.", 11, "secondary")
    for r, row in enumerate(rows):
        ry = top + r * pitch
        win.text(gx, ry, "%08x" % (0x100 + r * 16), size, "tertiary", face="mono")
        data = bytes.fromhex(row)
        for i, b in enumerate(data):
            bx = gx + (10 + i * 3 + (1 if i >= 8 else 0)) * ch
            win.text(bx, ry, "%02x" % b, size, byte_color(b), face="mono", weight=0.3)
            win.text(gx + (61 + i) * ch, ry, chr(b) if 0x20 <= b < 0x7F else "·", size, byte_color(b), face="mono", weight=0.3)

    # The cover again, as the scroll bar: the whole file top to bottom, with a frame around what is on screen.
    strip = win.child(W - 50, 70, 3)
    strip.rect(-4, -4, 34, 352, "#070A1F", 6)
    rng = random.Random(7)
    grid, mode, left = [], "code", 0
    for r in range(86):
        if left == 0:
            mode, left = rng.choice(["zero", "zero", "code", "code", "code", "text", "table"]), rng.randint(3, 10)
        left -= 1
        grid.append([rng.choice([2, 3, 4, 5, 6]) if r < 2 else (0 if rng.random() < 0.93 else 1) if mode == "zero"
                     else rng.choice([4, 4, 5, 6, 1]) if mode == "text" else [2, 0, 0, 1][c % 4] if mode == "table"
                     else rng.choice([1, 2, 2, 3, 3, 1, 0, 5]) for c in range(6)])
    strip.mosaic(0, 0, 26, 344, 6, 86, BYTES, lambda c, r: grid[r][c])
    strip.frame(-4, 0, 34, 30, "#FFFFFF", 4, 1.6)
    action_bar(win, W, H, "edit", "#2A3270", 0.50, "label", rim=0.30)


# ----------------------------------------------------------------------------- scene


def desktop():
    """The wallpaper: a slow diagonal blend, so the windows have something to float over."""
    mat = bpy.data.materials.new("wallpaper")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(-32))
    gradient = nodes.new("ShaderNodeTexGradient")
    ramp = nodes.new("ShaderNodeValToRGB")
    stops = [(0.0, "#1B1F4B"), (0.42, "#3A3F9E"), (0.72, "#8E63C7"), (1.0, "#F1A07E")]
    ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = stops[0][0], (*linear(stops[0][1]), 1)
    ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = stops[-1][0], (*linear(stops[-1][1]), 1)
    for pos, hex_color in stops[1:-1]:
        ramp.color_ramp.elements.new(pos).color = (*linear(hex_color), 1)
    links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], gradient.inputs["Vector"])
    links.new(gradient.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], diffuse.inputs["Color"])
    links.new(diffuse.outputs[0], out.inputs["Surface"])
    desk = Surface(0, 0, 0)
    desk.rect(-200, -200, BOARD_W + 400, BOARD_H + 400, "", material=mat)
    return desk


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene

    desk = desktop()
    desk.text(56, 64, "Anyfile", 60, "#FFFFFF", weight=0.7)
    desk.text(58, 144, "Every file has a face.", 23, "#FFFFFF")
    desk.lines(58, 190, ["One library for books, documents,", "notes and programs. One window.",
                         "Five actions that never move."], 15, 23, color="#D6D3F0")
    draw_library(desk, 470, 60)
    draw_reading(desk, 50, 490)
    draw_program(desk, 1330, 696)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = BOARD_W * PT
    cam_data.clip_end = 2000
    cam = bpy.data.objects.new("Camera", cam_data)
    cam.location = (BOARD_W * PT / 2, -600.0, -BOARD_H * PT / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    # Even light from everywhere keeps colours true; a broad sun from the upper left adds the shadows.
    # 0.72 + 0.95 * cos / pi comes to 1.0 on an unshadowed surface (measured), so white renders as white.
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (1, 1, 1, 1)
    background.inputs[1].default_value = 0.72
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 0.95
    sun_data.angle = math.radians(18)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector((0.25, 1.0, -0.35)).normalized().to_track_quat("-Z", "Y")
    scene.collection.objects.link(sun)


def frame_viewports_on_camera():
    """Make every 3D viewport in the saved file open looking through the camera, rendered."""
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.region_3d.view_perspective = "CAMERA"
                    space.shading.type = "MATERIAL"
                    space.overlay.show_overlays = False


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"render": None, "save": None, "scale": 2.0, "samples": 160}
    i = 0
    while i + 1 < len(argv):
        key = argv[i][2:]
        if key in ("render", "save"):
            opts[key] = argv[i + 1]
        elif key == "scale":
            opts[key] = float(argv[i + 1])
        elif key == "samples":
            opts[key] = int(argv[i + 1])
        i += 2

    build()
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = int(BOARD_W * opts["scale"]), int(BOARD_H * opts["scale"])
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.engine = "CYCLES"                     # ray tracing: the glass and the shadows are computed, not painted
    scene.cycles.samples = opts["samples"]
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 6
    scene.cycles.transparent_max_bounces = 16
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.view_settings.view_transform = "Standard"    # show the colours as written, not tone-mapped for film
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
