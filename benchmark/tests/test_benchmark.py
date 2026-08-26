from __future__ import annotations

import importlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = BENCHMARK_DIR.parent
sys.path.insert(0, str(BENCHMARK_DIR))

_validation = importlib.import_module("validate_benchmark")
ValidationError = _validation.ValidationError
validate_benchmark = _validation.validate_benchmark


class BenchmarkValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.benchmark = BENCHMARK_DIR / "benchmark.json"
        self.evidence = PROJECT_ROOT / "docs" / "evidence_manifest.json"

    def test_exact_contract(self) -> None:
        report = validate_benchmark(self.benchmark, self.evidence)
        self.assertEqual(report["item_count"], 100)
        self.assertEqual(report["split_counts"], {"dev": 60, "heldout": 40})
        self.assertEqual(set(report["query_type_counts"].values()), {20})
        self.assertEqual(
            report["age_cohort_counts"],
            {
                "adult": 25,
                "age_ambiguous": 10,
                "child_caregiver": 25,
                "older_adult_caregiver": 15,
                "teen": 25,
            },
        )

    def test_generated_file_is_current(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(BENCHMARK_DIR / "build_benchmark.py"), "--check"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_count_drift_fails_closed(self) -> None:
        payload = json.loads(self.benchmark.read_text(encoding="utf-8"))
        payload["items"].pop()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "benchmark.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "exactly 100"):
                validate_benchmark(path, self.evidence)

    def test_unknown_source_fails_closed(self) -> None:
        payload = json.loads(self.benchmark.read_text(encoding="utf-8"))
        payload["items"][0]["expected_source_ids"] = ["unknown_source"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "benchmark.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "unknown sources"):
                validate_benchmark(path, self.evidence)

    def test_external_source_cannot_be_bundled(self) -> None:
        evidence = json.loads(self.evidence.read_text(encoding="utf-8"))
        evidence["sources"][0]["storage_mode"] = "bundled_copy"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            path.write_text(json.dumps(evidence), encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "link_only"):
                validate_benchmark(self.benchmark, path)


if __name__ == "__main__":
    unittest.main()
