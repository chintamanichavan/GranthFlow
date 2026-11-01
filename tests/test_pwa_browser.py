"""Headless-Chromium tests against the PWA.

Verifies the parts only a browser can show: that the C++ engine really loads as WebAssembly and
detects kinds, that a file added to the library gets a cover made from its own contents, that a
book opens and turns pages, that a mark survives a reload, and that the library exports in the
shape the Mac app reads back.

    .venv/bin/python -m pytest tests/test_pwa_browser.py -v
"""
from __future__ import annotations

import functools
import http.server
import json
import socket
import threading
import zipfile
from pathlib import Path
from typing import ClassVar

import pytest

playwright = pytest.importorskip("playwright.sync_api")
from playwright.sync_api import Page, sync_playwright

WEB = Path(__file__).resolve().parent.parent / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map: ClassVar[dict[str, str]] = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".mjs": "text/javascript",
        ".js": "text/javascript",
        ".wasm": "application/wasm",
        ".webmanifest": "application/manifest+json",
    }

    def log_message(self, fmt, *args):  # quiet
        pass


@pytest.fixture(scope="session")
def site() -> str:
    if not (WEB / "vendor" / "anyfile.wasm").exists():
        pytest.skip("the engine is not built; run web/build.sh first")
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(WEB)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{port}"
    server.shutdown()


@pytest.fixture(scope="module")
def browser():
    with sync_playwright() as p:
        b = p.chromium.launch()
        yield b
        b.close()


@pytest.fixture
def page(browser, site) -> Page:
    context = browser.new_context()
    page = context.new_page()
    problems: list[str] = []
    page.on("pageerror", lambda e: problems.append(str(e)))
    page.on("console", lambda m: problems.append(m.text) if m.type == "error" else None)
    page.goto(site)
    page.wait_for_selector("button.primary", timeout=20_000)   # the engine has loaded
    page.problems = problems
    yield page
    context.close()


def epub_bytes(title: str = "The Test Book", author: str = "Ada Lovelace", chapters: int = 3) -> bytes:
    """A small EPUB 3, built the way tests/conftest.py builds one."""
    import io

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as z:
        z.writestr("mimetype", "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
                   '<?xml version="1.0"?><container version="1.0" '
                   'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
                   '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
                   "</rootfiles></container>")
        items = "".join(f'<item id="c{i}" href="ch{i}.xhtml" media-type="application/xhtml+xml"/>'
                        for i in range(1, chapters + 1))
        refs = "".join(f'<itemref idref="c{i}"/>' for i in range(1, chapters + 1))
        z.writestr("OEBPS/content.opf",
                   f'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
                   f'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                   f'<dc:identifier id="id">urn:uuid:test</dc:identifier><dc:title>{title}</dc:title>'
                   f'<dc:creator>{author}</dc:creator><dc:language>en</dc:language></metadata>'
                   f'<manifest>{items}<item id="nav" href="nav.xhtml" '
                   f'media-type="application/xhtml+xml" properties="nav"/></manifest>'
                   f"<spine>{refs}</spine></package>")
        z.writestr("OEBPS/nav.xhtml",
                   '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body><nav '
                   'epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol>'
                   + "".join(f'<li><a href="ch{i}.xhtml">Chapter {i}</a></li>' for i in range(1, chapters + 1))
                   + "</ol></nav></body></html>")
        for i in range(1, chapters + 1):
            z.writestr(f"OEBPS/ch{i}.xhtml",
                       f'<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body>'
                       f"<h1>Chapter {i}</h1><p>The quick brown fox jumps over chapter {i}. "
                       f"Call me Ishmael, in chapter {i}.</p></body></html>")
    return buffer.getvalue()


def add_file(page: Page, name: str, data: bytes) -> None:
    """Puts a file through the picker, the way a reader would."""
    with page.expect_file_chooser() as chooser:
        page.click("button.primary")
    chooser.value.set_files([{"name": name, "mimeType": "application/octet-stream", "buffer": data}])
    page.wait_for_selector(".shelf .book", timeout=15_000)


