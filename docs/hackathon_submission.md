# Hack for Humanity submission and demo

## Submission draft

**Project:** PaceBack

**Tagline:** Private, age-aware AI that keeps concussion evidence retrieval on the Mac, iPhone, or iPad while keeping professional decisions with people.

**Primary category:** Physical Health

**Primary track:** Best Use of AI/ML & Responsible AI

**Secondary track:** Best Tech for Concussion Recovery

Also relevant: Best Design and Best Innovation and Creativity. Select any sponsor/deployment track only if its required service is actually integrated and demonstrated; PaceBack currently has no Render integration.

### The problem

Returning to school, work, or daily screen use after a concussion can involve changing symptoms, dense instructions, multiple caregivers or professionals, and uncertainty about what guidance applies. Generic chatbots can mix age groups, invent recommendations, hide uncertainty, or send sensitive health information to remote services.

### The solution

PaceBack's full clinician-plan and adaptive-RAG workflow is a native, local-first macOS research prototype for a person recovering from a clinician-evaluated concussion or a caregiver supporting them. It imports a clinician PDF as an unconfirmed page-cited draft, lets an authorized user verify each transcription, synchronizes only confirmed rows into that profile's private RAG namespace, offers low-stimulation focus sessions and guarded text simplification, and answers questions only from the active profile's age-filtered evidence. A separate native iOS 18+ companion provides deterministic safety, encrypted profiles, role gates, focus sessions, and retrieval-only on-device AI over seven bundled curated public-source summaries after an explicit model setup. Neither target diagnoses, prescribes, predicts recovery, or grants clearance.

All ages are supported through five explicit age bands and implemented role handoffs: caregivers operate ages 0–12, teens get a guardian-initialized view, adults self-manage, and adult caregiver access is revocable. LocalAuthentication protects elevation into guardian/owner controls. Danger-sign phrases bypass AI and show static CDC-based emergency directions. Unknown or unsupported claims are removed; no surviving evidence returns `I could not verify an answer.`

### How it works

- SwiftUI provides role-aware navigation and handoff, LocalAuthentication gates, encrypted profile envelopes, accessible reading modes, bounded PDFKit/Vision import, sessions, clipboard reports, and source cards.
- The separate `PaceBackiOS` iPhone/iPad target uses per-profile AES-GCM files with Keychain keys, LocalAuthentication gates, deterministic age-filtered danger signs, focus sessions, and a trusted-source catalog. A required first-use screen downloads and verifies exactly 157,716,998 bytes of pinned BGE-small and quantized MiniLM ONNX artifacts, then Swift BM25/dense search, RRF, and ONNX Runtime 1.24.2 reranking produce literal source excerpts with local locators.
- An authenticated loopback Python sidecar enforces strict profile, role, age, and evidence contracts. Native profiles keep their exact UUID, startup synchronization is queued, and only confirmed plan text is indexed.
- Retrieval combines FTS5/BM25 with signed local BGE-small ONNX embeddings, reciprocal-rank fusion, MiniLM ONNX reranking, prompt-injection filtering, global cross-round deduplication, a three-chunk-per-document cap, and a maximum of eight evidence chunks. A separate Ed25519 trust key and pinned artifact contract protect the model pack; the live `/v1/models` response identifies what actually produced a run.
- Bounded adaptive routing sends ordinary questions to single or iterative retrieval. Iterative retrieval uses deterministic subquery expansion and at most three rounds, six subqueries, 100 candidates, and eight configured actions; the current loop has no separate correction action.
- Extractive context reduction prioritizes numbers, negations, warnings, and relevant sentences while preserving locators. This is adaptive token reduction, not tokenizer retraining or task-adaptive tokenization.
- Medical/restriction text is simplified extractively only. Eligible general text may use Apple Foundation Models after exact prompt/instruction token and context-window checks, then must pass protected-span and grounding gates.
- A fixed 100-item all-age benchmark tests five query types, age cohorts, abstention, prompt injection, and isolation. Matching complete real-pack and fallback diagnostics expose retrieval differences, latency cost, passing automated isolation/canaries, and unchanged weak routing; human review and the four one-variable BM25/dense/hybrid/adaptive runs remain incomplete.

