# Verification provenance

Status: source-matched results for the current native macOS wellbeing prototype. Engineering verification does not establish clinical effectiveness.

| Check | Current result |
|---|---|
| Dependency-free wellbeing harness | PASS: 58 checks covering catalog, age gates, recommendation bounds and negative decay, branching game routes, support isolation, fail-closed state, real index tampering, memory-only guest behavior, Keychain/AES-GCM persistence, update/delete, and legacy schema migration |
| Native release compilation | PASS with Apple Command Line Tools and `swift build -c release --product PaceBack` |
| Static site contract | PASS: structural/claim checker and JavaScript syntax; the Codex in-app browser exposed the expected landmarks, headings, support links, and pressed-state semantics; choosing “Thoughts moving fast” updated the live region to Harbor Tiles and the expected alternatives |
| Packaged app signature/bundle inventory | PASS: 11 MiB universal arm64/x86_64 bundle; both slices declare macOS 14.0 minimum; strict deep signature valid; Apple Development team `8RMK4MG9T2`; only Apple system frameworks and Swift runtime libraries are linked |
| Packaged app launch and risk-based walkthrough | PASS: the signed bundle loaded the pre-change encrypted profile, ran the breathing pacer and shape-only/pause controls, placed/hinted/undid Harbor Tiles, advanced Harbor Path with Skip, rendered both new human-support controls, and displayed/cancelled the 911 confirmation; see `release_acceptance_2026-09-03.md` |
| Submission screenshots | PASS: current Retina captures for Calm, Play, Harbor Tiles, and Gentle breathing use the non-identifying `PaceBack Demo` alias in `output/submission/` |
| Distribution signing/notarization | Not performed |
| Accessibility testing with representative users | Not performed |
| Independent security/privacy review | Not performed |
| Clinical or wellbeing outcome study | Not performed |

The active build contains no Python helper, model pack, injury-recovery workflow, care-plan importer, chatbot, account, analytics SDK, or required network service. Historical mobile and injury-recovery source, generated packages, test environments, screenshots, and benchmark artifacts were permanently removed during the Mac-only cleanup. The universal packaged app is 11 MiB; SwiftPM's ignored local build cache is not part of the app or public source tree.

Storage cleanup also removed the user simulator directory, Xcode DerivedData, and the installed iOS 26.5 simulator runtime. The remaining shared CoreSimulator support is about 5 MiB. `/Applications/Xcode.app` remains a separate 3.5 GiB root-owned installation; `/Library/Developer/CommandLineTools` is intentionally retained because it builds the Mac app.

Evidence-source and competitor-repository links are recorded in `evidence_manifest.json`, `mental_wellbeing_evidence_contract.md`, `mental_wellbeing_game_research.md`, and `competitive_ux_research.md`. Those sources inform design and claims; they did not test PaceBack.
