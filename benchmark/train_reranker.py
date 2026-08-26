#!/usr/bin/env python3
"""Dependency-gated, offline training contract for the PaceBack reranker.

Only explicitly reviewed public/synthetic ``dev`` judgments are accepted.
Question groups—not individual passages—are split into train and validation.
Held-out benchmark prompts and labels are never loaded into the training rows.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import math
import os
import random
import re
import sys
from collections import defaultdict
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


class TrainingError(ValueError):
    """Fail-closed training contract violation."""


REQUIRED_FIELDS = {
    "judgment_id",
    "benchmark_item_id",
    "split",
    "source_kind",
    "review_status",
    "contains_user_data",
    "query",
    "passage",
    "relevance",
}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]{2,79}$")


def _canonical_hash(value: Any) -> str:
    encoded = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _read_dev_ids(benchmark_path: Path) -> set[str]:
    try:
        benchmark = json.loads(benchmark_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        raise TrainingError(f"cannot read benchmark metadata: {exc}") from exc
    items = benchmark.get("items") if isinstance(benchmark, dict) else None
    if not isinstance(items, list):
        raise TrainingError("benchmark.items must be a list")
    # Deliberately retain only identifiers and split metadata. Prompts, expected
    # behavior, and all held-out labels are not copied into the training process.
    return {
        item["id"]
        for item in items
        if isinstance(item, dict)
        and item.get("split") == "dev"
        and isinstance(item.get("id"), str)
    }


def load_reviewed_judgments(path: Path, benchmark_path: Path) -> list[dict[str, Any]]:
    dev_ids = _read_dev_ids(benchmark_path)
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except FileNotFoundError as exc:
        raise TrainingError(f"missing judgment file: {path}") from exc
    rows: list[dict[str, Any]] = []
    judgment_ids: set[str] = set()
    triples: set[tuple[str, str, str]] = set()
    for line_number, line in enumerate(lines, start=1):
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise TrainingError(f"invalid JSONL at line {line_number}: {exc}") from exc
        if not isinstance(row, dict) or set(row) != REQUIRED_FIELDS:
            raise TrainingError(
                f"line {line_number}: fields must be exactly {sorted(REQUIRED_FIELDS)}"
            )
        judgment_id = row["judgment_id"]
        item_id = row["benchmark_item_id"]
        if not isinstance(judgment_id, str) or not ID_PATTERN.fullmatch(judgment_id):
            raise TrainingError(f"line {line_number}: invalid judgment_id")
        if judgment_id in judgment_ids:
            raise TrainingError(f"line {line_number}: duplicate judgment_id")
        judgment_ids.add(judgment_id)
        if row["split"] != "dev" or item_id not in dev_ids:
            raise TrainingError(
                f"line {line_number}: heldout or unknown benchmark item is forbidden"
            )
        if row["source_kind"] not in {"public", "synthetic"}:
            raise TrainingError(
                f"line {line_number}: source_kind must be public or synthetic"
            )
        if row["review_status"] != "reviewed":
            raise TrainingError(f"line {line_number}: judgment is not reviewed")
        if row["contains_user_data"] is not False:
            raise TrainingError(f"line {line_number}: user data is forbidden")
        for key in ("query", "passage"):
            if not isinstance(row[key], str) or not row[key].strip():
                raise TrainingError(f"line {line_number}: {key} must be non-empty")
        relevance = row["relevance"]
        if (
            isinstance(relevance, bool)
            or not isinstance(relevance, int)
            or relevance not in {0, 1, 2}
        ):
            raise TrainingError(f"line {line_number}: relevance must be 0, 1, or 2")
        triple = (item_id, row["query"], row["passage"])
        if triple in triples:
            raise TrainingError(f"line {line_number}: duplicate query/passage judgment")
        triples.add(triple)
        rows.append(row)
    if not rows:
        raise TrainingError("judgment file is empty")

    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[row["benchmark_item_id"]].append(row)
    if len(grouped) < 5:
        raise TrainingError("at least five reviewed question groups are required")
    for item_id, group in grouped.items():
        labels = {row["relevance"] for row in group}
        if not any(label > 0 for label in labels) or 0 not in labels:
            raise TrainingError(
                f"question group {item_id} needs at least one relevant and one irrelevant passage"
            )
    return rows


def split_by_question(
    rows: list[dict[str, Any]], *, seed: int, validation_fraction: float
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str], list[str]]:
    if not 0.1 <= validation_fraction <= 0.5:
        raise TrainingError("validation_fraction must be between 0.1 and 0.5")
    group_ids = sorted(
        {row["benchmark_item_id"] for row in rows},
        key=lambda item_id: hashlib.sha256(f"{seed}:{item_id}".encode()).hexdigest(),
    )
    validation_count = max(1, round(len(group_ids) * validation_fraction))
    if len(group_ids) - validation_count < 2:
        raise TrainingError("split must retain at least two training question groups")
    validation_ids = set(group_ids[:validation_count])
    train_ids = set(group_ids[validation_count:])
    train_rows = [row for row in rows if row["benchmark_item_id"] in train_ids]
    validation_rows = [
        row for row in rows if row["benchmark_item_id"] in validation_ids
    ]
    return train_rows, validation_rows, sorted(train_ids), sorted(validation_ids)


def load_ml_dependencies(
    importer: Callable[[str], Any] = importlib.import_module,
) -> tuple[Any, Any]:
    try:
        sentence_transformers = importer("sentence_transformers")
        torch = importer("torch")
    except (ImportError, ModuleNotFoundError) as exc:
        raise TrainingError(
            "ML dependencies are unavailable. Install the pinned offline training extra; "
            "validation remains available with --validate-only."
        ) from exc
    for attribute in ("CrossEncoder", "InputExample"):
        if not hasattr(sentence_transformers, attribute):
            raise TrainingError(f"sentence_transformers is missing {attribute}")
    if not hasattr(torch, "utils"):
        raise TrainingError("torch DataLoader support is unavailable")
    return sentence_transformers, torch


def _ndcg_for_groups(rows: list[dict[str, Any]], scores: list[float]) -> float:
    if len(rows) != len(scores):
        raise TrainingError("prediction count does not match validation rows")
    grouped: dict[str, list[tuple[float, int]]] = defaultdict(list)
    for row, score in zip(rows, scores):
        if not math.isfinite(float(score)):
            raise TrainingError("model emitted a non-finite score")
        grouped[row["benchmark_item_id"]].append((float(score), row["relevance"]))
    values: list[float] = []
    for group in grouped.values():
        ranked = [label for _, label in sorted(group, reverse=True)]
        ideal = sorted((label for _, label in group), reverse=True)
        dcg = sum(label / math.log2(index + 2) for index, label in enumerate(ranked))
        idcg = sum(label / math.log2(index + 2) for index, label in enumerate(ideal))
        values.append(dcg / idcg if idcg else 0.0)
    return sum(values) / len(values)


def _tree_hash(path: Path) -> str:
    digest = hashlib.sha256()
    for child in sorted(
        candidate for candidate in path.rglob("*") if candidate.is_file()
    ):
        digest.update(str(child.relative_to(path)).encode("utf-8"))
        digest.update(b"\0")
        digest.update(child.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _validation_contract(
    rows: list[dict[str, Any]],
    train_rows: list[dict[str, Any]],
    validation_rows: list[dict[str, Any]],
    train_ids: list[str],
    validation_ids: list[str],
) -> dict[str, Any]:
    return {
        "valid": True,
        "judgment_sha256": _canonical_hash(rows),
        "row_count": len(rows),
        "question_group_count": len(train_ids) + len(validation_ids),
        "train_row_count": len(train_rows),
        "validation_row_count": len(validation_rows),
        "train_question_ids": train_ids,
        "validation_question_ids": validation_ids,
        "group_overlap": sorted(set(train_ids) & set(validation_ids)),
        "heldout_accessed": False,
        "user_data_used": False,
    }


def train(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    rows = load_reviewed_judgments(args.judgments, args.benchmark)
    train_rows, validation_rows, train_ids, validation_ids = split_by_question(
        rows, seed=args.seed, validation_fraction=args.validation_fraction
    )
    contract = _validation_contract(
        rows, train_rows, validation_rows, train_ids, validation_ids
    )
    if args.validate_only:
        return contract, 0

    sentence_transformers, torch = load_ml_dependencies()
    random.seed(args.seed)
    if hasattr(torch, "manual_seed"):
        torch.manual_seed(args.seed)
    artifact_id = (
        "reranker-"
        + hashlib.sha256(
            f"{contract['judgment_sha256']}:{args.base_model}:{args.seed}".encode()
        ).hexdigest()[:16]
    )
    artifact_dir = args.output_root / artifact_id
    if artifact_dir.exists():
        raise TrainingError(f"refusing to overwrite artifact: {artifact_dir}")
    model_dir = artifact_dir / "candidate_model"
    artifact_dir.mkdir(parents=True, exist_ok=False)

    pairs_validation = [(row["query"], row["passage"]) for row in validation_rows]
    baseline_model = sentence_transformers.CrossEncoder(args.base_model, max_length=512)
    baseline_scores = [
        float(value) for value in baseline_model.predict(pairs_validation)
    ]
    baseline_ndcg = _ndcg_for_groups(validation_rows, baseline_scores)

    candidate_model = sentence_transformers.CrossEncoder(
        args.base_model, num_labels=1, max_length=512
    )
    examples = [
        sentence_transformers.InputExample(
            texts=[row["query"], row["passage"]], label=float(row["relevance"])
        )
        for row in train_rows
    ]
    dataloader = torch.utils.data.DataLoader(
        examples,
        shuffle=True,
        batch_size=args.batch_size,
        generator=torch.Generator().manual_seed(args.seed),
    )
    candidate_model.fit(
        train_dataloader=dataloader,
        epochs=args.epochs,
        warmup_steps=0,
        show_progress_bar=True,
        output_path=str(model_dir),
    )
    candidate_scores = [
        float(value) for value in candidate_model.predict(pairs_validation)
    ]
    candidate_ndcg = _ndcg_for_groups(validation_rows, candidate_scores)
    improvement = candidate_ndcg - baseline_ndcg
    promotion_eligible = improvement > args.minimum_improvement
    manifest = {
        "schema_version": "1.0",
        "artifact_id": artifact_id,
        "created_at": datetime.now(UTC).isoformat(),
        "base_model": args.base_model,
        "seed": args.seed,
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "minimum_improvement": args.minimum_improvement,
        "validation_contract": contract,
        "metrics": {
            "name": "question_group_ndcg",
            "baseline": baseline_ndcg,
            "candidate": candidate_ndcg,
            "absolute_improvement": improvement,
        },
        "promotion_eligible": promotion_eligible,
        "heldout_accessed": False,
        "user_data_used": False,
        "model_tree_sha256": _tree_hash(model_dir),
        "limitations": "Offline dev validation only; not a clinical, production, or held-out performance claim.",
    }
    (artifact_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if promotion_eligible:
        (artifact_dir / "PROMOTED.json").write_text(
            json.dumps(
                {
                    "artifact_id": artifact_id,
                    "manifest_sha256": _canonical_hash(manifest),
                    "reason": "candidate validation NDCG strictly exceeded baseline by more than the configured minimum",
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        return manifest, 0
    return manifest, 5


def main(argv: list[str] | None = None) -> int:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--judgments", type=Path, required=True)
    parser.add_argument(
        "--benchmark", type=Path, default=project_root / "benchmark" / "benchmark.json"
    )
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument(
        "--output-root", type=Path, default=project_root / "benchmark" / "artifacts"
    )
    parser.add_argument("--base-model", default="cross-encoder/ms-marco-MiniLM-L6-v2")
    parser.add_argument("--seed", type=int, default=20260825)
    parser.add_argument("--validation-fraction", type=float, default=0.2)
    parser.add_argument("--epochs", type=int, default=1)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--minimum-improvement", type=float, default=0.0)
    args = parser.parse_args(argv)
    if args.epochs < 1 or args.batch_size < 1:
        print(
            json.dumps(
                {"valid": False, "error": "epochs and batch-size must be positive"}
            ),
            file=sys.stderr,
        )
        return 2
    if args.minimum_improvement < 0:
        print(
            json.dumps(
                {"valid": False, "error": "minimum-improvement must be non-negative"}
            ),
            file=sys.stderr,
        )
        return 2
    try:
        report, exit_code = train(args)
    except TrainingError as exc:
        print(
            json.dumps({"valid": False, "error": str(exc)}, indent=2), file=sys.stderr
        )
        return 4
    print(json.dumps(report, indent=2, sort_keys=True))
    if exit_code == 5:
        print(
            "promotion refused: validation improvement gate was not met",
            file=sys.stderr,
        )
    return exit_code


if __name__ == "__main__":
    # Prevent accidental online model retrieval in normal project verification.
    # A deliberate training run may pre-populate the model cache, but this script
    # itself never opts into remote code or network-dependent corpus access.
    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
    raise SystemExit(main())
