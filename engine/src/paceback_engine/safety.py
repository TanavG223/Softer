"""Deterministic danger-sign routing that runs before retrieval or generation."""

from __future__ import annotations

import re
from dataclasses import dataclass

from paceback_engine.schemas import AgeBand


@dataclass(frozen=True, slots=True)
class SafetyMatch:
    matched_signs: tuple[str, ...]
    answer: str
    source_document_id: str = "cdc-danger-signs-2025"


_COMMON_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "worsening headache",
        re.compile(
            r"\b(?:headache\s+(?:is\s+)?(?:getting\s+)?worse|worsening\s+headache)\b",
            re.I,
        ),
    ),
    (
        "repeated vomiting",
        re.compile(
            r"\b(?:vomit(?:ing|ed)?\s+(?:again|repeatedly)|repeated\s+vomit(?:ing)?)\b",
            re.I,
        ),
    ),
    ("seizure or convulsion", re.compile(r"\b(?:seizure|convulsion)s?\b", re.I)),
    (
        "weakness or numbness",
        re.compile(r"\b(?:new\s+)?(?:weakness|numbness|cannot\s+move)\b", re.I),
    ),
    ("slurred speech", re.compile(r"\bslurr(?:ed|ing)\s+speech\b", re.I)),
    ("unusual behavior", re.compile(r"\bunusual\s+behavio(?:u)?r\b", re.I)),
    (
        "unequal pupils",
        re.compile(r"\b(?:one\s+pupil\s+(?:is\s+)?larger|unequal\s+pupils?)\b", re.I),
    ),
    (
        "confusion or agitation",
        re.compile(
            r"\b(?:cannot\s+recognize|confus(?:ed|ion)|restless|agitat(?:ed|ion))\b",
            re.I,
        ),
    ),
    ("loss of consciousness", re.compile(r"\b(?:lost|lose|loss\s+of)\s+consciousness\b", re.I)),
    (
        "cannot wake",
        re.compile(
            r"\b(?:cannot|can't|won't|unable\s+to)\s+(?:be\s+)?(?:wake|woken|wake\s+up)\b",
            re.I,
        ),
    ),
    ("very drowsy", re.compile(r"\b(?:extremely|very|unusually)\s+drowsy\b", re.I)),
)

_CHILD_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "inconsolable crying",
        re.compile(
            r"\b(?:inconsolable|won't\s+stop\s+crying|cannot\s+be\s+consoled)\b",
            re.I,
        ),
    ),
    (
        "refusing to nurse or eat",
        re.compile(
            r"\b(?:won't|will\s+not|refus(?:e|es|ing)\s+to)\s+(?:nurse|eat)\b",
            re.I,
        ),
    ),
)

_YOUNG_CHILD_BANDS = {AgeBand.YOUNG_CHILD_0_TO_5}


class DangerSignGate:
    """Conservative lexical detector; it does not classify or diagnose symptoms."""

    answer = (
        "A possible danger sign was detected. Call 911 or go to an emergency department "
        "right away. This alert is based on static CDC guidance, not an AI assessment."
    )

    def evaluate(self, text: str, age_band: AgeBand) -> SafetyMatch | None:
        patterns = _COMMON_PATTERNS + (
            _CHILD_PATTERNS if age_band in _YOUNG_CHILD_BANDS else ()
        )
        matches = tuple(label for label, pattern in patterns if pattern.search(text))
        if not matches:
            return None
        return SafetyMatch(matched_signs=matches, answer=self.answer)
