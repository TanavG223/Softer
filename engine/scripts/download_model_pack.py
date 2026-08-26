#!/usr/bin/env python3
"""Build a signed PaceBack ONNX model pack from immutable upstream revisions.

Network access occurs only in this build-time script. The engine itself has no
download path and validates this script's pinned byte lengths and SHA-256 values
before signing a pack.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


@dataclass(frozen=True, slots=True)
class UpstreamArtifact:
    component: str
    filename: str
    url: str
    sha256: str
    size_bytes: int


DENSE_REVISION = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
RERANKER_REVISION = "233902d25c440f23af6f7d6e94d2946bac0bee0a"
ARTIFACTS = (
    UpstreamArtifact(
        component="dense",
        filename="model.onnx",
        url=(
            "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/"
            f"{DENSE_REVISION}/onnx/model.onnx"
        ),
        sha256="828e1496d7fabb79cfa4dcd84fa38625c0d3d21da474a00f08db0f559940cf35",
        size_bytes=133_093_490,
    ),
    UpstreamArtifact(
        component="dense",
        filename="tokenizer.json",
        url=(
            "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/"
            f"{DENSE_REVISION}/tokenizer.json"
        ),
        sha256="d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66",
        size_bytes=711_396,
    ),
    UpstreamArtifact(
        component="reranker",
        filename="model.onnx",
        url=(
            "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2/resolve/"
            f"{RERANKER_REVISION}/onnx/model_qint8_arm64.onnx"
        ),
        sha256="3573b6b9593cb2f75987a31815d409ca3dd8808629118fd20451bb1a5d90cec7",
        size_bytes=23_200_716,
    ),
    UpstreamArtifact(
        component="reranker",
        filename="tokenizer.json",
        url=(
            "https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2/resolve/"
            f"{RERANKER_REVISION}/tokenizer.json"
        ),
        sha256="d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66",
        size_bytes=711_396,
    ),
)


def _hash_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def _download(artifact: UpstreamArtifact, destination: Path) -> None:
    request = urllib.request.Request(
        artifact.url,
        headers={"User-Agent": "PaceBack-model-pack-builder/1"},
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as out:
        while block := response.read(1024 * 1024):
            out.write(block)
    digest, size = _hash_file(destination)
    if digest != artifact.sha256 or size != artifact.size_bytes:
        raise RuntimeError(
            f"Pinned integrity check failed for {artifact.component}/{artifact.filename}"
        )


def _canonical(payload: dict) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _load_or_create_key(path: Path, generate: bool) -> Ed25519PrivateKey:
    if generate:
        if path.exists():
            raise FileExistsError(f"Refusing to overwrite existing signing key: {path}")
        key = Ed25519PrivateKey.generate()
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.write_bytes(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
        os.chmod(path, 0o600)
        return key
    payload = path.read_bytes()
    key = serialization.load_pem_private_key(payload, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise TypeError("Signing key must be an Ed25519 private key")
    return key


def _artifact_manifest(component: str, filename: str) -> dict[str, object]:
    artifact = next(
        item
        for item in ARTIFACTS
        if item.component == component and item.filename == filename
    )
    return {
        "path": f"{component}/{filename}",
        "sha256": artifact.sha256,
        "sizeBytes": artifact.size_bytes,
    }


def build_pack(output: Path, signing_key: Ed25519PrivateKey) -> None:
    output_parent = output.parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="paceback-model-pack-", dir=output_parent) as temp:
        staging = Path(temp) / "model-pack"
        for artifact in ARTIFACTS:
            _download(artifact, staging / artifact.component / artifact.filename)
        unsigned = {
            "formatVersion": 1,
            "packID": "paceback-bge-small-minilm-onnx-v1",
            "createdAt": datetime.now(UTC).isoformat(),
            "components": {
                "dense": {
                    "kind": "denseEmbedding",
                    "modelID": "BAAI/bge-small-en-v1.5",
                    "revision": DENSE_REVISION,
                    "adapterVersion": "1",
                    "license": "MIT",
                    "sourceURL": (
                        "https://huggingface.co/BAAI/bge-small-en-v1.5/tree/"
                        f"{DENSE_REVISION}"
                    ),
                    "model": _artifact_manifest("dense", "model.onnx"),
                    "tokenizer": _artifact_manifest("dense", "tokenizer.json"),
                    "maxLength": 512,
                    "dimensions": 384,
                    "pooling": "cls",
                    "normalize": True,
                    "queryPrefix": (
                        "Represent this sentence for searching relevant passages: "
                    ),
                    "outputName": "last_hidden_state",
                },
                "reranker": {
                    "kind": "crossEncoderReranker",
                    "modelID": "cross-encoder/ms-marco-MiniLM-L-6-v2",
                    "revision": RERANKER_REVISION,
                    "adapterVersion": "1",
                    "license": "Apache-2.0",
                    "sourceURL": (
                        "https://huggingface.co/cross-encoder/"
                        "ms-marco-MiniLM-L-6-v2/tree/"
                        f"{RERANKER_REVISION}"
                    ),
                    "model": _artifact_manifest("reranker", "model.onnx"),
                    "tokenizer": _artifact_manifest("reranker", "tokenizer.json"),
                    "maxLength": 512,
                    "dimensions": None,
                    "pooling": "logit",
                    "normalize": False,
                    "queryPrefix": "",
                    "outputName": "logits",
                },
            },
        }
        signature = signing_key.sign(_canonical(unsigned))
        signed = {
            **unsigned,
            "signature": {
                "algorithm": "ed25519",
                "value": base64.b64encode(signature).decode("ascii"),
            },
        }
        (staging / "manifest.json").write_text(
            json.dumps(signed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        if output.exists():
            raise FileExistsError(f"Refusing to overwrite existing model pack: {output}")
        shutil.move(staging, output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--signing-key", type=Path, required=True)
    parser.add_argument(
        "--generate-signing-key",
        action="store_true",
        help="Create the requested signing key; private keys are never written into the pack.",
    )
    parser.add_argument(
        "--public-key-output",
        type=Path,
        required=True,
        help="Write the base64 trust key outside the model-pack directory.",
    )
    args = parser.parse_args()
    key = _load_or_create_key(args.signing_key, args.generate_signing_key)
    build_pack(args.output.resolve(), key)
    public_bytes = key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    args.public_key_output.parent.mkdir(parents=True, exist_ok=True)
    args.public_key_output.write_text(
        base64.b64encode(public_bytes).decode("ascii") + "\n", encoding="ascii"
    )
    print(f"Built signed offline model pack: {args.output.resolve()}")
    print(f"Trust key: {args.public_key_output.resolve()}")
    print(f"Artifact bytes: {sum(item.size_bytes for item in ARTIFACTS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
