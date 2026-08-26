"""Strict, camelCase JSON contracts shared with the native client."""

from __future__ import annotations

import re
from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)


def _to_camel(value: str) -> str:
    head, *tail = value.split("_")
    return head + "".join(part.capitalize() for part in tail)


class StrictModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        alias_generator=_to_camel,
        populate_by_name=True,
        serialize_by_alias=True,
        str_strip_whitespace=True,
        use_enum_values=False,
    )


SafeText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class AgeBand(StrEnum):
    YOUNG_CHILD_0_TO_5 = "youngChild0To5"
    CHILD_6_TO_12 = "child6To12"
    TEEN_13_TO_17 = "teen13To17"
    ADULT_18_TO_64 = "adult18To64"
    OLDER_ADULT_65_PLUS = "olderAdult65Plus"


class ActingRole(StrEnum):
    SELF_MANAGED = "selfManaged"
    TEEN_USER = "teenUser"
    CAREGIVER = "caregiver"
    GUARDIAN = "guardian"


class CareContext(StrEnum):
    HOME = "home"
    SCHOOL = "school"
    WORK = "work"
    DAILY_LIVING = "dailyLiving"


class ProfilePermission(StrEnum):
    USE_GUIDED_SESSION = "useGuidedSession"
    ASK_EVIDENCE = "askEvidence"
    IMPORT_DOCUMENT = "importDocument"
    EXPORT_DATA = "exportData"
    DELETE_PROFILE = "deleteProfile"
    MANAGE_SETTINGS = "manageSettings"


class EvidenceScope(StrEnum):
    ALL_AGES = "allAges"
    YOUNG_CHILD_0_TO_5 = AgeBand.YOUNG_CHILD_0_TO_5.value
    CHILD_6_TO_12 = AgeBand.CHILD_6_TO_12.value
    TEEN_13_TO_17 = AgeBand.TEEN_13_TO_17.value
    ADULT_18_TO_64 = AgeBand.ADULT_18_TO_64.value
    OLDER_ADULT_65_PLUS = AgeBand.OLDER_ADULT_65_PLUS.value


class SourceKind(StrEnum):
    CLINICIAN_PLAN = "clinicianPlan"
    USER_PROVIDED = "userProvided"
    OFFICIAL_BUNDLED = "officialBundled"


class Route(StrEnum):
    DIRECT = "direct"
    SINGLE_RETRIEVAL = "singleRetrieval"
    ITERATIVE_RETRIEVAL = "iterativeRetrieval"


class SupportStatus(StrEnum):
    VERIFIED = "verified"
    PARTIAL = "partial"
    INSUFFICIENT_INFORMATION = "insufficientInformation"
    DANGER_SIGN_DETECTED = "dangerSignDetected"
    CANCELLED = "cancelled"


class StopReason(StrEnum):
    SAFETY_GATE = "safetyGate"
    SUFFICIENT_EVIDENCE = "sufficientEvidence"
    NO_NEW_EVIDENCE = "noNewEvidence"
    COVERAGE_PLATEAU = "coveragePlateau"
    MAX_ROUNDS = "maxRounds"
    NO_EVIDENCE = "noEvidence"
    CANCELLED = "cancelled"
    RESOURCE_LIMIT = "resourceLimit"


class ProfileCreate(StrictModel):
    alias: str = Field(min_length=1, max_length=40)
    age_band: AgeBand
    owner_role: ActingRole
    caregiver_access: bool = False

    @field_validator("alias")
    @classmethod
    def validate_alias(cls, value: str) -> str:
        if any(ord(character) < 32 for character in value):
            raise ValueError("alias cannot contain control characters")
        return value


class ProfileUpdate(StrictModel):
    acting_role: ActingRole
    alias: str | None = Field(default=None, min_length=1, max_length=40)
    caregiver_access: bool | None = None

    @model_validator(mode="after")
    def require_change(self) -> ProfileUpdate:
        if self.alias is None and self.caregiver_access is None:
            raise ValueError("at least one profile field must be provided")
        return self


