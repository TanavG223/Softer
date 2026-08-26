# Development and release runbook

All commands start in the PaceBack repository root. They do not require or authorize real health data.

## Prerequisites

- Apple-silicon Mac with macOS 26.4 or newer and Xcode 26.4 or newer.
- iOS 18 or newer simulator/device support in Xcode for the optional native iPhone/iPad companion.
- Python 3.11–3.13 for the sidecar. Python 3.13 is the exact verified hash-locked packaging environment; Python 3.14 is outside the engine's declared compatibility range.
- No cloud API key. The prototype must run with networking disabled.

## One-time engine environment

```bash
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e 'engine[dev]'
```

Do not install the optional reranker training stack into the packaged runtime. Training is an offline development workflow with separate dependencies.

## Verification

```bash
make benchmark-validate
make benchmark-test
make benchmark-lint
make reranker-contract
make engine-test
make engine-lint
make macos-test
make macos-build
make ios-test
make ios-build
make site-test
```

`make verify` runs all 11 prerequisite targets above. The iOS targets default to the `PaceBackiOS` scheme, an `iPhone 17 Pro` simulator with the latest installed simulator OS for tests, a generic iOS Simulator destination for the Release build, and `ios/.derivedData-make`; override `IOS_PROJECT`, `IOS_SCHEME`, `IOS_DESTINATION`, or `IOS_DERIVED_DATA` when needed. Benchmark construction/validation, benchmark unit tests, and the site checker use the Python standard library; lint, engine tests, and the engine use `ENGINE_PYTHON`, which defaults to `.venv/bin/python`. Override `ENGINE_PYTHON=/absolute/path/to/python` when necessary. macOS Swift commands write build caches under `macos/.build`. `site-test` performs the project-authored structural/accessibility/no-network checks and runs `node --check` on the landing-page JavaScript; it is not a browser, assistive-technology, or penetration test.

The checked-in GitHub Actions workflow invokes all 11 source targets across a Linux Python job and a macOS Apple-build job, including `ios-test` and `ios-build`. It does **not** run the iOS first-use model download/activation or real ONNX inference, run `package-macos`, install or activate the macOS signed ML model pack, exercise SQLCipher release startup, test a generated macOS `.app`, use distribution credentials, notarize, staple, run clean-Mac Gatekeeper checks, measure Foundation Models availability, or perform clinical/accessibility/security review.

The Python CI job installs `engine[dev]`, not `engine[ml]`. It therefore validates fallback behavior and skips dependency-gated real-model activation tests; the signed BGE/MiniLM pack must be verified separately on the final Apple-silicon package.

## Run the deterministic native demo

```bash
cd macos
swift run PaceBack
```

The source-run executable attempts to start a bundled helper or, in a debug build only, the absolute path in `PACEBACK_ENGINE_EXECUTABLE`. It validates the JSON handshake and storage health before enabling evidence Q&A. Without a valid helper it remains in a visibly labeled offline-UI-only state and Q&A is disabled. `MockAIEngine` is available to tests/previews but is not the app's automatic runtime fallback.

## Build, test, and analyze the iOS companion

The checked-in project uses scheme `PaceBackiOS`, bundle identifier `org.paceback.research.ios`, and iOS 18 minimum deployment for iPhone and iPad. Open it directly or regenerate it from `ios/project.yml` with XcodeGen:

```bash
open ios/PaceBackiOS.xcodeproj
```

Run its simulator checks separately from `make verify`:

