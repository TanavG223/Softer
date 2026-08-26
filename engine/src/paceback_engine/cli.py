"""Hardened loopback launcher for the bundled sidecar."""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import threading
from pathlib import Path

import uvicorn

from paceback_engine.api import create_app
from paceback_engine.config import Settings


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the PaceBack local engine")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--development", action="store_true")
    return parser


def _read_startup_secrets(*, development: bool) -> tuple[str, str | None]:
    if development:
        token = os.getenv("PACEBACK_AUTH_TOKEN")
        if token:
            return token, os.getenv("PACEBACK_STORAGE_KEY")
    if sys.stdin.isatty():
        raise RuntimeError("Pass a one-line startup JSON object on stdin")
    try:
        payload = json.loads(sys.stdin.readline())
    except (json.JSONDecodeError, TypeError) as exc:
        raise RuntimeError("Startup stdin must be one valid JSON object") from exc
    if not isinstance(payload, dict) or set(payload) - {"authToken", "databaseKey"}:
        raise RuntimeError("Startup JSON accepts only authToken and databaseKey")
    token = payload.get("authToken")
    database_key = payload.get("databaseKey")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Startup JSON requires authToken")
    if database_key is not None and not isinstance(database_key, str):
        raise RuntimeError("databaseKey must be a string")
    return token, database_key


def _model_pack_environment() -> tuple[Path | None, str | None]:
    configured_dir = os.getenv("PACEBACK_MODEL_PACK_DIR")
    return (
        Path(configured_dir).expanduser() if configured_dir else None,
        os.getenv("PACEBACK_MODEL_TRUST_KEY"),
    )


def main() -> None:
    args = _parser().parse_args()
    token, database_key = _read_startup_secrets(development=args.development)
    model_pack_dir, model_pack_trust_key = _model_pack_environment()
    data_dir = args.data_dir or (
        Path.home() / "Library" / "Application Support" / "PaceBack" / "Engine"
    )
    settings = Settings(
        data_dir=data_dir,
        auth_token=token,
        release_mode=not args.development,
        database_driver="sqlite" if args.development and not database_key else "sqlcipher",
        storage_key=database_key,
        model_pack_dir=model_pack_dir,
        # This is a public verification key, not a startup secret. Keeping it
        # separate from the pack prevents a replaced pack from replacing trust.
        model_pack_trust_key=model_pack_trust_key,
    )
    app = create_app(settings)
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", args.port))
    listener.listen(128)
    selected_port = listener.getsockname()[1]
    print(
        json.dumps(
            {
                "protocolVersion": "v1",
                "pid": os.getpid(),
                "port": selected_port,
                "ready": True,
            },
            separators=(",", ":"),
        ),
        flush=True,
    )
    config = uvicorn.Config(
        app,
        host="127.0.0.1",
        port=selected_port,
        access_log=False,
        server_header=False,
        date_header=False,
        log_level="warning",
    )
    server = uvicorn.Server(config)

    # The native parent keeps stdin open for the helper's lifetime. If the app crashes or
    # quits, the pipe closes and the sidecar exits instead of becoming an orphan process.
    def stop_when_parent_closes() -> None:
        try:
            sys.stdin.read()
        finally:
            server.should_exit = True

    threading.Thread(
        target=stop_when_parent_closes,
        name="paceback-parent-liveness",
        daemon=True,
    ).start()
    server.run(sockets=[listener])


if __name__ == "__main__":
    main()
