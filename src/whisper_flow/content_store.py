from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from whisper_flow.config import APP_DIR

CONTENT_DB_PATH = APP_DIR / "content.sqlite3"


@dataclass
class DictionaryEntry:
    id: int | None = None
    trigger: str = ""
    replacement: str = ""
    created_at: str = ""
    updated_at: str = ""


@dataclass
class SnippetEntry:
    id: int | None = None
    title: str = ""
    body: str = ""
    shortcut: str = ""
    created_at: str = ""
    updated_at: str = ""


@dataclass
class StyleProfile:
    id: int | None = None
    name: str = ""
    instructions: str = ""
    is_default: bool = False
    created_at: str = ""
    updated_at: str = ""


@dataclass
class NoteEntry:
    id: int | None = None
    title: str = ""
    body: str = ""
    pinned: bool = False
    created_at: str = ""
    updated_at: str = ""


class ContentStore:
    def __init__(self, db_path: Path = CONTENT_DB_PATH) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(str(self.db_path))
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout = 5000")
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS dictionary_entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    trigger TEXT NOT NULL,
                    replacement TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS snippets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    shortcut TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS style_profiles (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    instructions TEXT NOT NULL,
                    is_default INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS notes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_dictionary_trigger_unique
                ON dictionary_entries (trigger)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_snippets_title
                ON snippets (title)
                """
            )
            conn.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_snippets_shortcut_unique
                ON snippets (shortcut)
                WHERE shortcut IS NOT NULL AND shortcut != ''
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_notes_updated_at
                ON notes (updated_at DESC)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_notes_pinned
                ON notes (pinned DESC, updated_at DESC)
                """
            )

    # Dictionary
    def list_dictionary(self, query: str, limit: int, offset: int) -> list[DictionaryEntry]:
        q = query.strip()
        with self._connect() as conn:
            if q:
                rows = conn.execute(
                    """
                    SELECT id, trigger, replacement, created_at, updated_at
                    FROM dictionary_entries
                    WHERE trigger LIKE ? OR replacement LIKE ?
                    ORDER BY updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (f"%{q}%", f"%{q}%", limit, offset),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, trigger, replacement, created_at, updated_at
                    FROM dictionary_entries
                    ORDER BY updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()

        return [
            DictionaryEntry(
                id=int(row[0]),
                trigger=str(row[1]),
                replacement=str(row[2]),
                created_at=str(row[3]),
                updated_at=str(row[4]),
            )
            for row in rows
        ]

    def upsert_dictionary(self, entry: DictionaryEntry) -> int:
        now = self._now_iso()
        with self._connect() as conn:
            if entry.id is None:
                cur = conn.execute(
                    """
                    INSERT INTO dictionary_entries (trigger, replacement, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    (entry.trigger.strip(), entry.replacement.strip(), now, now),
                )
                return int(cur.lastrowid)

            conn.execute(
                """
                UPDATE dictionary_entries
                SET trigger = ?, replacement = ?, updated_at = ?
                WHERE id = ?
                """,
                (entry.trigger.strip(), entry.replacement.strip(), now, entry.id),
            )
            return int(entry.id)

    def delete_dictionary(self, entry_id: int) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM dictionary_entries WHERE id = ?", (entry_id,))

    # Snippets
    def list_snippets(self, query: str, limit: int, offset: int) -> list[SnippetEntry]:
        q = query.strip()
        with self._connect() as conn:
            if q:
                rows = conn.execute(
                    """
                    SELECT id, title, body, shortcut, created_at, updated_at
                    FROM snippets
                    WHERE title LIKE ? OR body LIKE ? OR shortcut LIKE ?
                    ORDER BY updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (f"%{q}%", f"%{q}%", f"%{q}%", limit, offset),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, title, body, shortcut, created_at, updated_at
                    FROM snippets
                    ORDER BY updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()

        return [
            SnippetEntry(
                id=int(row[0]),
                title=str(row[1]),
                body=str(row[2]),
                shortcut=str(row[3] or ""),
                created_at=str(row[4]),
                updated_at=str(row[5]),
            )
            for row in rows
        ]

    def upsert_snippet(self, entry: SnippetEntry) -> int:
        now = self._now_iso()
        shortcut = entry.shortcut.strip()
        with self._connect() as conn:
            if entry.id is None:
                cur = conn.execute(
                    """
                    INSERT INTO snippets (title, body, shortcut, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (entry.title.strip(), entry.body.strip(), shortcut, now, now),
                )
                return int(cur.lastrowid)

            conn.execute(
                """
                UPDATE snippets
                SET title = ?, body = ?, shortcut = ?, updated_at = ?
                WHERE id = ?
                """,
                (entry.title.strip(), entry.body.strip(), shortcut, now, entry.id),
            )
            return int(entry.id)

    def delete_snippet(self, entry_id: int) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM snippets WHERE id = ?", (entry_id,))

    # Styles
    def list_styles(self, query: str, limit: int, offset: int) -> list[StyleProfile]:
        q = query.strip()
        with self._connect() as conn:
            if q:
                rows = conn.execute(
                    """
                    SELECT id, name, instructions, is_default, created_at, updated_at
                    FROM style_profiles
                    WHERE name LIKE ? OR instructions LIKE ?
                    ORDER BY is_default DESC, updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (f"%{q}%", f"%{q}%", limit, offset),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, name, instructions, is_default, created_at, updated_at
                    FROM style_profiles
                    ORDER BY is_default DESC, updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()

        return [
            StyleProfile(
                id=int(row[0]),
                name=str(row[1]),
                instructions=str(row[2]),
                is_default=bool(int(row[3])),
                created_at=str(row[4]),
                updated_at=str(row[5]),
            )
            for row in rows
        ]

    def upsert_style(self, entry: StyleProfile) -> int:
        now = self._now_iso()
        with self._connect() as conn:
            if entry.id is None:
                cur = conn.execute(
                    """
                    INSERT INTO style_profiles (name, instructions, is_default, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (entry.name.strip(), entry.instructions.strip(), int(entry.is_default), now, now),
                )
                style_id = int(cur.lastrowid)
                if entry.is_default:
                    self._set_default_style_in_tx(conn, style_id)
                return style_id

            conn.execute(
                """
                UPDATE style_profiles
                SET name = ?, instructions = ?, is_default = ?, updated_at = ?
                WHERE id = ?
                """,
                (entry.name.strip(), entry.instructions.strip(), int(entry.is_default), now, entry.id),
            )
            if entry.is_default:
                self._set_default_style_in_tx(conn, int(entry.id))
            return int(entry.id)

    def delete_style(self, entry_id: int) -> None:
        with self._connect() as conn:
            was_default = conn.execute(
                "SELECT is_default FROM style_profiles WHERE id = ?", (entry_id,)
            ).fetchone()
            conn.execute("DELETE FROM style_profiles WHERE id = ?", (entry_id,))
            if was_default and int(was_default[0]) == 1:
                row = conn.execute(
                    "SELECT id FROM style_profiles ORDER BY updated_at DESC, id DESC LIMIT 1"
                ).fetchone()
                if row:
                    self._set_default_style_in_tx(conn, int(row[0]))

    def set_default_style(self, style_id: int) -> None:
        with self._connect() as conn:
            self._set_default_style_in_tx(conn, style_id)

    @staticmethod
    def _set_default_style_in_tx(conn: sqlite3.Connection, style_id: int) -> None:
        conn.execute("UPDATE style_profiles SET is_default = 0")
        conn.execute("UPDATE style_profiles SET is_default = 1 WHERE id = ?", (style_id,))

    # Notes
    def list_notes(self, query: str, limit: int, offset: int) -> list[NoteEntry]:
        q = query.strip()
        with self._connect() as conn:
            if q:
                rows = conn.execute(
                    """
                    SELECT id, title, body, pinned, created_at, updated_at
                    FROM notes
                    WHERE title LIKE ? OR body LIKE ?
                    ORDER BY pinned DESC, updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (f"%{q}%", f"%{q}%", limit, offset),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, title, body, pinned, created_at, updated_at
                    FROM notes
                    ORDER BY pinned DESC, updated_at DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()

        return [
            NoteEntry(
                id=int(row[0]),
                title=str(row[1]),
                body=str(row[2]),
                pinned=bool(int(row[3])),
                created_at=str(row[4]),
                updated_at=str(row[5]),
            )
            for row in rows
        ]

    def upsert_note(self, entry: NoteEntry) -> int:
        now = self._now_iso()
        with self._connect() as conn:
            if entry.id is None:
                cur = conn.execute(
                    """
                    INSERT INTO notes (title, body, pinned, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (entry.title.strip(), entry.body.strip(), int(entry.pinned), now, now),
                )
                return int(cur.lastrowid)

            conn.execute(
                """
                UPDATE notes
                SET title = ?, body = ?, pinned = ?, updated_at = ?
                WHERE id = ?
                """,
                (entry.title.strip(), entry.body.strip(), int(entry.pinned), now, entry.id),
            )
            return int(entry.id)

    def delete_note(self, note_id: int) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM notes WHERE id = ?", (note_id,))

    def stats(self) -> dict[str, int]:
        with self._connect() as conn:
            dictionary_count = int(conn.execute("SELECT COUNT(*) FROM dictionary_entries").fetchone()[0])
            snippet_count = int(conn.execute("SELECT COUNT(*) FROM snippets").fetchone()[0])
            style_count = int(conn.execute("SELECT COUNT(*) FROM style_profiles").fetchone()[0])
            note_count = int(conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0])

        return {
            "dictionary_count": dictionary_count,
            "snippet_count": snippet_count,
            "style_count": style_count,
            "note_count": note_count,
            "total_count": dictionary_count + snippet_count + style_count + note_count,
        }


__all__ = [
    "CONTENT_DB_PATH",
    "ContentStore",
    "DictionaryEntry",
    "SnippetEntry",
    "StyleProfile",
    "NoteEntry",
]
