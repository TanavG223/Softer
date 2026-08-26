# PaceBack threat model

Version 1.0, reviewed 2026-08-25. This is a design review, not a penetration-test or compliance report.

## Assets

- Profile aliases, age bands, roles, caregiver approvals, and preferences.
- Clinician documents, OCR text, confirmed restrictions, symptom/check-in history, prompts, feedback, and clipboard reports.
- Profile encryption keys and the per-launch loopback bearer token.
- Public-evidence and private-evidence indexes, citations, run logs, and model artifacts.
- Safety policy, evidence manifest, code-signing identity, notarization credentials, release hashes, and benchmark held-out labels.

## Adversaries and non-adversarial failures

- A malicious or compromised document containing prompt injection, executable text, oversized content, malformed PDF structures, deceptive metadata, or false clinical claims.
- Another local process running as the same or a different macOS user.
- A caregiver, teen, or ordinary user attempting a role or profile boundary they do not possess.
- Accidental profile selection, clipboard oversharing, stale evidence, corrupted indexes, incomplete deletion, model mismatch, low disk, cancellation race, synchronization failure, or helper crash.
- A compromised dependency, model file, package, CI action, signing credential, or release download.
- A model or parser that hallucinates, follows retrieved instructions, drops negation, confuses age scopes, or emits malformed structured output.

Remote account takeover and server-side cloud compromise are outside the current design because PaceBack has no account or remote service. They become in scope immediately if networking is added.

## Trust boundaries

1. Human input → SwiftUI.
2. Imported files → PDFKit/Vision and the confirmation workflow.
3. Swift process → authenticated loopback sidecar.
4. Sidecar → SQLite/index/model resources.
5. Retrieved evidence → answer/verifier pipeline.
6. Profile → selected-field report text → macOS clipboard.
7. Development workstation/CI → signed release artifact.
8. Dev benchmark labels → training process; held-out labels are a protected evaluation boundary.

## Threats and required controls

| Threat | Prevent/detect controls | Required test |
|---|---|---|
| Cross-profile read/write | Exact-ID native sync, profile ID in every private query, database predicates, foreign keys, separate native keys/namespaces, server-side role checks | Attempt profile/document/run/feedback CRUD with another profile ID; require 404/403 and zero content leakage |
| Wrong-age evidence | Exactly `allAges` plus one explicit `AgeBand`, profile-age equality, pre-retrieval sparse/dense filters | Run all five age bands plus the benchmark's age-ambiguous safety cases; require zero wrong-age chunks |
| Unconfirmed plan enters RAG | Native draft/confirmed separation; sidecar reconciliation serializes only checked rows | Import a mixed-confirmation synthetic plan and require only confirmed page-cited rows in the sidecar document/index |
| Retrieved prompt injection | Treat documents as data, injection filtering, no shell/Python/web tools, structured verifier, adversarial canaries | All 20 canary items produce zero canary tokens and execute nothing |
| Danger-sign miss or overwrite | Deterministic gate before model, static reviewed copy, generation bypass | Adult and pediatric variants route to emergency card with zero retrieval rounds |
| Unsupported medical claim | Locatable citations, strict source IDs, claim deletion, exact abstention fallback | Unknown source, bad locator, unsupported extract, malformed verifier all fail closed |
| Role bypass | Server-side age/role matrix and LocalAuthentication administrative gate | Under-13 direct user, teen admin, and unapproved adult caregiver are denied |
| Loopback hijack | Random port, 256-bit-equivalent token, bearer auth on all routes, host allowlist, no token in handshake/logs | Missing/wrong token denied; port handshake contains no secret; docs disabled in release |
| Same-user process steals token | Minimize token lifetime/exposure, pass through stdin, never command line or logs | Inspect process args/logs; residual risk remains because same-user malware is powerful |
| Path traversal/symlink overwrite | Native file coordination, resolved application-support root, create-new semantics, no user-controlled engine path in release | `..`, absolute paths, symlinks, aliases, and race attempts cannot escape root |
| PDF/resource exhaustion | Implemented file/page/character/OCR-page/duration/row limits and cancellation checks; memory/disk preflight remains pending | Oversized, deeply nested, corrupt, image-only, cancellation, and low-disk fixtures fail with structured errors |
| Partial/poisoned index | Transactional rebuild, validate counts/hashes before atomic activation, retain prior valid index | Kill process during indexing and prove old index remains active |
| Context loses warning/negation | Extractive reduction, protected numeric/negation/warning terms, source locators | Compression corpus retains numbers, units, `not`, warnings, danger text, and citation mapping |
| Model/artifact substitution | Nested code-signature validation and model/version endpoint are implemented. A configured model pack is accepted only after separate Ed25519 trust-key verification, pinned per-file hashes/sizes, exact model IDs/revisions, dimensions, and ONNX I/O probes; an invalid configured pack fails release startup. Evidence-resource integrity relies on the signed helper/app bundle. | Modify each model/manifest/signature/trust-key input and require startup refusal; modify an evidence resource and require code-signature failure or unavailable startup in the freshly packaged app |
| Incomplete deletion | Key destruction, queued sidecar tombstone, cascade records/chunks, WAL/SHM handling, `secure_delete`; copied clipboard text cannot be recalled | Seed synthetic profile, delete during connected and unavailable states, search every store/index, verify other profile unchanged, then clear clipboard manually |
| Clipboard oversharing | Field-level toggles, factual construction, authorization, disclaimer, no automatic recipients; clipboard lifetime remains a residual risk | Snapshot copied text and confirm excluded fields never appear; verify no report file is created |
| Benchmark contamination | Immutable hash, 60 dev/40 heldout, training script accepts dev IDs only, group split by question | Inject held-out row; training exits before importing ML dependencies or writing artifacts |
| Supply-chain compromise | Hash-locked Python 3.13 release dependency file, CycloneDX 1.6 SBOM, model-pack signature/hashes, license review, CI-action pinning required for release, least-privilege signing | Install with `--require-hashes` in a clean environment, run `pip check`, reproduce the final build, scan artifact inventory, and require no secrets in CI logs |

## Residual risks

- Same-user malware can potentially read process memory or UI content; explicit development-mode SQLite is unencrypted and must never contain real data.
- Deterministic string matching cannot recognize every way a danger sign may be described.
- Source correctness, freshness, and applicability still require human clinical governance.
- A correct citation can be misinterpreted, incomplete, or inappropriate for the individual.
- Local-only design does not protect against screenshots, copied reports, backups, or a compromised operating system.
- PaceBack cannot control or erase selected-report text after it is placed on the shared system clipboard or copied by another process.
- Parental gates are device controls, not legal identity or guardianship proof.
- Synthetic benchmarks underrepresent real language, disabilities, multilingual users, document corruption, and adversarial creativity.

## Security release gates

- Zero cross-profile and wrong-age retrievals in automated tests and the frozen benchmark.
- Zero adversarial canary executions.
- Auth required for every loopback route; no secret in process arguments, handshake, logs, errors, or clipboard reports.
- No unreviewed network entitlement or remote endpoint.
- Release health confirms active SQLCipher sidecar storage; native AES-GCM behavior is established separately by the repository/tests and is not reported by `/v1/health` or `/v1/models`. Explicit development SQLite is never presented as encrypted.
- Clean uninstall/deletion evidence, clipboard-risk review, dependency/model license inventory, live packaged model-manifest capture, evidence-resource/package integrity checks, signed nested code, notarization, and clean-Mac Gatekeeper verification.
- Independent review of any residual severity-one issue before distribution.
