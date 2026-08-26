# PaceBack local engine

The engine is an authenticated loopback-only FastAPI sidecar for PaceBack's AI/ML and Responsible AI pipeline. It stores profiles and private evidence in encrypted SQLCipher storage for release (plain SQLite only in explicit development mode), filters every query to one exact profile and age allowlist before both retrievers, performs local hybrid retrieval and reranking, and returns extractive, locatable citations. It does not call the internet, execute code, diagnose, prescribe, update a care plan, or train on user data.

## Runtime contract

Every `/v1` route, including `/v1/health`, requires
`Authorization: Bearer <per-launch-token>`. The packaged launcher reads that token from
a one-line JSON object on stdin together with a database key, binds only to `127.0.0.1`,
selects an ephemeral port by default, and prints readiness JSON containing only the protocol
version, process ID, and selected port. Secrets are never accepted in argv or printed.
Environment secrets are accepted only with `--development`.

Release mode fails closed unless a real `sqlcipher3` or `pysqlcipher3` DB-API driver and a
32-byte-or-longer database key are present. Plain SQLite is available only through the
explicit `--development` mode and is reported as unencrypted by health and model-manifest
responses. File permissions alone are not represented as encryption.

The release sidecar must be built with `.[encrypted]`; version `0.6.2` is pinned because the encrypted database implementation is a release artifact, not a floating runtime choice. `.[packaging]` installs that driver plus the pinned PyInstaller and Hatchling build backend used by `make package-macos`. `.[ml]` installs the pinned ONNX Runtime, tokenizer, NumPy, and Ed25519 verification dependencies used by the real-model path. The production package requires both extras; a source development run may omit `.[ml]` and will report deterministic fallbacks.

`PUT /v1/profiles/{profileID}` is the idempotent native synchronization route: it preserves the Swift profile UUID and refuses a later age-band or owner-role mutation. Confirmed clinician-plan text arrives through profile-scoped document CRUD. Unconfirmed care-plan draft fields are not sent by the native client.

The synchronous Swift integration endpoint is `POST /v1/runs`. Run replay uses `GET /v1/runs/{runID}?profileID=...`; event replay uses `GET /v1/runs/{runID}/events?profileID=...`; cancellation is the idempotent `DELETE /v1/runs/{runID}?profileID=...`. FastAPI runs the synchronous retrieval request in a worker thread, so a concurrent cancellation request can set the run's database flag while retrieval is in progress; the bounded loop checks that flag before each round and returns a structured cancelled result. This is cooperative cancellation, not preemption in the middle of one retriever call.

Development (explicitly unencrypted):

```bash
python -m pip install -e '.[dev]'
pytest
```

Every run requires exactly `allAges` plus the selected `AgeBand` raw value. There is no unknown-age profile or fallback scope. Single-step questions use one hybrid retrieval; multi-step questions use deterministic subquery expansion with at most three rounds. The `direct` route is currently reserved for deterministic danger-sign handling. Although the configuration exposes a maximum of six subqueries, 100 candidates, and eight actions, the current loop performs one retrieval action per round and has no separate query-correction action.

Each retrieval round requests up to 50 FTS5/BM25 and 50 dense candidates, fuses them with RRF `k=60`, reranks at most 30, rejects known prompt-injection text, and applies content-hash deduplication plus a three-chunk-per-document cap. The service reapplies those constraints globally across all iterative rounds before keeping at most eight evidence chunks. `AdaptiveContextBudgeter` performs extractive sentence selection only and preserves citation mapping.

When a verified model pack is configured, dense retrieval uses the local ONNX artifact for `BAAI/bge-small-en-v1.5` (384 dimensions) and reranking uses the local ONNX artifact for `cross-encoder/ms-marco-MiniLM-L-6-v2`. The engine has no downloader. It accepts a pack only after a separately configured Ed25519 trust key verifies the manifest and every loaded model/tokenizer matches its pinned SHA-256, byte length, model ID, upstream revision, dimensions, and I/O probe. A configured invalid pack stops release startup. With no configured pack, the deterministic hashing and lexical implementations remain active and are explicitly reported as fallbacks; they are not represented as trained ML.

Build-time model-pack creation downloads exactly 157,716,998 pinned artifact bytes (about 150.4 MiB) from immutable upstream revisions:

