# Mental-wellbeing evidence contract

Status: product and claim contract for the current native macOS prototype, reviewed 2026-09-02. This is not clinical validation, a medical guideline, or evidence that Softer itself improves an outcome.

## Supported problem

Softer supports a narrow moment: **a person experiencing ordinary stress wants a small, optional way to feel a little steadier or decide what to do next**.

The [World Health Organization](https://www.who.int/news-room/questions-and-answers/item/stress) describes stress as worry or mental tension caused by a difficult situation. [NIMH](https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health) describes mental health as emotional, psychological, and social wellbeing and notes that self-care differs between people. The [CDC](https://www.cdc.gov/emotional-well-being/about/index.html) notes that emotional wellbeing does not mean never feeling sad or stressed.

Therefore Softer may say:

- “Try one short option.”
- “A little more settled.”
- “This may offer a brief change of focus.”
- “Different things work for different people.”
- “Stop, skip, or choose something else.”

Softer must not say or imply:

- “fix,” “cure,” “treat,” “prevent,” or “guarantee calm”;
- “return to normal,” “normalize your mental state,” or “recover”;
- “we detected anxiety/depression/trauma/stress”;
- “this activity is clinically proven for you”;
- “your score shows improvement or deterioration”; or
- that the app replaces a clinician, therapist, emergency service, trusted person, sleep, food, movement, medication, or another individual need.

## Activity contract

Evidence and public guidance inform the choice and cautious wording of modalities; they do not validate the exact Softer sequence, dose, interface, or outcome.

| Activity | Intended role | Required wording and stop rule | Prohibited interpretation |
|---|---|---|---|
| Notice the room | Eyes-open, outside-in orientation to reduce decision load | Offer one concrete visual, sound, or contact cue. Keep eyes open if preferred. Stop if distress, frustration, unreality, or feeling unsafe increases. | Not trauma treatment, dissociation treatment, or a guaranteed grounding response |
| Gentle breathing | One optional relaxation route | Breath stays gentle, comfortable, and unforced. No deep-breath command, breath hold, required count, or respiratory target. Stop with dizziness, light-headedness, shortness of breath, or feeling worse. | Not vagal regulation, panic treatment, oxygen training, or proof of calm |
| Soften and release | Release-first muscle relaxation | Never strain. Skip painful, injured, spasm-prone, or recently operated areas. Release-only is sufficient. | Not physical therapy, pain treatment, or a prescribed exercise |
| Small movement | Brief movement within a person’s usual range | Seated or standing choices; stop with pain, dizziness, chest pain, or unusual breathlessness. | Not an exercise prescription or fitness/medical clearance |
| Reach someone trusted | Reduce the friction of asking a person for company | User chooses recipient and content. A generic draft may open the system share sheet; Softer never selects or sends automatically. | Not monitoring, therapy, emergency dispatch, or proof the contact is safe/available |
| Screen-off pause | Lowest-stimulation exit | No countdown, completion requirement, alert, or required return. | Not avoidance treatment or evidence that screen use caused distress |
| One small step | Make the next ten minutes more controllable | Only safe, manageable actions; doing nothing is valid. | Not executive-function treatment, productivity scoring, or a prescribed priority |
| Harbor Tiles | Optional active-focus spatial distraction | Three authored irregular 4 × 4 square-cell coves; fixed 3-, 3-, and 4-cell pieces; exactly nine solver-approved placements; tap or drag with accessible auto-place, Hint, and Undo. No score, timer, losing, line clear, streak, reward, or endless loop. Stop and Skip are successful outcomes. | Not a therapeutic game, cognitive training, clinical intervention, attention test, mental-state measure, or proof of calm |
| Harbor Path | Optional predictable visual distraction | Finite path, static cues, no timer, score, failure, streak, currency, surprise reward, or endless loop. Stop and Skip are successful outcomes. | Not a therapeutic game, clinical intervention, attention test, or outcome measure |

Sources that inform this boundary include WHO’s [Doing What Matters in Times of Stress](https://www.who.int/publications/i/item/9789240003927), [NIMH self-care guidance](https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health), [CDC stress guidance](https://www.cdc.gov/mental-health/living-with/index.html), the UK NHS [breathing exercise](https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/), and the U.S. Department of Veterans Affairs [progressive muscle relaxation](https://www.va.gov/WHOLEHEALTHLIBRARY/tools/progressive-muscle-relaxation.asp). Source availability and wording require re-verification before public release.

Research on breathwork and games is heterogeneous. Promising group-level findings do not establish that Softer’s activities work for an individual. Representative game evidence includes a mixed-result study of a [spatial block puzzle](https://mental.jmir.org/2019/7/e12853), brief-casual-game studies of [recovery experience](https://doi.org/10.1177/0018720817715360), [flow during uncertain waiting](https://pubmed.ncbi.nlm.nih.gov/30265082/), and [casual play versus body scan](https://pubmed.ncbi.nlm.nih.gov/40477391/), plus reviews of [casual games](https://pubmed.ncbi.nlm.nih.gov/32053021/) and [commercial games](https://pubmed.ncbi.nlm.nih.gov/34398795/). None validates Harbor Tiles, Harbor Path, or an individual outcome. The product therefore uses optional, low-claim wording and an explicit “Less settled” path.

## Check-out and activity-ordering personalization contract

The activity check-out is optional and closed:

1. A little more settled
2. About the same
3. Less settled
4. Skip

It evaluates only the user’s experience of that activity in that moment. It is not a symptom scale, clinical outcome measure, mood score, safety assessment, or diagnostic label.

Wellbeing activity ordering may use only:

- selected non-diagnostic need ID;
- selected activity ID;
- optional check-out value; and
- timestamp needed for decay and cooldown.

Current mechanical bounds are 120 retained events, score clamping to `-0.40...0.40`, a 30-day half-life, and a 24-hour exact-activity cooldown after its latest “Less settled” outcome. These values are conservative product parameters, not medically calibrated thresholds. They need usability and harm-oriented review.

Activity ordering must never consume free text, questions, source searches, sensors, biometrics, typing, dwell time, notifications, contacts, share recipients, support actions, or inferred affect. It ranks already-available activities; it does not train or fine-tune BGE, MiniLM, or any other model.

## Less-settled and stop contract

If a person chooses “Less settled”:

1. stop the activity;
2. state that stopping was appropriate;
3. offer a different modality or no activity;
4. make trusted-person and urgent-help paths visible; and
5. remove only that exact activity from automatic suggestions for 24 hours, then retain a bounded negative preference signal that decays over 30 days.

Do not interpret the response as self-harm risk, notify a contact, begin a crisis flow automatically, or use it as evidence about mental health.

## Crisis and urgent-support contract

“Need help now?” is persistent and independent of the model, profile feedback, and personalization ledger.

- If someone may hurt themselves or someone else, or cannot stay safe, the U.S. route offers [988 call, text, and chat](https://988lifeline.org/).
- Immediate life-threatening danger routes to 911 or the nearest emergency department.
- People outside the United States receive a link to [Find A Helpline](https://findahelpline.com/).
- Minors are told to involve a trusted adult who can stay with them.

Softer is not a crisis service, does not monitor anyone, and cannot confirm that a call, text, share, or link was completed. Opening support is never logged as feedback or used for personalization. See [SAMHSA’s 988 overview](https://www.samhsa.gov/find-help/988) and [NIMH’s help guidance](https://www.nimh.nih.gov/health/find-help).

## Age contract

Under-13 use is caregiver-operated. The app may offer short caregiver-led orientation, comfortable movement, trusted connection, screen-off, and one-small-step choices. Self-directed breathing, muscle-release content, and both on-screen games are withheld for ages 0–5. Ages 6–12 may use either game only through the caregiver-operated profile, while breathing and muscle-release content remain withheld. These are product safety boundaries pending pediatric review, not age-specific efficacy claims.

## Evidence required before stronger claims

Before saying Softer “helps,” “reduces stress,” “calms,” or “improves wellbeing” as an observed product effect, complete:

- independent clinical/domain review of activity wording and stop rules;
- representative-user task testing, including people using VoiceOver, large text, Reduce Motion, and cognitive accessibility supports;
- a predeclared protocol with an appropriate comparator and validated outcome measures;
- adverse-event and “Less settled” review;
- pediatric review before expanding child-directed activities;
- privacy and security assessment; and
- reproducible source-matched software verification.

Until then, the honest claim is: **Softer offers short, optional, evidence-informed wellbeing activities and makes it easier to choose, stop, switch, or seek human support.**
