from __future__ import annotations

import os
import sqlite3
import unicodedata
import uuid
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import (
    FileResponse,
    HTMLResponse,
    JSONResponse,
    PlainTextResponse,
    RedirectResponse,
    Response,
)
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import db, epub_meta
from .models import HighlightCreate, HighlightUpdate, HighlightOut, LocationUpdate

PKG_DIR = Path(__file__).parent
DATA_DIR = Path(os.environ.get("GRANTHFLOW_DATA_DIR", "data")).resolve()
FILES_DIR = DATA_DIR / "files"
COVERS_DIR = DATA_DIR / "covers"
DB_PATH = DATA_DIR / "books.db"

_autoimport_env = os.environ.get("GRANTHFLOW_AUTOIMPORT_DIR")
AUTOIMPORT_DIR: Path | None = Path(_autoimport_env).expanduser() if _autoimport_env else None

EXT_TO_MIME = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
}


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    FILES_DIR.mkdir(parents=True, exist_ok=True)
    COVERS_DIR.mkdir(parents=True, exist_ok=True)
    conn = db.connect(DB_PATH)
    db.init_db(conn)
    app.state.conn = conn
    if AUTOIMPORT_DIR is not None:
        # Run the scan in a background thread. iCloud paths can be slow (large trees,
        # placeholder downloads, or TCC-blocked syscalls that hang) — we never want
        # startup to depend on it. The /scan endpoint provides a manual retry.
        import threading

        scan_path = AUTOIMPORT_DIR

        def _bg_scan() -> None:
            try:
                scan_directory(conn, scan_path)
            except Exception:
                pass
        t = threading.Thread(target=_bg_scan, daemon=True)
        t.start()
        app.state.scan_thread = t
    try:
        yield
    finally:
        conn.close()


app = FastAPI(title="granthflow", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=PKG_DIR / "static"), name="static")
templates = Jinja2Templates(directory=PKG_DIR / "templates")
templates.env.globals["autoimport_enabled"] = AUTOIMPORT_DIR is not None


def conn(request: Request) -> sqlite3.Connection:
    return request.app.state.conn  # type: ignore[no-any-return]


def _safe_filename(name: str) -> str:
    """Strip path separators and unicode oddities. Caller still prefixes a uuid."""
    name = unicodedata.normalize("NFKD", name)
    name = "".join(c for c in name if c.isalnum() or c in "._- ")
    name = name.strip().replace(" ", "_")
    return name or "book.epub"


