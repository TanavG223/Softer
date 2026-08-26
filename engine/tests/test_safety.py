from __future__ import annotations

from conftest import create_profile, run_payload


def test_child_specific_danger_sign_bypasses_retrieval(client, auth):
    profile = create_profile(
        client,
        auth,
        age_band="youngChild0To5",
        owner_role="guardian",
    )
    payload = run_payload(
        profile["profileID"],
        age_band="youngChild0To5",
        acting_role="guardian",
        care_context="home",
        question="My child will not stop crying and cannot be consoled.",
    )
    response = client.post("/v1/runs", headers=auth, json=payload)
    assert response.status_code == 201
    result = response.json()
    assert result["supportStatus"] == "dangerSignDetected"
    assert result["route"] == "direct"
    assert result["stopReason"] == "safetyGate"
    assert result["usage"]["retrievalRounds"] == 0
    assert "911" in result["answer"]
    assert result["citations"][0]["documentID"] == "cdc-danger-signs-2025"


def test_common_danger_sign_applies_to_adults(client, auth):
    profile = create_profile(
        client,
        auth,
        age_band="adult18To64",
        owner_role="selfManaged",
    )
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile["profileID"],
            age_band="adult18To64",
            acting_role="selfManaged",
            care_context="home",
            question="The headache is getting worse and does not go away.",
        ),
    )
    assert response.status_code == 201
    assert response.json()["supportStatus"] == "dangerSignDetected"


def test_infant_specific_sign_is_not_applied_to_school_age_profile(client, auth):
    profile = create_profile(
        client,
        auth,
        age_band="child6To12",
        owner_role="guardian",
    )
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile["profileID"],
            age_band="child6To12",
            acting_role="guardian",
            question="They will not nurse or eat.",
        ),
    )
    assert response.status_code == 201
    assert response.json()["supportStatus"] != "dangerSignDetected"


def test_child_only_phrase_does_not_trigger_adult_gate(client, auth):
    profile = create_profile(
        client,
        auth,
        age_band="adult18To64",
        owner_role="selfManaged",
    )
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile["profileID"],
            age_band="adult18To64",
            acting_role="selfManaged",
            care_context="dailyLiving",
            question="What does the phrase inconsolable crying mean?",
        ),
    )
    assert response.status_code == 201
    assert response.json()["supportStatus"] != "dangerSignDetected"