```bash
xcodebuild \
  -project ios/PaceBackiOS.xcodeproj \
  -scheme PaceBackiOS \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project ios/PaceBackiOS.xcodeproj \
  -scheme PaceBackiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild \
  -project ios/PaceBackiOS.xcodeproj \
  -scheme PaceBackiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

Current separate evidence is 34/34 passing tests across nine suites on an iPhone 17 Pro simulator and a passing generic iOS Simulator Release build independently repeated through XcodeBuildMCP. Inspection of the Release binary found neither the debug synthetic-profile launch argument nor its demo UUID. AppIcon, AccentColor, `evidence_seed`, signed manifest, and public trust key are bundled. These checks do not establish physical-device behavior, App Store archive/signing readiness, accessibility review, or clinical validity.

The iOS target cannot launch the macOS Python sidecar. Its required first-use setup instead downloads exactly 157,716,998 bytes for frozen BGE-small dense retrieval and a quantized MiniLM reranker, with tokenizers, then runs them through the official ONNX Runtime Swift package pinned at 1.24.2. Before installation, confirm the UI reports the 357,919,352-byte working-space requirement and asks the user to choose Wi-Fi only or Wi-Fi/cellular. Keep the app open; no background download is claimed.

For a clean synthetic runtime check:

1. Start from no installed iOS model pack and a synthetic profile.
2. Choose the network policy explicitly. Inspect the ephemeral HTTPS requests: they may fetch only the four pinned Hugging Face artifacts through approved redirect hosts and must contain no profile, alias, age band, symptom, question, or care-plan value.
3. Cancel once and verify that no partial pack activates; retry/resume and wait for all 157,716,998 bytes.
4. Verify that the bundled Ed25519-signed manifest, separate public key, immutable revisions, exact artifact sizes, and SHA-256 values pass before atomic activation. The active pins are dense `828e1496d7fabb79cfa4dcd84fa38625c0d3d21da474a00f08db0f559940cf35`, tokenizer `d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66` (used twice), reranker `3573b6b9593cb2f75987a31815d409ca3dd8808629118fd20451bb1a5d90cec7`, and manifest `9d432e366d410fe049313341e58b9d39e30f13b13f5310b2fe5fe9d0ad83c61d`.
5. With networking disabled, ask a supported age-appropriate question and inspect the extractive excerpt, source locator, and local inference time. Then try unsupported and professional-decision questions and confirm abstention.
6. Delete and reinstall the model pack; confirm that encrypted profiles are not deleted.

A real iPhone 17 Pro simulator completed the full download/verification/activation flow and returned a source-linked CDC excerpt for one supported adult-work query in 361 ms on 2026-08-26. This is one smoke observation, not a physical-device benchmark, accuracy metric, threshold calibration, or clinical result. The iOS corpus currently contains seven bundled curated public-source summaries; it has no recorded independent/human corpus review. It has no generation, training, user-data learning/upload, clinician-document ingestion, clinician-plan RAG, or multi-round adaptive loop. Its support thresholds remain provisional and require held-out review.

## Run the sidecar manually

Use a disposable directory and a random token of at least 32 UTF-8 bytes. Avoid putting tokens in shell history for real packaging; this command is local development only.

```bash
PACEBACK_AUTH_TOKEN='development-only-token-at-least-32-bytes' \
  .venv/bin/paceback-engine --development --port 0 --data-dir /tmp/paceback-engine-dev
```

The first stdout line is readiness JSON containing protocol `v1`, process ID, and the chosen port; it never includes either secret. The manual command uses explicit unencrypted development mode because no database key is supplied. Stop the process before deleting the disposable directory. Never point a development instance at a real user's application-support directory.

## Validate the frozen benchmark

```bash
python3 benchmark/build_benchmark.py --check
python3 benchmark/validate_benchmark.py
python3 benchmark/train_reranker.py \
  --judgments benchmark/reranker_dev_judgments.example.jsonl \
  --validate-only
```

The checked-in judgment file is a synthetic format example, not a model-quality claim.

The benchmark's 100 `human_review.status` values remain pending until the review procedure in `docs/evaluation_protocol.md` is completed. Validation of its shape and hashes is not a substitute for review.

The primary archived diagnostic is `benchmark/results/full_real_models_unreviewed_unmeasured_2026-08-25-v2.*`; the matching fallback is `full_fallback_unreviewed_unmeasured_2026-08-25-v3.*`. The real-pack run recorded Recall@20 0.9767 versus 0.9667, nDCG@20 0.954886 versus 0.894214, and mean latency 51.53 ms versus 7.09 ms. Both recorded zero age leaks and canary executions, but only 40/100 response-type and 3/63 boundary-routing matches. Both are plaintext-development, unreviewed diagnostics; both metadata files hash all runtime inputs; BGE and MiniLM changed together; human correctness, citation precision, and unsupported-claim rate are unmeasured; promotion is forbidden. Older artifacts are retained only as provenance and are superseded for the reasons in `benchmark/results/README.md`.

After creating `.release-venv` and the signed pack in the packaging section below, create a new non-overwriting real-model diagnostic artifact:

```bash
.release-venv/bin/python benchmark/run_engine.py \
  --mode full \
  --model-pack-dir build/model-pack \
  --model-trust-key-file build/model-pack-trust-key.b64 \
  --output runs/full-real-model-reproduction.jsonl
.release-venv/bin/python benchmark/evaluate.py \
  runs/full-real-model-reproduction.jsonl \
  --output runs/full-real-model-reproduction.summary.json
```

Omit both model-pack arguments for the deterministic fallback. The runner never downloads weights and never stores the trust-key value in run metadata. BGE and MiniLM still change together in this diagnostic path; use the one-variable matrix below for promotion evidence.

## Evaluate a run

Produce one JSON object per literal LF in benchmark order using the schema in `docs/evaluation_protocol.md`, then run:

```bash
python3 benchmark/evaluate.py runs/hybrid.jsonl --output runs/hybrid.summary.json
```

The evaluator refuses incomplete runs unless `--allow-partial` is explicit. Partial output is diagnostic only and cannot be used for a performance claim.

After completing all four frozen BM25, dense, hybrid, and adaptive runs:

```bash
python3 benchmark/compare_runs.py \
  --bm25 runs/bm25.summary.json \
  --dense runs/dense.summary.json \
  --hybrid runs/hybrid.summary.json \
  --adaptive runs/adaptive.summary.json \
  --output runs/comparison.json
