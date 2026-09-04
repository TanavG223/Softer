# Softer for macOS

Softer is a native SwiftUI mental-wellbeing prototype for macOS 14 or newer. The production target has no Python process, model pack, chatbot, server, account, analytics SDK, or required network service.

From the repository root:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools /usr/bin/swift run --package-path macos SofterVerification
DEVELOPER_DIR=/Library/Developer/CommandLineTools /usr/bin/swift build --package-path macos -c release --product Softer
make package-macos
```

`SofterVerification` is a dependency-free executable because the standalone Command Line Tools installation on this machine does not include XCTest or Swift Testing. It verifies the wellbeing catalog, age gates, deterministic recommendations, bounded feedback, both finite games, support isolation, fail-closed storage, Keychain/AES-GCM persistence, migration, and prohibited health claims.

The packaged app stores each profile in an authenticated encrypted envelope and keeps its key in macOS Keychain. If Keychain or the encrypted index cannot be read, the app shows an unavailable screen and will not silently create a replacement workspace.

This is not treatment, diagnosis, crisis monitoring, or proof of effectiveness. See `docs/clinical_limitations.md` and `docs/safety_privacy.md`.
