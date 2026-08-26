"""Runtime configuration with release-safe defaults."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass(frozen=True, slots=True)
class Settings:
    data_dir: Path
    auth_token: str
    release_mode: bool = True
    database_driver: Literal["sqlite", "sqlcipher"] = "sqlite"
    storage_key: str | None = None
    allowed_hosts: tuple[str, ...] = ("127.0.0.1", "localhost", "testserver")
    max_retrieval_rounds: int = 3
    max_subqueries: int = 6
    max_candidates: int = 100
    max_actions: int = 8
    context_token_budget: int = 2_400
    model_pack_dir: Path | None = None
    model_pack_trust_key: str | None = None

    def __post_init__(self) -> None:
        if len(self.auth_token.encode("utf-8")) < 32:
            raise ValueError("auth_token must contain at least 32 UTF-8 bytes")
        if not (1 <= self.max_retrieval_rounds <= 3):
            raise ValueError("max_retrieval_rounds must be between 1 and 3")
        if not (1 <= self.max_subqueries <= 6):
            raise ValueError("max_subqueries must be between 1 and 6")
        if not (1 <= self.max_candidates <= 100):
            raise ValueError("max_candidates must be between 1 and 100")
        if not (1 <= self.max_actions <= 8):
            raise ValueError("max_actions must be between 1 and 8")
        if self.context_token_budget < 256:
            raise ValueError("context_token_budget must be at least 256")
        if self.release_mode and (
            self.database_driver != "sqlcipher" or not self.storage_key
        ):
            raise ValueError(
                "release mode requires an active SQLCipher driver and a storage key"
            )
        if self.storage_key is not None and len(self.storage_key.encode("utf-8")) < 32:
            raise ValueError("storage_key must contain at least 32 UTF-8 bytes")
        if self.model_pack_dir is None and self.model_pack_trust_key is not None:
            raise ValueError("model_pack_trust_key requires model_pack_dir")

    @property
    def database_path(self) -> Path:
        return self.data_dir / "paceback.sqlite3"

    @classmethod
    def from_env(cls) -> Settings:
        token = os.getenv("PACEBACK_AUTH_TOKEN", "")
        if not token:
            raise RuntimeError(
                "PACEBACK_AUTH_TOKEN is required; the packaged launcher may read it from stdin"
            )
        configured_dir = os.getenv("PACEBACK_DATA_DIR")
        data_dir = (
            Path(configured_dir).expanduser()
            if configured_dir
            else Path.home() / "Library" / "Application Support" / "PaceBack" / "Engine"
        )
        release = os.getenv("PACEBACK_RELEASE_MODE", "1").strip().lower() not in {
            "0",
            "false",
            "no",
        }
        driver = os.getenv("PACEBACK_DATABASE_DRIVER", "sqlcipher" if release else "sqlite")
        if driver not in {"sqlite", "sqlcipher"}:
            raise ValueError("PACEBACK_DATABASE_DRIVER must be sqlite or sqlcipher")
        return cls(
            data_dir=data_dir,
            auth_token=token,
            release_mode=release,
            database_driver=driver,  # type: ignore[arg-type]
            storage_key=os.getenv("PACEBACK_STORAGE_KEY"),
            model_pack_dir=(
                Path(value).expanduser()
                if (value := os.getenv("PACEBACK_MODEL_PACK_DIR"))
                else None
            ),
            model_pack_trust_key=os.getenv("PACEBACK_MODEL_TRUST_KEY"),
        )