# ---------------------------------------------------------------- the engine

def test_the_engine_loads_as_webassembly_and_detects_kinds(page: Page):
    kinds = page.evaluate("""async () => {
        const engine = await import("./app/engine.js");
        await engine.load();
        const bytes = (s) => new TextEncoder().encode(s);
        return {
            pdf: engine.detectKind(bytes("%PDF-1.4\\n"), "a.pdf"),
            md: engine.detectKind(bytes("# hi"), "a.md"),
            text: engine.detectKind(bytes("plain"), "a.txt"),
            binary: engine.detectKind(new Uint8Array([0, 1, 2]), "a.dat"),
            commands: engine.commands("pdf").map((c) => c.name),
        };
    }""")
    assert kinds["pdf"] == "pdf"
    assert kinds["md"] == "markdown"
    assert kinds["text"] == "text"
    assert kinds["binary"] == "binary"
    assert "pages" in kinds["commands"] and "hex" in kinds["commands"]


def test_an_epub_is_read_by_the_engine_in_the_browser(page: Page):
    result = page.evaluate("""async (base64) => {
        const engine = await import("./app/engine.js");
        const doc = await import("./app/document.js");
        await engine.load();
        const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
        return {
            kind: engine.detectKind(bytes, "book.epub"),
            meta: doc.meta(bytes, "book.epub", "epub"),
            chapters: doc.contents(bytes, "book.epub", "epub").map((c) => c.title),
            second: doc.textAt(bytes, "book.epub", "epub", 2),
        };
    }""", __import__("base64").b64encode(epub_bytes()).decode())
    assert result["kind"] == "epub"
    assert result["meta"]["title"] == "The Test Book"
    assert result["meta"]["creator"] == "Ada Lovelace"
    assert result["chapters"] == ["Chapter 1", "Chapter 2", "Chapter 3"]
    assert "chapter 2" in result["second"]


# ---------------------------------------------------------------- the library

def test_a_book_added_gets_a_cover_from_its_own_contents(page: Page):
    add_file(page, "book.epub", epub_bytes())
    page.wait_for_selector(".art.cloth", timeout=15_000)
    # The title and author come out of the book, not the file name.
    assert page.inner_text(".book .name").strip() == "The Test Book"
    assert "Ada Lovelace" in page.inner_text(".book .note")
    assert page.inner_text(".art.cloth .title").replace("\n", " ") == "The Test Book"
    assert page.get_attribute(".badge", "class") == "badge"      # New
    assert page.problems == []


def test_a_text_file_and_a_binary_get_their_own_faces(page: Page):
    add_file(page, "notes.txt", b"first line\nsecond line\nthird line\n")
    page.wait_for_selector(".art.leaf.plain", timeout=15_000)
    assert "first line" in page.inner_text(".art.leaf.plain")

    add_file(page, "firmware.bin", bytes(range(256)) * 40)
    page.wait_for_selector(".art canvas", timeout=15_000)      # a map of its bytes
    assert page.problems == []


# ---------------------------------------------------------------- reading

def test_a_book_opens_turns_pages_and_remembers_the_place(page: Page):
    add_file(page, "book.epub", epub_bytes())
    page.click(".book")
    page.wait_for_selector(".column", timeout=15_000)
    assert "Chapter 1" in page.inner_text(".column")
    assert "Chapter 1 of 3" in page.inner_text(".left")

    page.click("button:text('Next ›')")
    page.wait_for_function("document.querySelector('.left')?.textContent.includes('Chapter 2 of 3')")
    assert "chapter 2" in page.inner_text(".column")

    # Back to the library, and the place is on the card.
    page.click("button:text('‹ Library')")
    page.wait_for_selector(".shelf .book", timeout=10_000)
    assert "Chapter 2 of 3" in page.inner_text(".book .note")

    # And it survives a reload, because it is in IndexedDB.
    page.reload()
    page.wait_for_selector(".shelf .book", timeout=20_000)
    assert "Chapter 2 of 3" in page.inner_text(".book .note")
    assert page.problems == []


