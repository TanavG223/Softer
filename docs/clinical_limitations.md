# Clinical and scientific limitations

## What is established

- The prototype targets a real practical problem: organizing clinician-provided restrictions, accessible pacing, and source-grounded school/work information after a clinician-evaluated concussion.
- The evidence manifest points to CDC return-to-school, danger-sign, and return-to-work resources and the Amsterdam sport-concussion consensus. The runtime seed contains project-authored, link-attributed summaries for all four evidence families, including an Amsterdam boundary summary.
- The software has explicit boundaries, age filtering, profile isolation, deterministic emergency routing, and fail-closed citation behavior that can be tested with synthetic data.
- Native profiles synchronize to the sidecar with exact IDs, and only user-confirmed page-cited care-plan rows are eligible for private RAG. This is a software boundary, not proof that OCR or the user's confirmation is medically correct.
- Matching unreviewed real-pack and fallback diagnostics completed all 100 synthetic/public items. The real BGE + MiniLM run recorded higher automated source retrieval/order metrics than fallback (Recall@20 0.9767 vs 0.9667; nDCG@20 0.954886 vs 0.894214) at higher mean latency (51.53 ms vs 7.09 ms). Both had zero automated cross-age leaks and canary executions, but both matched only 40/100 response types and 3/63 boundary-routing cases. This is transparent engineering evidence—not clinical readiness.

## What is not established

- No clinician or institutional review board has validated PaceBack.
- No clinical trial, usability study, prospective study, patient study, pediatric study, older-adult study, external validation, or real-world deployment has been completed.
- No evidence shows that PaceBack improves recovery time, symptoms, adherence, learning, work performance, mental health, safety, or healthcare utilization.
- The application cannot determine whether a concussion occurred, whether symptoms are caused by it, whether a person is improving, or when a person can return to any activity.
- Benchmark retrieval/citation metrics are software-test results, not medical accuracy or clinical validity.
- The 100 benchmark items are pending the required non-author and qualified-domain review, and the frozen BM25, dense, hybrid, and adaptive runs have not yet been accepted through the promotion gates.
- Synthetic profiles and synthetic clinician plans do not represent clinical diversity or workflow validity.
- CDC and consensus guidance may change; a link or reviewed summary can become stale.
- The English/U.S. scope does not establish suitability for another language, country, school system, workplace, emergency number, privacy regime, or standard of care.
- Age bands are policy-routing inputs, not clinical categories. Older-adult mode has no validated age-specific model.

## Current engineering gaps that block a production claim

1. Release storage is SQLCipher-gated and native profiles use independent envelope keys. The current packaged-app launch created an encrypted mode-`0600` database that ordinary `sqlite3` rejected, but clean-Mac installation, migration, deletion, and restart evidence remain incomplete. Sidecar SQLCipher uses one database key rather than separate per-profile database keys, so deletion behavior still needs independent review.
2. A signed pack containing pinned BGE-small embeddings and MiniLM reranking has passed direct local activation/inference, release-mode SQLCipher exact-profile/index/run, current packaged-app smoke testing, and a complete unreviewed 100-item run. BGE and MiniLM changed together, no human claim-support metric is measured, and response/boundary routing remains weak. Archive the exact authenticated live `/v1/models` response with the submission artifact; all four frozen one-variable runs remain required, and no component-specific, promoted, or clinical improvement may be claimed.
3. Native helper lifecycle, exact-ID synchronization, confirmed-plan reconciliation, bearer/database-key handoff, signature and PID/port/health validation, cooperative in-flight cancellation, parent-pipe liveness, and fail-closed unavailable state are implemented and tested at the contract level. Crash/restart, deletion, Keychain migration, update, and clean-Mac behavior still need release-artifact testing.
4. PDF import now enforces file, page, extracted-character, OCR-page, duration, candidate-row, and cancellation bounds. A real PDFKit test imports all four generated two-page synthetic demo plans, locates rows on pages 1 and 2, and leaves every row unconfirmed. That narrow digital-PDF test is not OCR accuracy: representative scanned PDFs, tables, handwriting exclusion, malformed files, and low-quality scans remain unmeasured.
5. Evidence summaries need qualified domain review, version pinning, change monitoring, and an expiration policy.
6. The deterministic phrase safety gate can miss paraphrased danger signs or create false positives. It is a routing aid, not triage validation.
7. Accessibility requires hands-on VoiceOver, keyboard-only, large-text, contrast, reduced-motion, reduced-transparency, and cognitive-load testing with representative users.
8. The package pipeline and signing path are implemented and require the signed model pack. The current development build is Apple Development-signed under team `8RMK4MG9T2`; strict deep signature verification and app/helper/encrypted-storage lifecycle smoke testing passed. Canonical upstream model-license texts are now checked in and selected by the package script. Apple Development signing is not public distribution signing. Developer ID signing, hardened-runtime review, notarization, stapling, clean-Mac Gatekeeper validation, final packaged model/resource tamper testing, complete dependency/license inventory and redistribution review, and 8/16 GB performance remain unproven.
9. Child privacy architecture needs qualified legal review before any online, account, support-upload, telemetry, or cloud capability.
10. Threat modeling and automated tests reduce known risks but do not prove security.
11. The selected-field report currently copies text to the system clipboard. Clipboard lifetime and reads by other local apps are outside PaceBack's control; no file export, recipient workflow, or automatic clipboard clearing is implemented.
12. Confirmed preferences are an editable encrypted ledger but are behaviorally inert in the current pipeline. They do not yet personalize retrieval, context reduction, simplification, or responses.

## Claim ladder

Permitted before measured evaluation:

- “PaceBack is a local-first macOS research prototype.”
- “The code implements bounded, age-scoped local hybrid retrieval; the active components are disclosed by the runtime manifest.”
- “The checked-in benchmark contains exactly 100 synthetic/public, human-review-ready items under a validated split contract.”
- “The app is designed to support—not replace—professional care.”
- “Only confirmed care-plan transcriptions are synchronized into the profile's private retrieval namespace.”

Permitted only after attaching a frozen run, hash, protocol, and review coverage:

- Exact Recall@20, nDCG@20, citation-locatability, citation-precision, unsupported-claim, latency, token, and canary results for the named configuration and hardware.
- A comparison statement limited to the fixed PaceBack benchmark.
- Any statement that a model-backed dense retriever or reranker improves over the deterministic baseline.

Not permitted without independent clinical evidence and appropriate review:

- “Clinically accurate,” “clinically validated,” “medically safe,” “prevents harm,” “improves recovery,” “works for all concussion patients,” or equivalent claims.
- Any diagnostic, prognostic, treatment, clearance, or regulatory-status claim.

## Review needed before wider use

- Concussion clinician review of every medical summary, red-flag phrase, age-specific message, and demo claim.
- Pediatric and adolescent clinical/usability review.
- Accessibility review with representative disabled users.
- Privacy counsel review, including current COPPA and state health/privacy requirements.
- FDA/regulatory counsel review of intended use, claims, features, labeling, and distribution.
- Independent security assessment of storage, helper authentication, package integrity, deletion, clipboard sharing, and local attack surface.

Until those reviews and relevant validations are complete, distribute only as a clearly labeled hackathon research prototype using synthetic demonstration data.
