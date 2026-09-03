# Evaluation protocol

Engineering checks establish software behavior, not a mental-health outcome.

Run `make verify`, then `make package-macos`. The verification harness must cover all nine activities, child/caregiver gates, deterministic ranking, feedback bounds and cooldowns, exact finite-game completion, Hint/Undo paths, static support behavior, workspace lockout, the no-save guest fallback, encrypted persistence, update/delete, and legacy Mac vault migration. The release executable must build using Command Line Tools only.

For the packaged app, verify the code signature, entitlements, linked libraries, bundle inventory, launch, onboarding or existing-profile state, navigation, both games, reduced motion, keyboard access, text scaling, and the encrypted-workspace failure screen. Record exact commands, app size, hash, and any unverified boundary in `provenance.md`.

Before effectiveness claims, a separate study would need a preregistered outcome, comparison condition, representative sample, adverse-event handling, validated measures, independent analysis, and appropriate ethics/privacy review. No such study has been completed.
