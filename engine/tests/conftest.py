from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from paceback_engine import Settings, create_app

TOKEN = "test-token-that-is-at-least-thirty-two-bytes-long"


@pytest.fixture
def app(tmp_path):
    return create_app(
        Settings(
            data_dir=tmp_path / "data",
            auth_token=TOKEN,
            release_mode=False,
            database_driver="sqlite",
        )
    )


@pytest.fixture
def client(app) -> Iterator[TestClient]:
    with TestClient(app) as instance:
        yield instance


@pytest.fixture
def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


def create_profile(
    client: TestClient,
    auth: dict[str, str],
    *,
    alias: str = "Taylor",
    age_band: str = "teen13To17",
    owner_role: str = "guardian",
    caregiver_access: bool = False,
) -> dict:
    response = client.post(
        "/v1/profiles",
        headers=auth,
        json={
            "alias": alias,
            "ageBand": age_band,
            "ownerRole": owner_role,
            "caregiverAccess": caregiver_access,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def add_document(
    client: TestClient,
    auth: dict[str, str],
    profile_id: str,
    *,
    content: str,
    title: str = "Confirmed plan",
    acting_role: str = "guardian",
    scope: str = "teen13To17",
) -> dict:
    response = client.post(
        f"/v1/profiles/{profile_id}/documents",
        headers=auth,
        json={
            "actingRole": acting_role,
            "title": title,
            "content": content,
            "sourceKind": "clinicianPlan",
            "evidenceScope": scope,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def run_payload(
    profile_id: str,
    *,
    question: str,
    age_band: str = "teen13To17",
    acting_role: str = "teenUser",
    care_context: str = "school",
    max_output_tokens: int = 256,
) -> dict:
    return {
        "profileID": profile_id,
        "ageBand": age_band,
        "actingRole": acting_role,
        "careContext": care_context,
        "evidenceScope": ["allAges", age_band],
        "question": question,
        "maxOutputTokens": max_output_tokens,
    }
