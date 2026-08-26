from __future__ import annotations

import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = BENCHMARK_DIR.parent
sys.path.insert(0, str(BENCHMARK_DIR))

runner = importlib.import_module("run_engine")


class EngineBenchmarkRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.benchmark_path = BENCHMARK_DIR / "benchmark.json"
        self.evidence_path = PROJECT_ROOT / "docs" / "evidence_manifest.json"
        self.benchmark = json.loads(self.benchmark_path.read_text(encoding="utf-8"))
        self.evidence = json.loads(self.evidence_path.read_text(encoding="utf-8"))
        self.validation = runner.validate_benchmark(
            self.benchmark_path, self.evidence_path
        )

    def test_modes_select_exact_counts_without_expected_labels(self) -> None:
        dev = runner._runtime_items(self.benchmark, "dev")
        full = runner._runtime_items(self.benchmark, "full")
        self.assertEqual(len(dev), 60)
        self.assertEqual(len(full), 100)
        self.assertTrue(all(item.split == "dev" for item in dev))
        self.assertNotIn("expected_response", runner.RuntimeItem.__dataclass_fields__)
        self.assertNotIn("expected_source_ids", runner.RuntimeItem.__dataclass_fields__)
        self.assertNotIn("human_review", runner.RuntimeItem.__dataclass_fields__)

    def test_model_pack_and_trust_key_must_be_supplied_together(self) -> None:
        with self.assertRaisesRegex(
            runner.RunnerError,
            "model pack directory and public trust key must be supplied together",
        ):
            runner.run_benchmark(
                mode="dev",
                benchmark_path=self.benchmark_path,
                evidence_path=self.evidence_path,
                model_pack_dir=PROJECT_ROOT / "build" / "model-pack",
            )

    def test_local_adapter_preserves_runtime_and_private_namespace_metadata(
        self,
    ) -> None:
        source = next(
            item for item in self.benchmark["items"] if item["id"] == "kn_012"
        )
        item = runner.RuntimeItem(
            item_id=source["id"],
            split=source["split"],
            age_cohort=source["age_cohort"],
            prompt=source["prompt"],
            care_context=source["care_context"],
        )
        with tempfile.TemporaryDirectory() as directory:
            adapter = runner.LocalEngineAdapter(
                project_root=PROJECT_ROOT,
                benchmark_sha256=self.validation["benchmark_sha256"],
                evidence_manifest=self.evidence,
                data_dir=Path(directory),
            )
            adapter.prepare({item.age_cohort})
            record = adapter.run_item(item, "0" * 64)

        private_sources = [
            evidence
            for evidence in record["retrieved_sources"]
            if evidence["namespace"] != runner.PUBLIC_NAMESPACE
        ]
        self.assertTrue(private_sources)
        self.assertTrue(
            all(
                source["profile_id"] == record["profile_id"]
                for source in private_sources
            )
        )
        self.assertTrue(
            all(source["runtime_source_id"] for source in record["retrieved_sources"])
        )
        self.assertTrue(
            all(claim["review"] == "unreviewed" for claim in record["claims"])
        )
        self.assertNotIn("human_review", record)
        self.assertFalse(
            record["run_metadata"]["expected_labels_used_for_runtime_decisions"]
        )

    def test_frozen_config_hashes_every_runtime_corpus_input(self) -> None:
        source = next(
            item for item in self.benchmark["items"] if item["id"] == "kn_012"
        )
        item = runner.RuntimeItem(
            item_id=source["id"],
            split=source["split"],
            age_cohort=source["age_cohort"],
            prompt=source["prompt"],
            care_context=source["care_context"],
        )
        with tempfile.TemporaryDirectory() as directory:
            adapter = runner.LocalEngineAdapter(
                project_root=PROJECT_ROOT,
                benchmark_sha256=self.validation["benchmark_sha256"],
                evidence_manifest=self.evidence,
                data_dir=Path(directory),
            )
            adapter.prepare({item.age_cohort})
            frozen = runner._frozen_config(
                mode="dev",
                validation=self.validation,
                items=[item],
                adapter=adapter,
            )

        hashes = frozen["runtime_input_sha256"]
        self.assertEqual(
            set(hashes),
            {
                "product_policy_sha256",
                "synthetic_plans_sha256",
                "evidence_seed_sha256",
                "engine_python_tree_sha256",
            },
        )
        self.assertTrue(
            all(
                len(value) == 64
                and all(character in "0123456789abcdef" for character in value)
                for value in hashes.values()
            )
        )

    def test_malformed_runtime_locator_fails_closed(self) -> None:
        source = next(
            item for item in self.benchmark["items"] if item["id"] == "kn_012"
        )
        item = runner.RuntimeItem(
            item_id=source["id"],
            split=source["split"],
            age_cohort=source["age_cohort"],
            prompt=source["prompt"],
            care_context=source["care_context"],
        )
        with tempfile.TemporaryDirectory() as directory:
            adapter = runner.LocalEngineAdapter(
                project_root=PROJECT_ROOT,
                benchmark_sha256=self.validation["benchmark_sha256"],
                evidence_manifest=self.evidence,
                data_dir=Path(directory),
            )
            adapter.prepare({item.age_cohort})
            profile_id = adapter.profile_ids[item.age_cohort]
            config = runner.COHORT_CONFIG[item.age_cohort]
            age_band = config["age_band"]
            response = adapter.service.run(
                runner.RunRequest(
                    profile_id=profile_id,
                    age_band=age_band,
                    acting_role=config["acting_role"],
                    care_context=runner.CARE_CONTEXT_MAP[item.care_context],
                    evidence_scope=[
                        runner.EvidenceScope.ALL_AGES,
                        runner.EvidenceScope(age_band.value),
                    ],
                    question=item.prompt,
                )
            )
            self.assertTrue(response.citations)
            first = response.citations[0].model_copy(
                update={"char_start": response.citations[0].char_end + 10}
            )
            malformed = response.model_copy(
                update={"citations": [first, *response.citations[1:]]}
            )
            with self.assertRaisesRegex(runner.RunnerError, "not locatable"):
                adapter._adapt_citations(item, malformed)

    def test_writer_uses_literal_lf_and_refuses_overwrite(self) -> None:
        records = [{"item_id": "example", "answer": "line one\nline two"}]
        metadata = {"review_status": "unreviewed"}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "run.jsonl"
            metadata_path = runner.write_artifacts(output, records, metadata)
            payload = output.read_bytes()
            self.assertNotIn(b"\r", payload)
            self.assertTrue(payload.endswith(b"\n"))
            self.assertEqual(payload.count(b"\n"), 1)
            self.assertTrue(metadata_path.exists())
            with self.assertRaisesRegex(runner.RunnerError, "refusing to overwrite"):
                runner.write_artifacts(output, records, metadata)


if __name__ == "__main__":
    unittest.main()