def _book_or_404(c: sqlite3.Connection, book_id: int) -> sqlite3.Row:
    row = c.execute("SELECT * FROM books WHERE id = ?", (book_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="book not found")
    return row


def _highlight_or_404(c: sqlite3.Connection, hl_id: int) -> sqlite3.Row:
    row = c.execute("SELECT * FROM highlights WHERE id = ?", (hl_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="highlight not found")
    return row


def _tags_for(c: sqlite3.Connection, hl_id: int) -> list[str]:
    rows = c.execute(
        "SELECT tag FROM highlight_tags WHERE highlight_id = ? ORDER BY tag", (hl_id,)
    ).fetchall()
    return [r["tag"] for r in rows]


def _replace_tags(c: sqlite3.Connection, hl_id: int, tags: list[str]) -> None:
    c.execute("DELETE FROM highlight_tags WHERE highlight_id = ?", (hl_id,))
    cleaned = sorted({t.strip() for t in tags if t.strip()})
    if cleaned:
        c.executemany(
            "INSERT INTO highlight_tags (highlight_id, tag) VALUES (?, ?)",
            [(hl_id, t) for t in cleaned],
        )


def _highlight_to_dict(c: sqlite3.Connection, row: sqlite3.Row) -> dict:
    return HighlightOut(
        id=row["id"],
        book_id=row["book_id"],
        cfi=row["cfi"],
        text=row["text"],
        note=row["note"],
        color=row["color"],
        created_at=row["created_at"],
        tags=_tags_for(c, row["id"]),
    ).model_dump()


# ---------- import helpers ----------


def _import_epub_from_path(c: sqlite3.Connection, src: Path) -> bool:
    """Copy an EPUB at `src` into the library, parse metadata, insert a book row.

    Returns True if a new book was added; False if it was already in the library
    (deduped by source basename) or could not be parsed.
    """
    name = src.name
    if not name.lower().endswith(".epub"):
        return False
    safe = _safe_filename(name)
    # stored filenames are formatted as f"{uuid32}_{safe}", so a like-pattern
    # `%_<safe>` matches any prior import of the same source basename
    existing = c.execute(
        "SELECT 1 FROM books WHERE filename LIKE ?", (f"%_{safe}",)
    ).fetchone()
    if existing:
        return False

    stored = f"{uuid.uuid4().hex}_{safe}"
    target = FILES_DIR / stored
    try:
        target.write_bytes(src.read_bytes())
    except OSError:
        return False

    try:
        meta = epub_meta.parse(target)
    except Exception:
        target.unlink(missing_ok=True)
        return False

    cover_rel: str | None = None
    if meta.cover_bytes:
        ext = meta.cover_ext or ".jpg"
        cover_rel = f"{Path(stored).stem}{ext}"
        (COVERS_DIR / cover_rel).write_bytes(meta.cover_bytes)

    with db.tx(c):
        c.execute(
            "INSERT INTO books (title, author, filename, cover_path) VALUES (?, ?, ?, ?)",
            (meta.title, meta.author, stored, cover_rel),
        )
    return True


def scan_directory(c: sqlite3.Connection, dir_path: Path) -> dict[str, int]:
    """Walk dir_path recursively for .epub files; import any not already in the library.

    iCloud placeholder stubs are named `.<original>.epub.icloud` (dotfile + .icloud
    suffix) and don't match `*.epub`, so rglob skips them automatically.
    """
    if not dir_path.is_dir():
        return {"imported": 0, "skipped": 0}
    imported = 0
    skipped = 0
    for p in dir_path.rglob("*.epub"):
        if not p.is_file():
            continue
        if _import_epub_from_path(c, p):
            imported += 1
        else:
            skipped += 1
    return {"imported": imported, "skipped": skipped}


@app.post("/scan")
def scan(request: Request) -> RedirectResponse:
    if AUTOIMPORT_DIR is None:
        raise HTTPException(
            status_code=400, detail="GRANTHFLOW_AUTOIMPORT_DIR is not configured"
        )
    scan_directory(conn(request), AUTOIMPORT_DIR)
    return RedirectResponse(url="/", status_code=303)


# ---------- pages ----------


@app.get("/", response_class=HTMLResponse)
def library(request: Request) -> HTMLResponse:
    rows = conn(request).execute(
        "SELECT id, title, author, cover_path FROM books ORDER BY added_at DESC"
    ).fetchall()
    return templates.TemplateResponse(
        request, "library.html", {"books": rows}
    )


@app.get("/book/{book_id}", response_class=HTMLResponse)
def book_detail(book_id: int, request: Request) -> HTMLResponse:
    c = conn(request)
    book = _book_or_404(c, book_id)
    hl_rows = c.execute(
        "SELECT * FROM highlights WHERE book_id = ? ORDER BY created_at DESC", (book_id,)
    ).fetchall()
    highlights = [_highlight_to_dict(c, r) for r in hl_rows]
    return templates.TemplateResponse(
        request, "book.html", {"book": book, "highlights": highlights}
    )


@app.get("/book/{book_id}/read", response_class=HTMLResponse)
def reader(book_id: int, request: Request) -> HTMLResponse:
    book = _book_or_404(conn(request), book_id)
    return templates.TemplateResponse(request, "reader.html", {"book": book})


# ---------- file/cover ----------


@app.get("/book/{book_id}/book.epub")
def book_file(book_id: int, request: Request) -> FileResponse:
    book = _book_or_404(conn(request), book_id)
    path = FILES_DIR / book["filename"]
    if not path.is_file():
        raise HTTPException(status_code=404, detail="file missing on disk")
    return FileResponse(path, media_type="application/epub+zip", filename=book["filename"])


@app.get("/book/{book_id}/cover")
def book_cover(book_id: int, request: Request) -> Response:
    book = _book_or_404(conn(request), book_id)
    if not book["cover_path"]:
        raise HTTPException(status_code=404, detail="no cover")
    path = COVERS_DIR / book["cover_path"]
    if not path.is_file():
        raise HTTPException(status_code=404, detail="cover missing on disk")
    media = EXT_TO_MIME.get(path.suffix.lower(), "application/octet-stream")
    return FileResponse(path, media_type=media)


# ---------- upload / delete book ----------


@app.post("/upload")
async def upload(request: Request, file: UploadFile = File(...)) -> RedirectResponse:
    if not file.filename or not file.filename.lower().endswith(".epub"):
        raise HTTPException(status_code=400, detail="only .epub files are accepted")

    safe = _safe_filename(file.filename)
    stored_name = f"{uuid.uuid4().hex}_{safe}"
    target = FILES_DIR / stored_name
    data = await file.read()
    target.write_bytes(data)

    try:
        meta = epub_meta.parse(target)
    except Exception as e:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"invalid epub: {e}") from e

    cover_rel: str | None = None
    if meta.cover_bytes:
        # name cover after the stored file so it's traceable; book_id not yet known
        ext = meta.cover_ext or ".jpg"
        cover_rel = f"{Path(stored_name).stem}{ext}"
        (COVERS_DIR / cover_rel).write_bytes(meta.cover_bytes)

    c = conn(request)
    with db.tx(c):
        c.execute(
            "INSERT INTO books (title, author, filename, cover_path) VALUES (?, ?, ?, ?)",
            (meta.title, meta.author, stored_name, cover_rel),
        )

    return RedirectResponse(url="/", status_code=303)


@app.post("/book/{book_id}/delete")
def delete_book(book_id: int, request: Request) -> RedirectResponse:
    c = conn(request)
    book = _book_or_404(c, book_id)
    with db.tx(c):
        c.execute("DELETE FROM books WHERE id = ?", (book_id,))
    (FILES_DIR / book["filename"]).unlink(missing_ok=True)
    if book["cover_path"]:
        (COVERS_DIR / book["cover_path"]).unlink(missing_ok=True)
    return RedirectResponse(url="/", status_code=303)


# ---------- reading position ----------


@app.post("/book/{book_id}/location")
def save_location(book_id: int, body: LocationUpdate, request: Request) -> dict:
    c = conn(request)
    _book_or_404(c, book_id)
    with db.tx(c):
        c.execute("UPDATE books SET last_location = ? WHERE id = ?", (body.cfi, book_id))
    return {"ok": True}


# ---------- highlights ----------


@app.get("/book/{book_id}/highlights")
def list_highlights(book_id: int, request: Request) -> list[dict]:
    c = conn(request)
    _book_or_404(c, book_id)
    rows = c.execute(
        "SELECT * FROM highlights WHERE book_id = ? ORDER BY created_at", (book_id,)
    ).fetchall()
    return [_highlight_to_dict(c, r) for r in rows]


@app.post("/book/{book_id}/highlight")
def create_highlight(book_id: int, body: HighlightCreate, request: Request) -> dict:
    c = conn(request)
    _book_or_404(c, book_id)
    with db.tx(c):
        cur = c.execute(
            "INSERT INTO highlights (book_id, cfi, text, note, color) VALUES (?, ?, ?, ?, ?)",
            (book_id, body.cfi, body.text, body.note, body.color),
        )
        hl_id = int(cur.lastrowid or 0)
        _replace_tags(c, hl_id, body.tags)
    row = _highlight_or_404(c, hl_id)
    return _highlight_to_dict(c, row)


@app.patch("/highlight/{hl_id}")
def update_highlight(hl_id: int, body: HighlightUpdate, request: Request) -> dict:
    c = conn(request)
    row = _highlight_or_404(c, hl_id)
    with db.tx(c):
        if body.color is not None:
            c.execute("UPDATE highlights SET color = ? WHERE id = ?", (body.color, hl_id))
        if body.note is not None:
            c.execute("UPDATE highlights SET note = ? WHERE id = ?", (body.note, hl_id))
        if body.tags is not None:
            _replace_tags(c, hl_id, body.tags)
    row = _highlight_or_404(c, hl_id)
    return _highlight_to_dict(c, row)


@app.delete("/highlight/{hl_id}")
def delete_highlight(hl_id: int, request: Request) -> dict:
    c = conn(request)
    _highlight_or_404(c, hl_id)
    with db.tx(c):
        c.execute("DELETE FROM highlights WHERE id = ?", (hl_id,))
    return {"ok": True}


# ---------- exports ----------


@app.get("/book/{book_id}/export.md", response_class=PlainTextResponse)
def export_markdown(book_id: int, request: Request) -> PlainTextResponse:
    c = conn(request)
    book = _book_or_404(c, book_id)
    rows = c.execute(
        "SELECT * FROM highlights WHERE book_id = ? ORDER BY created_at", (book_id,)
    ).fetchall()

    lines: list[str] = [f"# {book['title']}"]
    if book["author"]:
        lines.append(f"_{book['author']}_")
    lines.append("")
    for r in rows:
        lines.append(f"> {r['text'].strip()}")
        meta_bits = [r["color"]]
        tags = _tags_for(c, r["id"])
        if tags:
            meta_bits.append(" ".join(f"#{t}" for t in tags))
        meta_bits.append(r["created_at"])
        lines.append("")
        lines.append(f"_{' · '.join(meta_bits)}_")
        if r["note"]:
            lines.append("")
            lines.append(r["note"])
        lines.append("")
        lines.append("---")
        lines.append("")
    return PlainTextResponse("\n".join(lines), media_type="text/markdown; charset=utf-8")


@app.get("/book/{book_id}/export.json")
def export_json(book_id: int, request: Request) -> JSONResponse:
    c = conn(request)
    book = _book_or_404(c, book_id)
    rows = c.execute(
        "SELECT * FROM highlights WHERE book_id = ? ORDER BY created_at", (book_id,)
    ).fetchall()
    payload = {
        "book": {"id": book["id"], "title": book["title"], "author": book["author"]},
        "highlights": [_highlight_to_dict(c, r) for r in rows],
    }
    return JSONResponse(
        payload,
        headers={"Content-Disposition": f'attachment; filename="book-{book_id}.json"'},
    )


def main() -> None:
    import uvicorn

    host = os.environ.get("GRANTHFLOW_HOST", "127.0.0.1")
    port = int(os.environ.get("GRANTHFLOW_PORT", "8000"))
    uvicorn.run("granthflow.app:app", host=host, port=port, reload=False)


if __name__ == "__main__":
    main()
