# Safety, privacy, and responsible-AI specification

PaceBack is an **unvalidated research prototype**. It supports organization and access to evidence; it does not provide medical advice, diagnosis, treatment, prognosis, or clearance. No current implementation or benchmark result may be presented as clinical effectiveness.

## Safety invariants

1. A danger-sign match uses reviewed deterministic logic and bypasses retrieval and generation.
2. The emergency card directs the user to call 911 or go to an emergency department; it does not claim that a dangerous condition is present.
3. Pediatric messaging includes child-specific signs, including inconsolable crying and refusal to nurse or eat, while retaining the adult danger signs listed by CDC.
4. Imported care-plan text remains an unconfirmed, page-located draft until a user or caregiver checks it against the original.
5. No model may create, change, remove, or advance a restriction or recovery stage.
6. No response may diagnose, prescribe, predict an individual outcome, or grant school, work, sports, driving, or exercise clearance.
7. Every health claim needs a source identifier and locator. Unknown, failed, wrong-age, wrong-profile, stale, or unsupported evidence is deleted rather than softened.
8. If verification leaves no claim, the answer is exactly `I could not verify an answer.`
9. Trend charts report entries and session history; they never infer improvement, deterioration, cause, readiness, or treatment need.
10. Cancellation, resource exhaustion, malformed model output, index failure, or verifier failure produces a structured failure or abstention—not a best-effort medical answer.
11. Unconfirmed care-plan draft rows remain in the encrypted native profile only; the sidecar RAG document is derived exclusively from confirmed page-cited rows.
12. Runtime model weights are frozen and local. A configured BGE/MiniLM pack must pass signature, hash, size, identity, revision, dimension, and I/O checks before activation; no result may credit a component that `/v1/models` reports inactive.

## Age-aware behavior

| User context | Safety behavior |
|---|---|
| Ages 0–5 | Caregiver operates the profile. Child-facing content is brief, calm, guided, and non-medical. |
| Ages 6–12 | Caregiver manages the profile; an optional guided child view has no unrestricted free-form medical AI. |
| Ages 13–17 | Guardian initializes the profile. The teen may use ordinary guided features, while administrative changes and sharing remain gated. |
| Ages 18–64 | Self-managed by default; caregiver access is explicit and revocable. |
| Ages 65+ | Self-managed or explicitly caregiver-shared; the app must not invent special geriatric conclusions. |

The runtime supports only these five explicit age bands; it does not infer age or create an unknown-age profile. Every query carries exactly `allAges` plus the selected `AgeBand` raw value. Age filtering occurs before sparse and dense retrieval. It is not sufficient to filter after ranking because even discarded chunks could influence a model or logs.

## Data inventory and purpose limitation

| Data | Purpose | Prototype location | Never used for |
|---|---|---|---|
| Alias and age band | Select age/role policy | Encrypted native profile; scoped engine record | Identity verification, advertising, demographic inference |
| Role and caregiver approval | Authorization | Encrypted native profile and scoped engine record | Automatic legal-guardian determination |
| Clinician PDF/draft | Local extraction and human confirmation | Encrypted native profile only while unconfirmed | Diagnosis, autonomous plan creation, model training |
| Confirmed care-plan rows | Profile-specific evidence Q&A | Encrypted native profile and profile-scoped sidecar document/index | Unconfirmed-text retrieval, autonomous plan changes, model training |
| Session/check-in entries | User-visible pacing history | Encrypted native profile | Readiness, prognosis, engagement optimization |
| Query, retrieved chunks, citations | Local evidence response | Profile-specific namespace in SQLCipher-gated release storage; explicit dev SQLite only | Cloud analytics, cross-profile personalization |
| Helpful/not-helpful feedback | Inspectable local run feedback | Profile-specific sidecar record | Runtime weight updates, personalization, or unattended retraining |
| Clipboard report | User-selected factual sharing | macOS system clipboard | File export, recipient discovery, background sharing, automatic clipboard clearing |

