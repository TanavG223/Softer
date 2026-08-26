from __future__ import annotations

import base64
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import pytest

from paceback_engine.config import Settings
from paceback_engine.database import Database
from paceback_engine.model_runtime import (
    DENSE_MODEL_ID,
    DENSE_REVISION,
    RERANKER_MODEL_ID,
    RERANKER_REVISION,
    ModelPackError,
    load_and_verify_manifest,
    load_model_runtime,
)
from paceback_engine.retrieval import HybridRetriever, SearchHit, pack_embedding


def _artifact(path: Path, content: bytes) -> dict[str, object]:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    return {
        "path": str(path.relative_to(path.parents[1])),
        "sha256": hashlib.sha256(content).hexdigest(),
        "sizeBytes": len(content),
    }


def _signed_pack(root: Path) -> tuple[Path, str]:
    cryptography = pytest.importorskip("cryptography.hazmat.primitives")
    del cryptography
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    pack = root / "pack"
    dense_model = _artifact(pack / "dense" / "model.onnx", b"tiny-dense-model")
    dense_tokenizer = _artifact(pack / "dense" / "tokenizer.json", b"tiny-tokenizer")
    reranker_model = _artifact(pack / "reranker" / "model.onnx", b"tiny-reranker")
    reranker_tokenizer = _artifact(
        pack / "reranker" / "tokenizer.json", b"tiny-tokenizer"
    )
    unsigned = {
        "formatVersion": 1,
        "packID": "test-pack-v1",
        "createdAt": "2026-08-25T12:00:00+00:00",
        "components": {
            "dense": {
                "kind": "denseEmbedding",
                "modelID": DENSE_MODEL_ID,
                "revision": DENSE_REVISION,
                "adapterVersion": "1",
                "license": "MIT",
                "sourceURL": f"https://huggingface.co/{DENSE_MODEL_ID}/tree/{DENSE_REVISION}",
                "model": dense_model,
                "tokenizer": dense_tokenizer,
                "maxLength": 512,
                "dimensions": 384,
                "pooling": "cls",
                "normalize": True,
                "queryPrefix": "Represent this sentence for searching relevant passages: ",
                "outputName": "last_hidden_state",
            },
            "reranker": {
                "kind": "crossEncoderReranker",
                "modelID": RERANKER_MODEL_ID,
                "revision": RERANKER_REVISION,
                "adapterVersion": "1",
                "license": "Apache-2.0",
                "sourceURL": (
                    f"https://huggingface.co/{RERANKER_MODEL_ID}/tree/{RERANKER_REVISION}"
                ),
                "model": reranker_model,
                "tokenizer": reranker_tokenizer,
                "maxLength": 512,
                "dimensions": None,
                "pooling": "logit",
                "normalize": False,
                "queryPrefix": "",
                "outputName": "logits",
            },
        },
    }
    private_key = Ed25519PrivateKey.generate()
    canonical = json.dumps(
        unsigned, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    ).encode()
    signature = private_key.sign(canonical)
    (pack / "manifest.json").write_text(
        json.dumps(
            {
                **unsigned,
                "signature": {
                    "algorithm": "ed25519",
                    "value": base64.b64encode(signature).decode(),
                },
            }
        ),
        encoding="utf-8",
    )
    public_key = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return pack, base64.b64encode(public_key).decode()


def test_signed_manifest_verifies_exact_models_hashes_and_dimensions(tmp_path):
    pack_dir, trust_key = _signed_pack(tmp_path)
    pack = load_and_verify_manifest(pack_dir, trust_key)
    assert pack.pack_id == "test-pack-v1"
    assert pack.components["dense"].dimensions == 384
    assert pack.components["dense"].revision == DENSE_REVISION
    assert pack.components["reranker"].revision == RERANKER_REVISION


def test_signed_manifest_rejects_artifact_tampering(tmp_path):
    pack_dir, trust_key = _signed_pack(tmp_path)
    (pack_dir / "dense" / "model.onnx").write_bytes(b"tampered")
    with pytest.raises(ModelPackError) as error:
        load_and_verify_manifest(pack_dir, trust_key)
    assert error.value.code == "artifact_integrity_failure"


def test_signed_manifest_rejects_artifact_symlink_even_with_matching_bytes(tmp_path):
    pack_dir, trust_key = _signed_pack(tmp_path)
    model = pack_dir / "dense" / "model.onnx"
    outside = tmp_path / "outside-model.onnx"
    outside.write_bytes(model.read_bytes())
    model.unlink()
    model.symlink_to(outside)
    with pytest.raises(ModelPackError) as error:
        load_and_verify_manifest(pack_dir, trust_key)
    assert error.value.code == "unsafe_artifact_path"


