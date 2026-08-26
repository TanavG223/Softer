from __future__ import annotations

import pytest

from paceback_engine import Settings


def test_every_v1_route_including_health_requires_bearer(client):
    response = client.get("/v1/health")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "authentication_required"
    assert response.headers["www-authenticate"] == "Bearer"


def test_bad_token_is_rejected(client):
    response = client.get("/v1/health", headers={"Authorization": "Bearer wrong"})
    assert response.status_code == 401


def test_health_is_local_and_reports_explicit_dev_storage(client, auth):
    response = client.get("/v1/health", headers=auth)
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": "0.1.0",
        "databaseReady": True,
        "fts5Ready": True,
        "releaseMode": False,
        "storageDriver": "sqlite",
        "storageEncryptionActive": False,
        "networkToolsEnabled": False,
    }
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"


def test_development_mode_exposes_docs_explicitly(client):
    assert client.get("/docs").status_code == 200
    assert client.get("/openapi.json").status_code == 200


def test_release_settings_refuse_plaintext_or_missing_key(tmp_path):
    with pytest.raises(ValueError, match="SQLCipher"):
        Settings(
            data_dir=tmp_path,
            auth_token="a" * 32,
            release_mode=True,
            database_driver="sqlite",
        )
    with pytest.raises(ValueError, match="SQLCipher"):
        Settings(
            data_dir=tmp_path,
            auth_token="a" * 32,
            release_mode=True,
            database_driver="sqlcipher",
            storage_key=None,
        )


def test_untrusted_host_is_rejected(client, auth):
    response = client.get("/v1/health", headers={**auth, "Host": "example.com"})
    assert response.status_code == 400


def test_validation_errors_are_structured_and_do_not_echo_input(client, auth):
    secret = "private-health-text-that-must-not-be-echoed"
    response = client.post(
        "/v1/profiles", headers=auth, json={"alias": secret, "unexpected": secret}
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert "correlationID" in response.json()["error"]
    assert secret not in response.text


def test_model_manifest_explicitly_disables_risky_tools(client, auth):
    response = client.get("/v1/models", headers=auth)
    assert response.status_code == 200
    payload = response.json()
    assert payload["webSearchEnabled"] is False
    assert payload["codeExecutionEnabled"] is False
    assert payload["runtimeWeightUpdatesEnabled"] is False
    assert payload["storageDriver"] == "sqlite"
    assert payload["storageEncryptionActive"] is False
    assert payload["modelPackActivation"] == "unconfigured"
    assert payload["modelPackID"] is None
    assert {item["name"] for item in payload["components"]} >= {
        "sqlite-fts5-bm25",
        "signed-hashing-vector",
        "reciprocal-rank-fusion",
    }
    adapters = {item["name"]: item for item in payload["components"]}
    assert adapters["bge-small-en-v1.5-onnx"]["active"] is False
    assert adapters["bge-small-en-v1.5-onnx"]["activation"] == "unconfigured"
    assert adapters["ms-marco-MiniLM-L6-v2-onnx"]["active"] is False
    assert adapters["ms-marco-MiniLM-L6-v2-onnx"]["activation"] == "unconfigured"
    assert adapters["signed-hashing-vector"]["activation"] == "fallback"
    assert adapters["deterministic-lexical-reranker"]["activation"] == "fallback"
