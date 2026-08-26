"""Local hybrid retrieval, deterministic reranking, and context budgeting."""

from __future__ import annotations

import hashlib
import math
import re
import struct
from collections import Counter, defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from typing import Protocol

TOKEN_PATTERN = re.compile(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)?")
SENTENCE_PATTERN = re.compile(r"[^.!?\n]+(?:[.!?]+|$)")
INJECTION_PATTERN = re.compile(
    r"(?:ignore\s+(?:all\s+)?(?:previous|prior)\s+instructions|"
    r"reveal\s+(?:the\s+)?system\s+prompt|"
    r"execute\s+(?:this\s+)?(?:code|command)|"
    r"developer\s+message\s*:|system\s+message\s*:)",
    re.I,
)
PROTECTED_PATTERN = re.compile(
    r"(?:\b\d+(?:\.\d+)?\b|\b(?:not|never|no|without|must|warning|danger|emergency)\b)",
    re.I,
)


def tokenize(text: str) -> list[str]:
    return [match.group(0).lower().replace("’", "'") for match in TOKEN_PATTERN.finditer(text)]


def token_count(text: str) -> int:
    return len(TOKEN_PATTERN.findall(text))


def deterministic_embedding(text: str, dimensions: int = 128) -> tuple[float, ...]:
    """Signed hashing-vector embedding: local, stable, inspectable, and model-free."""
    values = [0.0] * dimensions
    counts = Counter(tokenize(text))
    for token, frequency in counts.items():
        digest = hashlib.blake2b(token.encode("utf-8"), digest_size=16).digest()
        index = int.from_bytes(digest[:8], "big") % dimensions
        sign = 1.0 if digest[8] & 1 else -1.0
        values[index] += sign * (1.0 + math.log(frequency))
    norm = math.sqrt(sum(value * value for value in values))
    if norm:
        values = [value / norm for value in values]
    return tuple(values)


class Embedder(Protocol):
    """Backend-neutral local embedding contract.

    Implementations must be deterministic for a fixed artifact and must never fetch
    weights at runtime. ``index_version`` changes whenever stored vectors are no
    longer compatible with a component.
    """

    dimensions: int
    index_version: str
    model_backed: bool

    def embed(self, text: str) -> tuple[float, ...]: ...

    def embed_query(self, text: str) -> tuple[float, ...]: ...


class DeterministicEmbedder:
    dimensions = 128
    index_version = "signed-hashing-vector:1:128"
    model_backed = False

    def embed(self, text: str) -> tuple[float, ...]:
        return deterministic_embedding(text, self.dimensions)

    def embed_query(self, text: str) -> tuple[float, ...]:
        return self.embed(text)


def pack_embedding(values: Sequence[float]) -> bytes:
    return struct.pack(f"!{len(values)}f", *values)


def unpack_embedding(payload: bytes) -> tuple[float, ...]:
    if not payload or len(payload) % 4:
        return ()
    return struct.unpack(f"!{len(payload) // 4}f", payload)


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    if not left or len(left) != len(right):
        return 0.0
    return sum(a * b for a, b in zip(left, right, strict=True))


@dataclass(frozen=True, slots=True)
class ChunkDraft:
    ordinal: int
    page_number: int
    char_start: int
    char_end: int
    content: str
    parent_text: str
    content_hash: str
    embedding: bytes


@dataclass(frozen=True, slots=True)
class SearchHit:
    chunk_id: str
    document_id: str
    title: str
    source_url: str | None
    page_number: int
    char_start: int
    char_end: int
    content: str
    content_hash: str
    sparse_rank: int | None = None
    dense_rank: int | None = None
    rrf_score: float = 0.0
    rerank_score: float = 0.0


def chunk_document(
    text: str,
    *,
    child_tokens: int = 512,
    overlap_tokens: int = 64,
    parent_tokens: int = 2_048,
    embedder: Embedder | None = None,
) -> list[ChunkDraft]:
    if child_tokens <= overlap_tokens:
        raise ValueError("child_tokens must exceed overlap_tokens")
    active_embedder = embedder or DeterministicEmbedder()
    pages = text.split("\f")
    drafts: list[ChunkDraft] = []
    document_offset = 0
    ordinal = 0
    for page_index, page in enumerate(pages, start=1):
        matches = list(TOKEN_PATTERN.finditer(page))
        if not matches:
            document_offset += len(page) + (1 if page_index < len(pages) else 0)
            continue
        parent_end = matches[min(len(matches), parent_tokens) - 1].end()
        parent_text = page[:parent_end].strip()
        step = child_tokens - overlap_tokens
        for start_index in range(0, len(matches), step):
            end_index = min(start_index + child_tokens, len(matches))
            start = matches[start_index].start()
            end = matches[end_index - 1].end()
            content = page[start:end].strip()
            if not content:
                continue
            absolute_start = document_offset + start
            absolute_end = document_offset + end
            drafts.append(
                ChunkDraft(
                    ordinal=ordinal,
                    page_number=page_index,
                    char_start=absolute_start,
                    char_end=absolute_end,
                    content=content,
                    parent_text=parent_text,
                    content_hash=hashlib.sha256(content.encode("utf-8")).hexdigest(),
                    embedding=pack_embedding(active_embedder.embed(content)),
                )
            )
            ordinal += 1
            if end_index == len(matches):
                break
        document_offset += len(page) + (1 if page_index < len(pages) else 0)
    return drafts


