"""Authenticated loopback API for the native PaceBack client."""

from __future__ import annotations

import asyncio
import hmac
import json
from collections.abc import AsyncIterator
from uuid import uuid4

from fastapi import APIRouter, Depends, FastAPI, Header, Query, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from starlette.middleware.trustedhost import TrustedHostMiddleware

from paceback_engine import __version__
from paceback_engine.config import Settings
from paceback_engine.database import Database
from paceback_engine.schemas import (
    ActingRole,
    CancellationResponse,
    Document,
    DocumentCreate,
    DocumentUpdate,
    ErrorDetail,
    ErrorResponse,
    Feedback,
    FeedbackCreate,
    HealthResponse,
    ModelManifest,
    Profile,
    ProfileCreate,
    ProfileUpdate,
    RunRecord,
    RunRequest,
    RunResponse,
    VerifyRequest,
    VerifyResponse,
)
from paceback_engine.service import DomainError, PaceBackService

_bearer = HTTPBearer(auto_error=False)
_auth_dependency = Depends(_bearer)
_acting_role_header = Header(alias="X-Acting-Role")


def create_app(settings: Settings | None = None) -> FastAPI:
    configured = settings or Settings.from_env()
    configured.data_dir.mkdir(parents=True, exist_ok=True)
    database = Database(
        configured.database_path,
        driver=configured.database_driver,
        storage_key=configured.storage_key,
    )
    database.initialize()
    service = PaceBackService(database, configured)
    docs_url = None if configured.release_mode else "/docs"
    openapi_url = None if configured.release_mode else "/openapi.json"
    app = FastAPI(
        title="PaceBack Local Engine",
        version=__version__,
        description="Local, bounded, citation-first retrieval for a research prototype.",
        docs_url=docs_url,
        redoc_url=None,
        openapi_url=openapi_url,
    )
    app.state.settings = configured
    app.state.database = database
    app.state.service = service
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=list(configured.allowed_hosts))

    @app.middleware("http")
    async def response_safety_headers(request: Request, call_next) -> Response:
        request.state.correlation_id = request.headers.get("X-Correlation-ID") or str(uuid4())
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = request.state.correlation_id
        response.headers.setdefault("Cache-Control", "no-store")
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy", "camera=(), microphone=(), geolocation=()"
        )
        return response

    @app.exception_handler(DomainError)
    async def domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
        return _error_response(
            request,
            status_code=exc.status_code,
            code=exc.code,
            message=exc.message,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        fields = sorted(
            {
                ".".join(str(part) for part in error["loc"] if part != "body")
                for error in exc.errors()
            }
        )
        return _error_response(
            request,
            status_code=422,
            code="validation_error",
            message="The request did not match the required contract.",
            fields=fields,
        )

    async def authenticate(
        request: Request,
        credentials: HTTPAuthorizationCredentials | None = _auth_dependency,
    ) -> None:
        if (
            credentials is None
            or credentials.scheme.lower() != "bearer"
            or not hmac.compare_digest(credentials.credentials, configured.auth_token)
        ):
            raise DomainError("authentication_required", "Bearer authentication failed.", 401)

    router = APIRouter(prefix="/v1", dependencies=[Depends(authenticate)])

    @router.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        return HealthResponse(
            version=__version__,
            database_ready=database.healthy(),
            fts5_ready=database.fts5_ready(),
            release_mode=configured.release_mode,
            storage_driver=configured.database_driver,
            storage_encryption_active=database.encryption_active,
        )

    @router.post("/profiles", response_model=Profile, status_code=status.HTTP_201_CREATED)
    def create_profile(request: ProfileCreate) -> Profile:
        return service.create_profile(request)

    @router.put("/profiles/{profile_id}", response_model=Profile)
    def sync_profile(profile_id: str, request: ProfileCreate) -> Profile:
        return service.sync_profile(profile_id, request)

    @router.get("/profiles", response_model=list[Profile])
    def list_profiles() -> list[Profile]:
        return service.list_profiles()

    @router.get("/profiles/{profile_id}", response_model=Profile)
    def get_profile(profile_id: str) -> Profile:
        return service.get_profile(profile_id)

    @router.patch("/profiles/{profile_id}", response_model=Profile)
    def update_profile(profile_id: str, request: ProfileUpdate) -> Profile:
        return service.update_profile(profile_id, request)

    @router.delete("/profiles/{profile_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_profile(
        profile_id: str,
        acting_role: ActingRole = _acting_role_header,
    ) -> Response:
        service.delete_profile(profile_id, acting_role)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.post(
        "/profiles/{profile_id}/documents",
        response_model=Document,
        status_code=status.HTTP_201_CREATED,
    )
    def create_document(profile_id: str, request: DocumentCreate) -> Document:
        return service.create_document(profile_id, request)

    @router.get("/profiles/{profile_id}/documents", response_model=list[Document])
    def list_documents(profile_id: str) -> list[Document]:
        return service.list_documents(profile_id)

    @router.get("/profiles/{profile_id}/documents/{document_id}", response_model=Document)
    def get_document(profile_id: str, document_id: str) -> Document:
        return service.get_document(profile_id, document_id)

    @router.patch("/profiles/{profile_id}/documents/{document_id}", response_model=Document)
    def update_document(
        profile_id: str, document_id: str, request: DocumentUpdate
    ) -> Document:
        return service.update_document(profile_id, document_id, request)

    @router.delete(
        "/profiles/{profile_id}/documents/{document_id}",
        status_code=status.HTTP_204_NO_CONTENT,
    )
    def delete_document(
        profile_id: str,
        document_id: str,
        acting_role: ActingRole = _acting_role_header,
    ) -> Response:
        service.delete_document(profile_id, document_id, acting_role)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.post("/runs", response_model=RunResponse, status_code=status.HTTP_201_CREATED)
    def create_run(request: RunRequest) -> RunResponse:
        return service.run(request)

    @router.get("/runs/{run_id}", response_model=RunRecord)
    def get_run(
        run_id: str,
        profile_id: str = Query(alias="profileID"),
    ) -> RunRecord:
        return service.get_run(run_id, profile_id)

    @router.get("/runs/{run_id}/events")
    async def run_events(
        run_id: str,
        profile_id: str = Query(alias="profileID"),
        last_event_id: int = Header(default=0, alias="Last-Event-ID", ge=0),
    ) -> StreamingResponse:
        if database.get_run(run_id, profile_id) is None:
            raise DomainError("run_not_found", "Run not found.", 404)
        return StreamingResponse(
            _event_stream(database, run_id, profile_id, last_event_id),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache, no-store", "X-Accel-Buffering": "no"},
        )

    @router.delete("/runs/{run_id}", response_model=CancellationResponse)
    def cancel_run(
        run_id: str,
        profile_id: str = Query(alias="profileID"),
    ) -> CancellationResponse:
        return service.cancel_run(run_id, profile_id)

    @router.post("/verify", response_model=VerifyResponse)
    def verify(request: VerifyRequest) -> VerifyResponse:
        return service.verify(request)

    @router.post(
        "/feedback", response_model=Feedback, status_code=status.HTTP_201_CREATED
    )
    def create_feedback(request: FeedbackCreate) -> Feedback:
        return service.create_feedback(request)

    @router.get("/models", response_model=ModelManifest)
    def models() -> ModelManifest:
        return service.model_manifest()

    app.include_router(router)
    return app


async def _event_stream(
    database: Database,
    run_id: str,
    profile_id: str,
    after: int,
) -> AsyncIterator[str]:
    deadline = asyncio.get_running_loop().time() + 30.0
    cursor = after
    while True:
        events = database.run_events(run_id, profile_id, cursor)
        for event in events:
            cursor = event["sequence"]
            data = json.dumps(event["payload"], separators=(",", ":"))
            yield f"id: {cursor}\nevent: {event['event']}\ndata: {data}\n\n"
        run = database.get_run(run_id, profile_id)
        if run is None or run["status"] in {"completed", "cancelled", "failed"}:
            return
        if asyncio.get_running_loop().time() >= deadline:
            yield "event: timeout\ndata: {}\n\n"
            return
        await asyncio.sleep(0.2)


def _error_response(
    request: Request,
    *,
    status_code: int,
    code: str,
    message: str,
    fields: list[str] | None = None,
) -> JSONResponse:
    correlation_id = getattr(request.state, "correlation_id", str(uuid4()))
    payload = ErrorResponse(
        error=ErrorDetail(
            code=code,
            message=message,
            correlation_id=correlation_id,
            fields=fields or [],
        )
    )
    headers = {"WWW-Authenticate": "Bearer"} if status_code == 401 else None
    return JSONResponse(
        status_code=status_code,
        content=payload.model_dump(mode="json", by_alias=True),
        headers=headers,
    )
