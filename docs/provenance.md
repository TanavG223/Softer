# Provenance and attribution

## Project origin

PaceBack was created for Hack for Humanity Summer 2026 after the stated project-start date. The repository should record its public source commit and release artifact hashes at submission time. This file records design and data provenance; it does not establish ownership of material not created by PaceBack contributors.

## Internal design precedent

PaceBack reused architecture lessons from the user's local `research_agent` project under `/Users/tanavgosala/Downloads/BIOMED/research_agent`, inspected on 2026-08-25. That project had no Git commit metadata or license file available from the containing workspace, so PaceBack treats it as internal design provenance and does not redistribute it as a third-party package. Its own regression suite was run separately and reported **84 passing tests**, plus Ruff and dependency checks; that count establishes only the condition of the inspected precedent and is not part of PaceBack's test count or benchmark evidence.

| Internal source at inspection | SHA-256 | Concept carried forward |
|---|---|---|
| `src/research_agent/verifier.py` | `26fd0619f4860d476b3a5beb3f6b2ea2dee98c0e19e01c159beffe4481f5fa3a` | Fail-closed claim/source verification |
| `src/research_agent/benchmarking.py` | `64a3b4cb674e76cae1eea3296b3a8a31a335049fd8057c24bd257eb7de2cc33f` | Exact benchmark contracts, immutable hashes, structured metrics |
| `src/research_agent/schemas.py` | `2b25da2c0c2004c8664aa36a5b0d2a3997789de810b99c9e45010a1d14d9e7f6` | Strict typed JSON boundaries |

The previous experiment's numerical results do not transfer to PaceBack. They concern a different model, task, corpus, and toolchain and must not appear as PaceBack performance.

Before public distribution, the repository owner must confirm authority to license any directly reused internal code. If that authority cannot be documented, replace it with a clean implementation based only on public interface requirements.

## Evidence provenance

`docs/evidence_manifest.json` is the source of truth for publisher, URL, age scope, review date, license status, storage mode, and redistribution notes. External texts, article PDFs, images, logos, and screenshots are not committed by the benchmark/docs layer.

CDC says most CDC/ATSDR information is U.S. public domain but identifies important contractor, grantee, third-party, state/local, image, international, attribution, non-endorsement, no-substantive-change, update, and logo exceptions. PaceBack therefore links to CDC and stores reviewed project-authored summaries rather than assuming every page element may be copied. CDC and HHS do not endorse PaceBack.

The Amsterdam consensus and ACL papers remain link-only scholarly references. Apple documentation remains link-only. FTC and FDA guidance is cited as current guidance, not legal or regulatory approval. Re-check every external record immediately before release.

## Synthetic data provenance

- `benchmark/benchmark.json`: deterministic prompts written for this project; no user or patient data.
- `benchmark/synthetic_clinician_plans.json`: invented records with no names, dates, clinicians, signatures, or real restrictions.
- `scripts/generate_synthetic_plan_pdfs.py`: renders those invented records into four clearly watermarked, two-page demo PDFs using the separately pinned `reportlab==4.4.9` dependency in `scripts/requirements-pdf.txt`; generated files are disposable demo artifacts under `output/pdf/`.
- `benchmark/reranker_dev_judgments.example.jsonl`: invented reviewed-format examples from public/project-policy paraphrases; not a trained dataset or result.

Synthetic material is intentionally labeled in content and UI. Do not remove those labels in screenshots, demos, or clipboard reports.

## Model and dependency provenance

The final `/v1/models` response and package inventory are the source of truth for active and inactive runtime components. Merely installing or committing a model adapter does not prove that it produced a result or improved quality.