```

Missing human or citation review makes required gates unmeasured and the comparison fails closed.

## Offline reranker training

1. Copy the example judgment schema to a new append-only file.
2. Use only public or synthetic passages associated with `dev` benchmark item IDs.
3. Record an actual human review on every row. No patient, user, or held-out data is permitted.
4. Install a separately pinned `sentence-transformers`/PyTorch environment with its model cache populated under an approved development process.
5. Run:

```bash
python3 benchmark/train_reranker.py \
  --judgments /absolute/path/to/reviewed-dev-judgments.jsonl \
  --output-root /absolute/path/to/new-artifacts
```

The script groups by question, emits a hash/version manifest, refuses overwrite, and exits `5` without a `PROMOTED.json` marker when validation NDCG fails to improve by more than the configured threshold. It never evaluates held-out items.

## Clean-data test procedure

- Generate the importable synthetic PDFs in a disposable ReportLab environment:

  ```bash
  uv run --with reportlab==4.4.9 python scripts/generate_synthetic_plan_pdfs.py
  ```

  Alternatively install `scripts/requirements-pdf.txt`. The generated files go to `output/pdf/`; record their hashes and never substitute real documents.
- Use only the four synthetic demo profiles and `benchmark/synthetic_clinician_plans.json`.
- Confirm the sidecar starts with no network connectivity.
- Exercise emergency, abstention, wrong-age, wrong-profile, cancellation, and deletion flows.
- Inspect the clipboard report for only selected fields and the prototype disclaimer. Paste it into a disposable local text editor to verify the content, then clear the clipboard manually.
- Delete the synthetic profiles and verify keys, envelopes, sidecar documents/indexes, runs, feedback, WAL, and SHM behavior according to the release checklist. Confirm the other profiles remain intact.

## Build the local app bundle

Create the verified Python 3.13 release environment from the hash-locked dependency closure, then install the local PaceBack engine without resolving or downloading another dependency:

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
```

This clean-install sequence has been executed successfully. The lock SHA-256 is `c2f91df65b26c394e17f162a2be2341e8bd4d2af4f2aca001a9dc9eb984d6b9d`; the 42-component CycloneDX 1.6 SBOM SHA-256 is `f2878e6d5aff312e3f6c3ef7595f5cc5de65df66b4fb58f04a811d5289edaebe`. The time-stamped `engine/pip-audit-2026-08-25.json` records zero known vulnerabilities across 40 audited dependencies as of that date; rerun the audit at release because this evidence expires as advisory databases change.

Create the signed, pinned model pack once. This is an explicit networked build-time download; activation and inference remain offline. The command refuses to overwrite an existing pack or private key.

```bash
.release-venv/bin/python engine/scripts/download_model_pack.py \
  --output build/model-pack \
  --signing-key ~/.config/paceback/model-pack-signing-key.pem \
  --generate-signing-key \
  --public-key-output build/model-pack-trust-key.b64
```

Keep the private key outside the repository and bundle. Review `engine/MODEL_PROVENANCE.md` and the upstream MIT and Apache-2.0 terms before distribution. Point the package target at the release environment:

```bash
make package-macos ENGINE_PYTHON=.release-venv/bin/python
```

The package target requires `build/model-pack/manifest.json` and `build/model-pack-trust-key.b64` by default. It builds the arm64 Swift release executable; freezes the selected environment as a PyInstaller `onedir` helper app; includes SQLCipher, ONNX Runtime, tokenizers, the public evidence seed, the signed model pack, its separate public trust key, model provenance, NOTICE, the canonical upstream MIT/Apache-2.0 model-license texts under `third_party/model_licenses/`, and the ONNX Runtime MIT text under `third_party/software_licenses/`; embeds `packaging/PaceBack.icns`; nests the helper at the fixed runtime path; signs nested code first; signs the outer app; and runs strict code-signature verification. PyInstaller bundles that environment's Python runtime, so a compatible system Python is not required on a destination Mac. If `output/pdf/` exists, the script also copies those synthetic demo files to `build/PaceBack-Demo-Plans/`, outside the app bundle.

The default is local ad-hoc signing (`SIGN_IDENTITY=-`). A generated `build/PaceBack.app` is disposable output and becomes stale whenever source, evidence, model pack, dependencies, entitlements, or assets change.

