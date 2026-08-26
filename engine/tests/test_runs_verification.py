from __future__ import annotations

from conftest import add_document, create_profile, run_payload


def _grounded_run(client, auth):
    profile = create_profile(client, auth)
    add_document(
        client,
        auth,
        profile["profileID"],
        content="The confirmed clinician plan allows a quiet break after 18 minutes of screen use.",
    )
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile["profileID"],
            question="What does my confirmed plan say about screen use?",
        ),
    )
    assert response.status_code == 201, response.text
    return profile, response.json()


def test_synchronous_run_contract_and_replay(client, auth):
    profile, result = _grounded_run(client, auth)
    assert set(result) == {
        "runID",
        "answer",
        "supportStatus",
        "citations",
        "route",
        "stopReason",
        "usage",
    }
    assert set(result["usage"]) == {
        "retrievedTokens",
        "inputTokens",
        "outputTokens",
        "retrievalRounds",
        "latencyMS",
    }
    assert result["supportStatus"] == "verified"
    citation = result["citations"][0]
    assert {"sourceID", "title", "url", "page", "quote"} <= set(citation)
    replay = client.get(
        f"/v1/runs/{result['runID']}",
        headers=auth,
        params={"profileID": profile["profileID"]},
    )
    assert replay.status_code == 200
    assert replay.json()["answer"] == result["answer"]
    assert replay.json()["profileID"] == profile["profileID"]


def test_client_supplied_run_id_supports_early_cancellation_contract(client, auth):
    profile = create_profile(client, auth)
    run_id = "0C182C6D-D389-4ED2-BD4E-6E9E6BB1515C"
    payload = run_payload(profile["profileID"], question="What support is listed?")
    payload["runID"] = run_id
    response = client.post("/v1/runs", headers=auth, json=payload)
    assert response.status_code == 201, response.text
    assert response.json()["runID"] == run_id

    duplicate = client.post("/v1/runs", headers=auth, json=payload)
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "run_id_conflict"


def test_client_supplied_run_id_must_be_uuid(client, auth):
    profile = create_profile(client, auth)
    payload = run_payload(profile["profileID"], question="What support is listed?")
    payload["runID"] = "not-a-run-uuid"
    response = client.post("/v1/runs", headers=auth, json=payload)
    assert response.status_code == 422


def test_run_scope_is_exactly_all_ages_plus_selected_band(client, auth):
    profile = create_profile(client, auth)
    payload = run_payload(profile["profileID"], question="What support is listed?")
    payload["evidenceScope"] = ["allAges", "adult18To64"]
    response = client.post("/v1/runs", headers=auth, json=payload)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_run_rejects_age_band_mismatch_even_with_valid_scope(client, auth):
    profile = create_profile(client, auth)
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(
            profile["profileID"],
            age_band="adult18To64",
            acting_role="selfManaged",
            care_context="work",
            question="What support is listed?",
        ),
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "age_band_mismatch"


def test_max_output_tokens_is_bounded(client, auth):
    profile = create_profile(client, auth)
    payload = run_payload(profile["profileID"], question="What support is listed?")
    payload["maxOutputTokens"] = 2_000
    assert client.post("/v1/runs", headers=auth, json=payload).status_code == 422


def test_exact_extractive_claim_verifies_and_paraphrase_fails_closed(client, auth):
    profile, result = _grounded_run(client, auth)
    citation = result["citations"][0]
    exact = client.post(
        "/v1/verify",
        headers=auth,
        json={
            "profileID": profile["profileID"],
            "runID": result["runID"],
            "claims": [{"text": citation["quote"], "sourceID": citation["sourceID"]}],
        },
    )
    assert exact.status_code == 200
    assert exact.json()["supportStatus"] == "verified"
    unsupported = client.post(
        "/v1/verify",
        headers=auth,
        json={
            "profileID": profile["profileID"],
            "runID": result["runID"],
            "claims": [
                {
                    "text": "This plan guarantees complete recovery tomorrow.",
                    "sourceID": citation["sourceID"],
                }
            ],
        },
    )
    assert unsupported.status_code == 200
    assert unsupported.json()["supportStatus"] == "insufficientInformation"
    assert unsupported.json()["deletedClaims"][0]["reason"] == "unsupportedByExtract"


def test_unknown_citation_is_deleted_not_returned(client, auth):
    profile, result = _grounded_run(client, auth)
    response = client.post(
        "/v1/verify",
        headers=auth,
        json={
            "profileID": profile["profileID"],
            "runID": result["runID"],
            "claims": [{"text": "Invented claim", "sourceID": "not-in-this-run"}],
        },
    )
    assert response.status_code == 200
    assert response.json()["verifiedClaims"] == []
    assert response.json()["deletedClaims"][0]["reason"] == "unknownSource"


def test_sse_replays_started_and_completed_events(client, auth):
    profile, result = _grounded_run(client, auth)
    response = client.get(
        f"/v1/runs/{result['runID']}/events",
        headers=auth,
        params={"profileID": profile["profileID"]},
    )
    assert response.status_code == 200
    assert "event: started" in response.text
    assert "event: completed" in response.text
    assert "test-token" not in response.text


def test_cancelling_completed_run_is_idempotent(client, auth):
    profile, result = _grounded_run(client, auth)
    url = f"/v1/runs/{result['runID']}"
    parameters = {"profileID": profile["profileID"]}
    first = client.delete(url, headers=auth, params=parameters)
    second = client.delete(url, headers=auth, params=parameters)
    assert first.status_code == second.status_code == 200
    assert first.json()["status"] == second.json()["status"] == "completed"


def test_feedback_is_local_and_upserted(client, auth):
    profile, result = _grounded_run(client, auth)
    payload = {
        "profileID": profile["profileID"],
        "runID": result["runID"],
        "helpful": True,
        "reason": "The citation was clear.",
    }
    first = client.post("/v1/feedback", headers=auth, json=payload)
    assert first.status_code == 201
    payload["helpful"] = False
    second = client.post("/v1/feedback", headers=auth, json=payload)
    assert second.status_code == 201
    assert second.json()["helpful"] is False


def test_retrieval_exception_returns_unverified_fallback(client, auth, app, monkeypatch):
    profile = create_profile(client, auth)

    def fail(*args, **kwargs):
        raise RuntimeError("simulated model failure")

    monkeypatch.setattr(app.state.service.retriever, "search", fail)
    response = client.post(
        "/v1/runs",
        headers=auth,
        json=run_payload(profile["profileID"], question="What support is listed?"),
    )
    assert response.status_code == 201
    assert response.json()["answer"] == "I could not verify an answer."
    assert response.json()["supportStatus"] == "insufficientInformation"
    assert response.json()["stopReason"] == "resourceLimit"
    assert response.json()["citations"] == []
