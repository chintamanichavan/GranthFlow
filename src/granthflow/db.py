from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Generator
from contextlib import contextmanager

SCHEMA = """
CREATE TABLE IF NOT EXISTS books (
    id            INTEGER PRIMARY KEY,
    title         TEXT NOT NULL,
    author        TEXT,
    filename      TEXT NOT NULL UNIQUE,
    cover_path    TEXT,
    added_at      TEXT NOT NULL DEFAULT (datetime('now')),
    last_location TEXT
);

CREATE TABLE IF NOT EXISTS highlights (
    id         INTEGER PRIMARY KEY,
    book_id    INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    cfi        TEXT NOT NULL,
    text       TEXT NOT NULL,
    note       TEXT,
    color      TEXT NOT NULL DEFAULT 'yellow',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS ix_highlights_book ON highlights(book_id);

CREATE TABLE IF NOT EXISTS highlight_tags (
    highlight_id INTEGER NOT NULL REFERENCES highlights(id) ON DELETE CASCADE,
    tag          TEXT NOT NULL,
    PRIMARY KEY (highlight_id, tag)
);
CREATE INDEX IF NOT EXISTS ix_tags_tag ON highlight_tags(tag);
"""


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


@contextmanager
def tx(conn: sqlite3.Connection) -> Generator[sqlite3.Connection, None, None]:
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
