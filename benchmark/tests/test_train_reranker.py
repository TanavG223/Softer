from __future__ import annotations

import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BENCHMARK_DIR))

_training = importlib.import_module("train_reranker")
TrainingError = _training.TrainingError
load_ml_dependencies = _training.load_ml_dependencies
load_reviewed_judgments = _training.load_reviewed_judgments
split_by_question = _training.split_by_question


class RerankerContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.benchmark = BENCHMARK_DIR / "benchmark.json"
        self.judgments = BENCHMARK_DIR / "reranker_dev_judgments.example.jsonl"

    def test_reviewed_dev_data_validates_and_groups_do_not_overlap(self) -> None:
        rows = load_reviewed_judgments(self.judgments, self.benchmark)
        train, validation, train_ids, validation_ids = split_by_question(
            rows, seed=20260825, validation_fraction=0.2
        )
        self.assertEqual(len(rows), 20)
        self.assertTrue(train)
        self.assertTrue(validation)
        self.assertFalse(set(train_ids) & set(validation_ids))
        self.assertEqual({row["benchmark_item_id"] for row in train}, set(train_ids))
        self.assertEqual(
            {row["benchmark_item_id"] for row in validation}, set(validation_ids)
        )

    def test_heldout_item_is_rejected(self) -> None:
        lines = self.judgments.read_text(encoding="utf-8").splitlines()
        first = json.loads(lines[0])
        first["benchmark_item_id"] = "kn_013"
        lines[0] = json.dumps(first)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "judgments.jsonl"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(TrainingError, "heldout or unknown"):
                load_reviewed_judgments(path, self.benchmark)

    def test_unreviewed_or_user_data_is_rejected(self) -> None:
        lines = self.judgments.read_text(encoding="utf-8").splitlines()
        first = json.loads(lines[0])
        first["contains_user_data"] = True
        lines[0] = json.dumps(first)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "judgments.jsonl"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(TrainingError, "user data"):
                load_reviewed_judgments(path, self.benchmark)

    def test_missing_ml_dependencies_fail_closed(self) -> None:
        def unavailable(_: str) -> object:
            raise ModuleNotFoundError("not installed")

        with self.assertRaisesRegex(TrainingError, "dependencies are unavailable"):
            load_ml_dependencies(unavailable)


if __name__ == "__main__":
    unittest.main()
