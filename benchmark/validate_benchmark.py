#!/usr/bin/env python3
"""Validate the PaceBack benchmark and evidence manifest with no dependencies.

This validator is intentionally strict. It treats a malformed item, an unknown
source, or any count drift as a release-blocking error instead of silently
dropping data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

QUERY_TYPES = (
    "keyword_numeric",
    "semantic",
    "multi_hop",
    "unanswerable_conflicting",
    "adversarial_isolation",
)
AGE_COHORTS = (
    "child_caregiver",
    "teen",
    "adult",
    "older_adult_caregiver",
    "age_ambiguous",
)
SPLITS = ("dev", "heldout")

EXPECTED_QUERY_COUNTS = {query_type: 20 for query_type in QUERY_TYPES}
EXPECTED_QUERY_SPLITS = {
    query_type: {"dev": 12, "heldout": 8} for query_type in QUERY_TYPES
}
EXPECTED_AGE_COUNTS = {
    "child_caregiver": 25,
    "teen": 25,
    "adult": 25,
    "older_adult_caregiver": 15,
    "age_ambiguous": 10,
}
EXPECTED_AGE_SPLITS = {
    "child_caregiver": {"dev": 15, "heldout": 10},
    "teen": {"dev": 15, "heldout": 10},
    "adult": {"dev": 15, "heldout": 10},
    "older_adult_caregiver": {"dev": 9, "heldout": 6},
    "age_ambiguous": {"dev": 6, "heldout": 4},
}
REQUIRED_ITEM_FIELDS = {
    "id",
    "query_type",
    "age_cohort",
    "split",
    "acting_role",
    "care_context",
    "prompt",
    "expected_response",
    "expected_behavior",
    "expected_source_ids",
    "required_concepts",
    "forbidden_claims",
    "canary_tokens",
    "human_review",
}
EXPECTED_RESPONSES = {"answer", "abstain", "boundary_redirect", "emergency_redirect"}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]{2,63}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class ValidationError(ValueError):
    """A deterministic, human-readable validation failure."""


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValidationError(f"missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationError(f"invalid JSON in {path}: {exc}") from exc


def _canonical_sha256(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _require_nonempty_string(value: Any, label: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{label} must be a non-empty string")


def _require_string_list(value: Any, label: str, *, allow_empty: bool = True) -> None:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise ValidationError(f"{label} must be a list of non-empty strings")
    if not allow_empty and not value:
        raise ValidationError(f"{label} must not be empty")
    if len(value) != len(set(value)):
        raise ValidationError(f"{label} must not contain duplicates")


def validate_evidence_manifest(path: Path) -> dict[str, Any]:
    manifest = _read_json(path)
    if not isinstance(manifest, dict) or manifest.get("schema_version") != "1.0":
        raise ValidationError("evidence manifest schema_version must be '1.0'")
    sources = manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        raise ValidationError("evidence manifest sources must be a non-empty list")

    ids: list[str] = []
    for index, source in enumerate(sources):
        label = f"evidence source[{index}]"
        if not isinstance(source, dict):
            raise ValidationError(f"{label} must be an object")
        for key in (
            "id",
            "kind",
            "title",
            "publisher",
            "url",
            "age_scopes",
            "license_status",
            "redistribution",
            "storage_mode",
            "last_verified",
        ):
            if key not in source:
                raise ValidationError(f"{label} missing {key}")
        source_id = source["id"]
        if not isinstance(source_id, str) or not ID_PATTERN.fullmatch(source_id):
            raise ValidationError(f"{label}.id has invalid format")
        ids.append(source_id)
        _require_nonempty_string(source["title"], f"{label}.title")
        _require_nonempty_string(source["publisher"], f"{label}.publisher")
        _require_string_list(
            source["age_scopes"], f"{label}.age_scopes", allow_empty=False
        )
        _require_nonempty_string(source["license_status"], f"{label}.license_status")
        _require_nonempty_string(source["redistribution"], f"{label}.redistribution")
        _require_nonempty_string(source["storage_mode"], f"{label}.storage_mode")
        _require_nonempty_string(source["last_verified"], f"{label}.last_verified")

        url = source["url"]
        kind = source["kind"]
        if kind == "external":
            if not isinstance(url, str) or not url.startswith("https://"):
                raise ValidationError(f"{label}.url must be HTTPS for external sources")
            if source["storage_mode"] != "link_only":
                raise ValidationError(
                    f"{label}: external material must remain link_only in this repository"
                )
        elif kind == "project_original":
            if not isinstance(url, str) or not url.startswith("repo://"):
                raise ValidationError(
                    f"{label}.url must use repo:// for project originals"
                )
        else:
            raise ValidationError(f"{label}.kind must be external or project_original")

    if len(ids) != len(set(ids)):
        raise ValidationError("evidence source ids must be unique")
    return manifest


def validate_benchmark(path: Path, evidence_path: Path) -> dict[str, Any]:
    evidence = validate_evidence_manifest(evidence_path)
    known_sources = {source["id"] for source in evidence["sources"]}
    benchmark = _read_json(path)
    if not isinstance(benchmark, dict) or benchmark.get("schema_version") != "1.0":
        raise ValidationError("benchmark schema_version must be '1.0'")
    if benchmark.get("dataset_name") != "paceback_all_ages_v1":
        raise ValidationError("unexpected dataset_name")
    items = benchmark.get("items")
    if not isinstance(items, list):
        raise ValidationError("benchmark.items must be a list")
    if len(items) != 100:
        raise ValidationError(
            f"benchmark must contain exactly 100 items, found {len(items)}"
        )

    ids: list[str] = []
    prompts: list[str] = []
    query_counts: Counter[str] = Counter()
    age_counts: Counter[str] = Counter()
    split_counts: Counter[str] = Counter()
    query_split_counts: Counter[tuple[str, str]] = Counter()
    age_split_counts: Counter[tuple[str, str]] = Counter()

    for index, item in enumerate(items):
        label = f"item[{index}]"
        if not isinstance(item, dict):
            raise ValidationError(f"{label} must be an object")
        missing = REQUIRED_ITEM_FIELDS - set(item)
        extra = set(item) - REQUIRED_ITEM_FIELDS
        if missing or extra:
            raise ValidationError(
                f"{label} fields mismatch; missing={sorted(missing)}, extra={sorted(extra)}"
            )
        item_id = item["id"]
        if not isinstance(item_id, str) or not ID_PATTERN.fullmatch(item_id):
            raise ValidationError(f"{label}.id has invalid format")
        ids.append(item_id)
        for key in ("acting_role", "care_context", "prompt", "expected_behavior"):
            _require_nonempty_string(item[key], f"{label}.{key}")

        query_type = item["query_type"]
        age_cohort = item["age_cohort"]
        split = item["split"]
        expected_response = item["expected_response"]
        if query_type not in QUERY_TYPES:
            raise ValidationError(f"{label}.query_type is invalid")
        if age_cohort not in AGE_COHORTS:
            raise ValidationError(f"{label}.age_cohort is invalid")
        if split not in SPLITS:
            raise ValidationError(f"{label}.split is invalid")
        if expected_response not in EXPECTED_RESPONSES:
            raise ValidationError(f"{label}.expected_response is invalid")

        for key in (
            "expected_source_ids",
            "required_concepts",
            "forbidden_claims",
            "canary_tokens",
        ):
            _require_string_list(item[key], f"{label}.{key}")
        unknown_sources = set(item["expected_source_ids"]) - known_sources
        if unknown_sources:
            raise ValidationError(
                f"{label} references unknown sources: {sorted(unknown_sources)}"
            )
        if expected_response == "answer" and not item["expected_source_ids"]:
            raise ValidationError(
                f"{label}: answer items require at least one expected source"
            )
        if query_type == "adversarial_isolation" and not item["canary_tokens"]:
            raise ValidationError(f"{label}: adversarial items require a canary token")
        if query_type != "adversarial_isolation" and item["canary_tokens"]:
            raise ValidationError(
                f"{label}: only adversarial items may define canary tokens"
            )

        review = item["human_review"]
        if not isinstance(review, dict) or set(review) != {"status", "notes"}:
            raise ValidationError(f"{label}.human_review must contain status and notes")
        if review["status"] not in {"pending", "reviewed"}:
            raise ValidationError(f"{label}.human_review.status is invalid")
        if not isinstance(review["notes"], str):
            raise ValidationError(f"{label}.human_review.notes must be a string")

        normalized_prompt = " ".join(item["prompt"].casefold().split())
        prompts.append(normalized_prompt)
        query_counts[query_type] += 1
        age_counts[age_cohort] += 1
        split_counts[split] += 1
        query_split_counts[(query_type, split)] += 1
        age_split_counts[(age_cohort, split)] += 1

    if len(ids) != len(set(ids)):
        raise ValidationError("benchmark ids must be unique")
    if len(prompts) != len(set(prompts)):
        raise ValidationError("benchmark prompts must be unique after normalization")
    if dict(query_counts) != EXPECTED_QUERY_COUNTS:
        raise ValidationError(
            f"query counts must be {EXPECTED_QUERY_COUNTS}, found {dict(query_counts)}"
        )
    if dict(age_counts) != EXPECTED_AGE_COUNTS:
        raise ValidationError(
            f"age counts must be {EXPECTED_AGE_COUNTS}, found {dict(age_counts)}"
        )
    if dict(split_counts) != {"dev": 60, "heldout": 40}:
        raise ValidationError(
            f"split counts must be dev=60/heldout=40, found {dict(split_counts)}"
        )
    for query_type, expected in EXPECTED_QUERY_SPLITS.items():
        found = {split: query_split_counts[(query_type, split)] for split in SPLITS}
        if found != expected:
            raise ValidationError(
                f"{query_type} split counts must be {expected}, found {found}"
            )
    for age_cohort, expected in EXPECTED_AGE_SPLITS.items():
        found = {split: age_split_counts[(age_cohort, split)] for split in SPLITS}
        if found != expected:
            raise ValidationError(
                f"{age_cohort} split counts must be {expected}, found {found}"
            )

    return {
        "valid": True,
        "benchmark_sha256": _canonical_sha256(benchmark),
        "evidence_manifest_sha256": _canonical_sha256(evidence),
        "item_count": len(items),
        "query_type_counts": dict(sorted(query_counts.items())),
        "age_cohort_counts": dict(sorted(age_counts.items())),
        "split_counts": dict(sorted(split_counts.items())),
    }


def _default_paths() -> tuple[Path, Path]:
    project_root = Path(__file__).resolve().parents[1]
    return (
        project_root / "benchmark" / "benchmark.json",
        project_root / "docs" / "evidence_manifest.json",
    )


def main(argv: list[str] | None = None) -> int:
    default_benchmark, default_evidence = _default_paths()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", type=Path, default=default_benchmark)
    parser.add_argument("--evidence", type=Path, default=default_evidence)
    args = parser.parse_args(argv)
    try:
        report = validate_benchmark(args.benchmark, args.evidence)
    except ValidationError as exc:
        print(
            json.dumps({"valid": False, "error": str(exc)}, indent=2), file=sys.stderr
        )
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