class Profile(StrictModel):
    profile_id: str = Field(alias="profileID")
    alias: str
    age_band: AgeBand
    owner_role: ActingRole
    caregiver_access: bool
    permissions: list[ProfilePermission]
    created_at: datetime
    updated_at: datetime


class DocumentCreate(StrictModel):
    acting_role: ActingRole
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=1_000_000)
    source_kind: SourceKind = SourceKind.USER_PROVIDED
    source_url: str | None = Field(default=None, max_length=2_048)
    evidence_scope: EvidenceScope

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not re.match(r"^https://[^\s]+$", value):
            raise ValueError("sourceUrl must be an https URL")
        return value

    @model_validator(mode="after")
    def reject_reserved_kind(self) -> DocumentCreate:
        if self.source_kind is SourceKind.OFFICIAL_BUNDLED:
            raise ValueError("officialBundled is reserved for signed application resources")
        return self


class DocumentUpdate(StrictModel):
    acting_role: ActingRole
    title: str | None = Field(default=None, min_length=1, max_length=200)
    content: str | None = Field(default=None, min_length=1, max_length=1_000_000)
    source_url: str | None = Field(default=None, max_length=2_048)
    evidence_scope: EvidenceScope | None = None

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not re.match(r"^https://[^\s]+$", value):
            raise ValueError("sourceUrl must be an https URL")
        return value

    @model_validator(mode="after")
    def require_change(self) -> DocumentUpdate:
        if all(
            value is None
            for value in (self.title, self.content, self.source_url, self.evidence_scope)
        ):
            raise ValueError("at least one document field must be provided")
        return self


class Document(StrictModel):
    document_id: str = Field(alias="documentID")
    profile_id: str = Field(alias="profileID")
    title: str
    source_kind: SourceKind
    source_url: str | None
    evidence_scope: EvidenceScope
    content_hash: str
    chunk_count: int = Field(ge=0)
    created_at: datetime
    updated_at: datetime
    content: str | None = None


class RunRequest(StrictModel):
    run_id: str | None = Field(default=None, alias="runID", min_length=1, max_length=100)
    profile_id: str = Field(alias="profileID", min_length=1, max_length=100)
    age_band: AgeBand
    acting_role: ActingRole
    care_context: CareContext
    evidence_scope: list[EvidenceScope] = Field(min_length=2, max_length=2)
    question: str = Field(min_length=1, max_length=10_000)
    max_output_tokens: int = Field(default=512, ge=64, le=1_024)

    @field_validator("evidence_scope")
    @classmethod
    def scopes_are_unique(cls, value: list[EvidenceScope]) -> list[EvidenceScope]:
        if len(set(value)) != len(value):
            raise ValueError("evidenceScope cannot contain duplicates")
        return value

    @field_validator("run_id")
    @classmethod
    def run_id_is_uuid(cls, value: str | None) -> str | None:
        if value is None:
            return None
        try:
            UUID(value)
        except ValueError as exc:
            raise ValueError("runID must be a UUID") from exc
        return value

    @model_validator(mode="after")
    def scopes_match_age_band(self) -> RunRequest:
        expected = {EvidenceScope.ALL_AGES, EvidenceScope(self.age_band.value)}
        if set(self.evidence_scope) != expected:
            raise ValueError("evidenceScope must be exactly [allAges, selected ageBand]")
        return self


class Citation(StrictModel):
    source_id: str = Field(alias="sourceID")
    title: str
    url: str | None = None
    page: int | None = Field(default=None, ge=1)
    quote: str
    document_id: str = Field(alias="documentID")
    char_start: int = Field(ge=0)
    char_end: int = Field(ge=0)
    content_hash: str

    @model_validator(mode="after")
    def validate_span(self) -> Citation:
        if self.char_end < self.char_start:
            raise ValueError("charEnd cannot precede charStart")
        return self


