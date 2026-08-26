# PaceBack macOS client

This Swift package contains the native client for the all-ages, local-first PaceBack research prototype. The application target requires macOS 26.4 or newer.

The shared design system maps the bounded in-app text-scale preference into Dynamic Type and native control size, and honors system Reduce Motion, Reduce Transparency, and Increase Contrast settings. These implemented hooks do not replace the pending hands-on VoiceOver, keyboard-only, large-text, contrast, motion, and cognitive-load review with representative users.

```bash
swift build
swift test
swift run PaceBack
```

`swift run PaceBack` exercises the UI package but does not bundle the Python engine or model pack. The actual app entry point injects `SwitchingAIEngine`, starts with evidence Q&A unavailable, and enables Q&A only after an authenticated local helper passes the PID, protocol-version, FTS5, network-tool, storage-driver, and encryption health checks. `MockAIEngine` is retained for tests and previews; it is not silently presented as the live packaged backend.

For a debug integration run, set an absolute executable path and opt into visibly unencrypted development storage:

```bash
PACEBACK_ENGINE_EXECUTABLE=/absolute/path/to/paceback-engine \
PACEBACK_ENGINE_DEVELOPMENT=1 \
swift run PaceBack
```

The URL client accepts only HTTP loopback hosts and a non-empty per-launch token, uses an ephemeral no-cache/no-cookie session, and refuses redirects. The release runtime verifies the nested helper signature and signing-team match, generates a launch token, retrieves a SQLCipher key from Keychain, transfers both secrets through a single JSON stdin line, sanitizes the helper environment, locates the bundled signed model pack and separate public trust key, and fails closed if the helper reports a non-release or unencrypted configuration. The sidecar independently verifies the model-pack signature and pinned artifacts before activation.

## Native data and authorization

- Profile identity is limited to an alias and `AgeBand`; no name or birth date is requested.
- Each profile is a separate AES-GCM envelope with its own Keychain key.
- Under-13 profiles are caregiver-managed. A teen profile must be initialized by a guardian; entering guardian mode requires LocalAuthentication, while handing the session back to teen mode immediately hides administrative controls.
- Adult caregiver mode requires explicit profile-owner approval. Returning to owner controls requires LocalAuthentication.
- LocalAuthentication confirms access to this Mac, not identity or legal guardianship.

Native profiles are mirrored to the sidecar with the same UUID. Synchronization is queued across helper startup, deletion tombstones are replayed, and an evidence question synchronizes the active profile before its run. Only restrictions explicitly confirmed against the original PDF are serialized into the sidecar's clinician-plan document; unconfirmed OCR/PDF text is excluded from RAG.

## Import, simplification, and sharing

PDF import is local and bounded to a regular PDF of at most 25 MB, 100 pages, 200,000 extracted characters, 20 OCR pages, 30 seconds, and 20 proposed restriction rows. PDFKit text extraction and Vision OCR create an unconfirmed, page-located draft; they do not create medical instructions.

Medical or restriction-bearing text always uses the extractive simplifier. Eligible general text may use Apple Foundation Models only when the on-device model is available and the exact instruction plus prompt token count, a 512-token response reserve, and `contextSize` fit. Generated general-text output is rejected to the extractive fallback if protected numbers, units, negations, warnings, restrictions, or grounding checks fail.

The current report action builds a factual selected-field preview and copies it to the macOS clipboard after authorization. It does not write a report file, choose a destination, track recipients, or clear the clipboard automatically.

Confirmed preferences are encrypted and editable, but the current implementation does not feed them into retrieval, context budgeting, simplification, or generation. They are an inspectable ledger, not active adaptive memory.

Build the full application bundle from the repository root with `make package-macos`; the target requires a previously built signed model pack and the `[packaging,ml]` Python extras. See `docs/runbook.md` for exact commands and release limitations. The current arm64 app occupies 306,068 KiB on disk (about 299 MiB), is Apple Development-signed under team `8RMK4MG9T2`, passes strict deep code-signature verification, and reached a responsive 1180×780 window in the fresh packaged startup smoke after the Keychain-main-actor fix. The current 151,185,197-byte development ZIP and exact hashes are recorded in `docs/provenance.md`. It is not Developer ID signed, notarized, stapled, clean-Mac assessed, or approved for public clinical distribution; `spctl` rejects it.
