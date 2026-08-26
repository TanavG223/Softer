"""Application services: authorization, bounded retrieval, and fail-closed verification."""

from __future__ import annotations

import re
import time
from typing import Any
from uuid import uuid4

from paceback_engine.config import Settings
from paceback_engine.database import Database
from paceback_engine.model_runtime import load_model_runtime
from paceback_engine.retrieval import (
    AdaptiveContextBudgeter,
    AdaptiveRouter,
    HybridRetriever,
    SearchHit,
    query_coverage,
    token_count,
)
from paceback_engine.safety import DangerSignGate
from paceback_engine.schemas import (
    ActingRole,
    AgeBand,
    CancellationResponse,
    Citation,
    DeletedClaim,
    Document,
    DocumentCreate,
    DocumentUpdate,
    EvidenceScope,
    Feedback,
    FeedbackCreate,
    ModelComponent,
    ModelManifest,
    Profile,
    ProfileCreate,
    ProfilePermission,
    ProfileUpdate,
    Route,
    RunRecord,
    RunRequest,
    RunResponse,
    RunUsage,
    StopReason,
    SupportStatus,
    VerifyRequest,
    VerifyResponse,
)

UNVERIFIED_ANSWER = "I could not verify an answer."


def _bounded_hits(hits: Any, *, limit: int) -> list[SearchHit]:
    """Apply final cross-round deduplication and per-document limits."""

    ordered = sorted(
        hits,
        key=lambda hit: (-hit.rerank_score, -hit.rrf_score, hit.chunk_id),
    )
    selected: list[SearchHit] = []
    per_document: dict[str, int] = {}
    seen_hashes: set[str] = set()
    for hit in ordered:
        if hit.content_hash in seen_hashes:
            continue
        if per_document.get(hit.document_id, 0) >= 3:
            continue
        selected.append(hit)
        seen_hashes.add(hit.content_hash)
        per_document[hit.document_id] = per_document.get(hit.document_id, 0) + 1
        if len(selected) >= limit:
            break
    return selected


class DomainError(Exception):
    def __init__(self, code: str, message: str, status_code: int) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


def _all_permissions() -> list[ProfilePermission]:
    return list(ProfilePermission)


def _permissions_for(profile: dict[str, Any], role: ActingRole) -> set[ProfilePermission]:
    age_band = AgeBand(profile["age_band"])
    caregiver_access = bool(profile["caregiver_access"])
    admin = {
        ProfilePermission.USE_GUIDED_SESSION,
        ProfilePermission.ASK_EVIDENCE,
        ProfilePermission.IMPORT_DOCUMENT,
        ProfilePermission.EXPORT_DATA,
        ProfilePermission.DELETE_PROFILE,
        ProfilePermission.MANAGE_SETTINGS,
    }
    if age_band in {AgeBand.YOUNG_CHILD_0_TO_5, AgeBand.CHILD_6_TO_12}:
        return admin if role in {ActingRole.GUARDIAN, ActingRole.CAREGIVER} else set()
    if age_band is AgeBand.TEEN_13_TO_17:
        if role is ActingRole.TEEN_USER:
            return {
                ProfilePermission.USE_GUIDED_SESSION,
                ProfilePermission.ASK_EVIDENCE,
            }
        return admin if role is ActingRole.GUARDIAN else set()
    if role is ActingRole.SELF_MANAGED:
        return admin
    if role is ActingRole.CAREGIVER and caregiver_access:
        return {
            ProfilePermission.USE_GUIDED_SESSION,
            ProfilePermission.ASK_EVIDENCE,
            ProfilePermission.IMPORT_DOCUMENT,
            ProfilePermission.EXPORT_DATA,
        }
    return set()


def _validate_owner_role(request: ProfileCreate) -> None:
    if request.age_band in {AgeBand.YOUNG_CHILD_0_TO_5, AgeBand.CHILD_6_TO_12}:
        allowed = {ActingRole.GUARDIAN, ActingRole.CAREGIVER}
    elif request.age_band is AgeBand.TEEN_13_TO_17:
        allowed = {ActingRole.GUARDIAN}
    else:
        allowed = {ActingRole.SELF_MANAGED}
    if request.owner_role not in allowed:
        raise DomainError(
            "invalid_owner_role",
            "The owner role is not permitted for this age band.",
            422,
        )


