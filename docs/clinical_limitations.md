# Clinical and scientific limitations

Status: current native macOS wellbeing prototype, reviewed 2026-09-02.

PaceBack is a consumer research prototype, not a medical device, diagnostic, treatment, crisis service, or substitute for professional care. It does not determine whether a person is calm, anxious, depressed, traumatized, safe, or “normal.”

## What the evidence does and does not establish

Public guidance supports offering general self-care options such as grounding, comfortable movement, relaxation practices, priorities, and social connection. Reviews also suggest that some brief casual games may change momentary stress or affect for some groups. This establishes plausible design inputs only.

It does not validate:

- PaceBack's exact wording, sequence, interface, duration, age gates, or two games;
- the claim that a person will feel calmer or improve their mental health;
- the four-value check-out as a clinical outcome measure;
- the deterministic activity ordering parameters;
- pediatric suitability, cultural fit, accessibility, or safety for an individual; or
- superiority over another wellbeing app.

The current ranker is fixed code, not a trained mental-health model. It uses only explicit closed activity receipts, retains at most 120 events, applies a 30-day decay, clamps activity signals to -0.40 through 0.40, and pauses an exact activity for 24 hours after a “Less settled” receipt. After that pause, its negative preference signal continues to decay rather than being erased. Those are product parameters without clinical calibration.

## Activity cautions

- Breathing is optional, gentle, unforced, and contains no holds. Stop for dizziness, shortness of breath, or increased distress.
- Muscle release must not involve straining or painful, injured, spasm-prone, or recently operated areas.
- Movement stays within the person's usual comfortable range and stops for pain, dizziness, chest pain, or unusual breathlessness.
- Grounding/orienting can feel unhelpful or worsening for some people; eyes may remain open and stopping is always valid.
- Trusted-person contact is user-selected; PaceBack cannot establish that a recipient is safe or available.
- Play is optional distraction. Neither Harbor Tiles nor Harbor Path is a therapeutic game or mental-state test.

## Evidence required for stronger outcome claims

Before saying that PaceBack reduces stress, calms users, or improves wellbeing, complete independent clinical and pediatric review, representative accessibility and usability work, a preregistered comparative study using validated outcomes, adverse-event review, privacy/security assessment, and reproducible source-matched release verification.

Current engineering checks prove only that declared software rules execute in the tested build. They do not prove health benefit.