### Privacy and responsible AI

The prototype has no account, analytics, ads, trackers, web search, cloud generation, or intentional transmission of profile data. It stores an alias and age band rather than a name or birth date. On iOS, the disclosed first-use model installer is a narrow network exception: four ephemeral, allowlisted HTTPS artifact requests contain no profile, alias, age band, symptom, care-plan field, or question. Evidence queries stay on-device. Retrieved documents are untrusted evidence, not executable instructions. The confirmed-preference ledger is editable but currently behaviorally inert; no runtime component retrains on user data.

This privacy architecture is not a COPPA, HIPAA, FDA, medical-device, or security certification. Release mode is SQLCipher-gated and obtains its database secret from Keychain through the native helper lifecycle; explicit development SQLite remains possible and is always reported as unencrypted.

### UX research basis

The [official judging page](https://hack-for-humanity-summer-26.devpost.com/) scores all entries on Innovation/Novelty and UI/UX/Accessibility and adds concussion-specific clinical/domain, safety, neuroscience, research, technical, and UX criteria. Its [2026 project gallery](https://hack-for-humanity-summer-26.devpost.com/project-gallery) was not published as of 2026-08-26, so PaceBack was not benchmarked against unseen entries.

Design choices were instead informed by published concussion-app usability evidence. A [2025 Rhea study](https://formative.jmir.org/2025/1/e67275) supports clear navigation, understandable voice/reporting, shorter interaction time, and stronger error recovery for people with visual sensitivity or cognitive load. The [pediatric NeuroCare study](https://humanfactors.jmir.org/2019/2/e12135) used iterative user-centered design, reported mean SUS 81.9 and greater than 90% task success for 11 of 12 tasks, and described reading/screen-time burden as a concern. A [2025 adult study](https://humanfactors.jmir.org/2025/1/e75323) used three user-and-clinician iteration cycles with MAUQ, MARS, interviews, and safety assessment. These papers informed PaceBack's short flows, calm hierarchy, explicit recovery/error states, text/display controls, focus pauses, and caregiver-aware navigation; they do **not** validate PaceBack. Representative-user testing and independent accessibility review remain pending.

### Current limitations

PaceBack has not been clinically validated, independently security/accessibility tested, or studied with patients. The demonstration uses only synthetic profiles and synthetic clinician plans. In matching unreviewed full diagnostics, the real BGE + MiniLM pack recorded Recall@20 0.9767 and nDCG@20 0.954886 versus fallback 0.9667 and 0.894214, while mean latency rose from 7.09 ms to 51.53 ms. Both had zero automated age leaks and canary executions, but both matched only 40/100 response types and 3/63 boundary cases. Human correctness, citation precision, and unsupported claims are unmeasured; BGE and MiniLM changed together; promotion gates are not passed. The current arm64 app occupies 306,068 KiB on disk (about 299 MiB), and its 151,185,197-byte ZIP passes strict Apple Development signature checks. A fresh packaged startup smoke reached a responsive 1180×780 window in about 0.6 seconds after moving Keychain work off the main actor. Apple Development signing is not Developer ID distribution signing, and `spctl` rejects this unnotarized build. Developer ID signing, notarization, stapling, clean-Mac testing, full current-artifact lifecycle smoke, and 8/16 GB profiling remain pending. PaceBack supports professional care and does not replace a qualified clinician.

The separate static submission site was exercised in a real browser at 375, 768, 1024, and 1440 CSS pixels with no horizontal overflow or console errors, only local requests, and a skip link that reached `main`. After the final immutable-revision URL wording, the structural checker still passes and mobile Lighthouse reports 100 accessibility, best-practices, SEO, and agentic scores. Those are automated site checks—not independent accessibility evidence for the native app.

The iOS companion separately passed 34/34 tests across nine suites on an iPhone 17 Pro simulator and a generic iOS Simulator Release build independently repeated through XcodeBuildMCP. The simulator downloaded and atomically activated all 157,716,998 pinned bytes after Ed25519/size/SHA checks, then one supported adult-work query returned a source-linked CDC excerpt in 361 ms. That is one smoke observation, not an accuracy or device benchmark. The seven bundled curated public-source summaries have no recorded independent/human corpus review, and provisional support thresholds still need held-out/domain review. iOS has no generation, training, user-data learning/upload, clinician-document ingestion, clinician-plan RAG, or adaptive multi-round loop. It has not been physically tested on iPhone/iPad, archived or signed for distribution, submitted to the App Store, or independently accessibility reviewed.

### What we built during the event

- Native SwiftUI all-age experience, explicit role policy, and authenticated role handoff.
- Native iOS 18+ iPhone/iPad companion with encrypted local profiles, deterministic danger signs, role gates, focus sessions, signed-model setup, age-filtered hybrid retrieval over seven bundled curated public-source summaries, MiniLM reranking, source-linked extracts, and structured abstention.
- Local authenticated engine with exact-ID/confirmed-plan sync, bounded hybrid retrieval, global cross-round caps, citations, verification, cooperative in-flight cancellation, and profile isolation.
- Signed, offline-only BGE-small/MiniLM ONNX pack with pinned upstream revisions, Ed25519 manifest verification, per-artifact hashes/sizes, I/O probes, and honest deterministic fallback labels.
- Deterministic danger-sign routing and fail-closed boundaries.
- Guarded on-device Foundation Models simplification for eligible general text and extractive-only handling for medical/restriction text.
- Synthetic clinician-plan fixtures, an executable local benchmark adapter, and exactly 100 benchmark cases under a machine-validated contract.
- Static submission landing page with local assets, responsive/reduced-motion/forced-color styling, structural checks, and no runtime network API.
- Threat model, evidence/rights manifest, evaluation protocol, release runbook, and automated CI.

Before submitting, add the exact public repository commit, contributor list, and artifact URL. The current package, executable, model-manifest, dependency, and benchmark hashes are recorded in `docs/provenance.md`; do not copy a value without verifying the files still match it. Human review and the four frozen runs remain incomplete, so state “performance gates not yet evaluated” and do not turn the automated retrieval diagnostics into a quality or medical-accuracy score.

## Four-minute demo script

Use the freshly packaged macOS app on an offline Mac, a large cursor, readable display scaling, and synthetic data only. Keep the primary scored AI/ML walkthrough on macOS because it demonstrates clinician-plan RAG and bounded adaptation. If iOS appears, preinstall the model pack rather than spending the video on a 157,716,998-byte download, show its signed privacy receipt, and describe its output only as retrieval-only, source-linked extraction over seven bundled curated public-source summaries. Keep the timer visible to the presenter. Do not improvise clinical or benchmark claims.

### Pre-recording setup

1. Run `make verify` and use the current hash-matched package, or rebuild `make package-macos` from the signed model pack after any package-input change. Preserve the exact output. Confirm the app's status bar says the private local evidence engine is connected and that `/v1/models` reports the components actually embedded in that build.
2. Generate the four **synthetic** PDFs with `uv run --with reportlab==4.4.9 python scripts/generate_synthetic_plan_pdfs.py` (or install `scripts/requirements-pdf.txt` in a disposable environment). Record each output's SHA-256 in the evidence packet. The checked Swift test imports all four two-page PDFs with page 1 and 2 locators and every row unconfirmed; do not generalize that narrow fixture result to OCR accuracy.
3. Create synthetic aliases “Age 7,” “Age 15,” “Age 35,” and “Age 72” in their correct bands. Import the matching synthetic PDF as the authorized role. Leave at least one draft row unconfirmed in the Age 7 profile so the confirmation boundary is visible.
4. For Age 72, enable local caregiver approval while in owner mode, then hand the session to caregiver mode. Add synthetic check-ins in advance if a trend chart will be shown.
5. Rehearse every query against the final artifact. If a result, model badge, route, or timing differs, show what actually happened; do not splice a preferred result from another build.
6. If showing iOS, use a synthetic profile, finish model setup before recording, preserve the receipt, disable networking before the question, and rehearse one supported age-appropriate query plus one abstention. Do not call the 361 ms simulator smoke a benchmark or imply clinician-plan ingestion.

### 0:00–0:25 — Problem, track, and boundary

**Say:** “PaceBack enters Best Use of AI/ML and Responsible AI, with Concussion Recovery as its second track. Its Mac app keeps clinician-plan RAG local, and its iPhone and iPad companion runs a smaller retrieval-only BGE and MiniLM pipeline after a transparent model download. Neither sends a health question to a cloud model. PaceBack supports care; it never diagnoses, treats, predicts recovery, or grants clearance.”

**Show:** Welcome/prototype boundary, the five age bands, then the connected local-engine status.

### 0:25–1:05 — Age 7: confirmation-to-RAG boundary

**Show:** Select synthetic “Age 7.” In Care Plan, point out a confirmed and an unconfirmed page-cited row. Confirm the prepared quiet-workspace row, then choose the caregiver-safe “What school adjustments does CDC describe?” question. Open its source card. Briefly show that free-form AI is disabled for under 13.

**Say:** “PDFKit or Vision creates a bounded draft, never an order. Only rows the caregiver confirms are synchronized into this profile's private RAG document. The query also receives public evidence from exactly `allAges` plus the 6-to-12 scope.”

**Proof:** Show the page label, confirmation count, under-13 free-form lock, and cited answer. Do not claim OCR accuracy from this one file.

### 1:05–1:40 — Age 15: guarded on-device AI and role handoff

**Show:** In teen mode, simplify a synthetic **general, non-medical** school paragraph. Point to the actual “Apple on-device model” or “Extractive fallback” badge. Then show clipboard-report controls disabled, go to Privacy, and choose “Unlock parent or guardian controls…” to invoke LocalAuthentication. Hand the session back to teen mode and show protected controls disappear.

**Say:** “Eligible general text can use Apple's on-device model only after exact token and context checks and output grounding gates. Medical or restriction text is always extractive-only. Teen administration requires guardian mode; Mac authentication is a device gate, not legal identity proof.”

**Optional if time:** Ask “Can PaceBack clear me for sports?” and show the cited boundary or abstention exactly as returned.

### 1:40–2:25 — Age 35: hybrid search and bounded adaptation

**Show:** Select Age 35 and ask: “Compare what the CDC work form says about screen time and quiet rest breaks, and explain who can change those restrictions.” Open source cards and Run details. If the final run is still loading long enough, press Cancel and rerun; otherwise do not stage a cancellation result.

**Say:** “Before ranking, both retrievers see only this profile, `allAges`, and the adult scope. FTS5 and the active local dense component retrieve independently, RRF fuses them, reranking scores at most 30, and global cross-round controls keep three chunks per document and eight total. Iteration stops after three rounds or earlier when evidence is sufficient or stalls.”

**Disclosure on screen:** Show the actual route, round count, stop reason, citations, and final model-manifest names from the same build. Do not call a configured-but-inactive adapter the runtime model. The current UI exposes route/round/latency, not a context-savings percentage.

### 2:25–2:55 — Age 72: revocable caregiver mode and minimal sharing

**Show:** Select Age 72 in approved caregiver mode. In Care Plan, select only confirmed plan items and copy the report; paste it into a blank local editor to show the exact selected text and disclaimer, then clear the clipboard. Show the Trends “Descriptive only” label. In Privacy, show that returning to owner mode requires Mac authentication.

**Say:** “Adult caregiver access is explicit and revocable. The report is clipboard text, not a managed file export, and PaceBack cannot control the clipboard after copying. Trends connect entered values for readability but never infer recovery.”

Do not stage a cross-profile denial in the profile picker: this prototype has no accounts and any local operator can select a profile in the app. Cross-profile isolation means one profile's retrieval request cannot read another profile's namespace; demonstrate that with the automated isolation test in the final segment.

### 2:55–3:25 — Deterministic safety and adversarial isolation

**Show:** In an adult free-form evidence box, enter “They vomited again after the hit.” Show the safety-gate badge, `direct` route, and zero retrieval rounds. Then show the terminal result for the engine's prompt-injection/profile-isolation tests; do not fabricate an interactive canary outcome.

**Say:** “Reviewed danger phrases bypass model and retrieval work. Retrieved documents are untrusted data: they cannot enable web search or code execution, change age scope, reveal another profile, or remove citation requirements.”

Do not simulate an emergency with a real person's information. State that the card does not diagnose a condition.

### 3:25–3:48 — Evaluation and accessibility

**Show:** Terminal running `python3 benchmark/validate_benchmark.py`, the real-model and fallback diagnostic summaries, and the exact final `make verify` output, followed by one keyboard shortcut, a VoiceOver label, and the bounded text-scale or comfortable-spacing control.

**Say:** “The validator locks 100 cases. Real-model Recall at 20 was 0.9767 versus 0.9667 for fallback, and nDCG was 0.9549 versus 0.8942, at 51.53 versus 7.09 milliseconds. Both had zero automated age leaks and canary executions, but only 40 of 100 response types and 3 of 63 boundary cases. Both models changed together, and human claim support is unmeasured.”

If a complete reviewed comparison later exists, state only the exact scoped numbers from the frozen report. Otherwise keep the current two-configuration diagnostic explicitly labeled unreviewed, combined-component, and not promotable.

### 3:48–4:00 — Close

**Say:** “PaceBack makes evidence and uncertainty visible while keeping sensitive recovery work on the Mac. It is an unvalidated prototype designed to help families and adults use professional guidance—not replace it.”

**Show:** AI/ML architecture/safety summary and repository QR/link. End by 3:58 to avoid upload trimming.

## Recording checklist

- [ ] Video is at most four minutes and publicly accessible at the required URL.
- [ ] No names, birth dates, real documents, health histories, tokens, local paths, or signing credentials appear.
- [ ] All four profiles and plans are visibly labeled synthetic.
- [ ] On-device/offline behavior is demonstrated with network disabled.
- [ ] The live dense/reranking components are named exactly as the final `/v1/models` response reports; inactive adapters are not credited with a run.
- [ ] The hash-matched package contains the signed pack, public trust key, model provenance, NOTICE, and the checked-in upstream model-license texts. A final dependency/license inventory and redistribution review is still required before public distribution.
- [ ] No metric appears without its benchmark hash, configuration, hardware, and review coverage.
- [ ] SQLCipher release state, explicit plaintext development mode, pending human/frozen-run gates, and lack of clinical validation are disclosed.
- [ ] Any iOS screenshot labels its output as local retrieval-only source extraction, not generation or clinician-plan RAG; model-download network use and the seven-summary corpus are disclosed.
- [ ] Clipboard report limitations are stated and the demo clipboard is cleared after use.
- [ ] Captions are corrected manually; audio and on-screen text are readable.
- [ ] Repository is public, team size/rules are satisfied, contributors and reused work are attributed.
- [ ] Submission is completed before September 4, 2026 at 11:45 PM EDT; do not rely on a last-minute upload.

## Final Devpost checklist

- Project began after August 7, 2026.
- Team contains no more than four eligible participants.
- Public source repository and exact commit are linked.
- Four-minute video, written description, technologies, track selections, screenshots, contributor credits, license, NOTICE, and evidence sources are present.
- Screenshots contain synthetic data only and include accessibility/safety states, not just a successful chat answer.
- Any downloadable app has app/helper SHA-256 values and current package evidence. Name the exact signing class; call it Developer ID signed, notarized, stapled, or clean-Mac verified only when the corresponding archived records exist.
- The iOS project is identified separately as `PaceBackiOS` (`org.paceback.research.ios`, iOS 18+, iPhone/iPad). Its 34 tests, generic Simulator Release build, complete model-install smoke, and one 361 ms retrieval observation are not presented as physical-device, App Store, accessibility, calibrated-quality, or clinical evidence.
- Claims in the submission are reconciled against `docs/clinical_limitations.md` and the frozen result artifacts.
