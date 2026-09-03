# Architecture

Status: current native macOS wellbeing prototype.

```text
SwiftUI app
  ├─ AppStore: profiles, navigation, recommendations, activity state
  ├─ Wellbeing catalog: nine bounded activities
  ├─ Harbor Tiles / Harbor Path: finite, scoreless game state
  ├─ ProfileRepository: AES-GCM envelopes + Keychain keys
  └─ Support Hub: static user-selected system links
```

The recommendation service is deterministic. It starts from an age-appropriate order, uses only the person’s selected need and optional three-choice checkout, retains a bounded event ledger, clamps adjustments, and applies cooldowns after “less settled.” It never consumes free text, sensors, game performance, support actions, or inferred mood.

There is no runtime backend, helper, downloaded model, or intentional app network request. External support links leave the app only after an explicit click.

Storage fails closed: an unreadable encrypted index is an error, not an empty workspace. Profile writes create a new immutable generation before atomically replacing the authenticated index pointer. Deletion removes keys before encrypted files so residual ciphertext is not usable.
