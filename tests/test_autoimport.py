"""Auto-import (GRANTHFLOW_AUTOIMPORT_DIR) — scan a directory, dedup, /scan endpoint."""
from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from tests.conftest import make_epub


def test_scan_directory_imports_new_epubs(autoimport_setup):
    client, appmod, scan_dir = autoimport_setup
    make_epub(scan_dir / "First.epub", title="First", author="A")
    make_epub(scan_dir / "Second.epub", title="Second", author="B")

    result = appmod.scan_directory(client.app.state.conn, scan_dir)
    assert result == {"imported": 2, "skipped": 0}

    rows = client.app.state.conn.execute("SELECT title FROM books ORDER BY title").fetchall()
    assert [r["title"] for r in rows] == ["First", "Second"]


def test_scan_directory_dedups_on_rescan(autoimport_setup):
    client, appmod, scan_dir = autoimport_setup
    make_epub(scan_dir / "OnlyOne.epub", title="OnlyOne", author="A")

    first = appmod.scan_directory(client.app.state.conn, scan_dir)
    assert first["imported"] == 1

    # second scan with same files → all skipped
    second = appmod.scan_directory(client.app.state.conn, scan_dir)
    assert second == {"imported": 0, "skipped": 1}


def test_scan_directory_recurses_into_subfolders(autoimport_setup):
    client, appmod, scan_dir = autoimport_setup
    sub = scan_dir / "Fiction" / "2024"
    sub.mkdir(parents=True)
    make_epub(sub / "Buried.epub", title="Buried Deep", author="X")

    result = appmod.scan_directory(client.app.state.conn, scan_dir)
    assert result == {"imported": 1, "skipped": 0}


def test_scan_directory_skips_icloud_placeholders(autoimport_setup):
    client, appmod, scan_dir = autoimport_setup
    # iCloud stubs look like .OriginalName.epub.icloud — dotfile, .icloud suffix.
    # rglob('*.epub') doesn't match them at all, so they're invisible to the scanner.
    (scan_dir / ".Pending.epub.icloud").write_bytes(b"placeholder stub")
    make_epub(scan_dir / "Real.epub", title="Real", author="Y")

    result = appmod.scan_directory(client.app.state.conn, scan_dir)
    assert result == {"imported": 1, "skipped": 0}


def test_scan_directory_handles_missing_dir(autoimport_setup):
    client, appmod, scan_dir = autoimport_setup
    nope = scan_dir.parent / "does_not_exist"
    result = appmod.scan_directory(client.app.state.conn, nope)
    assert result == {"imported": 0, "skipped": 0}


def test_scan_endpoint_redirects_to_library(autoimport_setup):
    client, _, scan_dir = autoimport_setup
    make_epub(scan_dir / "Endpoint.epub", title="Via Endpoint", author="Z")

    r = client.post("/scan", follow_redirects=False)
    assert r.status_code == 303
    assert r.headers["location"] == "/"

    # library page reflects the imported book
    r2 = client.get("/")
    assert "Via Endpoint" in r2.text


def test_scan_endpoint_400_when_not_configured(client: TestClient):
    """Default fixture has no autoimport env — endpoint should refuse."""
    r = client.post("/scan", follow_redirects=False)
    assert r.status_code == 400
    assert "AUTOIMPORT" in r.json()["detail"]


def test_scan_button_visible_only_when_configured(
    client: TestClient, autoimport_setup
):
    # default client (no autoimport env): no scan button
    r = client.get("/")
    assert "scan library" not in r.text

    # autoimport client: button is rendered
    ai_client, _, _ = autoimport_setup
    r2 = ai_client.get("/")
    assert "scan library" in r2.text


def test_startup_scan_imports_existing_files(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """If GRANTHFLOW_AUTOIMPORT_DIR is set when the app boots, the lifespan handler
    scans it on startup — books appear without any /scan call."""
    from tests.conftest import _fresh_app

    scan_dir = tmp_path / "icloud_books"
    scan_dir.mkdir()
    make_epub(scan_dir / "Boot.epub", title="At Startup", author="Q")

    appmod = _fresh_app(tmp_path, monkeypatch, GRANTHFLOW_AUTOIMPORT_DIR=str(scan_dir))
    with TestClient(appmod.app) as c:
        # startup scan is fired off in a background thread — wait for it before asserting
        appmod.app.state.scan_thread.join(timeout=5)
        r = c.get("/")
    assert "At Startup" in r.text