```bash
python -m pip install -e '.[ml]'
python scripts/download_model_pack.py \
  --output ../build/model-pack \
  --signing-key ~/.config/paceback/model-pack-signing-key.pem \
  --generate-signing-key \
  --public-key-output ../build/model-pack-trust-key.b64
```

Keep the private signing key outside the repository and application bundle. At runtime set `PACEBACK_MODEL_PACK_DIR` to the local pack and `PACEBACK_MODEL_TRUST_KEY` to the base64 public key. No network request is made during activation or inference. BGE is MIT-licensed; the MiniLM cross-encoder is Apache-2.0-licensed. These are frozen upstream artifacts, not custom fine-tuned PaceBack models.

The signed pack identified in `MODEL_PROVENANCE.md` has passed direct local activation/inference. A release-mode SQLCipher TestClient E2E smoke also activated BGE + MiniLM, synchronized an exact-UUID adult profile, indexed a confirmed synthetic clinician-plan sentence, and returned `verified` through `singleRetrieval` with four citations in one round; `/v1/models` simultaneously reported BGE, MiniLM, RRF, and FTS5 active. These checks establish loading, integrity verification, contracts, and wiring. A preceding packaged build passed the full app-managed model/helper lifecycle smoke; the current rebuilt artifact has passed signature and responsive-startup checks, but that complete lifecycle sequence has not yet been repeated against its final hashes.

The complete unreviewed real-pack diagnostic now records Recall@20 `0.9767`, nDCG@20 `0.954886`, and mean latency `51.53 ms`, compared with `0.9667`, `0.894214`, and `7.09 ms` for the matching deterministic-fallback run. Both model components changed together, both configurations retained the same weak 40/100 response-type and 3/63 boundary-routing results, and all human claim-support metrics remain unmeasured. This is not component attribution, promotion, or clinical evidence.

`GET /v1/models` is the source of truth for active component names and versions. Optional or inactive adapters must never be presented as the component that produced a run. Any trained reranker promotion remains governed by the offline reviewed-dev-data contract and frozen comparison protocol.

## Package runtime

From the repository root:

```bash
python3.13 -m venv .release-venv
.release-venv/bin/python -m pip install 'pip==25.3'
.release-venv/bin/python -m pip install \
  --require-hashes -r engine/requirements-release.lock
.release-venv/bin/python -m pip install \
  --no-build-isolation --no-deps ./engine
.release-venv/bin/python -m pip check
make package-macos ENGINE_PYTHON=.release-venv/bin/python
```

The hash-locked dependency install, local engine install, `pip check`, and required imports have passed in a clean Python 3.13 environment. See [provenance](../docs/provenance.md) for the lock, SBOM, and time-stamped pip-audit hashes. Python 3.11–3.13 remains the declared runtime range; Python 3.13 is the exact verified release-lock environment.

The package script accepts Python 3.11–3.13, requires `../build/model-pack` and `../build/model-pack-trust-key.b64` by default, freezes the selected environment with PyInstaller, embeds the signed model pack, separate public trust key, model provenance, NOTICE, canonical upstream MIT/Apache-2.0 model-license texts, and public evidence seed, and nests the helper at `PaceBack.app/Contents/Helpers/PaceBackEngine.app`. The helper therefore carries its Python runtime, ONNX Runtime, and tokenizer runtime; a compatible system Python is not a destination dependency. The seed currently includes CDC danger-sign, return-to-school and return-to-work summaries plus the link-attributed Amsterdam consensus boundary summary.

The current `../build/PaceBack.app` contains the pack and has passed strict deep Apple Development signature verification plus a responsive packaged-startup smoke after the Keychain-main-actor fix. The full helper check—random loopback binding, no observed outbound TCP, encrypted mode-`0600` SQLCipher storage rejected by plaintext `sqlite3`, and helper exit with its parent—was recorded on the immediately preceding package and has not been repeated against the current hashes. The archived current development ZIP and executable hashes are in [provenance](../docs/provenance.md). This artifact is not Developer ID signed, notarized, stapled, or clean-Mac assessed, and `spctl` rejects it.

This is an unvalidated research prototype that supports, but does not replace,
professional care.
