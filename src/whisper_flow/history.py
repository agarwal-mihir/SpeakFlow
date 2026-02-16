from __future__ import annotations

import sqlite3
from collections import Counter
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from whisper_flow.config import APP_DIR

HISTORY_DB_PATH = APP_DIR / "history.sqlite3"


@dataclass
class HistoryRecord:
    id: int
    created_at: str
    raw_text: str
    final_text: str
    detected_language: str | None
    confidence: float | None
    output_mode: str
    source_app: str | None


class TranscriptHistoryStore:
    def __init__(self, db_path: Path = HISTORY_DB_PATH) -> None:
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

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS transcripts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at TEXT NOT NULL,
                    raw_text TEXT NOT NULL,
                    final_text TEXT NOT NULL,
                    detected_language TEXT,
                    confidence REAL,
                    output_mode TEXT NOT NULL,
                    source_app TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_transcripts_created_at
                ON transcripts (created_at DESC)
                """
            )

    def add(
        self,
        raw_text: str,
        final_text: str,
        detected_language: str | None,
        confidence: float | None,
        output_mode: str,
        source_app: str | None,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO transcripts (
                    created_at,
                    raw_text,
                    final_text,
                    detected_language,
                    confidence,
                    output_mode,
                    source_app
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    now,
                    raw_text,
                    final_text,
                    detected_language,
                    confidence,
                    output_mode,
                    source_app,
                ),
            )

    def recent(self, limit: int = 200) -> list[HistoryRecord]:
        return self.search(query="", limit=limit, offset=0)

    def search(self, query: str, limit: int = 200, offset: int = 0) -> list[HistoryRecord]:
        like = f"%{query.strip()}%"
        with self._connect() as conn:
            if query.strip():
                rows = conn.execute(
                    """
                    SELECT id, created_at, raw_text, final_text, detected_language, confidence, output_mode, source_app
                    FROM transcripts
                    WHERE raw_text LIKE ? OR final_text LIKE ? OR COALESCE(source_app, '') LIKE ?
                    ORDER BY id DESC
                    LIMIT ?
                    OFFSET ?
                    """,
                    (like, like, like, limit, offset),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, created_at, raw_text, final_text, detected_language, confidence, output_mode, source_app
                    FROM transcripts
                    ORDER BY id DESC
                    LIMIT ?
                    OFFSET ?
                    """,
                    (limit, offset),
                ).fetchall()

        return [
            HistoryRecord(
                id=int(row[0]),
                created_at=row[1],
                raw_text=row[2],
                final_text=row[3],
                detected_language=row[4],
                confidence=row[5],
                output_mode=row[6],
                source_app=row[7],
            )
            for row in rows
        ]

    def delete(self, transcript_id: int) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM transcripts WHERE id = ?", (transcript_id,))

    def stats(self) -> dict[str, str | int]:
        with self._connect() as conn:
            total_row = conn.execute("SELECT COUNT(*) FROM transcripts").fetchone()
            latest_row = conn.execute(
                """
                SELECT created_at, source_app
                FROM transcripts
                ORDER BY id DESC
                LIMIT 1
                """
            ).fetchone()
            app_rows = conn.execute(
                """
                SELECT COALESCE(source_app, 'Unknown') AS app_name, COUNT(*)
                FROM transcripts
                GROUP BY app_name
                """
            ).fetchall()

        total = int(total_row[0] if total_row else 0)
        latest_created_at = str(latest_row[0]) if latest_row else ""
        latest_source_app = str(latest_row[1]) if latest_row and latest_row[1] else "Unknown"

        if app_rows:
            app_counter = Counter({str(row[0]): int(row[1]) for row in app_rows})
            top_app, top_count = app_counter.most_common(1)[0]
        else:
            top_app, top_count = "Unknown", 0

        return {
            "total_count": total,
            "latest_created_at": latest_created_at,
            "latest_source_app": latest_source_app,
            "top_source_app": top_app,
            "top_source_app_count": top_count,
        }

    def total_count(self) -> int:
        with self._connect() as conn:
            row = conn.execute("SELECT COUNT(*) FROM transcripts").fetchone()
        return int(row[0] if row else 0)


__all__ = ["HISTORY_DB_PATH", "HistoryRecord", "TranscriptHistoryStore"]
