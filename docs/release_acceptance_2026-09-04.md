# Softer 0.4.0 release acceptance — 2026-09-04

This record separates packaged-app behavior from wellbeing outcomes. Engineering
verification does not establish that Softer improves mental wellbeing.

## Packaged-app walkthrough

The signed `build/Softer.app` bundle was launched and exercised on macOS at
the standard desktop window size.

| Journey | Observed result |
|---|---|
| Rename and compatibility | PASS: the menu bar, sidebar, boundaries, About screen, and package display Softer; the app loaded the encrypted profile created under the former name |
| Calm entry | PASS: one starting activity, its reason, Harbor Tiles, alternatives, Stop, and static support were visible |
| Standard activity | PASS: Notice the room opened, began at step 1 of 3, and returned through Stop without a checkout |
| Gentle breathing | PASS: the visual pacer ran; pace changed; shape-only wording toggled; Pause changed to Resume; Stop returned without a checkout |
| Harbor Tiles | PASS: the board rendered above the fold with multiple available opening fits; placement, on-request hint, and Undo visibly changed the state as intended |
| Play choice | PASS: Harbor Tiles and Harbor Path appeared as separate active- and gentle-focus choices with explicit finite, scoreless boundaries |
| Support | PASS: U.S.-specific 988/911 labels, international support, trusted-person, and licensed-professional controls rendered; no external destination was invoked |
| About | PASS: Softer 0.4.0 and the unvalidated research-prototype boundary rendered |
| Runtime network check | PASS at observation time: `lsof` reported no active Internet socket for the running Softer process |
| Submission images | PASS: Calm, Play, Harbor Tiles, and Gentle breathing were captured with the profile sidebar hidden and visually inspected |

## Automated and package gates

- `make verify`: PASS, including all 58 behavioral checks, native compilation,
  the static-site contract, and JavaScript syntax.
- Universal arm64/x86_64 package: PASS.
- Minimum operating system in both slices: macOS 14.0.
- Extracted ZIP signature: PASS under strict deep verification.
- Package size: 11 MiB app; approximately 4.1 MiB ZIP.
- Signing: Apple Development with hardened runtime; not Developer ID notarized.

The app's exact activities and games remain unvalidated as mental-health
interventions. Representative-user accessibility testing, independent security
review, clinical review, Developer ID signing, and notarization remain outside
this hackathon release.
