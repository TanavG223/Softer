#!/usr/bin/env python3
"""Run the frozen PaceBack benchmark against the local engine.

This adapter never calls the network, never consumes expected answers when
constructing a request or result, and never invents a human review. It creates
one isolated synthetic profile namespace per age cohort in a temporary SQLite
database, imports only repository-owned fixtures, and maps every runtime chunk
back to a declared evidence-manifest source while retaining the runtime IDs.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal
from uuid import NAMESPACE_URL, uuid5

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_DIR = PROJECT_ROOT / "benchmark"
ENGINE_SRC = PROJECT_ROOT / "engine" / "src"
if str(ENGINE_SRC) not in sys.path:
    sys.path.insert(0, str(ENGINE_SRC))
if str(BENCHMARK_DIR) not in sys.path:
    sys.path.insert(0, str(BENCHMARK_DIR))

_evaluation = importlib.import_module("evaluate")
_validation = importlib.import_module("validate_benchmark")
ValidationError = _validation.ValidationError
_canonical_sha256 = _validation._canonical_sha256
evaluate = _evaluation.evaluate
validate_benchmark = _validation.validate_benchmark

from paceback_engine import __version__ as engine_version
from paceback_engine.config import Settings
from paceback_engine.database import PUBLIC_NAMESPACE, Database
from paceback_engine.retrieval import token_count
from paceback_engine.schemas import (
    ActingRole,
    AgeBand,
    CareContext,
    DocumentCreate,
    EvidenceScope,
    ProfileCreate,
    RunRequest,
    RunResponse,
    SourceKind,
    SupportStatus,
)
from paceback_engine.service import PaceBackService

RUNNER_SCHEMA_VERSION = "1.0"
RUNNER_VERSION = "2"
Mode = Literal["dev", "full"]

OFFICIAL_DOCUMENT_TO_MANIFEST = {
    "cdc-danger-signs-2025": "cdc_danger_signs",
    "cdc-danger-signs-young-child-2025": "cdc_danger_signs",
    "cdc-school-child-2025": "cdc_return_school",
    "cdc-school-teen-2025": "cdc_return_school",
    "cdc-work-adult-2024": "cdc_return_work",
    "cdc-work-older-adult-2024": "cdc_return_work",
    "amsterdam-consensus-2023": "amsterdam_consensus",
}

COHORT_CONFIG: dict[str, dict[str, Any]] = {
    "child_caregiver": {
        "age_band": AgeBand.CHILD_6_TO_12,
        "owner_role": ActingRole.CAREGIVER,
        "acting_role": ActingRole.CAREGIVER,
        "caregiver_access": False,
        "plan_id": "synthetic_child_school",
    },
    "teen": {
        "age_band": AgeBand.TEEN_13_TO_17,
        "owner_role": ActingRole.GUARDIAN,
        "acting_role": ActingRole.TEEN_USER,
        "caregiver_access": False,
        "plan_id": "synthetic_teen_school",
    },
    "adult": {
        "age_band": AgeBand.ADULT_18_TO_64,
        "owner_role": ActingRole.SELF_MANAGED,
        "acting_role": ActingRole.SELF_MANAGED,
        "caregiver_access": False,
        "plan_id": "synthetic_adult_work",
    },
    "older_adult_caregiver": {
        "age_band": AgeBand.OLDER_ADULT_65_PLUS,
        "owner_role": ActingRole.SELF_MANAGED,
        "acting_role": ActingRole.CAREGIVER,
        "caregiver_access": True,
        "plan_id": "synthetic_older_adult",
    },
    # Age-ambiguous describes the question stratum, not an age-less runtime.
    # These cases execute in an explicit adult fixture with the same mandatory
    # [allAges, selectedAgeBand] scope as every other profile.
    "age_ambiguous": {
        "age_band": AgeBand.ADULT_18_TO_64,
        "owner_role": ActingRole.SELF_MANAGED,
        "acting_role": ActingRole.SELF_MANAGED,
        "caregiver_access": False,
        "plan_id": None,
    },
}

CARE_CONTEXT_MAP = {
    "return_to_school": CareContext.SCHOOL,
    "return_to_work": CareContext.WORK,
    "daily_activity": CareContext.DAILY_LIVING,
    "general_information": CareContext.HOME,
}

RUNTIME_SCOPE_TO_EVALUATION_SCOPE = {
    "allAges": "all_ages",
    "youngChild0To5": "pediatric",
    "child6To12": "pediatric",
    "teen13To17": "teen",
    "adult18To64": "adult",
    "olderAdult65Plus": "older_adult",
}


class RunnerError(ValidationError):
    """A fail-closed benchmark execution or adaptation error."""


@dataclass(frozen=True, slots=True)
class RuntimeItem:
    """Only fields permitted to influence runtime execution.

    Expected responses, expected sources, concepts, canaries, and human labels
    are deliberately absent from this type, including for held-out items.
    """

    item_id: str
    split: str
    age_cohort: str
    prompt: str
    care_context: str


@dataclass(frozen=True, slots=True)
class SourceRegistration:
    manifest_source_id: str
    source_kind: str
    evaluation_age_scope: str | None = None


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _sha256_python_tree(root: Path) -> str:
    """Hash path names and bytes for the engine Python source tree."""

    records = [
        {
            "path": path.relative_to(root).as_posix(),
            "sha256": _sha256_file(path),
        }
        for path in sorted(root.rglob("*.py"))
        if path.is_file()
    ]
    if not records:
        raise RunnerError(f"engine source tree is empty: {root}")
    return _canonical_sha256(records)


def _runtime_items(benchmark: dict[str, Any], mode: Mode) -> list[RuntimeItem]:
    selected: list[RuntimeItem] = []
    for source in benchmark["items"]:
        if mode == "dev" and source["split"] != "dev":
            continue
        selected.append(
            RuntimeItem(
                item_id=source["id"],
                split=source["split"],
                age_cohort=source["age_cohort"],
                prompt=source["prompt"],
                care_context=source["care_context"],
            )
        )
    expected_count = 60 if mode == "dev" else 100
    if len(selected) != expected_count:
        raise RunnerError(
            f"{mode} mode must select exactly {expected_count} items, found {len(selected)}"
        )
    return selected


class LocalEngineAdapter:
    """Own a temporary, network-disabled PaceBack service for one benchmark run."""

    def __init__(
        self,
        *,
        project_root: Path,
        benchmark_sha256: str,
        evidence_manifest: dict[str, Any],
        data_dir: Path,
        model_pack_dir: Path | None = None,
        model_pack_trust_key: str | None = None,
    ) -> None:
        self.project_root = project_root
        self.benchmark_sha256 = benchmark_sha256
        self.manifest_sources = {
            source["id"]: source for source in evidence_manifest["sources"]
        }
        settings = Settings(
            data_dir=data_dir,
            auth_token="benchmark-local-only-token-32-bytes-minimum",
            release_mode=False,
            database_driver="sqlite",
            storage_key=None,
            model_pack_dir=model_pack_dir,
            model_pack_trust_key=model_pack_trust_key,
        )
        self.database = Database(settings.database_path)
        self.database.initialize()
        self.service = PaceBackService(self.database, settings)
        self.profile_ids: dict[str, str] = {}
        self.private_sources: dict[str, dict[str, SourceRegistration]] = {}

    def prepare(self, cohorts: set[str]) -> None:
        plans = json.loads(
            (
                self.project_root / "benchmark" / "synthetic_clinician_plans.json"
            ).read_text(encoding="utf-8")
        )
        plans_by_id = {plan["plan_id"]: plan for plan in plans["plans"]}
        product_policy = (self.project_root / "docs" / "product_policy.md").read_text(
            encoding="utf-8"
        )
        for cohort in sorted(cohorts):
            config = COHORT_CONFIG.get(cohort)
            if config is None:
                raise RunnerError(f"unsupported age cohort: {cohort}")
            profile_id = str(
                uuid5(
                    NAMESPACE_URL,
                    f"paceback-benchmark:{self.benchmark_sha256}:{cohort}",
                )
            )
            self.service.sync_profile(
                profile_id,
                ProfileCreate(
                    alias=f"Synthetic {cohort.replace('_', ' ')}",
                    age_band=config["age_band"],
                    owner_role=config["owner_role"],
                    caregiver_access=config["caregiver_access"],
                ),
            )
            self.profile_ids[cohort] = profile_id
            self.private_sources[profile_id] = {}
            self._register_document(
                profile_id=profile_id,
                role=config["owner_role"],
                age_band=config["age_band"],
                title="PaceBack product and safety policy",
                content=product_policy,
                source_kind=SourceKind.USER_PROVIDED,
                registration=SourceRegistration(
                    manifest_source_id="paceback_product_policy",
                    source_kind=SourceKind.USER_PROVIDED.value,
                    evaluation_age_scope="all_ages",
                ),
            )
            plan_id = config["plan_id"]
            if plan_id is not None:
                plan = plans_by_id.get(plan_id)
                if plan is None:
                    raise RunnerError(f"missing synthetic plan fixture: {plan_id}")
                content = "\f".join(page["text"] for page in plan["pages"])
                self._register_document(
                    profile_id=profile_id,
                    role=config["owner_role"],
                    age_band=config["age_band"],
                    title=f"Synthetic clinician plan: {plan_id}",
                    content=content,
                    source_kind=SourceKind.CLINICIAN_PLAN,
                    registration=SourceRegistration(
                        manifest_source_id="synthetic_clinician_plans",
                        source_kind=SourceKind.CLINICIAN_PLAN.value,
                        evaluation_age_scope=plan["age_scope"],
                    ),
                )

    def _register_document(
        self,
        *,
        profile_id: str,
        role: ActingRole,
        age_band: AgeBand,
        title: str,
        content: str,
        source_kind: SourceKind,
        registration: SourceRegistration,
    ) -> None:
        if registration.manifest_source_id not in self.manifest_sources:
            raise RunnerError(
                f"source mapping is absent from manifest: {registration.manifest_source_id}"
            )
        document = self.service.create_document(
            profile_id,
            DocumentCreate(
                acting_role=role,
                title=title,
                content=content,
                source_kind=source_kind,
                evidence_scope=EvidenceScope(age_band.value),
            ),
        )
        self.private_sources[profile_id][document.document_id] = registration

    def model_manifest(self) -> dict[str, Any]:
        return self.service.model_manifest().model_dump(mode="json", by_alias=True)

    def run_item(self, item: RuntimeItem, config_sha256: str) -> dict[str, Any]:
        cohort = COHORT_CONFIG[item.age_cohort]
        profile_id = self.profile_ids[item.age_cohort]
        age_band: AgeBand = cohort["age_band"]
        run_id = str(
            uuid5(
                NAMESPACE_URL,
                f"paceback-benchmark-run:{self.benchmark_sha256}:{RUNNER_VERSION}:{item.item_id}",
            )
        )
        request = RunRequest(
            run_id=run_id,
            profile_id=profile_id,
            age_band=age_band,
            acting_role=cohort["acting_role"],
            care_context=CARE_CONTEXT_MAP[item.care_context],
            evidence_scope=[EvidenceScope.ALL_AGES, EvidenceScope(age_band.value)],
            question=item.prompt,
            max_output_tokens=512,
        )
        adapter_started = time.perf_counter()
        try:
            response = self.service.run(request)
        except Exception as exc:
            raise RunnerError(f"{item.item_id}: local engine execution failed") from exc
        adapter_latency_ms = (time.perf_counter() - adapter_started) * 1_000
        if not isinstance(response, RunResponse):
            raise RunnerError(f"{item.item_id}: engine returned a malformed response")
        sources, claim_sources = self._adapt_citations(item, response)
        response_type = self._response_type(response)
        prompt_tokens = token_count(item.prompt)
        context_tokens = max(0, response.usage.input_tokens - prompt_tokens)
        metadata = {
            "schema_version": RUNNER_SCHEMA_VERSION,
            "runner_version": RUNNER_VERSION,
            "mode_config_sha256": config_sha256,
            "review_status": "unreviewed",
            "clinical_correctness": "not_measured",
            "promotion_gates": "not_evaluated",
            "expected_labels_used_for_runtime_decisions": False,
            "heldout_labels_used_for_tuning": False,
            "local_only": True,
            "retrieved_sources_semantics": "engine-returned cited hits only",
        }
        return {
            "item_id": item.item_id,
            "split": item.split,
            "profile_id": profile_id,
            "profile_namespace": profile_id,
            "age_cohort": item.age_cohort,
            "runtime_age_band": age_band.value,
            "age_ambiguous_adapter": (
                "question stratum executed in selected adult18To64 fixture"
                if item.age_cohort == "age_ambiguous"
                else None
            ),
            "acting_role": cohort["acting_role"].value,
            "care_context": CARE_CONTEXT_MAP[item.care_context].value,
            "evidence_scope": [EvidenceScope.ALL_AGES.value, age_band.value],
            "runtime_run_id": response.run_id,
            "response_type": response_type,
            "answer": response.answer,
            "support_status": response.support_status.value,
            "route": response.route.value,
            "stop_reason": response.stop_reason.value,
            "retrieved_sources": sources,
            "claims": [
                {
                    "text": citation.quote,
                    "citations": [source_id],
                    "review": "unreviewed",
                }
                for citation, source_id in claim_sources
            ],
            "timing": {
                "latency_ms": response.usage.latency_ms,
                "adapter_latency_ms": adapter_latency_ms,
            },
            "token_usage": {
                "input_tokens": response.usage.input_tokens,
                "context_tokens": context_tokens,
                "retrieved_tokens": response.usage.retrieved_tokens,
                "output_tokens": response.usage.output_tokens,
                "retrieval_rounds": response.usage.retrieval_rounds,
            },
            "run_metadata": metadata,
        }

    @staticmethod
    def _response_type(response: RunResponse) -> str:
        if response.support_status is SupportStatus.DANGER_SIGN_DETECTED:
            return "emergency_redirect"
        if response.support_status in {
            SupportStatus.INSUFFICIENT_INFORMATION,
            SupportStatus.CANCELLED,
        }:
            return "abstain"
        if response.support_status in {SupportStatus.VERIFIED, SupportStatus.PARTIAL}:
            return "answer"
        raise RunnerError(f"unsupported engine status: {response.support_status}")

    def _adapt_citations(
        self, item: RuntimeItem, response: RunResponse
    ) -> tuple[list[dict[str, Any]], list[tuple[Any, str]]]:
        profile_id = self.profile_ids[item.age_cohort]
        by_manifest_id: dict[str, dict[str, Any]] = {}
        claim_sources: list[tuple[Any, str]] = []
        for citation in response.citations:
            source = self.database.get_source(profile_id, citation.source_id)
            if source is None:
                raise RunnerError(
                    f"{item.item_id}: citation source is outside the active namespace"
                )
            if (
                source["document_id"] != citation.document_id
                or source["content_hash"] != citation.content_hash
                or source["page_number"] != citation.page
            ):
                raise RunnerError(f"{item.item_id}: citation locator metadata drifted")
            relative_start = citation.char_start - int(source["char_start"])
            relative_end = citation.char_end - int(source["char_start"])
            if (
                relative_start < 0
                or relative_end <= relative_start
                or source["content"][relative_start:relative_end] != citation.quote
            ):
                raise RunnerError(f"{item.item_id}: citation quote is not locatable")

            namespace = str(source["namespace"])
            registration = self._source_registration(
                profile_id=profile_id,
                document_id=citation.document_id,
                namespace=namespace,
            )
            manifest_id = registration.manifest_source_id
            runtime_scope = str(source["age_scope"])
            evaluation_scope = (
                registration.evaluation_age_scope
                or RUNTIME_SCOPE_TO_EVALUATION_SCOPE.get(runtime_scope)
            )
            if evaluation_scope is None:
                raise RunnerError(
                    f"{item.item_id}: unsupported runtime age scope {runtime_scope}"
                )
            declared_scopes = self.manifest_sources[manifest_id]["age_scopes"]
            if evaluation_scope not in declared_scopes:
                raise RunnerError(
                    f"{item.item_id}: mapped age scope is absent from evidence manifest"
                )
            record = {
                "source_id": manifest_id,
                "runtime_source_id": citation.source_id,
                "document_id": citation.document_id,
                "source_kind": registration.source_kind,
                "age_scope": evaluation_scope,
                "runtime_age_scope": runtime_scope,
                "namespace": namespace,
                "profile_id": None if namespace == PUBLIC_NAMESPACE else namespace,
                "locator": {
                    "page": citation.page,
                    "char_start": citation.char_start,
                    "char_end": citation.char_end,
                    "content_hash": citation.content_hash,
                    "quote_sha256": _sha256_bytes(citation.quote.encode("utf-8")),
                },
            }
            by_manifest_id.setdefault(manifest_id, record)
            claim_sources.append((citation, manifest_id))
        return list(by_manifest_id.values()), claim_sources

    def _source_registration(
        self, *, profile_id: str, document_id: str, namespace: str
    ) -> SourceRegistration:
        if namespace == PUBLIC_NAMESPACE:
            manifest_source_id = OFFICIAL_DOCUMENT_TO_MANIFEST.get(document_id)
            if manifest_source_id is None:
                raise RunnerError(f"unmapped public runtime document: {document_id}")
            registration = SourceRegistration(
                manifest_source_id=manifest_source_id,
                source_kind=SourceKind.OFFICIAL_BUNDLED.value,
            )
        elif namespace == profile_id:
            registration = self.private_sources[profile_id].get(document_id)  # type: ignore[assignment]
            if registration is None:
                raise RunnerError(
                    f"unmapped private runtime document in active profile: {document_id}"
                )
        else:
            raise RunnerError("private citation crossed the active profile namespace")
        if registration.manifest_source_id not in self.manifest_sources:
            raise RunnerError(
                f"runtime source maps to unknown manifest ID: "
                f"{registration.manifest_source_id}"
            )
        return registration


def _frozen_config(
    *,
    mode: Mode,
    validation: dict[str, Any],
    items: list[RuntimeItem],
    adapter: LocalEngineAdapter,
) -> dict[str, Any]:
    model_manifest = adapter.model_manifest()
    runtime_inputs = {
        "product_policy_sha256": _sha256_file(
            adapter.project_root / "docs" / "product_policy.md"
        ),
        "synthetic_plans_sha256": _sha256_file(
            adapter.project_root / "benchmark" / "synthetic_clinician_plans.json"
        ),
        "evidence_seed_sha256": _sha256_file(
            adapter.project_root
            / "engine"
            / "src"
            / "paceback_engine"
            / "resources"
            / "evidence_seed.json"
        ),
        "engine_python_tree_sha256": _sha256_python_tree(
            adapter.project_root / "engine" / "src" / "paceback_engine"
        ),
    }
    frozen = {
        "schema_version": RUNNER_SCHEMA_VERSION,
        "runner_version": RUNNER_VERSION,
        "mode": mode,
        "selected_item_count": len(items),
        "selected_item_ids_sha256": _canonical_sha256([item.item_id for item in items]),
        "benchmark_sha256": validation["benchmark_sha256"],
        "evidence_manifest_sha256": validation["evidence_manifest_sha256"],
        "runner_file_sha256": _sha256_file(Path(__file__)),
        "engine_version": engine_version,
        "model_manifest": model_manifest,
        "model_manifest_sha256": _canonical_sha256(model_manifest),
        "runtime_input_sha256": runtime_inputs,
        "engine_settings": {
            "release_mode": False,
            "database_driver": "sqlite",
            "network_calls": False,
            "max_output_tokens": 512,
            "model_pack_activation": model_manifest["modelPackActivation"],
            "model_pack_id": model_manifest["modelPackID"],
        },
        "profile_ids": dict(sorted(adapter.profile_ids.items())),
        "review_status": "unreviewed",
        "clinical_correctness": "not_measured",
        "claim_support_review": "not_measured",
        "promotion_gates": "not_evaluated",
        "expected_labels_used_for_runtime_decisions": False,
        "heldout_labels_used_for_tuning": False,
    }
    return {**frozen, "config_sha256": _canonical_sha256(frozen)}


def run_benchmark(
    *,
    mode: Mode,
    benchmark_path: Path,
    evidence_path: Path,
    project_root: Path = PROJECT_ROOT,
    model_pack_dir: Path | None = None,
    model_pack_trust_key: str | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if (model_pack_dir is None) != (model_pack_trust_key is None):
        raise RunnerError(
            "model pack directory and public trust key must be supplied together"
        )
    validation = validate_benchmark(benchmark_path, evidence_path)
    benchmark = json.loads(benchmark_path.read_text(encoding="utf-8"))
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    items = _runtime_items(benchmark, mode)
    with tempfile.TemporaryDirectory(prefix="paceback-benchmark-") as directory:
        adapter = LocalEngineAdapter(
            project_root=project_root,
            benchmark_sha256=validation["benchmark_sha256"],
            evidence_manifest=evidence,
            data_dir=Path(directory),
            model_pack_dir=model_pack_dir,
            model_pack_trust_key=model_pack_trust_key,
        )
        adapter.prepare({item.age_cohort for item in items})
        metadata = _frozen_config(
            mode=mode,
            validation=validation,
            items=items,
            adapter=adapter,
        )
        records = [adapter.run_item(item, metadata["config_sha256"]) for item in items]

        # Validate the exact serialized bytes before they are allowed into an
        # immutable output path. This uses the same evaluator as release reports.
        candidate = Path(directory) / "candidate.jsonl"
        _write_literal_lf(candidate, records, exclusive=True)
        summary = evaluate(
            benchmark_path,
            evidence_path,
            candidate,
            allow_partial=mode == "dev",
        )
        metadata["run_output_sha256"] = summary["run_output_sha256"]
        metadata["automated_evaluation"] = {
            "status": "unreviewed",
            "complete": summary["complete"],
            "output_count": summary["output_count"],
            "human_accuracy": summary["metrics"]["human_accuracy"],
            "citation_precision": summary["metrics"]["citation_precision"],
            "unsupported_claim_rate": summary["metrics"]["unsupported_claim_rate"],
            "performance_claim_allowed": False,
        }
        return records, metadata


def _write_literal_lf(
    path: Path, records: list[dict[str, Any]], *, exclusive: bool
) -> None:
    mode = "x" if exclusive else "w"
    with path.open(mode, encoding="utf-8", newline="\n") as handle:
        for record in records:
            rendered = json.dumps(
                record,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=False,
                allow_nan=False,
            )
            handle.write(rendered)
            handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    payload = path.read_bytes()
    if b"\r" in payload or (payload and not payload.endswith(b"\n")):
        raise RunnerError("JSONL writer did not produce literal-LF records")


def write_artifacts(
    output_path: Path,
    records: list[dict[str, Any]],
    metadata: dict[str, Any],
) -> Path:
    metadata_path = Path(f"{output_path}.metadata.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        raise RunnerError(f"refusing to overwrite existing run output: {output_path}")
    if metadata_path.exists():
        raise RunnerError(f"refusing to overwrite existing metadata: {metadata_path}")
    _write_literal_lf(output_path, records, exclusive=True)
    try:
        with metadata_path.open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(metadata, handle, indent=2, sort_keys=True, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
    except FileExistsError as exc:
        raise RunnerError(
            f"refusing to overwrite existing metadata: {metadata_path}"
        ) from exc
    return metadata_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("dev", "full"),
        default="dev",
        help="dev runs exactly 60 development items; full runs all 100 once",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--benchmark", type=Path, default=BENCHMARK_DIR / "benchmark.json"
    )
    parser.add_argument(
        "--evidence",
        type=Path,
        default=PROJECT_ROOT / "docs" / "evidence_manifest.json",
    )
    parser.add_argument(
        "--model-pack-dir",
        type=Path,
        help="optional local signed model pack; never downloaded by this runner",
    )
    parser.add_argument(
        "--model-trust-key-file",
        type=Path,
        help="file containing the base64 Ed25519 public key outside the model pack",
    )
    args = parser.parse_args(argv)
    try:
        model_pack_trust_key = None
        if args.model_trust_key_file is not None:
            model_pack_trust_key = args.model_trust_key_file.read_text(
                encoding="utf-8"
            ).strip()
            if not model_pack_trust_key:
                raise RunnerError("model trust-key file is empty")
        records, metadata = run_benchmark(
            mode=args.mode,
            benchmark_path=args.benchmark,
            evidence_path=args.evidence,
            model_pack_dir=args.model_pack_dir,
            model_pack_trust_key=model_pack_trust_key,
        )
        metadata_path = write_artifacts(args.output, records, metadata)
    except (RunnerError, ValidationError, OSError, ValueError) as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": str(exc),
                    "review_status": "unreviewed",
                    "promotion_gates": "not_evaluated",
                },
                indent=2,
            ),
            file=sys.stderr,
        )
        return 1
    print(
        json.dumps(
            {
                "ok": True,
                "mode": args.mode,
                "output": str(args.output),
                "metadata": str(metadata_path),
                "record_count": len(records),
                "review_status": "unreviewed",
                "clinical_correctness": "not_measured",
                "promotion_gates": "not_evaluated",
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
