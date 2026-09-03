# Mental-wellbeing and game research

Status: evidence and interaction rationale for Harbor Tiles and Harbor Path, updated 2026-08-27. This document does not establish that either game calms users, improves mental health, treats a condition, or changes a person’s mental status.

## Why include two forms of play

Some people do not want to meditate, label an emotion, write, or follow a body-focused exercise when stressed. PaceBack therefore offers two finite play options alongside screen-off, movement, connection, orientation, breathing, muscle release, and one-small-step activities:

- **Harbor Tiles — active focus:** a short spatial-fitting task for someone who wants more direct interaction.
- **Harbor Path — gentle focus:** a short visual scavenger path for someone who wants lower-demand interaction.

The product claim is deliberately narrow: either game **may offer a brief change of focus**, and either may feel unhelpful or uncomfortable. Neither is a validated coping skill, therapeutic game, attention assessment, exposure, neurofeedback, biofeedback, diagnostic test, or proof that someone is calmer.

## What the research does and does not support

Casual-game research is mixed and highly dependent on the game, task, population, comparison, dose, and outcome. The closest evidence does not validate PaceBack or justify a promise of calm:

| Source | Relevant finding | Limit for PaceBack |
|---|---|---|
| [Collins et al., 2019](https://mental.jmir.org/2019/7/e12853) | A study of the spatial puzzle Block! Hexa Puzzle reported higher energetic arousal in its laboratory sample (`n=45`), but no between-group recovery-experience difference; its field sample (`n=20`) showed no immediate arousal effect. | Small samples, a different game and dose, and mixed results. Increased energy is not the same as calm. |
| [Rupp et al., 2017](https://doi.org/10.1177/0018720817715360) | In a randomized laboratory study (`n=66`), 5.5 minutes of casual play improved engagement and affective restoration but not cognitive restoration. | A young sample and one different game do not establish an effect for Harbor Tiles or Harbor Path. |
| [Rankin et al., 2018](https://pubmed.ncbi.nlm.nih.gov/30265082/) | Adaptive Tetris increased flow and improved emotion during an uncertain waiting task (`n=309`). | The study did not directly reduce worry, used a specific stressor, and did not evaluate PaceBack. |
| [Desai et al.](https://pubmed.ncbi.nlm.nih.gov/40477391/) | In a comparison (`n=80`), both a casual game and a body-scan condition improved from pre- to post-session; the body-scan condition showed greater perceived-stress reduction. | Alternating allocation, undergraduates, a different 20-minute task, and no quiet control limit generalization. |
| [Pine et al., 2020](https://pubmed.ncbi.nlm.nih.gov/32053021/) | A systematic review found promising signals across a small set of casual-game studies. | The evidence was heterogeneous and does not establish that any casual game works for any individual. |
| [Pallavicini et al., 2021](https://pubmed.ncbi.nlm.nih.gov/34398795/) | A review of commercial-game studies found possible stress and anxiety effects in some settings. | Effects varied by game, population, dose, platform, and measure, with limited generalizability. |

This evidence supports testing optional, clearly bounded play as one modality. It does **not** support “this game will calm you,” “fix your mental state,” “reset your brain,” “regulate your nervous system,” or another efficacy claim. Representative-user, adverse-response, pediatric, accessibility, and outcome studies remain pending.

## Familiarity reference, not efficacy evidence

The official [Block Blast site](https://www.blockblast.com/) and [Google Play listing](https://play.google.com/store/apps/details?gl=US&id=com.block.juggle) demonstrate a contemporary interaction grammar: directly place shapes, judge spatial fit, and receive immediate feedback. PaceBack uses familiarity only as a design hypothesis to test; the listings do not prove that it reduces rule-learning effort or improves wellbeing.

Harbor Tiles retains only the broad ideas of direct placement, simple spatial fit, visible legal destinations, and immediate restrained feedback. It rejects Block Blast’s identity and retention mechanics. PaceBack does not use the Block Blast name, artwork, copy, trade dress, glossy cubes, 8 × 8 board, row or column clearing, score, combo, high-score chase, daily goals, rewards, revives, ads, in-app purchases, or endless replay.

## Harbor Tiles contract — active focus

1. A session contains three authored irregular coves, each represented on a 4 × 4 square-cell board with ten target cells.
2. Each cove has three fixed-orientation pieces containing 3, 3, and 4 cells.
3. Completion occurs after exactly nine placements: three pieces in each of three coves.
4. Every accepted placement is in bounds, nonoverlapping, and approved by a backtracking solver that proves all remaining pieces can still fit. Every accepted state therefore keeps at least one completion path.
5. A person can drag a piece or use the equivalent choose-piece then choose-destination path. Valid fits are not visually pre-marked; **Show a fit** and **Undo** remain available without penalty.
6. Completed pieces remain visible and one harbor light marks each completed cove. Nothing explodes, clears, drops, or disappears for reward.
7. There is no score, timer, accuracy label, speed target, losing, line clear, combo, streak, currency, rank, failure, punishment, surprise reward, daily goal, or endless loop.
8. Stop and Skip are valid terminal outcomes. Completion after the ninth placement does not prompt an endless restart.

The exact game has not been clinically validated. Its safe description is: **“Harbor Tiles may offer a brief, active change of focus. It may not feel helpful.”**

## Harbor Path contract — gentle focus

1. The objective is concrete: find gentle visual clues and guide a lantern home.
2. A session contains a finite one-to-three-waypoint path.
3. There is no score, timer, accuracy, speed, streak, currency, rank, failure, punishment, surprise reward, or endless loop.
4. Each interaction produces a predictable visual response. Sound is not required.
5. Skip, Stop, and screen-off are successful outcomes.
6. The game never labels performance or uses play behavior as a mental-health signal.
7. Completion may lead to the same optional four-choice activity check-out as other activities.

Its safe description is: **“Harbor Path may offer a brief, gentle change of focus. It may not feel helpful.”**

## Shared privacy and recommendation boundary

Board state, clues, invalid placements, hints, undo use, taps, speed, dwell time, completion behavior, sound, and haptics are session-local and are not stored or used for personalization. The only optional retained activity signal is the same closed check-out used elsewhere: activity ID, selected outcome, and timestamp within the declared encrypted bounded ledger.

Both games belong to the interactive-play modality family. A “Less settled” response cools down only that exact game for 24 hours and leaves a bounded negative preference signal that then decays. Any immediate activity alternative comes from a different modality rather than suggesting the other game; when none is eligible, the app offers no activity and keeps human support visible. No response triggers diagnosis, crisis inference, or a retry.

## Safety, age, and accessibility

- Ages 0–5 do not receive either on-screen game.
- Ages 6–12 may use either game only through a caregiver-operated, age-filtered profile pending pediatric review.
- The intro says to stop if distress, frustration, unreality, or feeling unsafe increases.
- Stop and Skip remain available throughout; screen-off remains a separate alternative.
- Motion is nonessential and respects Reduce Motion. There is no flashing, rapid movement, camera, microphone, reaction-time target, required sound, or required haptic feedback.
- Content must remain understandable at large Dynamic Type sizes, with semantic labels, deterministic focus, adequate targets, sufficient contrast, and state conveyed by text, icon, outline, or pattern rather than color alone.
- Dragging is never required. Apple’s [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility) informs the native control design, and [WCAG 2.5.7](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html) requires a single-pointer alternative to dragging.

These are design safeguards, not proof of accessibility, pediatric suitability, clinical safety, or absence of harm. Physical-device and representative assistive-technology testing remain pending.

## Originality boundary

Harbor Tiles uses project-original authored coves, square sea-glass pieces, three-light harbor objective, patterns, copy, finite state, and solver-protected placement rules. Harbor Path uses a project-original lantern world, finite clue path, prompts, art, and copy. Neither game may adopt another game’s distinctive brand, trade dress, visual assets, text, progression, board, scoring, clearing, or reward system.

Any proposal to add rotation, generated levels, scores, lines, combos, leaderboards, achievements, a replay feed, daily goals, monetization, or another retention mechanic requires a new design, evidence, safety, accessibility, and originality review.

## Evaluation plan

Software verification should establish the exact finite states, Harbor Tiles’ completion-preserving placement invariant, functional tap and drag alternatives, Hint/Undo/auto-place behavior, Stop/Skip, age withholding, stable accessibility identifiers, Reduce Motion behavior, and absence of score/timer/losing/reward/restart paths.

Human evaluation should separately measure rule comprehension, time to exit, perceived pressure, visual discomfort, frustration, whether each ending feels clear, preference between active and gentle focus, and the proportion selecting “Less settled.” Any observed change must be reported as a scoped study result, not proof of treatment or general effectiveness.
