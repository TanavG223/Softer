"""SQLite persistence with explicit profile namespaces and transactional indexing."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
from collections.abc import Iterable, Iterator, Sequence
from contextlib import contextmanager, suppress
from datetime import UTC, datetime
from importlib.resources import files
from pathlib import Path
from typing import Any
from uuid import NAMESPACE_URL, uuid4, uuid5

from paceback_engine.retrieval import (
    ChunkDraft,
    DeterministicEmbedder,
    Embedder,
    chunk_document,
    pack_embedding,
)
from paceback_engine.schemas import DocumentCreate, DocumentUpdate, ProfileCreate, ProfileUpdate

PUBLIC_NAMESPACE = "__public__"


def _now() -> str:
    return datetime.now(UTC).isoformat()


class Database:
    def __init__(
        self,
        path: Path,
        *,
        driver: str = "sqlite",
        storage_key: str | None = None,
    ) -> None:
        self.path = path
        self.driver = driver
        self._storage_key = storage_key
        self._dbapi = self._load_driver(driver)
        self._encryption_active = False
        self._embedder: Embedder = DeterministicEmbedder()

    @staticmethod
    def _load_driver(driver: str):
        if driver == "sqlite":
            return sqlite3
        if driver != "sqlcipher":
            raise ValueError("Unsupported database driver")
        try:
            from sqlcipher3 import dbapi2 as sqlcipher  # type: ignore[import-not-found]

            return sqlcipher
        except ImportError:
            try:
                from pysqlcipher3 import dbapi2 as sqlcipher  # type: ignore[import-not-found]

                return sqlcipher
            except ImportError as exc:
                raise RuntimeError(
                    "SQLCipher driver is required for encrypted release storage"
                ) from exc

    @property
    def encryption_active(self) -> bool:
        return self._encryption_active

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with suppress(OSError):
            os.chmod(self.path.parent, 0o700)
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS profiles (
                    id TEXT PRIMARY KEY,
                    alias TEXT NOT NULL CHECK(length(alias) BETWEEN 1 AND 40),
                    age_band TEXT NOT NULL,
                    owner_role TEXT NOT NULL,
                    caregiver_access INTEGER NOT NULL CHECK(caregiver_access IN (0, 1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS engine_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS documents (
                    id TEXT PRIMARY KEY,
                    profile_id TEXT REFERENCES profiles(id) ON DELETE CASCADE,
                    namespace TEXT NOT NULL,
                    title TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    source_url TEXT,
                    age_scope TEXT NOT NULL,
                    content TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK(
                        (namespace = '__public__' AND profile_id IS NULL) OR
                        (namespace <> '__public__' AND profile_id = namespace)
                    )
                );
                CREATE INDEX IF NOT EXISTS documents_profile_idx
                    ON documents(profile_id, updated_at DESC);

                CREATE TABLE IF NOT EXISTS chunks (
                    id TEXT PRIMARY KEY,
                    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                    namespace TEXT NOT NULL,
                    age_scope TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    page_number INTEGER NOT NULL,
                    char_start INTEGER NOT NULL,
                    char_end INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    parent_text TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    embedding BLOB NOT NULL,
                    UNIQUE(document_id, ordinal)
                );
                CREATE INDEX IF NOT EXISTS chunks_scope_idx
                    ON chunks(namespace, age_scope, document_id);

                CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                    chunk_id UNINDEXED,
                    content,
                    namespace UNINDEXED,
                    age_scope UNINDEXED,
                    tokenize='unicode61 remove_diacritics 2'
                );

                CREATE TABLE IF NOT EXISTS runs (
                    id TEXT PRIMARY KEY,
                    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
                    status TEXT NOT NULL,
                    cancel_requested INTEGER NOT NULL DEFAULT 0 CHECK(cancel_requested IN (0, 1)),
                    request_json TEXT NOT NULL,
                    response_json TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS runs_profile_idx
                    ON runs(profile_id, created_at DESC);

                CREATE TABLE IF NOT EXISTS run_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                    event_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS run_events_idx ON run_events(run_id, sequence);

                CREATE TABLE IF NOT EXISTS feedback (
                    id TEXT PRIMARY KEY,
                    run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
                    helpful INTEGER NOT NULL CHECK(helpful IN (0, 1)),
                    reason TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS feedback_once_idx
                    ON feedback(run_id, profile_id);
                """
            )
            self._seed_official_evidence(connection)
        with suppress(OSError):
            os.chmod(self.path, 0o600)

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        connection = self._dbapi.connect(self.path, timeout=10.0)
        try:
            connection.row_factory = self._dbapi.Row
            if self.driver == "sqlcipher":
                if not self._storage_key:
                    raise RuntimeError("Encrypted storage key is required")
                # Hex encoding makes the PRAGMA value data-only; the key is never
                # interpolated raw.
                key_hex = self._storage_key.encode("utf-8").hex()
                connection.execute(f"PRAGMA key = \"x'{key_hex}'\"")
                cipher_version = connection.execute("PRAGMA cipher_version").fetchone()
                if not cipher_version or not cipher_version[0]:
                    raise RuntimeError("The selected driver did not activate SQLCipher")
                self._encryption_active = True
            else:
                self._encryption_active = False
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = FULL")
            connection.execute("PRAGMA secure_delete = ON")
            connection.execute("PRAGMA busy_timeout = 5000")
            try:
                yield connection
            except Exception:
                connection.rollback()
                raise
            else:
                connection.commit()
        finally:
            connection.close()

    def configure_embedder(self, embedder: Embedder) -> None:
        """Atomically activate an embedding version and rebuild incompatible rows."""

        expected_bytes = embedder.dimensions * 4
        with self.connect() as connection:
            current = connection.execute(
                "SELECT value FROM engine_meta WHERE key = 'embedding_index_version'"
            ).fetchone()
            incompatible = connection.execute(
                "SELECT COUNT(*) FROM chunks WHERE length(embedding) <> ?",
                (expected_bytes,),
            ).fetchone()[0]
            if current is None or current["value"] != embedder.index_version or incompatible:
                rows = connection.execute("SELECT id, content FROM chunks ORDER BY id").fetchall()
                for row in rows:
                    vector = embedder.embed(row["content"])
                    if len(vector) != embedder.dimensions:
                        raise RuntimeError("Embedding adapter returned an invalid dimension")
                    connection.execute(
                        "UPDATE chunks SET embedding = ? WHERE id = ?",
                        (pack_embedding(vector), row["id"]),
                    )
                connection.execute(
                    """
                    INSERT INTO engine_meta(key, value)
                    VALUES ('embedding_index_version', ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    (embedder.index_version,),
                )
        self._embedder = embedder

    def healthy(self) -> bool:
        try:
            with self.connect() as connection:
                return connection.execute("SELECT 1").fetchone()[0] == 1
        except sqlite3.Error:
            return False

    def fts5_ready(self) -> bool:
        try:
            with self.connect() as connection:
                return bool(
                    connection.execute(
                        "SELECT sqlite_compileoption_used('ENABLE_FTS5')"
                    ).fetchone()[0]
                )
        except sqlite3.Error:
            return False

    def _seed_official_evidence(self, connection: sqlite3.Connection) -> None:
        resource = files("paceback_engine.resources").joinpath("evidence_seed.json")
        records = json.loads(resource.read_text(encoding="utf-8"))
        for record in records:
            content_hash = hashlib.sha256(record["content"].encode("utf-8")).hexdigest()
            existing = connection.execute(
                "SELECT content_hash FROM documents WHERE id = ?", (record["id"],)
            ).fetchone()
            if existing and existing["content_hash"] == content_hash:
                continue
            now = _now()
            if existing:
                self._delete_document_chunks(connection, record["id"])
                connection.execute(
                    """
                    UPDATE documents
                    SET title = ?, source_url = ?, age_scope = ?, content = ?,
                        content_hash = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        record["title"],
                        record["url"],
                        record["scope"],
                        record["content"],
                        content_hash,
                        now,
                        record["id"],
                    ),
                )
            else:
                connection.execute(
                    """
                    INSERT INTO documents(
                        id, profile_id, namespace, title, source_kind, source_url,
                        age_scope, content, content_hash, created_at, updated_at
                    ) VALUES (?, NULL, ?, ?, 'officialBundled', ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        record["id"],
                        PUBLIC_NAMESPACE,
                        record["title"],
                        record["url"],
                        record["scope"],
                        record["content"],
                        content_hash,
                        now,
                        now,
                    ),
                )
            self._insert_chunks(
                connection,
                document_id=record["id"],
                namespace=PUBLIC_NAMESPACE,
                age_scope=record["scope"],
                drafts=chunk_document(record["content"], embedder=self._embedder),
            )

    def create_profile(
        self, request: ProfileCreate, *, profile_id: str | None = None
    ) -> dict[str, Any]:
        profile_id = profile_id or str(uuid4())
        now = _now()
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO profiles(
                    id, alias, age_band, owner_role, caregiver_access, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    profile_id,
                    request.alias,
                    request.age_band.value,
                    request.owner_role.value,
                    int(request.caregiver_access),
                    now,
                    now,
                ),
            )
        return self.get_profile(profile_id)  # type: ignore[return-value]

    def list_profiles(self) -> list[dict[str, Any]]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT * FROM profiles ORDER BY created_at, id"
            ).fetchall()
        return [dict(row) for row in rows]

    def get_profile(self, profile_id: str) -> dict[str, Any] | None:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM profiles WHERE id = ?", (profile_id,)
            ).fetchone()
        return dict(row) if row else None

    def update_profile(self, profile_id: str, request: ProfileUpdate) -> dict[str, Any] | None:
        assignments: list[str] = []
        values: list[Any] = []
        if request.alias is not None:
            assignments.append("alias = ?")
            values.append(request.alias)
        if request.caregiver_access is not None:
            assignments.append("caregiver_access = ?")
            values.append(int(request.caregiver_access))
        assignments.append("updated_at = ?")
        values.append(_now())
        values.append(profile_id)
        with self.connect() as connection:
            cursor = connection.execute(
                f"UPDATE profiles SET {', '.join(assignments)} WHERE id = ?", values
            )
        return self.get_profile(profile_id) if cursor.rowcount else None

    def delete_profile(self, profile_id: str) -> bool:
        with self.connect() as connection:
            document_rows = connection.execute(
                "SELECT id FROM documents WHERE profile_id = ?", (profile_id,)
            ).fetchall()
            for row in document_rows:
                self._delete_document_chunks(connection, row["id"])
            cursor = connection.execute("DELETE FROM profiles WHERE id = ?", (profile_id,))
        return bool(cursor.rowcount)

    def create_document(
        self, profile_id: str, request: DocumentCreate
    ) -> dict[str, Any]:
        document_id = str(uuid4())
        now = _now()
        content_hash = hashlib.sha256(request.content.encode("utf-8")).hexdigest()
        drafts = chunk_document(request.content, embedder=self._embedder)
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO documents(
                    id, profile_id, namespace, title, source_kind, source_url,
                    age_scope, content, content_hash, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    document_id,
                    profile_id,
                    profile_id,
                    request.title,
                    request.source_kind.value,
                    request.source_url,
                    request.evidence_scope.value,
                    request.content,
                    content_hash,
                    now,
                    now,
                ),
            )
            self._insert_chunks(
                connection,
                document_id=document_id,
                namespace=profile_id,
                age_scope=request.evidence_scope.value,
                drafts=drafts,
            )
        return self.get_document(profile_id, document_id, include_content=True)  # type: ignore[return-value]

    def list_documents(self, profile_id: str) -> list[dict[str, Any]]:
        with self.connect() as connection:
            rows = connection.execute(
                """
                SELECT d.*, COUNT(c.id) AS chunk_count
                FROM documents d LEFT JOIN chunks c ON c.document_id = d.id
                WHERE d.profile_id = ?
                GROUP BY d.id
                ORDER BY d.updated_at DESC, d.id
                """,
                (profile_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_document(
        self, profile_id: str, document_id: str, *, include_content: bool = False
    ) -> dict[str, Any] | None:
        content_column = "d.content" if include_content else "NULL AS content"
        with self.connect() as connection:
            row = connection.execute(
                f"""
                SELECT d.id, d.profile_id, d.title, d.source_kind, d.source_url,
                       d.age_scope, d.content_hash, d.created_at, d.updated_at,
                       {content_column}, COUNT(c.id) AS chunk_count
                FROM documents d LEFT JOIN chunks c ON c.document_id = d.id
                WHERE d.id = ? AND d.profile_id = ?
                GROUP BY d.id
                """,
                (document_id, profile_id),
            ).fetchone()
        return dict(row) if row else None

    def update_document(
        self, profile_id: str, document_id: str, request: DocumentUpdate
    ) -> dict[str, Any] | None:
        current = self.get_document(profile_id, document_id, include_content=True)
        if current is None:
            return None
        title = request.title if request.title is not None else current["title"]
        content = request.content if request.content is not None else current["content"]
        source_url = request.source_url if request.source_url is not None else current["source_url"]
        age_scope = (
            request.evidence_scope.value
            if request.evidence_scope is not None
            else current["age_scope"]
        )
        content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
        drafts = chunk_document(content, embedder=self._embedder)
        with self.connect() as connection:
            self._delete_document_chunks(connection, document_id)
            connection.execute(
                """
                UPDATE documents
                SET title = ?, content = ?, source_url = ?, age_scope = ?,
                    content_hash = ?, updated_at = ?
                WHERE id = ? AND profile_id = ?
                """,
                (
                    title,
                    content,
                    source_url,
                    age_scope,
                    content_hash,
                    _now(),
                    document_id,
                    profile_id,
                ),
            )
            self._insert_chunks(
                connection,
                document_id=document_id,
                namespace=profile_id,
                age_scope=age_scope,
                drafts=drafts,
            )
        return self.get_document(profile_id, document_id, include_content=True)

    def delete_document(self, profile_id: str, document_id: str) -> bool:
        with self.connect() as connection:
            exists = connection.execute(
                "SELECT 1 FROM documents WHERE id = ? AND profile_id = ?",
                (document_id, profile_id),
            ).fetchone()
            if not exists:
                return False
            self._delete_document_chunks(connection, document_id)
            connection.execute(
                "DELETE FROM documents WHERE id = ? AND profile_id = ?",
                (document_id, profile_id),
            )
        return True

    def _insert_chunks(
        self,
        connection: sqlite3.Connection,
        *,
        document_id: str,
        namespace: str,
        age_scope: str,
        drafts: Iterable[ChunkDraft],
    ) -> None:
        for draft in drafts:
            chunk_id = str(
                uuid5(
                    NAMESPACE_URL,
                    f"paceback:{document_id}:{draft.ordinal}:{draft.content_hash}",
                )
            )
            connection.execute(
                """
                INSERT INTO chunks(
                    id, document_id, namespace, age_scope, ordinal, page_number,
                    char_start, char_end, content, parent_text, content_hash, embedding
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    chunk_id,
                    document_id,
                    namespace,
                    age_scope,
                    draft.ordinal,
                    draft.page_number,
                    draft.char_start,
                    draft.char_end,
                    draft.content,
                    draft.parent_text,
                    draft.content_hash,
                    draft.embedding,
                ),
            )
            connection.execute(
                """
                INSERT INTO chunks_fts(chunk_id, content, namespace, age_scope)
                VALUES (?, ?, ?, ?)
                """,
                (chunk_id, draft.content, namespace, age_scope),
            )

    def _delete_document_chunks(
        self, connection: sqlite3.Connection, document_id: str
    ) -> None:
        rows = connection.execute(
            "SELECT id FROM chunks WHERE document_id = ?", (document_id,)
        ).fetchall()
        for row in rows:
            connection.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", (row["id"],))
        connection.execute("DELETE FROM chunks WHERE document_id = ?", (document_id,))

    def sparse_search(
        self, query: str, profile_id: str, scopes: Sequence[str], limit: int
    ) -> list[dict[str, Any]]:
        terms = list(dict.fromkeys(re.findall(r"[A-Za-z0-9]+", query.lower())))[:32]
        if not terms or not scopes:
            return []
        match_query = " OR ".join(f'"{term}"' for term in terms)
        scope_placeholders = ",".join("?" for _ in scopes)
        sql = f"""
            SELECT c.id AS chunk_id, c.document_id, d.title, d.source_url,
                   c.page_number, c.char_start, c.char_end, c.content,
                   c.content_hash, c.embedding, bm25(chunks_fts) AS sparse_score
            FROM chunks_fts
            JOIN chunks c ON c.id = chunks_fts.chunk_id
            JOIN documents d ON d.id = c.document_id
            WHERE chunks_fts MATCH ?
              AND chunks_fts.namespace IN (?, ?)
              AND chunks_fts.age_scope IN ({scope_placeholders})
            ORDER BY sparse_score ASC, c.id ASC
            LIMIT ?
        """
        parameters: list[Any] = [match_query, PUBLIC_NAMESPACE, profile_id, *scopes, limit]
        with self.connect() as connection:
            rows = connection.execute(sql, parameters).fetchall()
        return [dict(row) for row in rows]

    def eligible_chunks(
        self, profile_id: str, scopes: Sequence[str]
    ) -> list[dict[str, Any]]:
        if not scopes:
            return []
        placeholders = ",".join("?" for _ in scopes)
        sql = f"""
            SELECT c.id AS chunk_id, c.document_id, d.title, d.source_url,
                   c.page_number, c.char_start, c.char_end, c.content,
                   c.content_hash, c.embedding
            FROM chunks c JOIN documents d ON d.id = c.document_id
            WHERE c.namespace IN (?, ?) AND c.age_scope IN ({placeholders})
            ORDER BY c.id
        """
        with self.connect() as connection:
            rows = connection.execute(
                sql, [PUBLIC_NAMESPACE, profile_id, *scopes]
            ).fetchall()
        return [dict(row) for row in rows]

    def get_source(self, profile_id: str, source_id: str) -> dict[str, Any] | None:
        with self.connect() as connection:
            chunk = connection.execute(
                """
                SELECT c.id AS source_id, c.document_id, d.title, d.source_url,
                       c.page_number, c.char_start, c.char_end, c.content,
                       c.content_hash, c.namespace, c.age_scope
                FROM chunks c JOIN documents d ON d.id = c.document_id
                WHERE c.id = ? AND c.namespace IN (?, ?)
                """,
                (source_id, PUBLIC_NAMESPACE, profile_id),
            ).fetchone()
            if chunk:
                return dict(chunk)
            document = connection.execute(
                """
                SELECT d.id AS source_id, d.id AS document_id, d.title, d.source_url,
                       1 AS page_number, 0 AS char_start, length(d.content) AS char_end,
                       d.content, d.content_hash, d.namespace, d.age_scope
                FROM documents d
                WHERE d.id = ? AND d.namespace IN (?, ?)
                """,
                (source_id, PUBLIC_NAMESPACE, profile_id),
            ).fetchone()
        return dict(document) if document else None

    def create_run(self, run_id: str, profile_id: str, request_json: str) -> None:
        now = _now()
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO runs(
                    id, profile_id, status, request_json, created_at, updated_at
                ) VALUES (?, ?, 'running', ?, ?, ?)
                """,
                (run_id, profile_id, request_json, now, now),
            )
            self._append_event(
                connection, run_id, "started", {"runID": run_id, "status": "running"}
            )

    def complete_run(self, run_id: str, profile_id: str, response_json: str) -> None:
        payload = json.loads(response_json)
        status = "cancelled" if payload.get("supportStatus") == "cancelled" else "completed"
        with self.connect() as connection:
            connection.execute(
                """
                UPDATE runs SET status = ?, response_json = ?, updated_at = ?
                WHERE id = ? AND profile_id = ?
                """,
                (status, response_json, _now(), run_id, profile_id),
            )
            self._append_event(
                connection,
                run_id,
                status,
                {"runID": run_id, "status": status, "response": payload},
            )

    def get_run(self, run_id: str, profile_id: str) -> dict[str, Any] | None:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT * FROM runs WHERE id = ? AND profile_id = ?",
                (run_id, profile_id),
            ).fetchone()
        return dict(row) if row else None

    def cancellation_requested(self, run_id: str, profile_id: str) -> bool:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT cancel_requested FROM runs WHERE id = ? AND profile_id = ?",
                (run_id, profile_id),
            ).fetchone()
        return bool(row and row["cancel_requested"])

    def request_cancellation(self, run_id: str, profile_id: str) -> str | None:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT status, cancel_requested FROM runs WHERE id = ? AND profile_id = ?",
                (run_id, profile_id),
            ).fetchone()
            if row is None:
                return None
            if row["status"] == "completed":
                return "completed"
            if row["status"] == "cancelled":
                return "cancelled"
            if not row["cancel_requested"]:
                connection.execute(
                    """
                    UPDATE runs SET cancel_requested = 1, updated_at = ?
                    WHERE id = ? AND profile_id = ?
                    """,
                    (_now(), run_id, profile_id),
                )
                self._append_event(
                    connection,
                    run_id,
                    "cancellationRequested",
                    {"runID": run_id, "status": "cancellationRequested"},
                )
            return "cancellationRequested"

    def run_events(self, run_id: str, profile_id: str, after: int = 0) -> list[dict[str, Any]]:
        with self.connect() as connection:
            owns_run = connection.execute(
                "SELECT 1 FROM runs WHERE id = ? AND profile_id = ?",
                (run_id, profile_id),
            ).fetchone()
            if not owns_run:
                return []
            rows = connection.execute(
                """
                SELECT sequence, event_type, payload_json, created_at
                FROM run_events WHERE run_id = ? AND sequence > ? ORDER BY sequence
                """,
                (run_id, after),
            ).fetchall()
        return [
            {
                "sequence": row["sequence"],
                "event": row["event_type"],
                "payload": json.loads(row["payload_json"]),
                "createdAt": row["created_at"],
            }
            for row in rows
        ]

    def _append_event(
        self,
        connection: sqlite3.Connection,
        run_id: str,
        event_type: str,
        payload: dict[str, Any],
    ) -> None:
        connection.execute(
            """
            INSERT INTO run_events(run_id, event_type, payload_json, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (run_id, event_type, json.dumps(payload, separators=(",", ":")), _now()),
        )

    def create_feedback(
        self, profile_id: str, run_id: str, helpful: bool, reason: str | None
    ) -> dict[str, Any]:
        feedback_id = str(uuid4())
        created_at = _now()
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO feedback(id, run_id, profile_id, helpful, reason, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(run_id, profile_id) DO UPDATE SET
                    helpful = excluded.helpful,
                    reason = excluded.reason,
                    created_at = excluded.created_at
                """,
                (feedback_id, run_id, profile_id, int(helpful), reason, created_at),
            )
            row = connection.execute(
                "SELECT * FROM feedback WHERE run_id = ? AND profile_id = ?",
                (run_id, profile_id),
            ).fetchone()
        return dict(row)