Current post-edit development evidence: the app occupies 306,068 KiB on disk (about 299 MiB), contains arm64 main/helper executables and the signed model pack, and both nested code and the outer app are Apple Development-signed under team `8RMK4MG9T2`; `codesign --verify --deep --strict` passes. A fresh packaged launch after the Keychain-main-actor fix and explicit launch activation created a layer-0 1180×780 window by the third observation (about 0.6 seconds), with the sampled main thread idle in AppKit's event loop while Keychain access ran off-main. This is startup evidence, not a repeat of the earlier package's complete helper/network/SQLCipher/lifecycle smoke. The earlier matching local source-verification command was:

```bash
make verify \
  PYTHON=../research_agent/.venv/bin/python \
  ENGINE_PYTHON=../research_agent/.venv/bin/python
```

The aggregate `make verify` now passes all 11 targets against current source: the benchmark contract and 26 benchmark tests; 55 engine tests and engine/benchmark Ruff checks; 64 macOS Swift tests and the macOS build; 34 iOS tests and the generic Simulator Release build; the reranker contract; and the site structural checker plus JavaScript syntax check. The regenerated iOS project no longer emits the former duplicate-XcodeGen-group malformed-project warning. Use the repository-local environments shown earlier for a portable reproduction. The current 151,185,197-byte `build/PaceBack-development-signed.zip` has SHA-256 `bd8732647df1cfed11a5565f778c6b4319a3db1cd8dc8251467695f0323785c5`; the 4,854,032-byte main executable is `4ee0c27775ce5f49d4bb2a5559f0c7bba94e8bb85ee1a8e9b33925d4d9d8b2b0`, the 9,282,992-byte helper is `55672e898527a364608bf1bbe93be89cc89249ec535c25732aad15b1ee0b9125`, and the embedded pack manifest is `9d432e366d410fe049313341e58b9d39e30f13b13f5310b2fe5fe9d0ad83c61d`. Embedded NOTICE, model provenance, clinical limitations, model licenses, and ONNX Runtime license byte-match the checked-in sources. `spctl` rejects this Apple Development-signed, unnotarized build; it is not a Gatekeeper-ready release.

For a release-candidate build, use a valid Developer ID Application identity. `NOTARY_PROFILE` must name credentials already stored by `notarytool`; never place credentials in the repository or command history.

```bash
SIGN_IDENTITY='Developer ID Application: Example Team (TEAMID)' \
NOTARY_PROFILE='paceback-notary' \
make package-macos ENGINE_PYTHON=.release-venv/bin/python
```

Archive the package command, Python/Swift/PyInstaller versions, dependency inventory, nested and outer `codesign` output, notarization log, stapler output, `spctl` result, app/helper SHA-256 hashes, live model manifest with both expected ONNX components active, model-pack/provenance hashes, and authenticated health response. A successful ad-hoc or Apple Development build and a direct model smoke test do not satisfy Developer ID, notarization, stapling, or Gatekeeper release gates.

## Release checklist

1. Complete non-author and qualified-domain review of all 100 benchmark items. Freeze evidence URLs, review dates, project-authored summaries, model hashes, benchmark hash, and dependency lock files.
2. Freeze and archive all four BM25, dense, hybrid, and adaptive runs; run the comparison; disclose every failed or unmeasured gate. Do not claim model improvement from unit tests or adapter activation.
3. Resolve every remaining blocker in `docs/clinical_limitations.md`, including independent clinical, accessibility, privacy, and security review.
4. Run `make verify` and the final package on both 8 GB and 16 GB Apple-silicon Macs; archive command output with hardware/OS/toolchain versions.
5. Perform keyboard, VoiceOver, increased-contrast, reduced-motion, reduced-transparency, and large-text checks on every core flow with representative users.
6. Rebuild the PyInstaller helper and app from the frozen source/dependencies; verify no development docs, external network path, or code-execution tool is present.
7. Tamper with a disposable copy of each model artifact and verify startup refusal; match the live model manifest to `engine/MODEL_PROVENANCE.md`; verify evidence resources are protected by the signed helper/app boundary; then sign nested binaries and the app with reviewed hardened-runtime entitlements.
8. Notarize, staple, run `codesign --verify --deep --strict --verbose=2`, and run `spctl --assess --type execute --verbose=4` on a clean Mac.
9. Test first launch, restart, helper crash, cancellation, Keychain access/migration, corrupted PDF, deletion, low disk, and uninstall behavior on a clean account.
10. Run the four-minute demo entirely with synthetic data and disclose that measured benchmark and usability results are prototype-specific.
11. Publish the exact source commit, release artifact hashes, NOTICE, evidence manifest, test results, review coverage, and known limitations.

Signing and notarization require credentials and external Apple services; they are intentionally outside ordinary CI and this implementation session.

The iOS companion additionally requires held-out threshold/citation review, physical iPhone and iPad performance and storage testing, mobile accessibility review, and a separately reviewed archive/signing/distribution process before any device or App Store release. None of those iOS release gates is satisfied by the simulator Release build, 34 tests, or single 361 ms retrieval smoke.
