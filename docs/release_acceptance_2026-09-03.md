# Release acceptance — 2026-09-03

This record separates behavior observed in the packaged Mac app from behavior
covered by the deterministic verification harness. A passing engineering check
does not establish that PaceBack improves mental wellbeing.

## Packaged-app walkthrough

The signed `build/PaceBack.app` bundle was launched and exercised on macOS at a
1,180 × 780 window size with an existing encrypted adult/self profile.

| Journey | Evidence | Result |
|---|---|---|
| Launch and saved workspace | Packaged app opened without a Keychain prompt and loaded the existing encrypted profile | PASS |
| Calm entry | The one-action Calm screen showed the fixed recommendation, its reason, Harbor Tiles, and progressive disclosure for other choices | PASS |
| Standard activity | “Notice the room” opened, began, displayed step 1 of 3, and returned through the always-available Stop action without saving a check-out | PASS |
| Gentle breathing | The visual pacer ran, changed to shape-only wording, paused, and exposed both in-content and persistent Stop controls | PASS |
| Harbor Tiles | The board rendered above the fold with two unmarked valid opening choices; one piece placed, Show a fit highlighted only on request, and Undo restored the opening state | PASS |
| Harbor Path | Skip advanced from waypoint 1 to waypoint 2 without ending the session | PASS |
| Support | The page displayed U.S.-specific 988/911 boundaries, the international option, and actionable Messages/Contacts controls; the 911 confirmation displayed Cancel plus a non-default destructive Open action and was cancelled | PASS; no external destination invoked |
| Privacy and About | Both destinations rendered the local-data contract, no-passive-inference boundary, mental-wellbeing definition, research boundary, and prototype status | PASS |
| Settings | Display, Accessibility, and Privacy panes rendered text scaling, comfortable spacing, reduced-motion, keyboard/drag alternatives, and privacy summaries | PASS; preferences were inspected without changing the saved configuration |
| Runtime network check | `lsof` found no active Internet socket for the running PaceBack process | PASS at the observation time |
| Temporary screenshot alias | A `PaceBack Demo` adult profile was created, used for screenshots, then deleted; the original encrypted profile remained selected and readable | PASS |
| Bundle | `codesign --verify --deep --strict` accepted the 11 MiB universal arm64/x86_64 package; both slices report a macOS 14.0 minimum | PASS |

Emergency call/text/chat actions, external research links, and a real
operating-system Keychain failure were not triggered during the walkthrough.
Those boundaries are not represented as manually exercised. A temporary
screenshot profile was deliberately deleted after its images were captured.

## Deterministic verification

`make verify` passed on the same source revision:

- 58 checks across all nine activity definitions and eligibility boundaries;
- deterministic recommendation, bounded positive/negative adaptation, decay, and cooldown behavior;
- Harbor Tiles finite completion, multiple opening fits in every cove, route variation, stop, and skip states;
- Harbor Path finite completion plus one-waypoint Skip, Stop, and age-specific presentation;
- support-route non-mutation;
- encrypted repository create/load/update/delete, real tampered-index rejection, and legacy schema migration;
- fail-closed workspace handling and memory-only guest behavior;
- native Swift build, static-site contract checks, and JavaScript syntax.

These are state-machine, persistence, and contract checks. They do not replace
representative-user testing, assistive-technology testing, security review,
distribution notarization, or an outcomes study.

## Release decision

No reproducible functional defect was found in the exercised release paths.
The current package is suitable for a hackathon prototype demonstration within
the limitations above. It is not evidence of clinical safety or effectiveness,
and the exact games and activities remain unvalidated as interventions.
