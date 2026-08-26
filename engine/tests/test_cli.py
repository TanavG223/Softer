from __future__ import annotations

import io

import pytest

from paceback_engine.cli import _model_pack_environment, _read_startup_secrets


def test_release_startup_reads_one_json_line_and_not_environment(monkeypatch):
    monkeypatch.setenv("PACEBACK_AUTH_TOKEN", "environment-token-must-not-win")
    monkeypatch.setattr(
        "sys.stdin",
        io.StringIO('{"authToken":"' + "a" * 32 + '","databaseKey":"' + "b" * 32 + '"}\n'),
    )
    token, key = _read_startup_secrets(development=False)
    assert token == "a" * 32
    assert key == "b" * 32


def test_startup_rejects_unknown_fields(monkeypatch):
    monkeypatch.setattr(
        "sys.stdin",
        io.StringIO('{"authToken":"' + "a" * 32 + '","secretInArgv":"forbidden"}\n'),
    )
    with pytest.raises(RuntimeError, match="accepts only"):
        _read_startup_secrets(development=False)


def test_startup_rejects_malformed_json(monkeypatch):
    monkeypatch.setattr("sys.stdin", io.StringIO("not-json\n"))
    with pytest.raises(RuntimeError, match="valid JSON"):
        _read_startup_secrets(development=False)


def test_development_may_read_environment(monkeypatch):
    monkeypatch.setenv("PACEBACK_AUTH_TOKEN", "a" * 32)
    monkeypatch.setenv("PACEBACK_STORAGE_KEY", "b" * 32)
    monkeypatch.setattr("sys.stdin", io.StringIO(""))
    assert _read_startup_secrets(development=True) == ("a" * 32, "b" * 32)


def test_model_pack_path_and_public_trust_key_are_read_from_environment(monkeypatch):
    monkeypatch.setenv("PACEBACK_MODEL_PACK_DIR", "/Applications/PaceBack/ModelPack")
    monkeypatch.setenv("PACEBACK_MODEL_TRUST_KEY", "public-ed25519-key")
    directory, trust_key = _model_pack_environment()
    assert str(directory) == "/Applications/PaceBack/ModelPack"
    assert trust_key == "public-ed25519-key"
