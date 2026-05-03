from __future__ import annotations

from pathlib import Path

from granthflow import epub_meta


def test_parse_extracts_title_and_author(epub_factory):
    path: Path = epub_factory(title="My Book", author="Alice")
    meta = epub_meta.parse(path)
    assert meta.title == "My Book"
    assert meta.author == "Alice"


def test_parse_extracts_cover_when_present(epub_factory):
    path: Path = epub_factory(with_cover=True)
    meta = epub_meta.parse(path)
    assert meta.cover_bytes is not None and len(meta.cover_bytes) > 0
    assert meta.cover_ext == ".png"


def test_parse_no_cover(epub_factory):
    path: Path = epub_factory(with_cover=False)
    meta = epub_meta.parse(path)
    assert meta.cover_bytes is None
    assert meta.cover_ext is None