class PaceBackService:
    def __init__(self, database: Database, settings: Settings) -> None:
        self.database = database
        self.settings = settings
        self.model_runtime = load_model_runtime(settings)
        self.database.configure_embedder(self.model_runtime.embedder)
        self.retriever = HybridRetriever(
            database,
            reranker=self.model_runtime.reranker,
            embedder=self.model_runtime.embedder,
        )
        self.router = AdaptiveRouter()
        self.budgeter = AdaptiveContextBudgeter()
        self.safety_gate = DangerSignGate()

    def create_profile(self, request: ProfileCreate) -> Profile:
        _validate_owner_role(request)
        return self._profile(self.database.create_profile(request))

    def sync_profile(self, profile_id: str, request: ProfileCreate) -> Profile:
        """Idempotently mirror an authoritative native profile into the sidecar.

        The native encrypted profile owns the identifier. Age band and owner role are
        immutable after first activation so a caller cannot silently change the
        authorization boundary of an existing retrieval namespace.
        """

        _validate_owner_role(request)
        try:
            from uuid import UUID

            UUID(profile_id)
        except (TypeError, ValueError, AttributeError) as exc:
            raise DomainError(
                "invalid_profile_id",
                "The profile identifier must be a UUID.",
                422,
            ) from exc

        existing = self.database.get_profile(profile_id)
        if existing is None:
            return self._profile(
                self.database.create_profile(request, profile_id=profile_id)
            )
        if (
            existing["age_band"] != request.age_band.value
            or existing["owner_role"] != request.owner_role.value
        ):
            raise DomainError(
                "immutable_profile_boundary",
                "Age band and owner role cannot change after profile activation.",
                409,
            )

        age_band = AgeBand(existing["age_band"])
        caregiver_access = (
            request.caregiver_access
            if age_band in {AgeBand.ADULT_18_TO_64, AgeBand.OLDER_ADULT_65_PLUS}
            else None
        )
        updated = self.database.update_profile(
            profile_id,
            ProfileUpdate(
                acting_role=request.owner_role,
                alias=request.alias,
                caregiver_access=caregiver_access,
            ),
        )
        if updated is None:
            raise DomainError("profile_not_found", "Profile not found.", 404)
        return self._profile(updated)

    def list_profiles(self) -> list[Profile]:
        return [self._profile(row) for row in self.database.list_profiles()]

    def get_profile(self, profile_id: str) -> Profile:
        return self._profile(self._require_profile(profile_id))

    def update_profile(self, profile_id: str, request: ProfileUpdate) -> Profile:
        profile = self._require_profile(profile_id)
        self._authorize(profile, request.acting_role, ProfilePermission.MANAGE_SETTINGS)
        if request.caregiver_access is not None and AgeBand(profile["age_band"]) in {
            AgeBand.YOUNG_CHILD_0_TO_5,
            AgeBand.CHILD_6_TO_12,
            AgeBand.TEEN_13_TO_17,
        }:
            raise DomainError(
                "invalid_caregiver_access_change",
                "Caregiver access is intrinsic to a minor profile.",
                422,
            )
        updated = self.database.update_profile(profile_id, request)
        if updated is None:
            raise DomainError("profile_not_found", "Profile not found.", 404)
        return self._profile(updated)

    def delete_profile(self, profile_id: str, role: ActingRole) -> None:
        profile = self._require_profile(profile_id)
        self._authorize(profile, role, ProfilePermission.DELETE_PROFILE)
        if not self.database.delete_profile(profile_id):
            raise DomainError("profile_not_found", "Profile not found.", 404)

    def create_document(self, profile_id: str, request: DocumentCreate) -> Document:
        profile = self._require_profile(profile_id)
        self._authorize(profile, request.acting_role, ProfilePermission.IMPORT_DOCUMENT)
        self._validate_document_scope(profile, request.evidence_scope)
        return self._document(self.database.create_document(profile_id, request))

    def list_documents(self, profile_id: str) -> list[Document]:
        self._require_profile(profile_id)
        return [self._document(row) for row in self.database.list_documents(profile_id)]

    def get_document(self, profile_id: str, document_id: str) -> Document:
        self._require_profile(profile_id)
        row = self.database.get_document(profile_id, document_id, include_content=True)
        if row is None:
            raise DomainError("document_not_found", "Document not found.", 404)
        return self._document(row)

    def update_document(
        self, profile_id: str, document_id: str, request: DocumentUpdate
    ) -> Document:
        profile = self._require_profile(profile_id)
        self._authorize(profile, request.acting_role, ProfilePermission.IMPORT_DOCUMENT)
        if request.evidence_scope is not None:
            self._validate_document_scope(profile, request.evidence_scope)
        row = self.database.update_document(profile_id, document_id, request)
        if row is None:
            raise DomainError("document_not_found", "Document not found.", 404)
        return self._document(row)

    def delete_document(
        self, profile_id: str, document_id: str, role: ActingRole
    ) -> None:
        profile = self._require_profile(profile_id)
        self._authorize(profile, role, ProfilePermission.IMPORT_DOCUMENT)
        if not self.database.delete_document(profile_id, document_id):
            raise DomainError("document_not_found", "Document not found.", 404)

    def run(self, request: RunRequest) -> RunResponse:
        started = time.perf_counter()
        profile = self._require_profile(request.profile_id)
        if AgeBand(profile["age_band"]) is not request.age_band:
            raise DomainError(
                "age_band_mismatch",
                "The request age band does not match the selected profile.",
                422,
            )
        self._authorize(profile, request.acting_role, ProfilePermission.ASK_EVIDENCE)
        expected_scopes = {EvidenceScope.ALL_AGES.value, request.age_band.value}
        scopes = {scope.value for scope in request.evidence_scope}
        if scopes != expected_scopes:
            raise DomainError(
                "invalid_evidence_scope",
                "Evidence scope must contain only allAges and the selected age band.",
                422,
            )
        run_id = request.run_id or str(uuid4())
        if self.database.get_run(run_id, request.profile_id) is not None:
            raise DomainError("run_id_conflict", "The run identifier already exists.", 409)
        request_json = request.model_dump_json(by_alias=True)
        self.database.create_run(run_id, request.profile_id, request_json)

        safety_match = self.safety_gate.evaluate(request.question, request.age_band)
        if safety_match:
            response = self._safety_response(run_id, request, safety_match.answer, started)
            self._complete(response, request.profile_id)
            return response

        route = Route(self.router.route(request.question))
        queries = (
            self.router.expand(request.question, self.settings.max_subqueries)
            if route is Route.ITERATIVE_RETRIEVAL
            else [request.question]
        )
        max_rounds = min(self.settings.max_retrieval_rounds, len(queries))
        collected: dict[str, SearchHit] = {}
        previous_coverage = 0.0
        stop_reason = StopReason.MAX_ROUNDS
        rounds = 0
        actions = 0

        try:
            for query in queries[:max_rounds]:
                if actions >= self.settings.max_actions:
                    stop_reason = StopReason.RESOURCE_LIMIT
                    break
                if self.database.cancellation_requested(run_id, request.profile_id):
                    stop_reason = StopReason.CANCELLED
                    break
                rounds += 1
                actions += 1
                hits = self.retriever.search(
                    query,
                    profile_id=request.profile_id,
                    scopes=sorted(scopes),
                )
                new_count = 0
                for hit in hits:
                    prior = collected.get(hit.chunk_id)
                    if prior is None:
                        new_count += 1
                    if prior is None or hit.rerank_score > prior.rerank_score:
                        collected[hit.chunk_id] = hit
                    if len(collected) >= self.settings.max_candidates:
                        break
                ordered = _bounded_hits(
                    collected.values(), limit=self.settings.max_candidates
                )
                coverage = query_coverage(request.question, ordered)
                if len(ordered) >= 3 and coverage >= 0.6:
                    stop_reason = StopReason.SUFFICIENT_EVIDENCE
                    break
                if rounds > 1 and new_count < 2:
                    stop_reason = StopReason.NO_NEW_EVIDENCE
                    break
                if rounds > 1 and coverage - previous_coverage < 0.05:
                    stop_reason = StopReason.COVERAGE_PLATEAU
                    break
                previous_coverage = coverage
            if stop_reason is StopReason.CANCELLED:
                response = self._empty_response(
                    run_id,
                    route,
                    stop_reason,
                    SupportStatus.CANCELLED,
                    rounds,
                    started,
                )
            elif not collected:
                response = self._empty_response(
                    run_id,
                    route,
                    StopReason.NO_EVIDENCE,
                    SupportStatus.INSUFFICIENT_INFORMATION,
                    rounds,
                    started,
                )
            else:
                ordered = _bounded_hits(collected.values(), limit=8)
                context_budget = min(
                    self.settings.context_token_budget,
                    max(256, request.max_output_tokens * 4),
                )
                budgeted = self.budgeter.reduce(
                    request.question, ordered, token_budget=context_budget
                )
                response = self._evidence_response(
                    run_id=run_id,
                    request=request,
                    route=route,
                    stop_reason=stop_reason,
                    hits=list(budgeted.hits),
                    retrieved_tokens=budgeted.retrieved_tokens,
                    retained_tokens=budgeted.retained_tokens,
                    rounds=rounds,
                    started=started,
                )
        except Exception:
            # Retrieval or parsing failures cannot become unsupported output.
            response = self._empty_response(
                run_id,
                route,
                StopReason.RESOURCE_LIMIT,
                SupportStatus.INSUFFICIENT_INFORMATION,
                rounds,
                started,
            )
        self._complete(response, request.profile_id)
        return response

    def get_run(self, run_id: str, profile_id: str) -> RunRecord:
        row = self.database.get_run(run_id, profile_id)
        if row is None:
            raise DomainError("run_not_found", "Run not found.", 404)
        if not row["response_json"]:
            raise DomainError("run_in_progress", "Run has not completed.", 409)
        response = RunResponse.model_validate_json(row["response_json"])
        return RunRecord(
            **response.model_dump(),
            profile_id=profile_id,
            created_at=row["created_at"],
        )

    def cancel_run(self, run_id: str, profile_id: str) -> CancellationResponse:
        self._require_profile(profile_id)
        status = self.database.request_cancellation(run_id, profile_id)
        if status is None:
            raise DomainError("run_not_found", "Run not found.", 404)
        return CancellationResponse(run_id=run_id, status=status)

    def verify(self, request: VerifyRequest) -> VerifyResponse:
        run = self.database.get_run(request.run_id, request.profile_id)
        if run is None:
            raise DomainError("run_not_found", "Run not found.", 404)
        response = (
            RunResponse.model_validate_json(run["response_json"])
            if run["response_json"]
            else None
        )
        citations = (
            {citation.source_id: citation for citation in response.citations}
            if response
            else {}
        )
        verified = []
        deleted: list[DeletedClaim] = []
        run_supports_claims = bool(
            response
            and response.support_status in {SupportStatus.VERIFIED, SupportStatus.PARTIAL}
        )
        for claim in request.claims:
            citation = citations.get(claim.source_id)
            if not run_supports_claims:
                deleted.append(
                    DeletedClaim(source_id=claim.source_id, reason="runNotVerified")
                )
                continue
            if citation is None:
                deleted.append(DeletedClaim(source_id=claim.source_id, reason="unknownSource"))
                continue
            source = self.database.get_source(request.profile_id, claim.source_id)
            if (
                source is None
                or source["content_hash"] != citation.content_hash
                or citation.quote not in source["content"]
            ):
                deleted.append(
                    DeletedClaim(source_id=claim.source_id, reason="unlocatableCitation")
                )
                continue
            if _normalize(claim.text) not in _normalize(source["content"]):
                deleted.append(
                    DeletedClaim(source_id=claim.source_id, reason="unsupportedByExtract")
                )
                continue
            verified.append(claim)
        if verified and not deleted:
            status = SupportStatus.VERIFIED
        elif verified:
            status = SupportStatus.PARTIAL
        else:
            status = SupportStatus.INSUFFICIENT_INFORMATION
        return VerifyResponse(
            support_status=status,
            verified_claims=verified,
            deleted_claims=deleted,
        )

    def create_feedback(self, request: FeedbackCreate) -> Feedback:
        self._require_profile(request.profile_id)
        if self.database.get_run(request.run_id, request.profile_id) is None:
            raise DomainError("run_not_found", "Run not found.", 404)
        row = self.database.create_feedback(
            request.profile_id, request.run_id, request.helpful, request.reason
        )
        return Feedback(
            feedback_id=row["id"],
            profile_id=row["profile_id"],
            run_id=row["run_id"],
            helpful=bool(row["helpful"]),
            reason=row["reason"],
            created_at=row["created_at"],
        )

    def model_manifest(self) -> ModelManifest:
        runtime_components = [
            ModelComponent(
                name=component.name,
                version=component.version,
                purpose=component.purpose,
                active=component.active,
                activation=component.activation,
                model_id=component.model_id,
                revision=component.revision,
                artifact_sha256=component.artifact_sha256,
                dimensions=component.dimensions,
                provider=component.provider,
                failure_reason=component.failure_reason,
            )
            for component in self.model_runtime.components
        ]
        return ModelManifest(
            components=[
                ModelComponent(
                    name="sqlite-fts5-bm25",
                    version="builtin",
                    purpose="sparse retrieval",
                    activation="active",
                ),
                ModelComponent(
                    name="reciprocal-rank-fusion",
                    version="k60",
                    purpose="hybrid rank fusion",
                    activation="active",
                ),
                *runtime_components,
            ],
            model_pack_id=self.model_runtime.pack_id,
            model_pack_activation=self.model_runtime.pack_activation,
            storage_driver=self.database.driver,
            storage_encryption_active=self.database.encryption_active,
        )

    def _require_profile(self, profile_id: str) -> dict[str, Any]:
        profile = self.database.get_profile(profile_id)
        if profile is None:
            raise DomainError("profile_not_found", "Profile not found.", 404)
        return profile

    def _authorize(
        self,
        profile: dict[str, Any],
        role: ActingRole,
        permission: ProfilePermission,
    ) -> None:
        if permission not in _permissions_for(profile, role):
            raise DomainError(
                "permission_denied",
                "The acting role is not permitted to perform this action.",
                403,
            )

    def _validate_document_scope(
        self, profile: dict[str, Any], scope: EvidenceScope
    ) -> None:
        if scope.value != profile["age_band"]:
            raise DomainError(
                "invalid_document_scope",
                "Private documents must use the profile's age-band evidence scope.",
                422,
            )

    def _profile(self, row: dict[str, Any]) -> Profile:
        owner_role = ActingRole(row["owner_role"])
        return Profile(
            profile_id=row["id"],
            alias=row["alias"],
            age_band=AgeBand(row["age_band"]),
            owner_role=owner_role,
            caregiver_access=bool(row["caregiver_access"]),
            permissions=sorted(_permissions_for(row, owner_role), key=lambda item: item.value),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def _document(self, row: dict[str, Any]) -> Document:
        return Document(
            document_id=row["id"],
            profile_id=row["profile_id"],
            title=row["title"],
            source_kind=row["source_kind"],
            source_url=row["source_url"],
            evidence_scope=row["age_scope"],
            content_hash=row["content_hash"],
            chunk_count=row["chunk_count"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            content=row.get("content"),
        )

    def _safety_response(
        self, run_id: str, request: RunRequest, answer: str, started: float
    ) -> RunResponse:
        source = self.database.get_source(request.profile_id, "cdc-danger-signs-2025")
        if source is None:
            return self._empty_response(
                run_id,
                Route.DIRECT,
                StopReason.SAFETY_GATE,
                SupportStatus.DANGER_SIGN_DETECTED,
                0,
                started,
                answer=answer,
            )
        quote = (
            "A possible danger sign after a bump, blow, or jolt requires immediate "
            "emergency medical care. Call 911 or go to an emergency department right away."
        )
        citation = Citation(
            source_id=source["source_id"],
            title=source["title"],
            url=source["source_url"],
            page=source["page_number"],
            quote=quote,
            document_id=source["document_id"],
            char_start=source["char_start"],
            char_end=source["char_start"] + len(quote),
            content_hash=source["content_hash"],
        )
        return RunResponse(
            run_id=run_id,
            answer=answer,
            support_status=SupportStatus.DANGER_SIGN_DETECTED,
            citations=[citation],
            route=Route.DIRECT,
            stop_reason=StopReason.SAFETY_GATE,
            usage=RunUsage(
                retrieved_tokens=0,
                input_tokens=token_count(request.question),
                output_tokens=token_count(answer),
                retrieval_rounds=0,
                latency_ms=(time.perf_counter() - started) * 1_000,
            ),
        )

    def _empty_response(
        self,
        run_id: str,
        route: Route,
        reason: StopReason,
        status: SupportStatus,
        rounds: int,
        started: float,
        *,
        answer: str = UNVERIFIED_ANSWER,
    ) -> RunResponse:
        return RunResponse(
            run_id=run_id,
            answer=answer,
            support_status=status,
            citations=[],
            route=route,
            stop_reason=reason,
            usage=RunUsage(
                retrieved_tokens=0,
                input_tokens=0,
                output_tokens=token_count(answer),
                retrieval_rounds=rounds,
                latency_ms=(time.perf_counter() - started) * 1_000,
            ),
        )

    def _evidence_response(
        self,
        *,
        run_id: str,
        request: RunRequest,
        route: Route,
        stop_reason: StopReason,
        hits: list[SearchHit],
        retrieved_tokens: int,
        retained_tokens: int,
        rounds: int,
        started: float,
    ) -> RunResponse:
        citations: list[Citation] = []
        answer_lines: list[str] = []
        used_tokens = token_count("Relevant source excerpts:")
        for hit in hits:
            quote = _best_locatable_sentence(request.question, hit.content)
            if not quote:
                continue
            quote_tokens = token_count(quote) + 1
            if used_tokens + quote_tokens > request.max_output_tokens:
                continue
            source = self.database.get_source(request.profile_id, hit.chunk_id)
            if source is None or source["content_hash"] != hit.content_hash:
                continue
            local_offset = source["content"].find(quote)
            if local_offset < 0:
                continue
            citations.append(
                Citation(
                    source_id=hit.chunk_id,
                    title=hit.title,
                    url=hit.source_url,
                    page=hit.page_number,
                    quote=quote,
                    document_id=hit.document_id,
                    char_start=hit.char_start + local_offset,
                    char_end=hit.char_start + local_offset + len(quote),
                    content_hash=hit.content_hash,
                )
            )
            answer_lines.append(f"{len(citations)}. {quote} [{len(citations)}]")
            used_tokens += quote_tokens
            if len(citations) == 8:
                break
        if not citations:
            return self._empty_response(
                run_id,
                route,
                StopReason.NO_EVIDENCE,
                SupportStatus.INSUFFICIENT_INFORMATION,
                rounds,
                started,
            )
        answer = "Relevant source excerpts:\n" + "\n".join(answer_lines)
        return RunResponse(
            run_id=run_id,
            answer=answer,
            support_status=SupportStatus.VERIFIED,
            citations=citations,
            route=route,
            stop_reason=stop_reason,
            usage=RunUsage(
                retrieved_tokens=retrieved_tokens,
                input_tokens=token_count(request.question) + retained_tokens,
                output_tokens=token_count(answer),
                retrieval_rounds=rounds,
                latency_ms=(time.perf_counter() - started) * 1_000,
            ),
        )

    def _complete(self, response: RunResponse, profile_id: str) -> None:
        self.database.complete_run(
            response.run_id,
            profile_id,
            response.model_dump_json(by_alias=True),
        )


def _best_locatable_sentence(question: str, content: str) -> str:
    query_terms = set(re.findall(r"[a-z0-9]+", question.lower()))
    candidates = [
        match.group(0).strip()
        for match in re.finditer(r"[^.!?\n]+(?:[.!?]+|$)", content)
        if match.group(0).strip()
    ]
    if not candidates:
        return content.strip()
    return max(
        candidates,
        key=lambda sentence: (
            len(query_terms & set(re.findall(r"[a-z0-9]+", sentence.lower()))),
            -content.find(sentence),
        ),
    )


def _normalize(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.lower()))
