"""Verified, offline-only ONNX model-pack loading.

The runtime never downloads model files. A configured pack is accepted only when
its detached trust anchor verifies the Ed25519-signed manifest and every artifact
matches its declared SHA-256 and byte length.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from paceback_engine.retrieval import (
    DeterministicEmbedder,
    DeterministicReranker,
    Embedder,
    Reranker,
    SearchHit,
)

if TYPE_CHECKING:
    from paceback_engine.config import Settings


DENSE_MODEL_ID = "BAAI/bge-small-en-v1.5"
DENSE_REVISION = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
RERANKER_MODEL_ID = "cross-encoder/ms-marco-MiniLM-L-6-v2"
RERANKER_REVISION = "233902d25c440f23af6f7d6e94d2946bac0bee0a"
MANIFEST_FILENAME = "manifest.json"
MAX_MANIFEST_BYTES = 1_000_000


class ModelPackError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class _StrictPackModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class ArtifactSpec(_StrictPackModel):
    path: str = Field(min_length=1, max_length=500)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    size_bytes: int = Field(alias="sizeBytes", gt=0, le=2_000_000_000)


class ComponentSpec(_StrictPackModel):
    kind: Literal["denseEmbedding", "crossEncoderReranker"]
    model_id: str = Field(alias="modelID", min_length=1, max_length=200)
    revision: str = Field(pattern=r"^[0-9a-f]{40}$")
    adapter_version: str = Field(alias="adapterVersion", pattern=r"^[0-9]+$")
    license: str = Field(min_length=1, max_length=100)
    source_url: str = Field(alias="sourceURL", pattern=r"^https://huggingface\.co/.+$")
    model: ArtifactSpec
    tokenizer: ArtifactSpec
    max_length: int = Field(alias="maxLength", ge=32, le=512)
    dimensions: int | None = Field(default=None, ge=1, le=4_096)
    pooling: Literal["cls", "mean", "logit"]
    normalize: bool = False
    query_prefix: str = Field(default="", alias="queryPrefix", max_length=500)
    output_name: str | None = Field(default=None, alias="outputName", max_length=100)


class SignatureSpec(_StrictPackModel):
    algorithm: Literal["ed25519"]
    value: str = Field(min_length=40, max_length=200)


class SignedModelPack(_StrictPackModel):
    format_version: Literal[1] = Field(alias="formatVersion")
    pack_id: str = Field(alias="packID", pattern=r"^[A-Za-z0-9._-]{1,100}$")
    created_at: str = Field(alias="createdAt", min_length=20, max_length=40)
    components: dict[str, ComponentSpec]
    signature: SignatureSpec

    @model_validator(mode="after")
    def exact_supported_components(self) -> SignedModelPack:
        if set(self.components) != {"dense", "reranker"}:
            raise ValueError("components must contain exactly dense and reranker")
        dense = self.components["dense"]
        reranker = self.components["reranker"]
        if (
            dense.kind != "denseEmbedding"
            or dense.model_id != DENSE_MODEL_ID
            or dense.revision != DENSE_REVISION
            or dense.license != "MIT"
            or dense.source_url
            != f"https://huggingface.co/{DENSE_MODEL_ID}/tree/{DENSE_REVISION}"
            or dense.dimensions != 384
            or dense.pooling not in {"cls", "mean"}
            or not dense.normalize
        ):
            raise ValueError("dense component does not match the pinned BGE contract")
        if (
            reranker.kind != "crossEncoderReranker"
            or reranker.model_id != RERANKER_MODEL_ID
            or reranker.revision != RERANKER_REVISION
            or reranker.license != "Apache-2.0"
            or reranker.source_url
            != f"https://huggingface.co/{RERANKER_MODEL_ID}/tree/{RERANKER_REVISION}"
            or reranker.dimensions is not None
            or reranker.pooling != "logit"
            or reranker.normalize
            or reranker.query_prefix
        ):
            raise ValueError("reranker component does not match the pinned MiniLM contract")
        return self


@dataclass(frozen=True, slots=True)
class RuntimeComponent:
    name: str
    version: str
    purpose: str
    activation: Literal["active", "fallback", "standby", "unconfigured", "failed"]
    model_id: str | None = None
    revision: str | None = None
    artifact_sha256: str | None = None
    dimensions: int | None = None
    provider: str | None = None
    failure_reason: str | None = None

    @property
    def active(self) -> bool:
        return self.activation in {"active", "fallback"}


@dataclass(frozen=True, slots=True)
class ModelRuntime:
    embedder: Embedder
    reranker: Reranker
    components: tuple[RuntimeComponent, ...]
    pack_id: str | None
    pack_activation: Literal["active", "unconfigured", "failed"]


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ModelPackError("manifest_duplicate_key", "Manifest contains duplicate keys")
        result[key] = value
    return result


def _canonical_unsigned_payload(raw: dict[str, Any]) -> bytes:
    unsigned = {key: value for key, value in raw.items() if key != "signature"}
    return json.dumps(
        unsigned,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _decode_trust_key(encoded: str) -> bytes:
    try:
        value = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError) as exc:
        raise ModelPackError("invalid_trust_key", "Trust key is not valid base64") from exc
    if len(value) != 32:
        raise ModelPackError("invalid_trust_key", "Ed25519 trust key must be 32 bytes")
    return value


def _verify_signature(raw: dict[str, Any], trust_key: str) -> None:
    signature = raw.get("signature")
    if not isinstance(signature, dict) or signature.get("algorithm") != "ed25519":
        raise ModelPackError("invalid_signature_contract", "Ed25519 signature is required")
    try:
        signature_bytes = base64.b64decode(signature.get("value", ""), validate=True)
    except (ValueError, TypeError) as exc:
        raise ModelPackError("invalid_signature", "Manifest signature is not valid base64") from exc
    if len(signature_bytes) != 64:
        raise ModelPackError("invalid_signature", "Ed25519 signature must be 64 bytes")
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError as exc:
        raise ModelPackError(
            "signature_dependency_missing",
            "The cryptography package is required to verify model packs",
        ) from exc
    public_key = Ed25519PublicKey.from_public_bytes(_decode_trust_key(trust_key))
    try:
        public_key.verify(signature_bytes, _canonical_unsigned_payload(raw))
    except InvalidSignature as exc:
        raise ModelPackError("invalid_signature", "Manifest signature verification failed") from exc


def _artifact_path(pack_dir: Path, artifact: ArtifactSpec) -> Path:
    relative = Path(artifact.path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ModelPackError("unsafe_artifact_path", "Artifact path escapes the model pack")
    root = pack_dir.resolve(strict=True)
    unresolved = root / relative
    current = root
    for part in relative.parts:
        current /= part
        if current.is_symlink():
            raise ModelPackError("unsafe_artifact_path", "Artifact symlinks are forbidden")
    candidate = unresolved.resolve(strict=True)
    if not candidate.is_relative_to(root) or not candidate.is_file():
        raise ModelPackError("unsafe_artifact_path", "Artifact must be a regular pack file")
    return candidate


def _hash_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def _validate_artifacts(pack_dir: Path, pack: SignedModelPack) -> None:
    for component in pack.components.values():
        for artifact in (component.model, component.tokenizer):
            try:
                path = _artifact_path(pack_dir, artifact)
            except (FileNotFoundError, OSError) as exc:
                raise ModelPackError("artifact_missing", "A declared artifact is missing") from exc
            actual_hash, actual_size = _hash_file(path)
            if actual_hash != artifact.sha256 or actual_size != artifact.size_bytes:
                raise ModelPackError(
                    "artifact_integrity_failure",
                    "A model artifact failed SHA-256 or size validation",
                )


def load_and_verify_manifest(pack_dir: Path, trust_key: str) -> SignedModelPack:
    try:
        if pack_dir.is_symlink():
            raise ModelPackError("unsafe_pack_path", "Model-pack root cannot be a symlink")
        manifest_path = pack_dir.resolve(strict=True) / MANIFEST_FILENAME
        if manifest_path.is_symlink():
            raise ModelPackError("unsafe_pack_path", "Model-pack manifest cannot be a symlink")
        payload = manifest_path.read_bytes()
    except ModelPackError:
        raise
    except (FileNotFoundError, OSError) as exc:
        raise ModelPackError("manifest_missing", "Model-pack manifest is missing") from exc
    if len(payload) > MAX_MANIFEST_BYTES:
        raise ModelPackError("manifest_too_large", "Model-pack manifest is too large")
    try:
        raw = json.loads(
            payload,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=lambda value: (_ for _ in ()).throw(
                ValueError(f"invalid JSON constant: {value}")
            ),
        )
    except ModelPackError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise ModelPackError("manifest_malformed", "Model-pack manifest is malformed") from exc
    if not isinstance(raw, dict):
        raise ModelPackError("manifest_malformed", "Model-pack manifest must be an object")
    _verify_signature(raw, trust_key)
    try:
        pack = SignedModelPack.model_validate(raw)
    except ValueError as exc:
        raise ModelPackError("manifest_contract_failure", "Manifest contract is invalid") from exc
    _validate_artifacts(pack_dir, pack)
    return pack


def _load_onnx_dependencies() -> tuple[Any, Any, Any]:
    try:
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
    except ImportError as exc:
        raise ModelPackError(
            "inference_dependency_missing",
            "numpy, onnxruntime, and tokenizers are required for a configured pack",
        ) from exc
    return np, ort, Tokenizer


class _OnnxTextModel:
    def __init__(self, pack_dir: Path, spec: ComponentSpec) -> None:
        self._np, ort, tokenizer_type = _load_onnx_dependencies()
        self._tokenizer = tokenizer_type.from_file(str(_artifact_path(pack_dir, spec.tokenizer)))
        self._tokenizer.enable_truncation(max_length=spec.max_length)
        options = ort.SessionOptions()
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self._session = ort.InferenceSession(
            str(_artifact_path(pack_dir, spec.model)),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )
        self._input_names = {item.name for item in self._session.get_inputs()}
        if "input_ids" not in self._input_names or "attention_mask" not in self._input_names:
            raise ModelPackError(
                "model_io_contract_failure",
                "ONNX model lacks required input_ids or attention_mask inputs",
            )
        output_names = {item.name for item in self._session.get_outputs()}
        self._output_name = spec.output_name or self._session.get_outputs()[0].name
        if self._output_name not in output_names:
            raise ModelPackError(
                "model_io_contract_failure", "Configured ONNX output does not exist"
            )
        self._lock = threading.Lock()

    def _infer(self, first: str, second: str | None = None) -> Any:
        with self._lock:
            encoding = self._tokenizer.encode(first, second)
            inputs: dict[str, Any] = {
                "input_ids": self._np.asarray([encoding.ids], dtype=self._np.int64),
                "attention_mask": self._np.asarray(
                    [encoding.attention_mask], dtype=self._np.int64
                ),
            }
            if "token_type_ids" in self._input_names:
                inputs["token_type_ids"] = self._np.asarray(
                    [encoding.type_ids], dtype=self._np.int64
                )
            return self._session.run([self._output_name], inputs)[0]


class OnnxDenseEmbedder(_OnnxTextModel):
    model_backed = True

    def __init__(self, pack_dir: Path, pack_id: str, spec: ComponentSpec) -> None:
        super().__init__(pack_dir, spec)
        if spec.dimensions is None:
            raise ModelPackError("model_dimension_failure", "Dense dimensions are required")
        self.dimensions = spec.dimensions
        self.index_version = (
            f"onnx:{pack_id}:{spec.model_id}:{spec.revision}:"
            f"{spec.model.sha256}:{self.dimensions}"
        )
        self._pooling = spec.pooling
        self._normalize = spec.normalize
        self._query_prefix = spec.query_prefix
        probe = self.embed("PaceBack local model activation probe")
        if len(probe) != self.dimensions:
            raise ModelPackError(
                "model_dimension_failure", "Dense model output dimensions do not match manifest"
            )

    def _embed_text(self, text: str) -> tuple[float, ...]:
        output = self._infer(text)
        if output.ndim == 3:
            vector = (
                output[0, 0, :]
                if self._pooling == "cls"
                else output[0].mean(axis=0)
            )
        elif output.ndim == 2 and output.shape[0] == 1:
            vector = output[0]
        else:
            raise ModelPackError(
                "model_output_failure", "Dense ONNX output has an unsupported shape"
            )
        values = [float(item) for item in vector.tolist()]
        if len(values) != self.dimensions or not all(math.isfinite(item) for item in values):
            raise ModelPackError(
                "model_dimension_failure", "Dense ONNX output is invalid or non-finite"
            )
        if self._normalize:
            norm = math.sqrt(sum(item * item for item in values))
            if not norm:
                raise ModelPackError("model_output_failure", "Dense ONNX output has zero norm")
            values = [item / norm for item in values]
        return tuple(values)

    def embed(self, text: str) -> tuple[float, ...]:
        return self._embed_text(text)

    def embed_query(self, text: str) -> tuple[float, ...]:
        return self._embed_text(f"{self._query_prefix}{text}")


class OnnxCrossEncoderReranker(_OnnxTextModel):
    def __init__(self, pack_dir: Path, spec: ComponentSpec) -> None:
        super().__init__(pack_dir, spec)
        probe = self._score_text("recovery question", "relevant recovery passage")
        if not math.isfinite(probe):
            raise ModelPackError("model_output_failure", "Reranker probe was non-finite")

    def _score_text(self, query: str, passage: str) -> float:
        output = self._infer(query, passage)
        if output.size != 1:
            raise ModelPackError(
                "model_output_failure", "Reranker ONNX output must contain one logit"
            )
        score = float(output.reshape(-1)[0])
        if not math.isfinite(score):
            raise ModelPackError("model_output_failure", "Reranker logit is non-finite")
        return score

    def score(self, query: str, hit: SearchHit) -> float:
        return self._score_text(query, hit.content)


def _component_digest(spec: ComponentSpec) -> str:
    return hashlib.sha256(
        f"{spec.model.sha256}:{spec.tokenizer.sha256}".encode("ascii")
    ).hexdigest()


def _fallback_runtime(
    *, failure_reason: str | None = None, pack_id: str | None = None
) -> ModelRuntime:
    adapter_activation: Literal["unconfigured", "failed"] = (
        "failed" if failure_reason else "unconfigured"
    )
    return ModelRuntime(
        embedder=DeterministicEmbedder(),
        reranker=DeterministicReranker(),
        pack_id=pack_id,
        pack_activation=adapter_activation,
        components=(
            RuntimeComponent(
                name="signed-hashing-vector",
                version="1",
                purpose="deterministic dense-like retrieval fallback",
                activation="fallback",
                dimensions=128,
            ),
            RuntimeComponent(
                name="deterministic-lexical-reranker",
                version="1",
                purpose="deterministic local reranking fallback",
                activation="fallback",
            ),
            RuntimeComponent(
                name="bge-small-en-v1.5-onnx",
                version="unconfigured",
                purpose="local semantic dense retrieval",
                activation=adapter_activation,
                model_id=DENSE_MODEL_ID,
                revision=DENSE_REVISION,
                dimensions=384,
                failure_reason=failure_reason,
            ),
            RuntimeComponent(
                name="ms-marco-MiniLM-L6-v2-onnx",
                version="unconfigured",
                purpose="local cross-encoder reranking",
                activation=adapter_activation,
                model_id=RERANKER_MODEL_ID,
                revision=RERANKER_REVISION,
                failure_reason=failure_reason,
            ),
        ),
    )


def load_model_runtime(settings: Settings) -> ModelRuntime:
    if settings.model_pack_dir is None:
        return _fallback_runtime()
    if not settings.model_pack_trust_key:
        error = ModelPackError(
            "trust_key_missing", "A configured model pack requires a separate trust key"
        )
        if settings.release_mode:
            raise error
        return _fallback_runtime(failure_reason=error.code)
    try:
        pack = load_and_verify_manifest(
            settings.model_pack_dir, settings.model_pack_trust_key
        )
        dense_spec = pack.components["dense"]
        reranker_spec = pack.components["reranker"]
        embedder = OnnxDenseEmbedder(settings.model_pack_dir, pack.pack_id, dense_spec)
        reranker = OnnxCrossEncoderReranker(settings.model_pack_dir, reranker_spec)
    except ModelPackError as exc:
        if settings.release_mode:
            raise
        return _fallback_runtime(failure_reason=exc.code)
    return ModelRuntime(
        embedder=embedder,
        reranker=reranker,
        pack_id=pack.pack_id,
        pack_activation="active",
        components=(
            RuntimeComponent(
                name="signed-hashing-vector",
                version="1",
                purpose="deterministic dense-like retrieval fallback",
                activation="standby",
                dimensions=128,
            ),
            RuntimeComponent(
                name="deterministic-lexical-reranker",
                version="1",
                purpose="deterministic local reranking fallback",
                activation="standby",
            ),
            RuntimeComponent(
                name="bge-small-en-v1.5-onnx",
                version=dense_spec.adapter_version,
                purpose="local semantic dense retrieval",
                activation="active",
                model_id=dense_spec.model_id,
                revision=dense_spec.revision,
                artifact_sha256=_component_digest(dense_spec),
                dimensions=dense_spec.dimensions,
                provider="CPUExecutionProvider",
            ),
            RuntimeComponent(
                name="ms-marco-MiniLM-L6-v2-onnx",
                version=reranker_spec.adapter_version,
                purpose="local cross-encoder reranking",
                activation="active",
                model_id=reranker_spec.model_id,
                revision=reranker_spec.revision,
                artifact_sha256=_component_digest(reranker_spec),
                provider="CPUExecutionProvider",
            ),
        ),
    )
