# PaceBack

PaceBack is an all-ages, local-first concussion-recovery companion built as an **unvalidated Hack for Humanity research prototype**. The macOS app provides the full clinician-plan and adaptive-RAG workflow; a separate native iPhone/iPad companion provides bounded, retrieval-only on-device AI after an explicit model setup. PaceBack helps a person or caregiver organize professional guidance and pace screen-based activities. It does not diagnose, treat, prescribe, predict recovery, or grant school, work, sports, driving, or exercise clearance.

**Primary track:** Best Use of AI/ML & Responsible AI. **Secondary track:** Best Tech for Concussion Recovery. The project also belongs in the core Physical Health category. The AI/ML entry is grounded in age-scoped local hybrid retrieval, bounded orchestration, source-linked extractive responses, privacy controls, and a frozen evaluation protocol—not in a medical-performance claim.

Young children are caregiver-operated, school-age children have an optional guided view, teens use a guardian-initialized mode, and adults or older adults may self-manage or authorize a caregiver.

## What is implemented

- Native macOS SwiftUI experience for onboarding, Today, focus sessions, simplification, evidence Q&A, trends, care-plan review, privacy, and About. Its bounded text-scale preference maps into Dynamic Type and control size; shared presentation honors the system Reduce Motion, Reduce Transparency, and Increase Contrast settings. Representative-user accessibility testing remains pending.
- Native iOS 18+ SwiftUI companion under `ios/` for iPhone and iPad (`PaceBackiOS`, bundle `org.paceback.research.ios`). It retains deterministic age-filtered danger signs, encrypted local profiles, age/role gates, focus sessions, and a trusted-source catalog.
- Required iOS model setup downloads exactly 157,716,998 frozen BGE-small/MiniLM ONNX and tokenizer bytes from pinned Hugging Face revisions through ephemeral, allowlisted HTTPS requests. The UI offers Wi-Fi-only or cellular permission, progress, safe cancel/resume, delete/reinstall, and a privacy receipt; signed-manifest, exact-size, and SHA-256 checks precede atomic activation. No profile, symptom, care-plan field, or question is part of a model request.
- iOS retrieval uses seven bundled curated public-source summaries, age filtering before Swift BM25 and BGE-small dense search, RRF fusion, MiniLM reranking through ONNX Runtime 1.24.2, and source-linked extractive excerpts. It has no generation, training, user-data learning/upload, multi-round adaptive loop, or clinician-document ingestion, and it abstains when its pack, corpus, thresholds, or citations cannot support a response.
- Explicit `AgeBand`, `ActingRole`, `CareContext`, permission policies, and implemented role handoffs. LocalAuthentication protects pediatric administration, entry to teen guardian mode, and return from an adult caregiver session to profile-owner controls; it is a device gate, not proof of legal guardianship.
- Separate AES-GCM native profile envelopes and per-profile Keychain keys.
- Exact-ID native-to-sidecar profile synchronization, queued replay after helper startup, deletion tombstones, and confirmed-only clinician-plan synchronization. Unconfirmed PDF draft fields never enter retrieval.
- Integrated helper lifecycle that discovers the bundled executable, verifies bundled code and release health, generates a per-launch bearer token, loads a SQLCipher key from Keychain, sends both secrets through one JSON stdin message, validates the PID/port/health handshake, switches to the live engine, and terminates the helper with the app.
- Authenticated loopback FastAPI sidecar with strict JSON, release-disabled API docs, SQLCipher-gated release storage, profile/age namespaces, bounded runs, SSE replay, true in-flight cancellation checks, feedback storage, and an honest runtime component manifest.
- Age-filtered hybrid search with SQLite FTS5/BM25, signed local BGE-small ONNX embeddings, MiniLM ONNX reranking, reciprocal-rank fusion, prompt-injection filtering, locatable citations, global cross-round content deduplication, a three-chunk-per-document cap, and extractive context reduction. If no pack is configured in a development run, explicitly labeled deterministic fallbacks are used instead.
- Deterministic adult/pediatric danger-sign routing that bypasses generative output. Medical or restriction-bearing text is simplified extractively only; eligible general text may use Apple Foundation Models after exact `tokenCount(for:)` and `contextSize` checks and must pass protected-span and grounding gates.
- Bounded PDFKit/Vision import: regular PDFs only, 25 MB, 100 pages, 200,000 extracted characters, 20 OCR pages, 30 seconds, 20 proposed restrictions, and cancellation checks.
- Exactly 100 synthetic/public, human-review-ready benchmark items with machine-enforced query, age, and 60/40 split contracts.
- Read-only evaluation/comparison tooling and a dependency-gated offline reranker training contract that rejects held-out or user data.

