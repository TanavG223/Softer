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
| Harbor Tiles | The intro opened, the game started, one named piece was selected, and a legal board position advanced the state from piece 1 to piece 2 | PASS |
| Harbor Path | The intro opened, all three waypoint actions advanced, the finite “PATH COMPLETE” state appeared, and Continue opened the optional check-out | PASS |
| Support | The static support page displayed U.S.-specific 988 and 911 boundaries, the international option, trusted-person guidance, and the non-monitoring disclaimer | PASS; external support actions deliberately not invoked |
| Privacy and About | Both destinations rendered the local-data contract, no-passive-inference boundary, mental-wellbeing definition, research boundary, and prototype status | PASS |
| Settings | Display, Accessibility, and Privacy panes rendered text scaling, comfortable spacing, reduced-motion, keyboard/drag alternatives, and privacy summaries | PASS; preferences were inspected without changing the saved configuration |
| Runtime network check | `lsof` found no active Internet socket for the running PaceBack process | PASS at the observation time |
| Bundle | `codesign --verify --deep --strict` accepted the 6.7 MiB package | PASS |

The emergency call/text/chat actions, external research links, destructive
profile deletion, and a real operating-system Keychain failure were not
triggered during the walkthrough. Doing so would create avoidable external or
user-data effects. Those boundaries are not represented as manually exercised.

## Deterministic verification

`make verify` passed on the same source revision:

- 50 checks across all nine activity definitions and eligibility boundaries;
- deterministic recommendation, bounded adaptation, and cooldown behavior;
- Harbor Tiles completion, legal-progress, Hint, Undo, stop, and skip states;
- Harbor Path finite completion, stop, skip, and age-specific presentation;
- support-route non-mutation;
- encrypted repository create/load/update/delete and legacy migration;
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