def test_the_contents_list_turns_to_a_chapter(page: Page):
    add_file(page, "book.epub", epub_bytes())
    page.click(".book")
    page.wait_for_selector(".contents a", timeout=15_000)
    page.click(".contents a:text('Chapter 3')")
    page.wait_for_function("document.querySelector('.left')?.textContent.includes('Chapter 3 of 3')")
    assert "chapter 3" in page.inner_text(".column")


def test_a_markdown_note_gets_an_outline(page: Page):
    add_file(page, "notes.md", b"# Title\n\nBody text.\n\n## Second\n\nMore body.\n")
    page.click(".book")
    page.wait_for_selector(".contents", timeout=15_000)
    outline = page.inner_text(".contents")
    assert "Title" in outline and "Second" in outline
    assert "Body text." in page.inner_text(".column")


def test_a_binary_gets_a_hex_view(page: Page):
    add_file(page, "firmware.bin", bytes(range(256)) * 40)
    page.click(".book")
    page.wait_for_selector(".column.mono", timeout=15_000)
    assert "0000" in page.inner_text(".column.mono")


# ---------------------------------------------------------------- marks

def test_a_mark_is_painted_over_the_text_and_survives_a_reload(page: Page):
    add_file(page, "book.epub", epub_bytes())
    page.click(".book")
    page.wait_for_selector(".column", timeout=15_000)

    # Marking goes through the store the way the colour buttons do.
    page.evaluate("""async () => {
        const store = await import("./app/store.js");
        await store.addMark({ path: "book.epub", kind: "epub", quote: "quick brown fox",
                              target: 1, place: "Chapter 1", colour: "green" });
    }""")
    page.reload()
    page.wait_for_selector(".shelf .book", timeout=20_000)
    page.click(".book")
    page.wait_for_selector(".column mark", timeout=15_000)
    painted = page.query_selector(".column mark")
    assert painted.inner_text() == "quick brown fox"
    assert "green" in painted.get_attribute("class")
    assert "Marks (1)" in page.inner_text(".actions")


# ---------------------------------------------------------------- moving a library

def test_the_library_exports_in_the_shape_the_mac_app_reads(page: Page):
    add_file(page, "book.epub", epub_bytes())
    page.click(".book")
    page.wait_for_selector(".column", timeout=15_000)
    page.click("button:text('Next ›')")
    page.wait_for_function("document.querySelector('.left')?.textContent.includes('Chapter 2 of 3')")
    page.evaluate("""async () => {
        const store = await import("./app/store.js");
        await store.addMark({ path: "book.epub", kind: "epub", quote: "Ishmael", target: 2,
                              place: "Chapter 2", note: "the opening", colour: "yellow" });
    }""")

    files = page.evaluate("""async () => {
        const store = await import("./app/store.js");
        return store.exportLibrary();
    }""")
    library = json.loads(files["library.json"])
    marks = json.loads(files["marks.json"])

    entry = library[0]
    assert entry["path"] == "book.epub"
    assert entry["kind"] == "epub"
    assert entry["position"] == 2 and entry["total"] == 3
    # Swift's .iso8601 strategy rejects fractional seconds, so they must not be written.
    assert entry["opened"].endswith("Z") and "." not in entry["opened"]
    assert list(entry) == sorted(entry), "keys are sorted, as JSONEncoder.sortedKeys writes them"

    mark = marks[0]
    assert mark["quote"] == "Ishmael"
    assert mark["path"] == "book.epub"
    assert mark["kind"] == "epub"
    assert mark["target"] == 2
    assert mark["place"] == "Chapter 2"
    assert mark["note"] == "the opening"
    assert mark["colour"] == "yellow"
    assert "." not in mark["created"] and mark["created"].endswith("Z")
    assert len(mark["id"]) == 36 and mark["id"] == mark["id"].upper()


