"""Headless-Chromium tests against the live epub.js reader.

Verifies the parts that can't be checked from the API alone:
- a saved highlight (range CFI) round-trips through epub.js and renders on next open
- reading position is persisted on relocate and resumed on reload
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest

playwright = pytest.importorskip("playwright.sync_api")
from playwright.sync_api import Browser, Page, sync_playwright  # noqa: E402

from tests.conftest import make_rich_epub  # noqa: E402


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture(scope="session")
def browser() -> Iterator[Browser]:
    with sync_playwright() as pw:
        b = pw.chromium.launch(headless=True)
        try:
            yield b
        finally:
            b.close()


PROJECT_SRC = Path(__file__).resolve().parent.parent / "src"


@pytest.fixture
def server(tmp_path: Path) -> Iterator[str]:
    port = _free_port()
    data_dir = tmp_path / "data"
    env = {
        **os.environ,
        "GRANTHFLOW_HOST": "127.0.0.1",
        "GRANTHFLOW_PORT": str(port),
        "GRANTHFLOW_DATA_DIR": str(data_dir),
        # editable install can be silently disabled on macOS when pip's .pth file
        # gets the hidden flag applied by the provenance system; PYTHONPATH is the
        # subprocess-stable fallback.
        "PYTHONPATH": str(PROJECT_SRC) + os.pathsep + os.environ.get("PYTHONPATH", ""),
    }
    proc = subprocess.Popen(
        [sys.executable, "-m", "granthflow.app"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + 15
    ready = False
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read().decode() if proc.stdout else ""
            raise RuntimeError(f"server exited rc={proc.returncode}:\n{out}")
        try:
            if httpx.get(base + "/", timeout=0.5).status_code == 200:
                ready = True
                break
        except Exception:
            time.sleep(0.1)
    if not ready:
        proc.terminate()
        out = proc.stdout.read().decode() if proc.stdout else ""
        raise RuntimeError(f"server did not start in 15s. output:\n{out}")
    try:
        yield base
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def _upload(server: str, epub_path: Path) -> None:
    with open(epub_path, "rb") as f:
        r = httpx.post(
            server + "/upload",
            files={"file": (epub_path.name, f, "application/epub+zip")},
            follow_redirects=False,
        )
    assert r.status_code == 303, r.text


def _open_reader(browser: Browser, url: str) -> Page:
    ctx = browser.new_context(viewport={"width": 1000, "height": 800})
    page = ctx.new_page()
    msgs: list[str] = []
    page.on("console", lambda m: msgs.append(f"[console.{m.type}] {m.text}"))
    page.on("pageerror", lambda e: msgs.append(f"[pageerror] {e}"))
    page.on(
        "requestfailed",
        lambda r: msgs.append(f"[reqfail] {r.method} {r.url}: {r.failure}"),
    )
    page.on(
        "response",
        lambda r: msgs.append(f"[resp {r.status}] {r.url}") if r.status >= 400 else None,
    )
    page.goto(url)
    try:
        page.wait_for_function("() => window.__readerReady === true", timeout=15000)
    except Exception:
        raise AssertionError("reader not ready in 15s. browser log:\n" + "\n".join(msgs))
    return page


def test_saved_highlight_renders_on_reload(browser: Browser, server: str, tmp_path: Path) -> None:
    """End-to-end CFI roundtrip: epub.js → server → epub.js again."""
    epub_path = make_rich_epub(tmp_path / "rich.epub")
    _upload(server, epub_path)

    page = _open_reader(browser, f"{server}/book/1/read")

    # Build a real range CFI from a paragraph in the rendered iframe
    cfi: str = page.evaluate(
        """() => {
            const contents = window.rendition.getContents()[0];
            const fdoc = contents.document;
            const p = fdoc.querySelector('p');
            if (!p || !p.firstChild) return null;
            const range = fdoc.createRange();
            range.setStart(p.firstChild, 0);
            range.setEnd(p.firstChild, Math.min(40, p.firstChild.length));
            return contents.cfiFromRange(range);
        }"""
    )
    assert cfi and cfi.startswith("epubcfi("), f"unexpected cfi: {cfi!r}"

    # Save via API (the popup wraps this exact call — exercising the popup
    # adds iframe-event flake without proving anything more)
    selected_text = "first paragraph fragment"
    r = httpx.post(
        f"{server}/book/1/highlight",
        json={"cfi": cfi, "text": selected_text, "color": "yellow", "tags": []},
    )
    assert r.status_code == 200, r.text

    # Reload and let the reader re-fetch and re-render annotations
    page.reload()
    page.wait_for_function("() => window.__readerReady === true", timeout=15000)
    page.wait_for_function("() => window.__hlLoaded === true", timeout=10000)

    annotation_count: int = page.evaluate(
        "() => Object.keys(window.rendition.annotations._annotations || {}).length"
    )
    assert annotation_count >= 1, "highlight was not re-registered with epub.js on reload"

    # epub.js renders the highlight as <g class="hl-{color}"><rect/></g> in the
    # parent document's overlay SVG (not in the iframe).
    page.wait_for_function(
        "() => document.querySelectorAll('g.hl-yellow > rect').length > 0",
        timeout=5000,
    )
    rect = page.evaluate(
        """() => {
            const r = document.querySelector('g.hl-yellow > rect');
            return r ? { width: +r.getAttribute('width'), height: +r.getAttribute('height') } : null;
        }"""
    )
    assert rect is not None and rect["width"] > 0 and rect["height"] > 0, (
        f"highlight rendered but has no visible area: {rect}"
    )

    page.context.close()


def test_peel_animation_runs_and_advances(browser: Browser, server: str, tmp_path: Path) -> None:
    """Click the next button; verify the WebGL peel canvas materializes, animates,
    removes itself, and the rendition has advanced."""
    epub_path = make_rich_epub(tmp_path / "rich.epub")
    _upload(server, epub_path)

    page = _open_reader(browser, f"{server}/book/1/read")

    # wait for the initial html2canvas snapshot to land (relocated → 80ms → html2canvas)
    page.wait_for_function(
        "() => document.querySelector('.viewer-frame') !== null", timeout=5000
    )
    page.wait_for_timeout(1500)

    initial_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")

    page.click("#next")

    # WebGL canvas appears synchronously after click
    page.wait_for_selector(".peel-canvas", timeout=2000)
    has_gl: bool = page.evaluate(
        "() => { const c = document.querySelector('.peel-canvas'); "
        "return !!(c && (c.getContext('webgl') || c.getContext('experimental-webgl'))); }"
    )
    assert has_gl, "peel-canvas was created but has no WebGL context"

    # canvas removes itself when the RAF animation completes (~700ms)
    page.wait_for_function(
        "() => document.querySelectorAll('.peel-canvas').length === 0", timeout=4000
    )

    advanced_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")
    assert advanced_cfi != initial_cfi, "peel animation completed but rendition did not advance"

    page.context.close()


def test_drag_from_corner_commits_turn(browser: Browser, server: str, tmp_path: Path) -> None:
    """Drag from the top-right corner zone past the commit threshold; verify the WebGL
    canvas appears, animates, removes itself, and the page advances."""
    epub_path = make_rich_epub(tmp_path / "rich.epub")
    _upload(server, epub_path)

    page = _open_reader(browser, f"{server}/book/1/read")
    page.wait_for_timeout(1500)  # let initial html2canvas snapshot land

    initial_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")

    # locate the top-right corner drag zone
    zone = page.locator(".drag-tr")
    box = zone.bounding_box()
    assert box is not None, "drag-tr zone not found"

    viewer = page.locator(".viewer-frame")
    vbox = viewer.bounding_box()
    assert vbox is not None

    # Press inside the corner zone, drag diagonally toward the bottom-left corner of
    # the viewer (well past the 40% commit threshold), then release.
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.mouse.move(
        vbox["x"] + 20,
        vbox["y"] + vbox["height"] - 20,
        steps=10,
    )
    # mid-drag: peel canvas should be live AND the rendition should have already
    # advanced to the next page (page-stack illusion: iframe shows next page
    # behind the curl, not after release)
    assert page.locator(".peel-canvas").count() == 1, "peel canvas not active mid-drag"
    page.wait_for_function(
        f"() => window.rendition.currentLocation().start.cfi !== {initial_cfi!r}",
        timeout=2000,
    )

    page.mouse.up()

    page.wait_for_function(
        "() => document.querySelectorAll('.peel-canvas').length === 0", timeout=3000
    )

    advanced_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")
    assert advanced_cfi != initial_cfi, "drag past threshold did not advance the rendition"

    page.context.close()


def test_drag_reverts_when_below_threshold(browser: Browser, server: str, tmp_path: Path) -> None:
    """Drag from the corner zone but release before the commit threshold; verify the
    rendition ends back on the original page (drag advances the iframe, revert path
    must un-advance it)."""
    epub_path = make_rich_epub(tmp_path / "rich.epub")
    _upload(server, epub_path)

    page = _open_reader(browser, f"{server}/book/1/read")
    page.wait_for_timeout(1500)

    initial_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")

    zone = page.locator(".drag-tr")
    box = zone.bounding_box()
    assert box is not None

    # short drag — well under the 40% commit threshold
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.mouse.move(
        box["x"] - 20,
        box["y"] + box["height"] + 20,
        steps=5,
    )
    page.mouse.up()

    page.wait_for_function(
        "() => document.querySelectorAll('.peel-canvas').length === 0", timeout=3000
    )
    # let the post-revert rendition.prev relocate settle
    page.wait_for_timeout(300)

    final_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")
    assert final_cfi == initial_cfi, (
        f"revert failed: drag below threshold should not advance the page, "
        f"but cfi went {initial_cfi!r} → {final_cfi!r}"
    )

    page.context.close()


def test_reading_position_saves_and_resumes(browser: Browser, server: str, tmp_path: Path) -> None:
    epub_path = make_rich_epub(tmp_path / "rich.epub")
    _upload(server, epub_path)

    page = _open_reader(browser, f"{server}/book/1/read")
    initial_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")

    # advance a couple of pages to land somewhere different
    page.evaluate("() => window.rendition.next()")
    page.wait_for_timeout(300)
    page.evaluate("() => window.rendition.next()")
    page.wait_for_timeout(300)

    advanced_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")
    assert advanced_cfi != initial_cfi, "rendition.next() did not advance the location"

    # debounced save in reader.js is 800ms — wait it out
    page.wait_for_timeout(1500)

    # the server-rendered reader page should now embed the saved cfi
    reader_html = httpx.get(f"{server}/book/1/read").text
    assert advanced_cfi in reader_html, "server did not persist the latest reading location"

    # reload and check rendition opens at the saved location
    page.reload()
    page.wait_for_function("() => window.__readerReady === true", timeout=15000)
    resumed_cfi: str = page.evaluate("() => window.rendition.currentLocation().start.cfi")
    assert resumed_cfi == advanced_cfi, (
        f"resume failed: expected {advanced_cfi!r}, got {resumed_cfi!r}"
    )

    page.context.close()
