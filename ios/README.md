# PaceBack for iOS

This directory contains a genuine, native SwiftUI iOS target. It is intentionally separate from the macOS app because iOS cannot launch the bundled Python helper used by the desktop hybrid-retrieval engine. iOS instead uses ONNX Runtime for local embedding and reranking after the user installs PaceBack's pinned model pack.

## Open in Xcode

```sh
cd ios
xcodegen generate
open PaceBackiOS.xcodeproj
```

Select the shared `PaceBackiOS` scheme and any iOS 18 or newer simulator.

For deterministic UI inspection, add `-PaceBackSyntheticProfile` to the Debug
scheme's launch arguments. This injects an in-memory adult profile named
`Demo`; the code is excluded from Release builds and writes no profile data.

## Required private-AI setup

Evidence search is gated until the local pack reaches `Ready offline`. The setup
screen explains and downloads four frozen artifacts—two model-weight files and
two tokenizer files—totalling exactly `157,716,998` bytes (about 151 MiB).
PaceBack does not train these models and does not use profile or health data in
the requests.

- The user explicitly chooses Wi-Fi only or Wi-Fi plus cellular.
- The preflight requires `357,919,352` bytes of working space (pack + largest
  artifact + 64 MiB), shown to users as roughly 350 MB.
- The foreground download uses an ephemeral, cookie-free, cache-free URL
  session. Keep PaceBack open; the UI makes no background-download promise.
- Source URLs are HTTPS-only, pinned to immutable Hugging Face revisions, and
  redirects are limited to `huggingface.co` or a `.hf.co` host.
- A bundled Ed25519 public key verifies the signed manifest. Exact size and
  SHA-256 are checked for every artifact.
- Downloads land in staging. Activation is atomic, incomplete data stays
  inactive, retry can reuse valid staged files, and a failed reinstall preserves
  the previously active pack.
- Active and staged files request complete-until-first-user-authentication file
  protection and are excluded from backup. Models can be deleted or reinstalled
  without deleting a profile.

The active root implements `ModelPackProviding.installedRootURL()`. The local
engine rechecks that root and fails closed if the pack, tokenizer, evidence
corpus, or inference output is unavailable or invalid.

## Verify from Terminal

```sh
xcodebuild \
  -project PaceBackiOS.xcodeproj \
  -scheme PaceBackiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Safety boundary

- The iOS app provides deterministic, age-filtered CDC danger-sign guidance without AI.
- Profiles use an alias and age band; each profile file is encrypted with its own AES-GCM key stored in the Keychain.
- Creating any pediatric profile requires LocalAuthentication. Under-13 profiles remain caregiver-operated, and teen administrative controls stay behind the guardian gate.
- After model setup, the iOS `LocalEvidenceEngine` performs local age-filtered hybrid retrieval and MiniLM reranking. Results are extractive, source-linked passages with direct locators—not medically verified answers.
- Before setup, or after any model/corpus/inference failure, the `AIEngine` fails closed and shows no fabricated answer or citation. Deterministic danger-sign guidance remains available.
- The project is an unvalidated research prototype that supports, but does not replace, professional care.

Bundle identifier: `org.paceback.research.ios`

Minimum deployment target: iOS 18.0
