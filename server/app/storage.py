"""SQLite store for study events (POST /log) and model call timings."""

import csv
import io
import json
import sqlite3
import threading
from datetime import UTC, datetime
from pathlib import Path


class Store:
    def __init__(self, path: str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock:
            self._db.executescript(
                """
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    client_time TEXT,
                    data TEXT NOT NULL,
                    received_at TEXT NOT NULL
                );
                -- One row per model call, so providers can be compared.
                CREATE TABLE IF NOT EXISTS llm_calls (
                    id INTEGER PRIMARY KEY,
                    session_id TEXT,
                    endpoint TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    ms INTEGER NOT NULL,
                    outcome TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            self._db.commit()

    @staticmethod
    def _now() -> str:
        return datetime.now(UTC).isoformat(timespec="milliseconds")

    def add_event(self, session_id: str, type_: str, client_time: str, data: dict) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO events (session_id, type, client_time, data, received_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (session_id, type_, client_time, json.dumps(data), self._now()),
            )
            self._db.commit()

    def add_llm_call(
        self, session_id: str, endpoint: str, provider: str, model: str, ms: int, outcome: str
    ) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO llm_calls (session_id, endpoint, provider, model, ms, outcome, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (session_id, endpoint, provider, model, ms, outcome, self._now()),
            )
            self._db.commit()

    def events_csv(self) -> str:
        with self._lock:
            rows = self._db.execute(
                "SELECT id, session_id, type, client_time, received_at, data FROM events ORDER BY id"
            ).fetchall()
        out = io.StringIO()
        writer = csv.writer(out)
        writer.writerow(["id", "sessionId", "type", "clientTime", "receivedAt", "data"])
        writer.writerows(rows)
        return out.getvalue()

    def count(self, table: str) -> int:
        assert table in ("events", "llm_calls")
        with self._lock:
            return self._db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