class RetrievalStore(Protocol):
    def sparse_search(
        self, query: str, profile_id: str, scopes: Sequence[str], limit: int
    ) -> list[dict]: ...

    def eligible_chunks(self, profile_id: str, scopes: Sequence[str]) -> list[dict]: ...


class Reranker(Protocol):
    def score(self, query: str, hit: SearchHit) -> float: ...


class DeterministicReranker:
    """An explicit seam that can later host a versioned local MiniLM model."""

    def score(self, query: str, hit: SearchHit) -> float:
        query_terms = set(tokenize(query))
        if not query_terms:
            return hit.rrf_score
        hit_terms = set(tokenize(hit.content))
        coverage = len(query_terms & hit_terms) / len(query_terms)
        phrase_bonus = 0.15 if query.lower() in hit.content.lower() else 0.0
        return hit.rrf_score + coverage + phrase_bonus


class HybridRetriever:
    def __init__(
        self,
        store: RetrievalStore,
        reranker: Reranker | None = None,
        embedder: Embedder | None = None,
    ) -> None:
        self.store = store
        self.reranker = reranker or DeterministicReranker()
        self.embedder = embedder or DeterministicEmbedder()

    def search(
        self,
        query: str,
        *,
        profile_id: str,
        scopes: Sequence[str],
        sparse_limit: int = 50,
        dense_limit: int = 50,
        rerank_limit: int = 30,
        result_limit: int = 8,
        max_per_document: int = 3,
    ) -> list[SearchHit]:
        sparse_rows = self.store.sparse_search(query, profile_id, scopes, sparse_limit)
        dense_rows = self._dense_search(query, profile_id, scopes, dense_limit)
        sparse_rank = {str(row["chunk_id"]): rank for rank, row in enumerate(sparse_rows, 1)}
        dense_rank = {str(row["chunk_id"]): rank for rank, row in enumerate(dense_rows, 1)}
        rows = {str(row["chunk_id"]): row for row in (*sparse_rows, *dense_rows)}
        fused: list[SearchHit] = []
        for chunk_id, row in rows.items():
            score = 0.0
            if chunk_id in sparse_rank:
                score += 1.0 / (60 + sparse_rank[chunk_id])
            if chunk_id in dense_rank:
                score += 1.0 / (60 + dense_rank[chunk_id])
            hit = _row_to_hit(
                row,
                sparse_rank=sparse_rank.get(chunk_id),
                dense_rank=dense_rank.get(chunk_id),
                rrf_score=score,
            )
            fused.append(hit)
        fused.sort(key=lambda item: (-item.rrf_score, item.chunk_id))
        reranked: list[SearchHit] = []
        for hit in fused[:rerank_limit]:
            reranked.append(
                SearchHit(
                    **{
                        field: getattr(hit, field)
                        for field in SearchHit.__dataclass_fields__
                        if field != "rerank_score"
                    },
                    rerank_score=self.reranker.score(query, hit),
                )
            )
        reranked.sort(key=lambda item: (-item.rerank_score, -item.rrf_score, item.chunk_id))
        result: list[SearchHit] = []
        per_document: defaultdict[str, int] = defaultdict(int)
        seen_hashes: set[str] = set()
        for hit in reranked:
            # Hashing vectors are a deterministic offline fallback, not a semantic model;
            # require a minimum reranker signal so collisions do not become evidence.
            if isinstance(self.reranker, DeterministicReranker) and hit.rerank_score < 0.1:
                continue
            if hit.content_hash in seen_hashes or per_document[hit.document_id] >= max_per_document:
                continue
            if INJECTION_PATTERN.search(hit.content):
                continue
            result.append(hit)
            seen_hashes.add(hit.content_hash)
            per_document[hit.document_id] += 1
            if len(result) == result_limit:
                break
        return result

    def _dense_search(
        self, query: str, profile_id: str, scopes: Sequence[str], limit: int
    ) -> list[dict]:
        query_vector = self.embedder.embed_query(query)
        scored: list[tuple[float, dict]] = []
        for row in self.store.eligible_chunks(profile_id, scopes):
            stored_vector = unpack_embedding(row["embedding"])
            # A model transition is atomically reindexed by Database. Recomputing a
            # mismatched row here is a fail-safe for corrupt or legacy stores, never a
            # network operation.
            candidate_vector = (
                stored_vector
                if len(stored_vector) == self.embedder.dimensions
                else self.embedder.embed(str(row["content"]))
            )
            score = cosine_similarity(query_vector, candidate_vector)
            scored.append((score, row))
        scored.sort(key=lambda item: (-item[0], str(item[1]["chunk_id"])))
        return [row for _, row in scored[:limit]]


