# granthflow

A personal EPUB reader with highlights, notes, tags, and Markdown/JSON export.
Designed to live on a homelab behind Tailscale — single user, no auth, all data local.

## Stack

- **Backend**: FastAPI + SQLite (stdlib `sqlite3`)
- **Frontend**: Jinja templates + vanilla JS
- **Reader**: [epub.js](https://github.com/futurepress/epub.js) — vendored under `src/granthflow/static/vendor/` (no CDN)
- **EPUB metadata**: stdlib `zipfile` + `xml.etree`

No external services. No telemetry. No CDN fetches.

## Run locally

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/python -m playwright install chromium   # for the browser tests
.venv/bin/python -m granthflow.app
# → http://127.0.0.1:8000
```

Env vars:

| var                          | default      | meaning                             |
|------------------------------|--------------|-------------------------------------|
| `GRANTHFLOW_DATA_DIR`        | `./data`     | where SQLite + epub files + covers live |
| `GRANTHFLOW_HOST`            | `127.0.0.1`  | bind address                        |
| `GRANTHFLOW_PORT`            | `8000`       | port                                |
| `GRANTHFLOW_AUTOIMPORT_DIR`  | unset        | directory to scan recursively for `.epub` files; new books auto-imported on startup and on `POST /scan` |

## Auto-import from a directory

Set `GRANTHFLOW_AUTOIMPORT_DIR` to any folder containing `.epub` files (e.g., your iCloud
Drive Books folder, a Calibre library, a synced rsync target). On startup, granthflow walks
the tree, dedupes against the library by source filename, and imports any new books. A
"scan library" button appears in the top bar to trigger a re-scan.

iCloud Drive on macOS lives at `~/Library/Mobile Documents/com~apple~CloudDocs/`. iCloud
placeholder stubs (`.<name>.epub.icloud`, files not yet downloaded) are silently skipped.

**macOS TCC**: reading `Mobile Documents/` requires Full Disk Access on the process. Grant
your Terminal (or the python binary) FDA in System Settings → Privacy & Security → Full
Disk Access. The startup scan runs in a background thread, so a permission-denied scan
won't block the server.

## Deploy on the homelab (behind Tailscale)

The app trusts the network — there is no auth. Only expose it on the Tailnet.

```bash
# on the homelab, bind to the Tailscale interface (or 0.0.0.0 if firewalled)
GRANTHFLOW_HOST=0.0.0.0 GRANTHFLOW_PORT=8000 \
  GRANTHFLOW_DATA_DIR=/var/lib/granthflow \
  .venv/bin/python -m granthflow.app
```

Reach it from any Tailnet device at `http://<tailscale-name>:8000`.

A minimal systemd unit:

```ini
[Unit]
Description=granthflow
After=network.target

[Service]
WorkingDirectory=/opt/granthflow
Environment=GRANTHFLOW_HOST=0.0.0.0
Environment=GRANTHFLOW_PORT=8000
Environment=GRANTHFLOW_DATA_DIR=/var/lib/granthflow
ExecStart=/opt/granthflow/.venv/bin/python -m granthflow.app
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## Tests

```bash
.venv/bin/python -m pytest -v
```

14 tests, ~4s total:
- API + EPUB parser unit tests use a synthetic EPUB built in-process (`tests/conftest.py`)
- Headless-Chromium tests (`tests/test_reader_browser.py`, via Playwright) exercise the
  live epub.js reader: round-trip a real range CFI through the API and verify the SVG
  highlight renders on reload, plus end-to-end position-save + resume.

First run after install needs `playwright install chromium` (≈90 MB).

## Layout

```
src/granthflow/
  app.py          # FastAPI routes + lifespan
  db.py           # SQLite schema + helpers
  epub_meta.py    # title/author/cover from .epub (stdlib only)
  models.py       # Pydantic request/response models
  templates/      # library, book detail, reader
  static/
    vendor/       # epub.min.js, jszip.min.js (vendored)
    reader.js     # epub.js glue, highlight popup, location save
    style.css
    reader.css
data/             # epubs, covers, books.db (gitignored)
tests/            # pytest, builds synthetic epubs in tmp_path
```

## Schema

```sql
books          (id, title, author, filename, cover_path, added_at, last_location)
highlights     (id, book_id, cfi, text, note, color, created_at)
highlight_tags (highlight_id, tag)
```

`cfi` is an [EPUB CFI](https://idpf.org/epub/linking/cfi/) — epub.js gives one for each
range selection. We re-render highlights from the stored CFI on next open.

## Routes

| method | path                       | purpose                          |
|--------|----------------------------|----------------------------------|
| GET    | `/`                        | library grid                     |
| POST   | `/upload`                  | upload `.epub`                   |
| GET    | `/book/{id}`               | book detail + highlights         |
| GET    | `/book/{id}/read`          | reader page                      |
| GET    | `/book/{id}/book.epub`     | epub bytes (served to epub.js)   |
| GET    | `/book/{id}/cover`         | cover image                      |
| POST   | `/book/{id}/location`      | save current CFI                 |
| GET    | `/book/{id}/highlights`    | list highlights (JSON)           |
| POST   | `/book/{id}/highlight`     | create highlight                 |
| PATCH  | `/highlight/{id}`          | update color/note/tags           |
| DELETE | `/highlight/{id}`          | remove highlight                 |
| GET    | `/book/{id}/export.md`     | Markdown export                  |
| GET    | `/book/{id}/export.json`   | JSON export                      |
| POST   | `/book/{id}/delete`        | delete book + cover + highlights |