def test_configured_invalid_pack_falls_back_in_dev_and_fails_closed_in_release(tmp_path):
    pack_dir, _ = _signed_pack(tmp_path)
    wrong_key = base64.b64encode(b"x" * 32).decode()
    development = Settings(
        data_dir=tmp_path / "dev",
        auth_token="a" * 32,
        release_mode=False,
        database_driver="sqlite",
        model_pack_dir=pack_dir,
        model_pack_trust_key=wrong_key,
    )
    runtime = load_model_runtime(development)
    assert runtime.pack_activation == "failed"
    assert runtime.embedder.model_backed is False
    assert {item.failure_reason for item in runtime.components if item.activation == "failed"} == {
        "invalid_signature"
    }

    release = Settings(
        data_dir=tmp_path / "release",
        auth_token="a" * 32,
        release_mode=True,
        database_driver="sqlcipher",
        storage_key="b" * 32,
        model_pack_dir=pack_dir,
        model_pack_trust_key=wrong_key,
    )
    with pytest.raises(ModelPackError) as error:
        load_model_runtime(release)
    assert error.value.code == "invalid_signature"


def test_verified_pack_activates_both_fake_model_adapters(tmp_path, monkeypatch):
    pack_dir, trust_key = _signed_pack(tmp_path)

    class FakeDense:
        dimensions = 384
        index_version = "fake-dense-v1"
        model_backed = True

        def __init__(self, *_args):
            pass

        def embed(self, _text: str) -> tuple[float, ...]:
            return (1.0,) + (0.0,) * 383

        def embed_query(self, text: str) -> tuple[float, ...]:
            return self.embed(text)

    class FakeReranker:
        def __init__(self, *_args):
            pass

        def score(self, _query: str, _hit: SearchHit) -> float:
            return 1.0

    monkeypatch.setattr("paceback_engine.model_runtime.OnnxDenseEmbedder", FakeDense)
    monkeypatch.setattr("paceback_engine.model_runtime.OnnxCrossEncoderReranker", FakeReranker)
    settings = Settings(
        data_dir=tmp_path / "data",
        auth_token="a" * 32,
        release_mode=False,
        database_driver="sqlite",
        model_pack_dir=pack_dir,
        model_pack_trust_key=trust_key,
    )
    runtime = load_model_runtime(settings)
    assert runtime.pack_activation == "active"
    assert runtime.pack_id == "test-pack-v1"
    active = {item.name for item in runtime.components if item.activation == "active"}
    assert active == {"bge-small-en-v1.5-onnx", "ms-marco-MiniLM-L6-v2-onnx"}


@dataclass
class TinyEmbedder:
    dimensions: int = 3
    index_version: str = "tiny:3:v1"
    model_backed: bool = True

    def embed(self, text: str) -> tuple[float, ...]:
        return (float(bool(text)), 0.0, 0.0)

    def embed_query(self, text: str) -> tuple[float, ...]:
        return self.embed(text)


def test_database_atomically_reindexes_existing_chunks_for_active_embedder(tmp_path):
    database = Database(tmp_path / "paceback.sqlite3")
    database.initialize()
    database.configure_embedder(TinyEmbedder())
    with database.connect() as connection:
        lengths = {
            row[0] for row in connection.execute("SELECT length(embedding) FROM chunks")
        }
        version = connection.execute(
            "SELECT value FROM engine_meta WHERE key = 'embedding_index_version'"
        ).fetchone()[0]
    assert lengths == {12}
    assert version == "tiny:3:v1"


class FakeStore:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, tuple[str, ...], int]] = []
        self.rows = [
            {
                "chunk_id": "semantic",
                "document_id": "doc-a",
                "title": "A",
                "source_url": None,
                "page_number": 1,
                "char_start": 0,
                "char_end": 8,
                "content": "semantic",
                "content_hash": "hash-a",
                "embedding": pack_embedding((1.0, 0.0, 0.0)),
            },
            {
                "chunk_id": "other",
                "document_id": "doc-b",
                "title": "B",
                "source_url": None,
                "page_number": 1,
                "char_start": 0,
                "char_end": 5,
                "content": "other",
                "content_hash": "hash-b",
                "embedding": pack_embedding((0.0, 1.0, 0.0)),
            },
        ]

    def sparse_search(self, query: str, profile_id: str, scopes, limit: int):
        self.calls.append((query, profile_id, tuple(scopes), limit))
        return []

    def eligible_chunks(self, profile_id: str, scopes):
        self.calls.append(("dense", profile_id, tuple(scopes), 50))
        return self.rows


class NegativeReranker:
    def score(self, _query: str, hit: SearchHit) -> float:
        return -1.0 if hit.chunk_id == "semantic" else -2.0


def test_hybrid_path_uses_model_embedder_and_reranks_negative_logits():
    store = FakeStore()
    retriever = HybridRetriever(
        store,
        embedder=TinyEmbedder(),
        reranker=NegativeReranker(),
    )
    hits = retriever.search(
        "meaning",
        profile_id="profile-1",
        scopes=("allAges", "teen13To17"),
    )
    assert [hit.chunk_id for hit in hits] == ["semantic", "other"]
    assert store.calls == [
        ("meaning", "profile-1", ("allAges", "teen13To17"), 50),
        ("dense", "profile-1", ("allAges", "teen13To17"), 50),
    ]