def _row_to_hit(
    row: dict,
    *,
    sparse_rank: int | None,
    dense_rank: int | None,
    rrf_score: float,
) -> SearchHit:
    return SearchHit(
        chunk_id=str(row["chunk_id"]),
        document_id=str(row["document_id"]),
        title=str(row["title"]),
        source_url=row["source_url"],
        page_number=int(row["page_number"]),
        char_start=int(row["char_start"]),
        char_end=int(row["char_end"]),
        content=str(row["content"]),
        content_hash=str(row["content_hash"]),
        sparse_rank=sparse_rank,
        dense_rank=dense_rank,
        rrf_score=rrf_score,
    )


@dataclass(frozen=True, slots=True)
class ContextBudgetResult:
    hits: tuple[SearchHit, ...]
    retrieved_tokens: int
    retained_tokens: int


class AdaptiveContextBudgeter:
    """Extractive reduction only; source text is never paraphrased or rewritten."""

    def reduce(
        self, query: str, hits: Sequence[SearchHit], *, token_budget: int
    ) -> ContextBudgetResult:
        retrieved_tokens = sum(token_count(hit.content) for hit in hits)
        remaining = token_budget
        reduced: list[SearchHit] = []
        seen_sentences: set[str] = set()
        query_terms = set(tokenize(query))
        for hit in hits:
            selected: list[str] = []
            sentences = [match.group(0).strip() for match in SENTENCE_PATTERN.finditer(hit.content)]
            ranked = sorted(
                enumerate(sentences),
                key=lambda pair: (
                    -int(bool(PROTECTED_PATTERN.search(pair[1]))),
                    -len(query_terms & set(tokenize(pair[1]))),
                    pair[0],
                ),
            )
            for _, sentence in ranked:
                fingerprint = hashlib.sha256(" ".join(tokenize(sentence)).encode()).hexdigest()
                cost = token_count(sentence)
                if not cost or fingerprint in seen_sentences or cost > remaining:
                    continue
                selected.append(sentence)
                seen_sentences.add(fingerprint)
                remaining -= cost
            if selected:
                # Restore source order by locating each unchanged extract in the source.
                selected.sort(key=hit.content.find)
                content = " ".join(selected)
                reduced.append(
                    SearchHit(
                        chunk_id=hit.chunk_id,
                        document_id=hit.document_id,
                        title=hit.title,
                        source_url=hit.source_url,
                        page_number=hit.page_number,
                        char_start=hit.char_start,
                        char_end=hit.char_end,
                        content=content,
                        content_hash=hit.content_hash,
                        sparse_rank=hit.sparse_rank,
                        dense_rank=hit.dense_rank,
                        rrf_score=hit.rrf_score,
                        rerank_score=hit.rerank_score,
                    )
                )
            if remaining <= 0:
                break
        return ContextBudgetResult(
            hits=tuple(reduced),
            retrieved_tokens=retrieved_tokens,
            retained_tokens=token_budget - remaining,
        )


class AdaptiveRouter:
    MULTI_STEP = re.compile(r"\b(?:compare|versus|and then|why.+and|how.+and|both)\b", re.I)

    def route(self, question: str) -> str:
        tokens = tokenize(question)
        if self.MULTI_STEP.search(question) or len(tokens) > 24 or question.count("?") > 1:
            return "iterativeRetrieval"
        return "singleRetrieval"

    def expand(self, question: str, max_subqueries: int = 6) -> list[str]:
        candidates = [question.strip()]
        clauses = re.split(r"(?:\?|;|\b(?:and|versus|vs\.?|then)\b)", question, flags=re.I)
        candidates.extend(clause.strip(" ,.-") for clause in clauses if token_count(clause) >= 3)
        content_terms = [token for token in tokenize(question) if len(token) > 3]
        if len(content_terms) >= 3:
            candidates.append(" ".join(dict.fromkeys(content_terms)))
        result: list[str] = []
        seen: set[str] = set()
        for candidate in candidates:
            normalized = " ".join(tokenize(candidate))
            if not normalized or normalized in seen:
                continue
            result.append(candidate)
            seen.add(normalized)
            if len(result) == max_subqueries:
                break
        return result


def query_coverage(question: str, hits: Iterable[SearchHit]) -> float:
    query_terms = set(tokenize(question))
    if not query_terms:
        return 0.0
    evidence_terms: set[str] = set()
    for hit in hits:
        evidence_terms.update(tokenize(hit.content))
    return len(query_terms & evidence_terms) / len(query_terms)
