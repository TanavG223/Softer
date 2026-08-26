# PaceBack architecture

Status: implementation architecture for an unvalidated research prototype. “Local” means the current application design has no intentional network path for health data; it is not a claim that the host device is secure or that every future build preserves this property. macOS and iOS use separate AI/ML runtimes with different capabilities and evidence stores.

## macOS components and trust boundaries

```text
User / caregiver
      |
      v
Native macOS SwiftUI process
  - age/role policy and parental gates
  - profile files encrypted with per-profile AES-GCM keys in Keychain
  - bounded PDFKit/Vision import draft and human confirmation
  - exact-ID profile/care-plan synchronization and deletion tombstones
  - deterministic danger-sign UI and text-to-speech
      |
      | random 127.0.0.1 port + per-launch bearer token
      v
Python sidecar
  - strict /v1 JSON contracts
  - profile and evidence namespaces
  - SQLite FTS5 + local dense retrieval
  - reciprocal-rank fusion, reranking seam, context reduction
  - cross-round bounds, citations, verification, structured failures
      |
      v
Local application-support directory
  - SQLCipher-encrypted private documents, chunks, runs, feedback, and indexes in release
  - explicit plaintext SQLite is permitted only in development mode and reported as such
  - no configured cloud provider or web-search tool
```

The native process and sidecar are separate trust zones. A bearer token prevents accidental unauthenticated loopback access but does not protect against a malicious process running as the same macOS user. Retrieved documents are untrusted data and never instructions. Public evidence, private profile evidence, and every other profile are separate retrieval namespaces. The runtime accepts only the five explicit `AgeBand` values; it has no unknown-age profile mode.

## iOS companion boundary

`ios/PaceBackiOS.xcodeproj` is a separate native SwiftUI target for iPhone and iPad (`PaceBackiOS`, bundle `org.paceback.research.ios`, minimum iOS 18). It cannot launch the bundled Python helper used by macOS. Instead, a required first-use `ModelSetupView` installs a separate pack of four frozen artifacts: BGE-small ONNX weights and tokenizer plus quantized MiniLM ONNX weights and tokenizer, exactly 157,716,998 bytes. The preflight requires 357,919,352 bytes of working space: final pack size, the largest temporary artifact, and 64 MiB of staging headroom.

The download uses an ephemeral `URLSession`, HTTPS-only pinned Hugging Face artifact URLs, an approved redirect-host allowlist, and an explicit Wi-Fi-only or Wi-Fi-plus-cellular choice. Requests contain no profile ID, alias, age band, symptom, question, or care-plan field. Cancel preserves resumable staging when available; retry, delete, and reinstall are user-visible. PaceBack validates the bundled Ed25519-signed manifest and separate public key, immutable model revisions, every artifact's exact size and SHA-256, and the installed manifest before atomic activation. A failed or partial replacement never becomes active, and the UI makes no background-download claim.

After activation, Swift applies profile/role validation and age scope before in-memory BM25 and BGE-small dense retrieval over seven bundled curated public-source summaries, fuses ranks with RRF (`k=60`), reranks at most 30 candidates with quantized MiniLM through the official ONNX Runtime Swift package pinned at 1.24.2, removes duplicate content, caps three excerpts per source, and returns no more than eight. Output is an extractive list of literal source substrings with source ID, passage ID, source publication date, URL, and content hash. A source-linked result means only that every displayed excerpt is locatable in its bundled passage; it is **not** clinical validity, correctness, or clearance.

The iOS engine has no generation, live or offline training, user-data learning/upload, multi-round adaptive loop, SQLCipher index, clinician-document ingestion, or clinician-plan RAG. It abstains on missing/corrupt models or corpus, unsupported questions, and professional decisions; its provisional support thresholds are not clinically calibrated and require held-out review. The deterministic age-filtered CDC danger-sign screen remains outside the AI path. Profiles use separate AES-GCM keys in Keychain and iOS Data Protection; role policy and LocalAuthentication gates, focus sessions, and trusted-source links remain available. Source links are explicit user-initiated browser navigation. macOS and iOS do not synchronize profiles, care plans, or documents.

## macOS age and role contract

| Age band | Normal operator | Direct capabilities | Protected capabilities |
|---|---|---|---|
| `youngChild0To5` | Guardian or caregiver | Caregiver-led guided sessions | PDF import, clipboard report, deletion, and settings require the pediatric administrative gate |
| `child6To12` | Guardian or caregiver | Optional guided child view | PDF import, clipboard report, deletion, and settings require the pediatric administrative gate |
| `teen13To17` | Teen after guardian setup | Guided sessions, simplification, age-filtered evidence questions | Entering guardian mode, care-plan administration, import, clipboard report, deletion, and settings |
| `adult18To64` | Self | Full self-managed prototype features | Caregiver use requires explicit revocable approval |
| `olderAdult65Plus` | Self or approved caregiver | Full self-managed prototype features | Caregiver use requires explicit revocable approval |

