from __future__ import annotations

import importlib
import sys
import zipfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


# 1x1 red PNG so cover roundtrip is testable
RED_PIXEL_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c63f8cfc0000000030001a0a4d6b300"
    "00000049454e44ae426082"
)

CONTAINER_XML = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def _opf(title: str, author: str, with_cover: bool) -> str:
    cover_item = (
        '<item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>'
        if with_cover
        else ""
    )
    return f"""<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">test-id</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>{author}</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    {cover_item}
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
"""


_LOREM_PARAS = [
    "The lights of the city glowed in the distance, blurred by rain on the glass. She "
    "watched them for a long time, thinking nothing in particular. The kettle clicked off "
    "behind her and she did not move. The room was warm, and the warmth made the cold "
    "outside feel real. Outside the wind kept up its low note against the eaves.",
    "He walked the long path beside the canal. Reeds bent under the wind and a heron lifted "
    "out of the shallows with a slow, patient beat of wings. The path was wet but firm. He "
    "had no particular destination, only the certainty that walking helped him think, and "
    "that thinking was, for once, what he wanted to do.",
    "By the time the train pulled in, the platform was already full. Voices rose and fell "
    "in that strange chorus you only hear in stations: greetings, instructions, last calls. "
    "She found her car and her seat and arranged her bag with the small ceremony of someone "
    "who has done it many times. The train began to move; she did not look back.",
    "There were three things in the box and only two of them surprised him. The third he "
    "had been expecting for years, though he could not have said why. He held it for a "
    "moment and then set it down on the table. The light from the lamp made it look smaller "
    "than it really was, and older, as if the years had finally caught up.",
]


def _chapter_xhtml(title: str, paragraphs: list[str]) -> str:
    body = "\n".join(f"<p>{p}</p>" for p in paragraphs)
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml">'
        f"<head><title>{title}</title></head>"
        f"<body><h1>{title}</h1>{body}</body></html>"
    )


def make_rich_epub(path: Path, title: str = "Rich Book", author: str = "Test Author") -> Path:
    """Build a multi-chapter epub with substantial paragraph content.

    epub.js needs real prose to paginate and resolve range CFIs against.
    """
    chapters = [
        ("Chapter One", _LOREM_PARAS[:2]),
        ("Chapter Two", _LOREM_PARAS[2:]),
    ]
    manifest_items = "\n".join(
        f'<item id="ch{i+1}" href="ch{i+1}.xhtml" media-type="application/xhtml+xml"/>'
        for i in range(len(chapters))
    )
    spine_items = "\n".join(f'<itemref idref="ch{i+1}"/>' for i in range(len(chapters)))
    opf = f"""<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">test-rich</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>{author}</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    {manifest_items}
  </manifest>
  <spine>
    {spine_items}
  </spine>
</package>
"""
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML)
        zf.writestr("OEBPS/content.opf", opf)
        for i, (chap_title, paras) in enumerate(chapters):
            zf.writestr(f"OEBPS/ch{i+1}.xhtml", _chapter_xhtml(chap_title, paras))
    return path


def make_epub(path: Path, title: str = "Test Book", author: str = "Test Author",
              with_cover: bool = True) -> Path:
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML)
        zf.writestr("OEBPS/content.opf", _opf(title, author, with_cover))
        zf.writestr(
            "OEBPS/ch1.xhtml",
            '<?xml version="1.0" encoding="utf-8"?>'
            '<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml">'
            "<head><title>ch1</title></head><body><p>Hello world.</p></body></html>",
        )
        if with_cover:
            zf.writestr("OEBPS/cover.png", RED_PIXEL_PNG)
    return path


@pytest.fixture
def epub_factory(tmp_path: Path):
    counter = {"n": 0}

    def _make(title: str = "Test Book", author: str = "Test Author",
              with_cover: bool = True) -> Path:
        counter["n"] += 1
        p = tmp_path / f"book_{counter['n']}.epub"
        return make_epub(p, title=title, author=author, with_cover=with_cover)

    return _make


def _fresh_app(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, **env: str):
    """Re-import granthflow with a fresh data dir + extra env, returns the app module."""
    monkeypatch.setenv("GRANTHFLOW_DATA_DIR", str(tmp_path / "data"))
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    for mod in list(sys.modules):
        if mod.startswith("granthflow"):
            del sys.modules[mod]
    return importlib.import_module("granthflow.app")


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    appmod = _fresh_app(tmp_path, monkeypatch)
    with TestClient(appmod.app) as c:
        yield c


@pytest.fixture
def autoimport_setup(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Returns (TestClient, appmod, scan_dir) — scan_dir is a tmp dir to drop epubs into."""
    scan_dir = tmp_path / "icloud_books"
    scan_dir.mkdir()
    appmod = _fresh_app(tmp_path, monkeypatch, GRANTHFLOW_AUTOIMPORT_DIR=str(scan_dir))
    client = TestClient(appmod.app)
    with client:
        yield client, appmod, scan_dir
