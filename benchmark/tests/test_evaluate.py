from __future__ import annotations

import hashlib
import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = BENCHMARK_DIR.parent
sys.path.insert(0, str(BENCHMARK_DIR))

evaluate = importlib.import_module("evaluate").evaluate
ValidationError = importlib.import_module("validate_benchmark").ValidationError


class EvaluationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.benchmark_path = BENCHMARK_DIR / "benchmark.json"
        self.evidence_path = PROJECT_ROOT / "docs" / "evidence_manifest.json"
        self.benchmark = json.loads(self.benchmark_path.read_text(encoding="utf-8"))
        evidence = json.loads(self.evidence_path.read_text(encoding="utf-8"))
        self.source_scopes = {
            source["id"]: set(source["age_scopes"]) for source in evidence["sources"]
        }

    def _scope(self, item: dict[str, object], source_id: str) -> str:
        desired = {
            "child_caregiver": "pediatric",
            "teen": "teen",
            "adult": "adult",
            "older_adult_caregiver": "older_adult",
            "age_ambiguous": "all_ages",
        }[str(item["age_cohort"])]
        return desired if desired in self.source_scopes[source_id] else "all_ages"

    def _record(self, item: dict[str, object]) -> dict[str, object]:
        profile_id = f"synthetic-{item['age_cohort']}"
        runtime_age_band = {
            "child_caregiver": "child6To12",
            "teen": "teen13To17",
            "adult": "adult18To64",
            "older_adult_caregiver": "olderAdult65Plus",
            "age_ambiguous": "adult18To64",
        }[str(item["age_cohort"])]
        sources = [
            {
                "source_id": source_id,
                "age_scope": self._scope(item, source_id),
                "runtime_source_id": f"chunk-{source_id}",
                "document_id": f"document-{source_id}",
                "source_kind": "officialBundled",
                "runtime_age_scope": "allAges",
                "namespace": "__public__",
                "profile_id": None,
                "locator": {
                    "page": 1,
                    "char_start": 0,
                    "char_end": 12,
                    "content_hash": hashlib.sha256(source_id.encode()).hexdigest(),
                    "quote_sha256": hashlib.sha256(b"example quote").hexdigest(),
                },
            }
            for source_id in item["expected_source_ids"]
        ]
        claims = (
            [
                {
                    "text": "Human-reviewed synthetic candidate claim.",
                    "citations": list(item["expected_source_ids"]),
                    "review": "supported",
                }
            ]
            if item["expected_source_ids"]
            else []
        )
        return {
            "item_id": item["id"],
            "profile_id": profile_id,
            "profile_namespace": profile_id,
            "age_cohort": item["age_cohort"],
            "split": item["split"],
            "runtime_age_band": runtime_age_band,
            "evidence_scope": ["allAges", runtime_age_band],
            "response_type": item["expected_response"],
            "answer": "Safe candidate response with no adversarial canary.",
            "retrieved_sources": sources,
            "claims": claims,
            "human_review": {"correct": True},
            "timing": {"latency_ms": 10},
            "token_usage": {"input_tokens": 100, "context_tokens": 80},
        }

    def _write(self, records: list[dict[str, object]], directory: str) -> Path:
        path = Path(directory) / "run.jsonl"
        path.write_text(
            "\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8"
        )
        return path

    def test_complete_reviewed_run_is_measured(self) -> None:
        records = [self._record(item) for item in self.benchmark["items"]]
        with tempfile.TemporaryDirectory() as directory:
            summary = evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write(records, directory),
            )
        self.assertTrue(summary["complete"])
        self.assertEqual(summary["output_count"], 100)
        self.assertEqual(summary["metrics"]["recall_at_20"]["value"], 1.0)
        self.assertEqual(summary["metrics"]["citation_locatability"]["value"], 1.0)
        self.assertEqual(summary["metrics"]["cross_age_leakage_count"]["value"], 0)
        self.assertFalse(summary["interpretation"]["performance_claim_allowed"])

    def test_partial_run_fails_without_explicit_flag(self) -> None:
        record = self._record(self.benchmark["items"][0])
        with tempfile.TemporaryDirectory() as directory:
            path = self._write([record], directory)
            with self.assertRaisesRegex(ValidationError, "incomplete"):
                evaluate(self.benchmark_path, self.evidence_path, path)

    def test_canary_and_wrong_age_scope_are_counted(self) -> None:
        item = next(item for item in self.benchmark["items"] if item["id"] == "ai_001")
        record = self._record(item)
        record["answer"] = "unsafe PACEBACK_CANARY_A01"
        record["retrieved_sources"] = [
            {
                "source_id": "cdc_return_school",
                "age_scope": "teen",
                "runtime_source_id": "chunk-school",
                "document_id": "cdc-school-teen-2025",
                "source_kind": "officialBundled",
                "runtime_age_scope": "teen13To17",
                "namespace": "__public__",
                "profile_id": None,
                "locator": {
                    "page": 1,
                    "char_start": 0,
                    "char_end": 7,
                    "content_hash": hashlib.sha256(b"school").hexdigest(),
                    "quote_sha256": hashlib.sha256(b"section").hexdigest(),
                },
            }
        ]
        with tempfile.TemporaryDirectory() as directory:
            summary = evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )
        self.assertEqual(summary["metrics"]["injection_execution_count"]["value"], 1)
        self.assertEqual(summary["metrics"]["cross_age_leakage_count"]["value"], 1)

    def test_age_ambiguous_item_uses_its_selected_profile_scope(self) -> None:
        item = next(
            item
            for item in self.benchmark["items"]
            if item["age_cohort"] == "age_ambiguous"
        )
        record = self._record(item)
        record["retrieved_sources"] = [
            {
                "source_id": "cdc_return_work",
                "age_scope": "adult",
                "runtime_source_id": "adult-work-chunk",
                "document_id": "cdc-work-adult-2024",
                "source_kind": "officialBundled",
                "runtime_age_scope": "adult18To64",
                "namespace": "__public__",
                "profile_id": None,
                "locator": {
                    "page": 1,
                    "char_start": 0,
                    "char_end": 7,
                    "content_hash": hashlib.sha256(b"adult work").hexdigest(),
                    "quote_sha256": hashlib.sha256(b"section").hexdigest(),
                },
            }
        ]
        record["claims"] = []
        with tempfile.TemporaryDirectory() as directory:
            summary = evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )
        self.assertEqual(summary["metrics"]["cross_age_leakage_count"]["value"], 0)

    def test_unknown_retrieved_source_fails_closed(self) -> None:
        record = self._record(self.benchmark["items"][0])
        record["retrieved_sources"] = [
            {
                "source_id": "unknown",
                "age_scope": "all_ages",
                "runtime_source_id": "chunk-unknown",
                "document_id": "document-unknown",
                "source_kind": "officialBundled",
                "runtime_age_scope": "allAges",
                "namespace": "__public__",
                "profile_id": None,
                "locator": {
                    "page": 1,
                    "char_start": 0,
                    "char_end": 1,
                    "content_hash": "0" * 64,
                    "quote_sha256": "1" * 64,
                },
            }
        ]
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(ValidationError, "evidence manifest"),
        ):
            evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )

    def test_non_structural_locator_fails_closed(self) -> None:
        record = self._record(self.benchmark["items"][0])
        record["retrieved_sources"][0]["locator"] = "page 1"
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(ValidationError, "must contain page"),
        ):
            evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )

    def test_cross_profile_private_source_fails_closed(self) -> None:
        item = next(
            item
            for item in self.benchmark["items"]
            if "paceback_product_policy" in item["expected_source_ids"]
        )
        record = self._record(item)
        source = next(
            source
            for source in record["retrieved_sources"]
            if source["source_id"] == "paceback_product_policy"
        )
        source.update(
            {
                "source_kind": "userProvided",
                "namespace": "different-profile",
                "profile_id": "different-profile",
            }
        )
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(ValidationError, "crossed the synthetic profile"),
        ):
            evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )

    def test_matching_private_source_is_accepted(self) -> None:
        item = next(
            item
            for item in self.benchmark["items"]
            if "paceback_product_policy" in item["expected_source_ids"]
        )
        record = self._record(item)
        source = next(
            source
            for source in record["retrieved_sources"]
            if source["source_id"] == "paceback_product_policy"
        )
        source.update(
            {
                "source_kind": "userProvided",
                "namespace": record["profile_id"],
                "profile_id": record["profile_id"],
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            summary = evaluate(
                self.benchmark_path,
                self.evidence_path,
                self._write([record], directory),
                allow_partial=True,
            )
        self.assertEqual(summary["output_count"], 1)

    def test_crlf_jsonl_is_rejected(self) -> None:
        record = self._record(self.benchmark["items"][0])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            path.write_bytes((json.dumps(record) + "\r\n").encode())
            with self.assertRaisesRegex(ValidationError, "literal LF"):
                evaluate(
                    self.benchmark_path,
                    self.evidence_path,
                    path,
                    allow_partial=True,
                )


if __name__ == "__main__":
    unittest.main()
