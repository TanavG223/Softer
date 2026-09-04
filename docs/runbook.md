# Native Mac runbook

Requirements: macOS 14+, Apple Command Line Tools, Swift 6.0+, and Node.js for the site JavaScript syntax check. Xcode and iOS simulators are not required.

```sh
make macos-test
make macos-build
make site-test
make verify
make package-macos
```

Inspect the final bundle:

```sh
codesign --verify --deep --strict build/Softer.app
codesign -d --entitlements :- build/Softer.app
otool -L build/Softer.app/Contents/MacOS/Softer
du -sh build/Softer.app
shasum -a 256 build/Softer.app/Contents/MacOS/Softer
open build/Softer.app
```

`make package-macos` also writes a versioned universal ZIP and prints its
SHA-256. Extract that ZIP to a temporary directory and verify the extracted
copy before publishing it; do not infer archive integrity from the source app.

Manual smoke path: create or select a synthetic profile; use the one-action start; choose each need; stop and skip an activity; verify Harbor Tiles Hint/Undo and finite completion; verify Harbor Path Skip/Stop and finite completion; submit each checkout; reset adaptation; open Support from normal and encrypted-workspace-error states; verify profile update/delete isolation.

Release checks: search current source/site/docs for injury-recovery, mobile, AI/model, efficacy, diagnostic, treatment, and “normal” claims; confirm only current Mac code ships; inventory files; record bundle size/hash/signing; visually inspect standard, narrow, increased-text, dark, keyboard, VoiceOver, and reduced-motion states.

Ad-hoc signing is for local demonstration only. Public distribution requires an appropriate Developer ID identity, hardened runtime, notarization, stapling, and testing on a clean Mac.