class RunUsage(StrictModel):
    retrieved_tokens: int = Field(ge=0)
    input_tokens: int = Field(ge=0)
    output_tokens: int = Field(ge=0)
    retrieval_rounds: int = Field(ge=0, le=3)
    latency_ms: float = Field(alias="latencyMS", ge=0)


class RunResponse(StrictModel):
    run_id: str = Field(alias="runID")
    answer: str
    support_status: SupportStatus
    citations: list[Citation]
    route: Route
    stop_reason: StopReason
    usage: RunUsage


class RunRecord(RunResponse):
    profile_id: str = Field(alias="profileID")
    created_at: datetime


class CancellationResponse(StrictModel):
    run_id: str = Field(alias="runID")
    status: Literal["cancellationRequested", "completed", "cancelled"]


class ClaimInput(StrictModel):
    text: str = Field(min_length=1, max_length=10_000)
    source_id: str = Field(alias="sourceID", min_length=1, max_length=200)


class VerifyRequest(StrictModel):
    profile_id: str = Field(alias="profileID")
    run_id: str = Field(alias="runID")
    claims: list[ClaimInput] = Field(min_length=1, max_length=50)


class DeletedClaim(StrictModel):
    source_id: str = Field(alias="sourceID")
    reason: Literal[
        "unknownSource",
        "unlocatableCitation",
        "unsupportedByExtract",
        "runNotVerified",
    ]


class VerifyResponse(StrictModel):
    support_status: SupportStatus
    verified_claims: list[ClaimInput]
    deleted_claims: list[DeletedClaim]


class FeedbackCreate(StrictModel):
    profile_id: str = Field(alias="profileID")
    run_id: str = Field(alias="runID")
    helpful: bool
    reason: str | None = Field(default=None, max_length=500)


class Feedback(FeedbackCreate):
    feedback_id: str = Field(alias="feedbackID")
    created_at: datetime


class ModelComponent(StrictModel):
    name: str
    version: str
    purpose: str
    local_only: bool = True
    active: bool = True
    activation: Literal["active", "fallback", "standby", "unconfigured", "failed"] = (
        "active"
    )
    model_id: str | None = Field(default=None, alias="modelID")
    revision: str | None = None
    artifact_sha256: str | None = Field(
        default=None, alias="artifactSHA256", pattern=r"^[0-9a-f]{64}$"
    )
    dimensions: int | None = Field(default=None, ge=1, le=4_096)
    provider: str | None = None
    failure_reason: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def activation_matches_active_flag(self) -> ModelComponent:
        if self.active != (self.activation in {"active", "fallback"}):
            raise ValueError("active must match the component activation state")
        if self.activation == "failed" and not self.failure_reason:
            raise ValueError("failed components require failureReason")
        if self.activation != "failed" and self.failure_reason is not None:
            raise ValueError("failureReason is reserved for failed components")
        return self


class ModelManifest(StrictModel):
    components: list[ModelComponent]
    model_pack_id: str | None = Field(default=None, alias="modelPackID")
    model_pack_activation: Literal["active", "unconfigured", "failed"]
    web_search_enabled: Literal[False] = False
    code_execution_enabled: Literal[False] = False
    runtime_weight_updates_enabled: Literal[False] = False
    storage_driver: Literal["sqlite", "sqlcipher"]
    storage_encryption_active: bool


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"
    version: str
    database_ready: bool
    fts5_ready: bool
    release_mode: bool
    storage_driver: Literal["sqlite", "sqlcipher"]
    storage_encryption_active: bool
    network_tools_enabled: Literal[False] = False


class ErrorDetail(StrictModel):
    code: str
    message: str
    correlation_id: str = Field(alias="correlationID")
    fields: list[str] = Field(default_factory=list)


class ErrorResponse(StrictModel):
    error: ErrorDetail


def utc_now() -> datetime:
    return datetime.now(UTC)
