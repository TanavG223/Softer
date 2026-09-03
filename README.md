# PaceBack

PaceBack is a native macOS mental-wellbeing prototype for ordinary stressful moments when choosing what to do next feels difficult. It offers a no-save guest start, one immediate option, six plain-language needs, nine short activities, two finite games, and static routes to human support.

It does **not** diagnose a mental state, treat a disorder, promise calm, return anyone to a predefined “normal,” or replace professional or emergency care. Its exact activities, games, interface, and recommendation parameters have not been clinically validated.

## What the Mac app does

- **Calm:** one obvious starting option or an optional six-choice need picker.
- **Start without setup:** teen, adult, and older-adult users can enter a temporary guest session without an alias or Keychain write. Nothing from that session survives after it ends.
- **Toolkit:** orientation, comfortable breathing, muscle release, movement, trusted connection, screen-off pause, and one small step.
- **Play:** Harbor Tiles for direct spatial focus and Harbor Path for gentler noticing. Both are scoreless, finite, session-only, and always stoppable.
- **Explicit adaptation:** an optional four-value check-out can reorder eligible activities. No free text, sensors, game behavior, dwell time, or support action is used.
- **Local privacy:** saved aliases, age/role boundaries, and check-outs are stored in AES-GCM encrypted profile generations with keys in macOS Keychain. An unreadable workspace fails closed instead of appearing empty, while a clearly labeled memory-only guest path keeps safe activities available without touching the locked data.
- **Support:** U.S.-labeled 988/911 actions, an international directory, trusted-person prompts, and professional-care prompts remain static and model-independent.

The production target contains no Python helper, downloaded model, chatbot, account system, analytics SDK, ad SDK, or network service.

## Current Mac experience

![PaceBack Calm screen with one gentle activity and one-click Harbor Tiles](output/submission/paceback-calm.png)

![PaceBack Play screen with two finite focus choices](output/submission/paceback-play.png)

![Harbor Tiles running with no score, timer, or losing state](output/submission/paceback-harbor-tiles.png)

## Build and verify without Xcode

PaceBack uses the standalone Apple Command Line Tools:

```sh
make macos-test
make macos-build
make package-macos
```

`make macos-test` runs the dependency-free `PaceBackVerification` executable. Its 50 checks cover the bounded catalogs, age gates, deterministic recommendation/cooldown behavior, finite game state machines, support non-mutation, encrypted repository round trips and deletion, the fail-closed workspace path, and the memory-only guest fallback. The historical XCTest files are not part of the current package because the standalone Command Line Tools installation on this machine does not include XCTest.

The packaged application is written to `build/PaceBack.app`. Packaging automatically uses an installed Apple Development identity so existing Keychain access survives rebuilds, with ad-hoc signing only as a fallback. Developer ID distribution signing and notarization are separate release gates.

## Read before making claims

- [Mental-wellbeing evidence contract](docs/mental_wellbeing_evidence_contract.md)
- [Competitive and open-source app comparison](docs/competitive_ux_research.md)
- [Game evidence boundary](docs/mental_wellbeing_game_research.md)
- [Safety and privacy](docs/safety_privacy.md)
- [Clinical and scientific limitations](docs/clinical_limitations.md)
- [Verification provenance](docs/provenance.md)

The defensible product claim is: **PaceBack makes a small set of optional, evidence-informed activities easy to choose, stop, switch, or leave for human support.** Whether PaceBack itself reduces stress or improves wellbeing remains untested.
