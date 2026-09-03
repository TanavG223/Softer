# Contributing to PaceBack

PaceBack is a safety-conscious research prototype. Contributions should keep
its scope narrow, local-first, stoppable, and honest about what has and has not
been validated.

## Before opening a change

1. Read `docs/product_policy.md`, `docs/mental_wellbeing_evidence_contract.md`,
   and `docs/safety_privacy.md`.
2. Do not add diagnostic labels, inferred mental-state scores, engagement
   pressure, unreviewed pediatric activities, or efficacy claims.
3. Preserve the static Support path and the user's ability to stop, skip, or
   leave without recording an outcome.

## Local checks

The native app builds with Apple Command Line Tools; an Xcode project is not
required. Node.js is used only to syntax-check the static site JavaScript.

```sh
make verify
```

For a distributable universal app and versioned ZIP:

```sh
make package-macos
```

Describe the user-visible behavior you exercised manually. Passing engineering
checks must not be presented as evidence that PaceBack improves wellbeing.

## Pull requests

Keep changes focused, include tests for state or persistence changes, and call
out any claim, privacy, age-boundary, accessibility, or external-link impact.
Do not include real names, personal wellbeing data, credentials, or Keychain
material in fixtures or screenshots.
