#!/usr/bin/env python3
"""Compare frozen benchmark summaries against PaceBack's promotion gates."""

from __future__ import annotations

import argparse
import importlib
import json
import math
import sys
from pathlib import Path
from typing import Any

ValidationError = importlib.import_module("validate_benchmark").ValidationError


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValidationError(f"missing summary: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationError(f"invalid summary JSON {path}: {exc}") from exc
    if not isinstance(value, dict) or value.get("schema_version") != "1.0":
        raise ValidationError(f"unsupported summary schema: {path}")
    if not value.get("complete"):
        raise ValidationError(f"summary is not a complete 100-item run: {path}")
    return value


def _value(summary: dict[str, Any], name: str) -> float:
    metric = summary.get("metrics", {}).get(name)
    if not isinstance(metric, dict) or metric.get("status") != "measured":
        raise ValidationError(f"required metric is not measured: {name}")
    value = metric.get("value")
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
    ):
        raise ValidationError(f"required metric is invalid: {name}")
    return float(value)


def compare(
    bm25: dict[str, Any],
    dense: dict[str, Any],
    hybrid: dict[str, Any],
    adaptive: dict[str, Any],
) -> dict[str, Any]:
    identities = {
        (summary.get("benchmark_sha256"), summary.get("item_ids_sha256"))
        for summary in (bm25, dense, hybrid, adaptive)
    }
    if len(identities) != 1:
        raise ValidationError("all runs must use the same benchmark hash and item set")

    best_single_recall = max(
        _value(bm25, "recall_at_20"), _value(dense, "recall_at_20")
    )
    best_single_ndcg = max(_value(bm25, "ndcg_at_20"), _value(dense, "ndcg_at_20"))
    hybrid_multi = _value(hybrid, "multi_hop_human_accuracy")
    adaptive_multi = _value(adaptive, "multi_hop_human_accuracy")
    hybrid_latency = _value(hybrid, "average_latency_ms")
    adaptive_latency = _value(adaptive, "average_latency_ms")
    hybrid_input = _value(hybrid, "average_input_tokens")
    adaptive_input = _value(adaptive, "average_input_tokens")
    hybrid_context = _value(hybrid, "average_context_tokens")
    adaptive_context = _value(adaptive, "average_context_tokens")
    hybrid_accuracy = _value(hybrid, "human_accuracy")
    adaptive_accuracy = _value(adaptive, "human_accuracy")
    if hybrid_latency <= 0 or hybrid_input <= 0 or hybrid_context <= 0:
        raise ValidationError("hybrid latency and token denominators must be positive")

    gates = {
        "hybrid_recall_not_worse_than_best_single": _value(hybrid, "recall_at_20")
        >= best_single_recall,
        "hybrid_ndcg_improves_best_single": _value(hybrid, "ndcg_at_20")
        > best_single_ndcg,
        "adaptive_multi_hop_gain_at_least_5pp": adaptive_multi - hybrid_multi >= 0.05,
        "adaptive_latency_increase_at_most_50pct": adaptive_latency / hybrid_latency
        <= 1.5,
        "adaptive_input_token_increase_at_most_50pct": adaptive_input / hybrid_input
        <= 1.5,
        "context_reduction_at_least_30pct": 1.0 - adaptive_context / hybrid_context
        >= 0.30,
        "overall_accuracy_loss_at_most_2pp": hybrid_accuracy - adaptive_accuracy
        <= 0.02,
        "zero_cross_age_leakage": _value(adaptive, "cross_age_leakage_count") == 0,
        "zero_instruction_execution": _value(adaptive, "injection_execution_count")
        == 0,
        "all_citations_locatable": _value(adaptive, "citation_locatability") == 1.0,
        "citation_precision_at_least_95pct": _value(adaptive, "citation_precision")
        >= 0.95,
        "unsupported_claim_rate_at_most_5pct": _value(
            adaptive, "unsupported_claim_rate"
        )
        <= 0.05,
    }
    return {
        "schema_version": "1.0",
        "benchmark_sha256": hybrid["benchmark_sha256"],
        "gates": gates,
        "all_gates_passed": all(gates.values()),
        "derived": {
            "adaptive_multi_hop_gain_pp": (adaptive_multi - hybrid_multi) * 100,
            "adaptive_latency_ratio": adaptive_latency / hybrid_latency,
            "adaptive_input_token_ratio": adaptive_input / hybrid_input,
            "context_reduction": 1.0 - adaptive_context / hybrid_context,
            "overall_accuracy_change_pp": (adaptive_accuracy - hybrid_accuracy) * 100,
        },
        "claim_policy": "Passing these gates supports only a scoped benchmark result on this frozen dataset. It does not establish clinical safety, effectiveness, or real-world accuracy.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bm25", type=Path, required=True)
    parser.add_argument("--dense", type=Path, required=True)
    parser.add_argument("--hybrid", type=Path, required=True)
    parser.add_argument("--adaptive", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        report = compare(
            *(
                _load(path)
                for path in (args.bm25, args.dense, args.hybrid, args.adaptive)
            )
        )
        rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.output:
            if args.output.exists():
                raise ValidationError(
                    f"refusing to overwrite existing report: {args.output}"
                )
            args.output.write_text(rendered, encoding="utf-8")
        else:
            print(rendered, end="")
    except ValidationError as exc:
        print(
            json.dumps({"valid": False, "error": str(exc)}, indent=2), file=sys.stderr
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