The engine independently checks role permissions, profile age, and the exact evidence-scope set. UI hiding is not an authorization control. Role handoff is implemented as a separate policy: entering teen guardian mode, switching administrators for an under-13 profile, and returning an adult caregiver session to owner controls require LocalAuthentication. Handoff from guardian to teen and from an approved adult owner to caregiver deliberately reduces privileges without another prompt.

The iOS target mirrors the all-age ownership boundary in a narrower interface: pediatric profile creation and protected pediatric/teen administration use LocalAuthentication, under-13 use remains caregiver-operated, and adult caregiver access requires explicit approval. It does not expose functional macOS PDF import, clinician-plan ingestion/RAG, general-text simplification, clipboard-report, or trend behavior. Its Evidence screen provides only the seven-summary curated-corpus local extractive retrieval described above; its Care Plan screen discloses that import and OCR remain macOS-only.

## macOS evidence-request path

1. Swift selects one profile and synchronizes its exact UUID, alias, immutable age/owner boundary, and adult caregiver-approval state. Only confirmed plan rows are serialized into an age-scoped `clinicianPlan` document; a matching content hash avoids needless reindexing, a replacement is activated before stale versions are deleted, and no confirmed rows removes the sidecar plan.
2. Swift constructs `profileID`, `ageBand`, `actingRole`, `careContext`, and exactly two wire scopes: `allAges` plus the profile-specific `AgeBand` raw value.
3. Before model or retrieval work, deterministic native and engine safety gates inspect the request for reviewed danger-sign phrases. A match uses the `direct` route, bypasses retrieval/generation, and returns static emergency-direction content without asserting a diagnosis.
4. The sidecar authenticates, verifies role/profile/scope consistency, and creates a bounded run record.
5. Ordinary questions route to `singleRetrieval` or `iterativeRetrieval`. Iterative retrieval uses deterministic subquery expansion and is limited to three rounds, six generated subqueries, 100 unique candidates, and eight configured actions. The current loop performs one retrieval action per round and does not implement a separate correction action.
6. Each retrieval operation filters by public/profile namespace and age scope before sparse and dense ranking. Sparse and dense top-50 lists are fused with RRF (`k=60`), and the top 30 enter reranking. Per-round selection rejects known prompt-injection text; final aggregation reapplies content-hash deduplication and a three-chunk-per-document cap globally across all rounds before keeping at most eight hits.
7. `AdaptiveContextBudgeter` performs extractive reduction only. It prioritizes sentences containing query terms, numbers, negations, warnings, and danger language; it does not paraphrase evidence.
8. The sidecar produces an extractive answer and locatable citations. Unknown, unlocatable, or unsupported claims are deleted; no surviving support returns `I could not verify an answer.`
9. Swift rejects a verified/partial response with no citations. Cancellation is idempotent and must include both run and profile identifiers. A concurrent `DELETE` marks an in-flight run; the worker checks before every retrieval round, while native task cancellation stops waiting for the HTTP response.

## macOS versioned loopback interface

Every route requires `Authorization: Bearer <per-launch-token>`. Release mode disables `/docs`, `/redoc`, and `/openapi.json`. Responses use `Cache-Control: no-store`, correlation IDs, and restrictive browser-style headers even though the caller is native.

| Method and path | Purpose | Important scope rule |
|---|---|---|
| `GET /v1/health` | Version, database, FTS5, release, and network-tool status | Authenticated even for health |
| `POST /v1/profiles` | Create an engine-native profile | Owner role must be valid for age |
| `PUT /v1/profiles/{profileID}` | Idempotently mirror a native profile using its exact UUID | Existing age band and owner role are immutable |
| `GET/PATCH/DELETE /v1/profiles...` | Profile lifecycle | Administrative role checked server-side |
| `POST/GET/PATCH/DELETE /v1/profiles/{profileID}/documents...` | Private evidence lifecycle | Document profile and age scope must match |
| `POST /v1/runs` | Bounded evidence request | Exact `allAges + selectedAgeBand` scope |
| `GET /v1/runs/{runID}` | Replay final record | Requires matching `profileID` query |
| `GET /v1/runs/{runID}/events` | SSE event replay | Requires matching `profileID`; bounded stream |
| `DELETE /v1/runs/{runID}` | Idempotent cancellation | Requires matching `profileID` query |
| `POST /v1/verify` | Fail-closed claim/source verification | Claims must belong to the named run/profile |
| `POST /v1/feedback` | Local helpful/not-helpful feedback | Never becomes live weight training data |
| `GET /v1/models` | Active/inactive runtime component and storage manifest | Source of truth for component claims; it does not report configured loop limits |