The prototype stores no legal name, exact birth date, address, contact information, advertising identifier, location, photo, voice recording, or account credential by design. Text-to-speech uses local speech output; microphone collection is not required.

## Child privacy

The FTC states that COPPA protects children under 13 in covered online services and places parents in control of online collection. The FAQ was updated to point to an amended rule published April 22, 2025. PaceBack avoids accounts and intentionally transmits no child data, but that architecture is **not a legal determination or compliance certification**.

- No telemetry, ads, trackers, cloud generation, remote crash payloads, push notifications, or web search.
- No persistent online identifier or contact information.
- Under-13 profiles are caregiver-managed.
- Teen administrative controls use LocalAuthentication as a local parental gate; biometric data remains managed by macOS and is not read by PaceBack.
- Parents/caregivers can inspect and delete the local profile under the product authorization rules.
- Any future network feature, account, support upload, remote analytics, or cloud backup is a scope change. Disable it for child profiles until qualified counsel reviews the current COPPA Rule and the product implements appropriate notice, consent, access, deletion, minimization, security, and retention controls.

LocalAuthentication proves that macOS accepted a local credential or biometric policy. It does not legally verify that the person is a parent or guardian.

## Explainability and user control

Each evidence answer exposes source title, URL where permitted, page where available, quoted extract, support status, route, retrieval-round count, and stop reason. The engine also records character offsets and content hashes for verification, but the current source-card UI does not display those fields. Confirmed preferences are an editable encrypted ledger, not hidden memory; the current AI pipeline does not consume them. Users can remove preferences or an entire profile. Plan-document synchronization is controlled by confirmation state rather than a separate document manager.

The UI must label:

- the active profile alias, age band, role, and care context;
- whether the local evidence engine is connected or unavailable, and whether simplification used Apple Foundation Models or the extractive fallback;
- whether a care-plan field is unconfirmed or confirmed;
- why a response abstained or stopped;
- that the clipboard report contains only the currently selected fields;
- the source review date and prototype limitation.

Do not show hidden chain-of-thought or claim that a model “reasoned like a clinician.” Show evidence and deterministic decision metadata instead.

## Bias and age-safety controls

- Evaluate every query type across child/caregiver, teen, adult, older-adult/caregiver, and ambiguous cohorts.
- Test wrong-age retrieval and cross-profile leakage as zero-tolerance failures.
- Never infer a person's age, cognitive capacity, family role, literacy, or disability from their writing.
- Provide brief/standard/full reading modes, bounded text/control scaling, comfortable spacing, VoiceOver, keyboard operation, text-to-speech, non-color state, and reduced-motion support. Automated mapping and labels do not replace hands-on testing with representative users.
- Avoid infantilizing teen or older-adult copy. Young-child mode is simplified because of the interaction contract, not because the model infers capability.
- The benchmark does not establish fairness across languages, cultures, disabilities, injury mechanisms, or healthcare systems; the launch scope is English/U.S. only.

## Incident response

Treat any of the following as a severity-one prototype safety defect: cross-profile disclosure, wrong-age clinician-plan retrieval, unconfirmed-plan retrieval, execution of document instructions, missing emergency bypass, unsupported clearance/treatment output, silent verifier failure, unencrypted distribution advertised as encrypted, or child-data transmission.

1. Stop distribution and disable the affected feature.
2. Preserve only non-sensitive build hashes, code versions, and synthetic reproduction steps; do not copy user health content into issue trackers.
3. Reproduce with synthetic fixtures.
4. Add a failing automated test before the fix.
5. Run the complete safety, isolation, benchmark, accessibility, and packaging gates.
6. Document the residual risk and obtain clinical/privacy review when applicable.

## Required wording

Prominent onboarding/about/clipboard-report wording:

> PaceBack is a research prototype that supports organization and access to evidence. It is not a medical device and is not intended to diagnose, treat, predict recovery, or provide clearance. Follow guidance from a qualified healthcare professional. If danger signs may be present, call 911 or go to an emergency department.

“Not a medical device” is product positioning, not a binding FDA classification. Qualified regulatory review is required before public clinical use.
