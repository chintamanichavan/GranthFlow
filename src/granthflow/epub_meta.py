"""Parse EPUB metadata (title, author, cover) using stdlib only."""
from __future__ import annotations

import posixpath
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree as ET

NS = {
    "container": "urn:oasis:names:tc:opendocument:xmlns:container",
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
}


@dataclass
class EpubMeta:
    title: str
    author: str | None
    cover_bytes: bytes | None
    cover_ext: str | None  # e.g. ".jpg", ".png"


class EpubParseError(Exception):
    pass


def parse(epub_path: Path) -> EpubMeta:
    with zipfile.ZipFile(epub_path) as zf:
        opf_path = _find_opf_path(zf)
        opf_dir = posixpath.dirname(opf_path)
        opf_root = ET.fromstring(zf.read(opf_path))

        title = _text(opf_root, ".//dc:title") or epub_path.stem
        author = _text(opf_root, ".//dc:creator")

        cover_href = _find_cover_href(opf_root)
        cover_bytes: bytes | None = None
        cover_ext: str | None = None
        if cover_href:
            cover_path = posixpath.normpath(posixpath.join(opf_dir, cover_href))
            try:
                cover_bytes = zf.read(cover_path)
                cover_ext = Path(cover_href).suffix.lower() or ".jpg"
            except KeyError:
                cover_bytes = None

        return EpubMeta(
            title=title.strip(),
            author=author.strip() if author else None,
            cover_bytes=cover_bytes,
            cover_ext=cover_ext,
        )


def _find_opf_path(zf: zipfile.ZipFile) -> str:
    try:
        container = ET.fromstring(zf.read("META-INF/container.xml"))
    except KeyError as e:
        raise EpubParseError("missing META-INF/container.xml") from e
    rootfile = container.find(".//container:rootfile", NS)
    if rootfile is None or "full-path" not in rootfile.attrib:
        raise EpubParseError("container.xml missing rootfile")
    return rootfile.attrib["full-path"]


def _text(root: ET.Element, xpath: str) -> str | None:
    el = root.find(xpath, NS)
    if el is None or el.text is None:
        return None
    return el.text


def _find_cover_href(opf_root: ET.Element) -> str | None:
    # epub3: manifest item with properties="cover-image"
    for item in opf_root.findall(".//opf:manifest/opf:item", NS):
        props = item.attrib.get("properties", "")
        if "cover-image" in props.split():
            return item.attrib.get("href")

    # epub2: <meta name="cover" content="<id>"/> → look up item by id
    for meta in opf_root.findall(".//opf:metadata/opf:meta", NS):
        if meta.attrib.get("name") == "cover":
            cover_id = meta.attrib.get("content")
            if cover_id:
                item = opf_root.find(f".//opf:manifest/opf:item[@id='{cover_id}']", NS)
                if item is not None:
                    return item.attrib.get("href")

    # last-ditch: an item literally named "cover"
    item = opf_root.find(".//opf:manifest/opf:item[@id='cover']", NS)
    if item is not None and item.attrib.get("media-type", "").startswith("image/"):
        return item.attrib.get("href")

    return None
