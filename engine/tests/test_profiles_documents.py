from __future__ import annotations

from conftest import add_document, create_profile, run_payload


def test_native_profile_sync_preserves_exact_id_and_is_idempotent(client, auth):
    profile_id = "A0E2F0B1-47A8-4D34-9B57-8236D403FB8D"
    payload = {
        "alias": "Local alias",
        "ageBand": "adult18To64",
        "ownerRole": "selfManaged",
        "caregiverAccess": False,
    }
    created = client.put(f"/v1/profiles/{profile_id}", headers=auth, json=payload)
    assert created.status_code == 200, created.text
    assert created.json()["profileID"] == profile_id

    payload["alias"] = "Updated local alias"
    payload["caregiverAccess"] = True
    updated = client.put(f"/v1/profiles/{profile_id}", headers=auth, json=payload)
    assert updated.status_code == 200, updated.text
    assert updated.json()["profileID"] == profile_id
    assert updated.json()["alias"] == "Updated local alias"
    assert updated.json()["caregiverAccess"] is True
    assert len(client.get("/v1/profiles", headers=auth).json()) == 1


def test_native_profile_sync_rejects_boundary_changes(client, auth):
    profile_id = "a0e2f0b1-47a8-4d34-9b57-8236d403fb8d"
    original = {
        "alias": "Teen",
        "ageBand": "teen13To17",
        "ownerRole": "guardian",
        "caregiverAccess": False,
    }
    assert client.put(f"/v1/profiles/{profile_id}", headers=auth, json=original).status_code == 200

    changed = {**original, "ageBand": "adult18To64", "ownerRole": "selfManaged"}
    response = client.put(f"/v1/profiles/{profile_id}", headers=auth, json=changed)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "immutable_profile_boundary"


def test_native_profile_sync_rejects_non_uuid_id(client, auth):
    response = client.put(
        "/v1/profiles/not-a-uuid",
        headers=auth,
        json={
            "alias": "Invalid",
            "ageBand": "adult18To64",
            "ownerRole": "selfManaged",
            "caregiverAccess": False,
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_profile_id"


def test_minor_profiles_require_caregiver_or_guardian_owner(client, auth):
    response = client.post(
        "/v1/profiles",
        headers=auth,
        json={
            "alias": "Kid",
            "ageBand": "child6To12",
            "ownerRole": "selfManaged",
            "caregiverAccess": False,
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_owner_role"


def test_adult_profiles_require_self_managed_owner(client, auth):
    response = client.post(
        "/v1/profiles",
        headers=auth,
        json={
            "alias": "Adult",
            "ageBand": "adult18To64",
            "ownerRole": "caregiver",
            "caregiverAccess": True,
        },
    )
    assert response.status_code == 422


def test_teen_profiles_require_guardian_owner(client, auth):
    response = client.post(
        "/v1/profiles",
        headers=auth,
        json={
            "alias": "Teen",
            "ageBand": "teen13To17",
            "ownerRole": "caregiver",
            "caregiverAccess": False,
        },
    )
    assert response.status_code == 422


def test_contract_rejects_birth_dates_and_unknown_roles(client, auth):
    response = client.post(
        "/v1/profiles",
        headers=auth,
        json={
            "alias": "No DOB",
            "ageBand": "adult18To64",
            "ownerRole": "self",
            "birthDate": "2000-01-01",
        },
    )
    assert response.status_code == 422
    assert set(response.json()["error"]["fields"]) >= {"birthDate", "ownerRole"}


def test_teen_can_query_but_cannot_import(client, auth):
    profile = create_profile(client, auth)
    response = client.post(
        f"/v1/profiles/{profile['profileID']}/documents",
        headers=auth,
        json={
            "actingRole": "teenUser",
            "title": "Attempt",
            "content": "This text must not be indexed.",
            "sourceKind": "userProvided",
            "evidenceScope": "teen13To17",
        },
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "permission_denied"


def test_private_document_must_match_profile_age_scope(client, auth):
    profile = create_profile(client, auth)
    response = client.post(
        f"/v1/profiles/{profile['profileID']}/documents",
        headers=auth,
        json={
            "actingRole": "guardian",
            "title": "Wrong scope",
            "content": "Private document content.",
            "sourceKind": "userProvided",
            "evidenceScope": "adult18To64",
        },
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_document_scope"


def test_document_crud_reindexes_and_deletes(client, auth):
    profile = create_profile(client, auth)
    profile_id = profile["profileID"]
    document = add_document(
        client,
        auth,
        profile_id,
        content="The confirmed plan says take a quiet break after fifteen minutes.",
    )
    document_id = document["documentID"]
    assert document["chunkCount"] == 1
    updated = client.patch(
        f"/v1/profiles/{profile_id}/documents/{document_id}",
        headers=auth,
        json={
            "actingRole": "guardian",
            "content": "The confirmed plan says use a quiet room after twenty minutes.",
        },
    )
    assert updated.status_code == 200
    assert updated.json()["contentHash"] != document["contentHash"]
    fetched = client.get(
        f"/v1/profiles/{profile_id}/documents/{document_id}", headers=auth
    )
    assert fetched.json()["content"].endswith("twenty minutes.")
    deleted = client.delete(
        f"/v1/profiles/{profile_id}/documents/{document_id}",
        headers={**auth, "X-Acting-Role": "guardian"},
    )
    assert deleted.status_code == 204
    assert (
        client.get(
            f"/v1/profiles/{profile_id}/documents/{document_id}", headers=auth
        ).status_code
        == 404
    )


def test_cross_profile_documents_and_runs_are_isolated(client, auth):
    first = create_profile(client, auth, alias="First")
    second = create_profile(client, auth, alias="Second")
    first_doc = add_document(
        client,
        auth,
        first["profileID"],
        title="First private plan",
        content="The private cobalt-marker plan says a 17 minute screen limit.",
    )
    add_document(
        client,
        auth,
        second["profileID"],
        title="Second private plan",
        content="The private amber-marker plan says a 29 minute screen limit.",
    )
    hidden = client.get(
        f"/v1/profiles/{second['profileID']}/documents/{first_doc['documentID']}",
        headers=auth,
    )
    assert hidden.status_code == 404
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            first["profileID"], question="What does the cobalt-marker plan say?"
        ),
    )
    assert response.status_code == 201
    assert "cobalt-marker" in response.json()["answer"]
    assert "amber-marker" not in response.text
    replay = client.get(
        f"/v1/runs/{response.json()['runID']}",
        headers=auth,
        params={"profileID": second["profileID"]},
    )
    assert replay.status_code == 404


def test_adult_caregiver_access_is_revocable_and_not_admin(client, auth):
    profile = create_profile(
        client,
        auth,
        age_band="adult18To64",
        owner_role="selfManaged",
        caregiver_access=False,
    )
    profile_id = profile["profileID"]
    denied = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile_id,
            age_band="adult18To64",
            acting_role="caregiver",
            care_context="work",
            question="What work supports are in the evidence?",
        ),
    )
    assert denied.status_code == 403
    enabled = client.patch(
        f"/v1/profiles/{profile_id}",
        headers=auth,
        json={"actingRole": "selfManaged", "caregiverAccess": True},
    )
    assert enabled.status_code == 200
    allowed = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile_id,
            age_band="adult18To64",
            acting_role="caregiver",
            care_context="work",
            question="What work supports are in the evidence?",
        ),
    )
    assert allowed.status_code == 201
    cannot_delete = client.delete(
        f"/v1/profiles/{profile_id}",
        headers={**auth, "X-Acting-Role": "caregiver"},
    )
    assert cannot_delete.status_code == 403
