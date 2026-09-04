# Competitive and open-source wellbeing app review

Status: desk research refreshed 2026-09-03. This is design input, not a clinical comparison, endorsement, or superiority claim. Repository activity, features, and licenses can change; verify them again before reuse.

## What was reviewed

The review asked a practical question: when attention is low during an ordinary stressful moment, how quickly can someone start, stop, switch modality, preserve privacy, or reach a person?

| Reference | What its public product or repository emphasizes | What Softer uses or deliberately does differently |
|---|---|---|
| [Medito](https://github.com/meditohq/medito-app) | Mature Flutter meditation library; free without ads or required signup; AGPL application code, separately licensed content, network/Firebase production configuration | Softer is a much smaller native Mac tool for an immediate choice, not a meditation catalog or content service. It ships no remote content stack and copies neither Medito code nor content. |
| [Breathly](https://github.com/mmazzarolo/breathly-app) | Focused React Native breath-training app with a technique picker and guided exercise; MPL-2.0 code | Softer treats breathing as only one optional modality. It uses comfortable, unforced breaths, no holds or performance target, with age restrictions and explicit stop cautions. |
| [The Baseline](https://github.com/anrinion/baseline) | MIT-licensed, modular Android self-care for food, movement, sleep, medication, mental-state tools, and one-button grounding; explicitly rejects scores, streaks, social features, and most history | Its low-pressure, configurable-module philosophy is close to Softer. Softer is narrower: no medication or health tracking, a six-choice in-the-moment need map, two finite games, encrypted multi-profile age/role boundaries, and persistent human support. |
| [Aware / 29k](https://github.com/29ki/29k) | Non-profit, co-created mental-health course/content platform; AGPL software and CC-BY-SA content | Softer does not reproduce a course, community, or therapeutic program. It offers short interactions and points outward when more support is needed. |
| [OpenCouch](https://github.com/whanyu1212/OpenCouch) | Pre-beta AGPL AI chat companion with durable conversational memory, multi-turn exercises, backend services, and safety routing | Softer deliberately has no chatbot, simulated relationship, free-text memory, cloud account, or crisis classifier. Recommendations use only explicit closed choices; support is static and model-independent. |
| [if-me](https://github.com/ifmeorg/ifme) | AGPL web community for sharing mental-health experiences with trusted allies | Softer reduces the friction of contacting a person but never hosts a social network, stores messages, selects a recipient, or claims the contact is safe or available. |
| [MindEase](https://github.com/bikram73/MindEase_Stress_Relief_App) | Student web project combining breathing, mood journaling, self-assessment, personalized stress insights, and mini-games | Softer rejects stress scores, diagnostic quizzes, inferred insights, open journals, and endless score loops. Harbor Tiles and Harbor Path are session-only, finite, scoreless, and not treated as measurements. |
| [Game Zone](https://github.com/akanksha-87977/game-zone) | Public stress-relief web app with an immediate “Relax Now” route, seven activities, progress, history, and streak surfaces | Softer uses the valuable immediate-entry pattern but deliberately hides secondary choices until requested and excludes progress and streak pressure. Its first screen offers one activity plus one-click finite play. |
| [Finch](https://finchcare.com/) | Commercial companion-led self-care and gamified goal engagement | Softer uses warmth and clear actions but no dependent pet, currency, shop, streak, level, or maintenance guilt. |
| [How We Feel](https://howwefeel.org/) | Emotion-led check-in and strategy discovery | Softer makes need-labeling optional, uses neutral non-diagnostic choices, and stores only an optional four-value activity checkout rather than a mood diary. |
| [#SelfCare](https://truluv.ai/selfcare) | Scoreless sensory interaction rather than productivity competition | Softer also rejects winning pressure, but both original games have visible finite endings and persistent Stop and Skip controls. |
| [Block Blast](https://www.blockblast.com/) | Familiar direct shape-placement grammar, line clears, scores, combos, and an endless replay loop | Harbor Tiles keeps only direct placement and clear fit feedback. Its authored irregular 4 x 4 coves, fixed pieces, nine total placements, harbor objective, and no-clearing/no-score rules are materially different. |

No third-party source, artwork, text, exercise script, brand element, or trade dress was copied into Softer. License labels above describe the references; Softer's own Apache-2.0 license does not override their terms.

## Softer's actual differentiation

Softer is not distinguished by inventing a new clinical intervention. Its product-level combination is:

1. a no-save guest start and one obvious action before a library;
2. six plain-language, non-diagnostic needs mapped to different modalities;
3. nine bounded options, including active and gentle finite play;
4. Stop and Skip treated as valid outcomes, with no engagement economy;
5. deterministic, visible adaptation from explicit closed check-outs only;
6. no chatbot, journal ingestion, passive sensing, mood score, account, ads, or analytics;
7. encrypted local profiles, a memory-only guest fallback, and age/role availability boundaries; and
8. persistent static human-support routes that never depend on inference.

## Gaps the comparison exposed

- Medito and Aware have much deeper reviewed content; Softer has breadth of modality but little depth.
- Breathly provides richer sensory pacing; Softer has no guided audio and still needs VoiceOver user testing.
- Baseline allows users to enable or disable modules; Softer should evaluate explicit favorites or hiding unwanted modalities, without turning preference into diagnosis.
- Mature products have localization; Softer is English-only and its U.S. call/text actions require prominent regional labeling.
- Softer has engineering verification but no representative-user study, clinical/pediatric review, comparative usability study, or outcome trial.

## Safe conclusion

The repository comparison supports product choices, not effectiveness. Softer can accurately claim that it offers a narrower, more private and less retention-driven interaction model than the reviewed feature-heavy examples. It cannot claim that users will be calmer, that its games improve mental health, or that it is better than another app until those outcomes are directly studied.