The current signed pack contains frozen, unmodified upstream ONNX artifacts for `BAAI/bge-small-en-v1.5` at revision `5c38ec7c405ec4b44b94cc5a9bb96e735b38267a` (declared MIT) and `cross-encoder/ms-marco-MiniLM-L-6-v2` at revision `233902d25c440f23af6f7d6e94d2946bac0bee0a` (declared Apache-2.0). [The model-provenance inventory](../engine/MODEL_PROVENANCE.md) records every distributed model/tokenizer SHA-256 and byte length, source URL, immutable revision, pack-manifest hash, signature hash, and public trust-key hash. Canonical upstream license texts are checked in as `third_party/model_licenses/BAAI-bge-small-en-v1.5-MIT.txt` (SHA-256 `587a673933425dbc36ec61268d3b954051b2d3ef3c9b322ede357976055ffdd5`) and `third_party/model_licenses/cross-encoder-ms-marco-MiniLM-L-6-v2-APACHE-2.0.txt` (SHA-256 `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`) and are embedded under `Contents/Resources/ThirdPartyModelLicenses/`. The macOS pack builder downloads 157,716,998 pinned artifact bytes at build time; the macOS app has no runtime downloader.

The iOS target separately pins the official [`onnxruntime-swift-package-manager`](https://github.com/microsoft/onnxruntime-swift-package-manager) package at exact version `1.24.2` in both `ios/project.yml` and SwiftPM's resolved package file. ONNX Runtime is declared MIT at the pinned upstream [`v1.24.2/LICENSE`](https://github.com/microsoft/onnxruntime/blob/v1.24.2/LICENSE). Its canonical text is checked in separately from the model licenses as `third_party/software_licenses/onnxruntime-1.24.2-MIT.txt` (1,073 bytes; SHA-256 `2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c`), copied into the iOS app resources, and embedded by the macOS package script under `Contents/Resources/ThirdPartySoftwareLicenses/`. That software license does not change or replace the BGE-small MIT declaration or MiniLM Apache-2.0 declaration.

The required iOS setup downloads the same four pinned model/tokenizer artifacts at runtime through ephemeral, allowlisted HTTPS requests, validates the bundled signed manifest and separate public key plus exact sizes and SHA-256 values, and atomically activates the pack. The production total is 157,716,998 bytes and the conservative working-space threshold is 357,919,352 bytes. On 2026-08-26, an iPhone 17 Pro simulator downloaded and activated all bytes; active dense (`828e1496…`), tokenizer (`d241a60d…`, used twice), reranker (`3573b6b9…`), and manifest (`9d432e36…`) hashes matched the pins. A supported adult-work query returned one source-linked CDC excerpt in 361 ms. This is installer/runtime wiring provenance only—not a physical-device benchmark, accuracy result, threshold calibration, or clinical evidence. The iOS corpus has seven bundled curated public-source summaries with no recorded independent/human corpus review and no clinician-document ingestion; the models are frozen and perform retrieval/reranking only, with no generation, training, or user-data upload.

The pack's Ed25519 signature, separate public trust key, hashes, sizes, IDs, revisions, dimensions, and ONNX I/O probes have passed direct local activation. `engine/real-model-smoke-2026-08-25.json` (SHA-256 `7d322a34fb29e6311e59f7e5e977570a06df7e0efb6c7a6f555512c22741181b`) records the release-mode SQLCipher exact-profile/index/run smoke and explicitly labels it non-quality and non-clinical. A preceding package completed an app-managed model/helper lifecycle smoke; the current final-hash artifact has only the narrower signature and responsive-startup check described below.

The complete real-pack diagnostic is separately archived as `benchmark/results/full_real_models_unreviewed_unmeasured_2026-08-25-v2.jsonl` (SHA-256 `051852d4dbbd10c4de1aad0859245ebd7f5658543982c86d94cc8be83f597462`), metadata (SHA-256 `509dc5703b30fd75331d12499fdde3290f1877cb7197f0332364c7f39d68f0ea`), and summary (SHA-256 `ee8ede4ce2fd7f0d2ae33e1dca1bea0f8c02064ef616c6fec523b1e96929774d`). The matching fallback is archived as `benchmark/results/full_fallback_unreviewed_unmeasured_2026-08-25-v3.jsonl` (SHA-256 `d8fef248118ded1d8e09528b57d05a7e3c0615b80581767e20809fe1ccf00ed3`), metadata (SHA-256 `2ad097fd6b6d3e18d889802dd952addb6938ea6149f79e1cd67596c226118580`), and summary (SHA-256 `309c3a3a8a42f1677b3cc127e0ec6e129dc19c0b20f0562b843bbb358c18a594`). Both metadata files identify the same runner and hash the engine source tree, evidence seed, product policy, and synthetic-plan inputs. They are unreviewed, BGE and MiniLM changed together, and promotion is forbidden.

## Current development package provenance

The post-edit development artifact produced on 2026-08-26 is `build/PaceBack-development-signed.zip`, 151,185,197 bytes, SHA-256 `bd8732647df1cfed11a5565f778c6b4319a3db1cd8dc8251467695f0323785c5`. Its expanded `build/PaceBack.app` occupies 306,068 KiB on disk (about 299 MiB) and contains:

- arm64 main executable `Contents/MacOS/PaceBack`, 4,854,032 bytes, SHA-256 `4ee0c27775ce5f49d4bb2a5559f0c7bba94e8bb85ee1a8e9b33925d4d9d8b2b0`;
- arm64 helper executable `Contents/Helpers/PaceBackEngine.app/Contents/MacOS/paceback-engine`, 9,282,992 bytes, SHA-256 `55672e898527a364608bf1bbe93be89cc89249ec535c25732aad15b1ee0b9125`;
- embedded model-pack manifest SHA-256 `9d432e366d410fe049313341e58b9d39e30f13b13f5310b2fe5fe9d0ad83c61d`.

Both nested code and the outer app are Apple Development-signed under team `8RMK4MG9T2`, and `codesign --verify --deep --strict` passes. The embedded NOTICE, model-provenance inventory, clinical-limitations file, two model-license texts, and ONNX Runtime license text byte-match their current checked-in sources. A fresh packaged launch after moving Keychain access off the main actor and adding explicit launch activation created a layer-0 1180×780 window by the third observation (about 0.6 seconds); a main-thread sample was idle in AppKit's event loop while Keychain work ran off-main. This final startup check did not repeat every network, database-encryption, or helper-lifecycle assertion from an earlier package smoke, so those checks remain release-artifact work. The aggregate `make verify` passes all 11 current-source targets: the benchmark contract and 26 benchmark tests; 55 engine tests plus engine/benchmark Ruff; 64 macOS Swift tests plus the macOS build; 34 iOS tests plus the generic Simulator Release build; the reranker contract; and the site structural checker plus JavaScript syntax. The regenerated iOS project no longer emits the former duplicate-XcodeGen-group malformed-project warning.

This artifact is not Developer ID signed, notarized, stapled, clean-Mac Gatekeeper assessed, clinically validated, or approved for public distribution. `spctl --assess --type execute` rejects it, as expected for this Apple Development-signed, unnotarized artifact. Apple Development signing does not satisfy the release gates. Any subsequent package-input change—application/engine code, embedded evidence or notices, model, dependency, entitlement, or asset—invalidates these package hashes.

Every distributed third-party model artifact requires:

- exact model ID, upstream revision, download URL, license, file list, and SHA-256;
- conversion and quantization commands with tool versions;
- approved-use and redistribution review;
- signed runtime manifest and integrity verification.

Any PaceBack-trained or fine-tuned artifact additionally requires training dataset/split hashes, reviewed data provenance, baseline/candidate validation metrics, and an explicit promotion decision. PaceBack has not fine-tuned either bundled model and never updates their weights from user data.

Names of referenced models or vendors do not imply endorsement.

The macOS package script supports Python 3.11–3.13 and freezes the selected packaging environment into the nested PyInstaller helper. `engine/requirements-release.lock` is the pip-compile-generated, hash-locked Python 3.13 `packaging+ml` dependency closure, including `hatchling==1.32.0` as the pinned build backend (SHA-256 `c2f91df65b26c394e17f162a2be2341e8bd4d2af4f2aca001a9dc9eb984d6b9d`). `engine/sbom-release.cdx.json` is the corresponding CycloneDX 1.6 inventory with 42 components (SHA-256 `f2878e6d5aff312e3f6c3ef7595f5cc5de65df66b4fb58f04a811d5289edaebe`). A clean temporary Python 3.13 environment passed hash-required dependency installation, `--no-build-isolation --no-deps` installation of the local engine, `pip check`, and imports of FastAPI, cryptography, NumPy, ONNX Runtime, SQLCipher, tokenizers, and Uvicorn.

`engine/pip-audit-2026-08-25.json` (SHA-256 `fdbe5b145fce84184a5bea8b399c1e94b614e4b7c0eeaf2ce570170316ec40d1`) records that pip-audit 2.10.0 found zero known vulnerabilities across 40 audited locked dependencies on 2026-08-25. Vulnerability databases change; this is time-stamped evidence, not a guarantee that the dependency set is vulnerability-free.

Those files improve dependency provenance but do not prove the contents of a later app bundle. The final release record must identify the actual bundled interpreter, PyInstaller version, lock/SBOM hashes, helper/native-library inventory, and artifact hashes.

## Generated app-icon provenance

The image-generation output is `/Users/tanavgosala/.codex/generated_images/01a03b5e-6e81-7090-bb56-d7cb9eff5ea3/exec-eec3158f-68f6-497d-af9d-42345ff59665.png` (SHA-256 `7d034c772eb6f31da93d61db363afa5597cc15c4d5ccd6b8a6f342499598786f`). The checked-in 1024 × 1024 derivative is `packaging/PaceBack-AppIcon-1024.png` (SHA-256 `a3efaba09f1d53a493d41d736a4888baa4dceb4f943b9cac1782f09e1bbf42b2`). It was generated with OpenAI's image-generation tool during the 2026-08-25 implementation session and converted locally into `packaging/PaceBack.icns` (SHA-256 `3ef46602205fc7c1d2430bcf17ec4baf75f43cf243afa2d9ffbf2e220fa479ba`). The absolute generation path is workstation provenance, not a distributable dependency. Record new hashes here if any asset is regenerated.

Exact generation prompt:

```text
Use case: logo-brand
Asset type: production macOS application icon for PaceBack, an all-ages local-first concussion-recovery companion
Primary request: Create one original, calm symbol that combines a gently paced curved pathway with a subtle protective arch and a simple rhythmic wave, communicating “pause, pace, and safely return” without making a medical claim.
Style/medium: premium macOS 26 app-icon artwork; crisp vector-friendly silhouette with restrained dimensional layering and soft material depth, polished but not glossy or childish
Composition/framing: centered inside a rounded-square icon tile, generous optical padding, symmetric visual weight, unmistakable at 16px and elegant at 1024px
Color palette: calm deep blue and teal matching #336399 and #217075, with one restrained warm amber #BF7338 accent; excellent light/dark contrast
Lighting/mood: reassuring, private, steady, humane
Constraints: no text, no letters, no numbers, no faces, no brain anatomy, no skull, no red medical cross, no heartbeat cliché, no hospital imagery, no watermark, no trademarked symbols, no mockup or device frame; single square icon only
```

This records tool and prompt provenance; it is not a representation that provider terms, trademark clearance, or other rights review is complete. Review the final asset and applicable provider terms before public distribution.

## Submission attribution checklist

- Publish the repository license and NOTICE.
- Record every contributor and teammate in the Devpost submission.
- Attribute the internal research-agent design precedent.
- Link—not copy—external evidence unless a rights review explicitly approves a specific artifact.
- Credit CDC where a reviewed CDC-derived summary is displayed and include a clear non-endorsement statement.
- Do not use CDC, HHS, FDA, FTC, BMJ, Apple, ACL, Concussion Alliance, Synapse, Devpost, or sponsor logos without permission.
- Identify all pre-existing frameworks, packages, models, templates, and generated assets.
- Record the final source commit, build time, dependency lock hashes, model hashes, benchmark hash, and signed artifact hashes.