On macOS, the exact active dense and reranking components must be read from `/v1/models` and matched to the frozen evaluation configuration. The signed BGE/MiniLM pack has passed direct activation. A separate release-mode SQLCipher E2E smoke activated exact BGE + MiniLM, synchronized an exact-UUID adult profile, indexed one confirmed synthetic plan sentence, and returned a one-round `singleRetrieval` response with four locatable citations. That is wiring evidence, not human correctness or a quality metric. A preceding package also passed the full app-managed helper/network/SQLCipher/lifecycle smoke; after the Keychain startup fix, the current artifact was rechecked for signature and responsive launch but has not repeated that complete lifecycle sequence. `MockAIEngine` exists for tests/previews; the real macOS app injects a switching engine whose failure state disables live evidence Q&A and displays an offline-UI-only status rather than presenting mock evidence as live.

Separately, a real iPhone 17 Pro simulator setup downloaded and activated all pinned iOS model bytes. One supported adult-work query then returned a literal, source-linked CDC excerpt in 361 ms on 2026-08-26. That is one runtime smoke observation—not a physical-device benchmark, accuracy result, clinical validation, or calibrated-threshold claim. See [clinical limitations](docs/clinical_limitations.md) before describing either target.

## Research-informed UX, not user validation

The official hackathon rubric scores every submission on innovation and UI/UX/accessibility and adds concussion-specific UX, research, safety, and domain criteria; the 2026 project gallery was still unpublished on 2026-08-26, so PaceBack was not compared with unseen entries. Its short flows, reduced reading burden, clear source/error states, comfortable display options, and caregiver-aware navigation were informed by published concussion-app usability work: [Rhea's 2025 usability study](https://formative.jmir.org/2025/1/e67275), the [pediatric NeuroCare study](https://humanfactors.jmir.org/2019/2/e12135), and a [2025 adult user-and-clinician iterative study](https://humanfactors.jmir.org/2025/1/e75323). PaceBack has not run those studies' SUS, MAUQ, or MARS protocols and has not been validated with representative users.

## Architecture

The full macOS sidecar path is:

```text
SwiftUI + per-profile encrypted native state
        |
        | authenticated 127.0.0.1 /v1
        v
Python sidecar: safety -> age/profile filters -> hybrid retrieval
                -> cross-round bounds -> context budget -> citations -> fail-closed verification
        |
        v
profile-scoped SQLCipher/index storage in release; explicit plaintext dev mode only
```

The iOS companion is a separate native target and cannot launch the Python sidecar. Instead, a required first-use screen installs a pinned, signed BGE-small/MiniLM pack and Swift uses ONNX Runtime for local dense retrieval and reranking over seven bundled curated public-source summaries. Responses are extractive source excerpts with local locators, not generated medical prose. The target stores profiles in per-profile AES-GCM envelopes with Keychain keys and iOS Data Protection, applies role gates, and has no clinician-plan RAG or cross-platform profile/document synchronization.

Every evidence request carries the profile ID, exact age band, acting role, care context, and exactly the wire scope `allAges` plus the selected `AgeBand` raw value. There is no unknown-age runtime profile. Retrieved documents are untrusted evidence, never application instructions. The iterative route is bounded by three retrieval rounds, six generated subqueries, 100 unique candidates, and eight configured actions; the current implementation does not perform a separate correction step. Global final selection permits at most three chunks per document and eight chunks total.

Read [architecture](docs/architecture.md) for interfaces, flows, and current release blockers.

## Requirements

- Apple-silicon Mac, macOS 26.4+
- Xcode 26.4+ / Swift 6.2+
- iOS 18+ for the optional `PaceBackiOS` iPhone/iPad target
- Python 3.11–3.13 for the sidecar; the checked release lock is generated and verified with Python 3.13

No cloud key or account is used.

## Quick start

Create the engine environment:

```bash
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e 'engine[dev]'
```

Verify all layers:

```bash
make verify
```

Run the deterministic native demo:

```bash
cd macos
swift run PaceBack
```

The source-run executable has no bundled helper and therefore displays the offline UI state unless a debug-only `PACEBACK_ENGINE_EXECUTABLE` is supplied. Use only synthetic data; do not import real health documents into a development build.

Open or test the separate iOS companion:

```bash
open ios/PaceBackiOS.xcodeproj
xcodebuild \
  -project ios/PaceBackiOS.xcodeproj \
  -scheme PaceBackiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The iOS target does not run the desktop Python sidecar. On first use, its required setup screen explains and downloads a separate 157,716,998-byte ONNX pack; keep the app open during installation. The pack download is the target's only automatic network workflow and contains no profile or question payload. After verification and atomic activation, evidence questions stay on-device and return only source-linked extractive excerpts or an abstention.

For macOS, build the signed model pack once, then create an ad-hoc-signed arm64 app bundle with an embedded Python runtime, SQLCipher sidecar, local BGE/MiniLM artifacts, and generated app icon. The macOS model download is a build-time step; only the separate iOS target has the disclosed runtime model installer described above.

```bash
python3.13 -m venv .release-venv
.release-venv/bin/python -m pip install 'pip==25.3'
.release-venv/bin/python -m pip install \
  --require-hashes \
  -r engine/requirements-release.lock
.release-venv/bin/python -m pip install \
  --no-build-isolation \
  --no-deps \
  ./engine
.release-venv/bin/python -m pip check
.release-venv/bin/python engine/scripts/download_model_pack.py \
  --output build/model-pack \
  --signing-key ~/.config/paceback/model-pack-signing-key.pem \
  --generate-signing-key \
  --public-key-output build/model-pack-trust-key.b64
make package-macos ENGINE_PYTHON=.release-venv/bin/python
open build/PaceBack.app
```

The pack builder refuses to overwrite an existing key or pack; keep the private key outside the repository. `make package-macos` requires the pack and separate public trust key, embeds both public runtime resources plus their provenance, and uses the selected Python 3.11–3.13 environment as the PyInstaller input. The resulting helper carries that interpreter and does not depend on a compatible system Python. The default `SIGN_IDENTITY=-` is suitable only for local verification. Developer ID signing and optional notarization require explicit credentials as described in the [runbook](docs/runbook.md).

## Benchmark

Validate its exact contract without third-party packages:

```bash
python3 benchmark/build_benchmark.py --check
python3 benchmark/validate_benchmark.py
python3 -m unittest discover -s benchmark/tests -p 'test_*.py'
```

The 100 items contain 20 each of keyword/numeric, semantic, multi-hop, unanswerable/conflicting, and adversarial/isolation questions. Age totals are 25 child/caregiver, 25 teen, 25 adult, 15 older-adult/caregiver, and 10 age-ambiguous. Every query type has 12 dev and 8 process-held-out items; age splits are also locked by the validator.

Two matching, complete, unreviewed engineering diagnostics are archived. The primary `full_real_models_unreviewed_unmeasured_2026-08-25-v2.*` run activated the signed BGE + MiniLM pack; `full_fallback_unreviewed_unmeasured_2026-08-25-v3.*` used deterministic hashing/lexical fallbacks. Both ran all 100 items in plaintext development SQLite with networking disabled and record hashes for the engine source tree, evidence seed, product policy, and synthetic plans used at runtime.

The real-pack run recorded Recall@20 `0.9767` versus fallback `0.9667`, nDCG@20 `0.954886` versus `0.894214`, and mean latency `51.53 ms` versus `7.09 ms`. It had zero cross-age leaks, zero adversarial-canary executions, and 662/662 mechanically locatable citations. Both configurations matched only 40/100 response types and 3/63 boundary-routing cases. BGE and MiniLM changed together, so neither component receives independent credit. Human correctness, citation precision, and unsupported-claim rate remain unmeasured; promotion is forbidden.

These diagnostics are not the required four one-variable BM25/dense/hybrid/adaptive comparisons and are not clinical-effectiveness results. All 100 items still require non-author and qualified-domain review. See the [result note](benchmark/results/README.md) and [evaluation protocol](docs/evaluation_protocol.md).

## Safety and privacy

- No accounts, advertising, trackers, telemetry, remote model, web search, or intentional transmission of profile data.
- No legal names or exact birth dates in the profile contract.
- Under-13 use is caregiver-managed; teen administrative actions are guardian-gated.
- Health claims require allowed, locatable citations; verifier failure returns `I could not verify an answer.`
- Trends are descriptive and never interpreted as improvement, deterioration, or readiness.
- Runtime model weights never learn from user or child health data.
- The editable confirmed-preference ledger is currently storage/UI only; retrieval, context reduction, simplification, and answer generation do not consume it.

This design is not a COPPA, HIPAA, FDA, security, or medical-safety certification. Release mode fails closed unless a real SQLCipher driver and Keychain-provided database key are active; explicit development mode may use plaintext SQLite and reports that state through health/model metadata. Read [safety and privacy](docs/safety_privacy.md) and the [threat model](docs/threat_model.md).

## Repository map

| Path | Purpose |
|---|---|
| `macos/` | SwiftUI application, native services, encrypted profile storage, role handoff, engine synchronization, and tests |
| `ios/` | Native iPhone/iPad companion, explicit signed-model setup, encrypted profiles, deterministic danger signs, role gates, focus sessions, hybrid retrieval over seven bundled curated public-source summaries, source-linked excerpts, and tests; no Python sidecar, generation, training, or clinician-plan RAG |
| `engine/` | Local FastAPI retrieval/verification sidecar, signed ONNX model-pack tooling/provenance, and tests |
| `benchmark/` | Frozen dataset, synthetic fixtures, validators, evaluator, comparison, and reranker contract |
| `scripts/` + `packaging/` | Synthetic-PDF generation and signed macOS application packaging inputs |
| `site/` | Static submission landing page with local assets and structural/accessibility/no-network checks |
| `third_party/model_licenses/` | Canonical upstream MIT and Apache-2.0 texts for the BGE-small and MiniLM model artifacts |
| `third_party/software_licenses/` | Canonical upstream MIT text for ONNX Runtime 1.24.2 linked by the iOS target |
| `docs/` | Architecture, evidence rights, safety, threat model, evaluation, runbook, rubric, provenance, and submission script |

## Documentation

- [Product policy](docs/product_policy.md)
- [Architecture](docs/architecture.md)
- [iOS target and safety boundary](ios/README.md)
- [Safety and privacy](docs/safety_privacy.md)
- [Clinical limitations](docs/clinical_limitations.md)
- [Threat model](docs/threat_model.md)
- [Evidence manifest](docs/evidence_manifest.json) and [provenance](docs/provenance.md)
- [ONNX model-pack provenance](engine/MODEL_PROVENANCE.md)
- [Evaluation protocol](docs/evaluation_protocol.md)
- [Development/release runbook](docs/runbook.md)
- [Hackathon rubric mapping](docs/rubric_mapping.md)
- [Submission copy and four-minute demo](docs/hackathon_submission.md)

## Distribution status

The repository includes a `make package-macos` pipeline that requires and embeds the signed BGE/MiniLM pack, separate public trust key, canonical upstream model-license texts, ONNX Runtime software-license text, and provenance, builds an arm64 Swift release executable, creates a nested PyInstaller helper app with SQLCipher, ONNX Runtime, tokenizers, and evidence resources, embeds the generated icon and notices, signs nested code before the outer app, and can submit/staple when `SIGN_IDENTITY` and `NOTARY_PROFILE` are provided.

The current `build/PaceBack.app` occupies 306,068 KiB on disk (about 299 MiB), contains arm64 main/helper executables and the signed model pack, and is signed with an Apple Development identity under team `8RMK4MG9T2`; `codesign --verify --deep --strict` passes. A fresh packaged launch after the Keychain startup fix produced a layer-0 1180×780 window by the third observation (about 0.6 seconds). A main-thread sample was idle in AppKit's event loop while the Keychain lookup ran off the main actor. This startup smoke is narrower than a clean-Mac or full lifecycle test.

The aggregate `make verify` passes all 11 targets against current source: the benchmark contract and 26 benchmark tests; 55 engine tests and engine/benchmark Ruff; 64 macOS Swift tests and the macOS build; 34 iOS tests and the generic Simulator Release build; the reranker contract; and the site structural checker plus JavaScript syntax. The regenerated iOS project no longer emits the former duplicate-XcodeGen-group malformed-project warning. An earlier real-browser site pass at 375, 768, 1024, and 1440 CSS pixels found no horizontal overflow or console errors, only local requests, and a working skip link to `main`; after the final immutable-revision URL wording, the structural check still passes and mobile Lighthouse reports 100 accessibility, best-practices, SEO, and agentic scores. Those browser and automated checks are not an independent accessibility or usability assessment.

The Python 3.13 `packaging+ml` dependency closure, including the pinned build backend, is recorded with hashes in `engine/requirements-release.lock`; its CycloneDX 1.6 SBOM contains 42 components in `engine/sbom-release.cdx.json`. A fresh Python 3.13 environment passed hash-required installation, no-build-isolation/no-dependency installation of the local engine, `pip check`, and required runtime imports. The checked time-stamped pip-audit artifact found zero known vulnerabilities across 40 audited dependencies as of 2026-08-25; that result is time-bound, not a safety guarantee. See [provenance](docs/provenance.md) for exact hashes.

The current development download is `build/PaceBack-development-signed.zip` (151,185,197 bytes; SHA-256 `bd8732647df1cfed11a5565f778c6b4319a3db1cd8dc8251467695f0323785c5`). It is **not** a public release artifact: Apple Development signing is not Developer ID distribution signing, `spctl` rejects it, and the app has not been Developer ID signed, notarized, stapled, or clean-Mac Gatekeeper assessed. The main and helper binary hashes are recorded in [provenance](docs/provenance.md). Any later package-input change—application/engine code, embedded evidence or notices, model, dependency, entitlement, or asset—requires a new package and hashes.

That ZIP is the macOS development build; it does not contain or distribute the iOS target. Separately, the iOS project passed 34/34 tests across nine suites on an iPhone 17 Pro simulator, and a generic iOS Simulator Release build was independently repeated through XcodeBuildMCP. The Release binary contains neither the debug synthetic-profile launch argument nor its demo UUID; AppIcon, AccentColor, `evidence_seed`, signed manifest, public trust key, and ONNX Runtime MIT text are bundled. A real simulator setup downloaded, verified, and atomically activated the exact 157,716,998-byte pack, then produced the single 361 ms source-linked adult-work smoke described above. These are simulator/static engineering checks, not physical-device, clinical, calibrated-quality, App Store archive, signing, or distribution evidence.

Public macOS distribution still requires Developer ID signing, notarization, stapling, clean-Mac Gatekeeper validation, 8 GB and 16 GB profiling, dependency/model license review, four frozen benchmark runs, human review, and independent clinical, accessibility, privacy, and security assessment. Physical iPhone/iPad testing and an iOS archive/signing/distribution review also remain pending. `make verify` and the checked-in CI workflow cover 11 source checks, including iOS tests/Release simulator build and the landing-page structural checker. CI does not perform the iOS model download/real inference smoke, install the optional macOS ML runtime, activate the macOS signed model pack, package, exercise SQLCipher release startup, sign, notarize, test Foundation Models availability, or establish clinical validity.

Record the final local test counts and artifact hashes only after the last source change. These are software-test results, never clinical validation.

## Contributing

- Use only synthetic data and public link-only evidence in tests, issues, screenshots, and pull requests.
- Never commit a real clinician document, health prompt, profile database, copied clipboard report, key, token, model cache, build product, or notarization credential.
- Preserve strict schemas, exact benchmark counts, age/profile filters, hard resource limits, structured failures, and the no-unverified-claim invariant.
- A changed held-out item or source snapshot requires a new benchmark version and new frozen hash.
- Regenerate the package after every code, evidence-seed, dependency, entitlement, or icon change; do not submit an older `build/PaceBack.app`.

## License and attribution

Project-original source and documentation are licensed under Apache License 2.0. External evidence, Apple documentation, scholarly papers, model weights, dependencies, trademarks, and generated-asset provider terms remain separate. BGE-small and MiniLM retain their separate model licenses; ONNX Runtime 1.24.2 linked by iOS retains its MIT software license under `third_party/software_licenses/`. The generated app-icon source and prompt are recorded in [provenance](docs/provenance.md). See [LICENSE](LICENSE) and [NOTICE](NOTICE).