def test_a_mac_library_imports_and_keeps_the_later_place(page: Page):
    add_file(page, "book.epub", epub_bytes())
    report = page.evaluate("""async () => {
        const store = await import("./app/store.js");
        // What the Mac app writes: absolute paths, and a reading place further on than ours.
        return store.importLibrary({
            library: [{ path: "/Users/someone/Books/book.epub", kind: "epub",
                        opened: "2099-01-01T00:00:00Z", position: 3, total: 3 },
                      { path: "/Users/someone/Books/elsewhere.epub", kind: "epub",
                        opened: "2026-01-01T00:00:00Z", position: 1, total: 9 }],
            marks: [{ id: "AAAAAAAA-0000-0000-0000-000000000001", path: "/Users/someone/Books/book.epub",
                      kind: "epub", quote: "Ishmael", target: 1, place: "Chapter 1",
                      created: "2026-01-01T00:00:00Z", note: "", colour: "blue" }],
        });
    }""")
    assert report["entries"] == 2 and report["marks"] == 1

    page.reload()
    page.wait_for_selector(".shelf .book", timeout=20_000)
    # The Mac entry was filed under the file's name, so it met the book already here.
    state = page.evaluate("""async () => {
        const store = await import("./app/store.js");
        const entry = await store.entry("book.epub");
        const marks = await store.marksFor("book.epub");
        return { position: entry.position, total: entry.total, count: (await store.entries()).length,
                 markPath: marks[0]?.path, markColour: marks[0]?.colour };
    }""")
    assert state["position"] == 3, "the later reading place wins"
    assert state["count"] == 2, "the book here, and the one only the Mac had"
    assert state["markPath"] == "book.epub", "the mark's path was rewritten to the file's name"
    assert state["markColour"] == "blue"

    # Importing the same marks again adds nothing.
    again = page.evaluate("""async () => {
        const store = await import("./app/store.js");
        return store.importLibrary({ marks: [{ id: "AAAAAAAA-0000-0000-0000-000000000001",
            path: "/Users/someone/Books/book.epub", kind: "epub", quote: "Ishmael", target: 1,
            place: "Chapter 1", created: "2026-01-01T00:00:00Z", note: "", colour: "blue" }] });
    }""")
    assert again["marks"] == 0 and again["marksSkipped"] == 1


# ---------------------------------------------------------------- installable and offline

def test_the_manifest_and_icons_make_it_installable(page: Page, site: str):
    manifest = page.evaluate("async () => (await fetch('./manifest.webmanifest')).json()")
    assert manifest["name"] == "GranthFlow"
    assert manifest["display"] == "standalone"
    assert manifest["start_url"] == "./"
    sizes = {icon["sizes"] for icon in manifest["icons"]}
    assert "512x512" in sizes, "a 512px icon is what browsers ask for"
    assert any(icon.get("purpose") == "maskable" for icon in manifest["icons"])
    for icon in manifest["icons"]:
        assert page.evaluate("async (src) => (await fetch(src)).ok", icon["src"]), icon["src"]


def test_the_service_worker_caches_the_shell_and_the_engine(page: Page):
    page.wait_for_function("navigator.serviceWorker.controller !== null || navigator.serviceWorker.ready", timeout=20_000)
    cached = page.evaluate("""async () => {
        await navigator.serviceWorker.ready;
        const names = await caches.keys();
        const cache = await caches.open(names[0]);
        return (await cache.keys()).map((r) => new URL(r.url).pathname);
    }""")
    assert any(path.endswith("/vendor/anyfile.wasm") for path in cached), "the engine is cached for offline use"
    assert any(path.endswith("/app/main.js") for path in cached)
    assert any(path.endswith(("/index.html", "/")) for path in cached)


def test_the_page_works_with_the_network_cut(page: Page, site: str):
    # The engine and shell are cached on the first visit; a second visit offline must still read.
    add_file(page, "book.epub", epub_bytes())
    page.evaluate("async () => navigator.serviceWorker.ready")
    page.context.set_offline(True)
    page.reload()
    page.wait_for_selector(".shelf .book", timeout=25_000)
    page.click(".book")
    page.wait_for_selector(".column", timeout=20_000)
    assert "Chapter 1" in page.inner_text(".column")
    page.context.set_offline(False)
