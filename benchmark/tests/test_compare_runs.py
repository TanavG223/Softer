from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path

BENCHMARK_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BENCHMARK_DIR))

compare = importlib.import_module("compare_runs").compare
ValidationError = importlib.import_module("validate_benchmark").ValidationError


def summary(**values: float) -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "complete": True,
        "benchmark_sha256": "a" * 64,
        "item_ids_sha256": "b" * 64,
        "metrics": {
            name: {
                "status": "measured",
                "value": value,
                "numerator": 0,
                "denominator": 100,
            }
            for name, value in values.items()
        },
    }


class CompareTests(unittest.TestCase):
    def test_all_gates_can_pass(self) -> None:
        common = {
            "multi_hop_human_accuracy": 0.75,
            "average_latency_ms": 100,
            "average_input_tokens": 100,
            "average_context_tokens": 100,
            "human_accuracy": 0.95,
            "cross_age_leakage_count": 0,
            "injection_execution_count": 0,
            "citation_locatability": 1.0,
            "citation_precision": 0.98,
            "unsupported_claim_rate": 0.02,
        }
        bm25 = summary(recall_at_20=0.70, ndcg_at_20=0.60, **common)
        dense = summary(recall_at_20=0.75, ndcg_at_20=0.62, **common)
        hybrid = summary(recall_at_20=0.80, ndcg_at_20=0.70, **common)
        adaptive_values = dict(common)
        adaptive_values.update(
            {
                "multi_hop_human_accuracy": 0.81,
                "average_latency_ms": 140,
                "average_input_tokens": 140,
                "average_context_tokens": 60,
                "human_accuracy": 0.94,
            }
        )
        adaptive = summary(recall_at_20=0.80, ndcg_at_20=0.70, **adaptive_values)
        report = compare(bm25, dense, hybrid, adaptive)
        self.assertTrue(report["all_gates_passed"])

    def test_unmeasured_metric_refuses_comparison(self) -> None:
        minimal = summary(recall_at_20=0.7)
        with self.assertRaisesRegex(ValidationError, "not measured"):
            compare(minimal, minimal, minimal, minimal)


if __name__ == "__main__":
    unittest.main()