All request and response models reject unknown fields. Error responses contain a stable code, non-sensitive message, correlation ID, and field names—not document text.

## macOS model and adaptive-compute boundary

`GET /v1/models` is the authoritative record of which sparse, dense, fusion, and reranking components are active. When a signed pack is configured, the engine verifies a separately supplied Ed25519 trust key, manifest signature, pinned hashes and sizes, model IDs, immutable upstream revisions, dimensions, and ONNX I/O probes before it activates BGE-small embeddings and MiniLM reranking. A configured invalid pack stops release startup; no configured pack leaves explicitly named deterministic fallbacks active. The signed pack recorded in `engine/MODEL_PROVENANCE.md` passed direct activation/inference and a release-mode SQLCipher profile/index/run smoke. A preceding packaged build completed the app-managed model/helper lifecycle smoke; the current final-hash artifact has only the narrower signature and responsive-startup check. A complete real-pack benchmark diagnostic also exists, but it changes BGE and MiniLM together and remains unreviewed; it is not component attribution or promotion evidence.

An adapter name or an artifact present on disk is not proof that it produced a particular result or improved retrieval quality. The offline reranker training contract in `benchmark/train_reranker.py` accepts only reviewed development judgments without user data and may emit a candidate only when validation nDCG strictly improves; a candidate still requires a frozen evaluation and explicit promotion decision.

Apple Foundation Models is used only by the native general-text simplification abstraction. Medical, clinician, restriction, danger, diagnosis, medication, and return-to-activity text is always routed to the extractive fallback. For eligible general text, Swift calls `tokenCount(for:)` for the exact instructions and prompt, reserves 512 response tokens, and compares the sum with the model's `contextSize` before creating a session. Generated text is accepted only after protected-span, unsupported-medical-action, and lexical-grounding checks; otherwise the source is reduced extractively.

The packaged application starts with a visibly unavailable local-engine state. `SidecarEngineRuntime` discovers the fixed nested helper (or a debug-only absolute override), validates its code signature, generates a per-launch secret, loads or creates a SQLCipher key in Keychain, and installs the live client only after validating the handshake and health response. Failure keeps evidence Q&A disabled. `MockAIEngine` is a test/preview dependency, not the packaged application's automatic answer fallback.

Confirmed preferences are stored as an editable encrypted ledger, but the current pipeline does not consume them in retrieval, budgeting, simplification, generation, or training. “Adaptive” currently refers to bounded query routing, iterative retrieval, and extractive context budgeting—not learned personalization, tokenizer retraining, or live weight updates.

## macOS persistence and deletion

The native profile repository encrypts separate profile envelopes with keys stored independently in Keychain. The sidecar enforces per-profile namespaces, foreign keys, cascading deletion, file mode `0600`, directory mode `0700`, WAL, `secure_delete`, and full synchronous writes. Release configuration also requires a real `sqlcipher3` or `pysqlcipher3` driver and a 32-byte-or-longer Keychain-provided database key; configuration and startup fail closed otherwise. Health and model-manifest responses report the actual storage driver and encryption state. Plain SQLite is available only through explicit development mode.

SQLCipher encrypts the sidecar database as one database, while native profile envelopes retain independent keys. It does not by itself provide per-profile cryptographic erasure inside the sidecar. Deletion verification must therefore still cover database pages, WAL/SHM, native envelopes, Keychain keys, and any text the user copied to the clipboard. The app does not create or cache report files, and it cannot retract clipboard content copied into another process.

## macOS packaging boundary

`make package-macos` requires a signed model pack plus its separate public trust key, builds an arm64 Swift release executable, freezes the selected Python 3.11–3.13 environment into a PyInstaller `onedir` helper app, embeds the model pack, trust key, model provenance, NOTICE, canonical upstream model-license texts, ONNX Runtime software-license text, evidence seed, and app icon, places the helper at the fixed nested path, signs nested code before the outer app, and performs strict code-signature verification. Because the Python interpreter and ML runtime are bundled, a compatible system Python is not a user runtime dependency. With an explicit Developer ID `SIGN_IDENTITY` and `NOTARY_PROFILE`, the script also submits, staples, and runs `spctl`.

The repository does not contain distribution-signing credentials and ordinary pull-request CI neither packages nor notarizes. The current arm64 app occupies 306,068 KiB on disk (about 299 MiB), is Apple Development-signed under team `8RMK4MG9T2`, and passes strict deep signature verification. A fresh packaged launch after the Keychain startup fix produced a layer-0 1180×780 window in about 0.6 seconds while the sampled main thread remained in AppKit's event loop; exact ZIP and executable hashes are archived in `docs/provenance.md`. This is development-build evidence only: `spctl` rejects the app because it is not a Developer ID/notarized distribution. Developer ID signing, notarization, stapling, clean-Mac Gatekeeper testing, 8/16 GB profiling, and independent review remain release gates.
