# PaceBack submission site

This dependency-free static site tells PaceBack’s two-platform hackathon story: a native macOS research prototype with confirmed clinician-plan retrieval and a native iPhone research prototype whose local AI searches only bundled public evidence. Its visual direction is a **calm industrial editorial field guide**—warm paper, deep navy evidence surfaces, restrained amber safety marks, and a continuous evidence spine. The page avoids the usual centered-gradient hero and interchangeable card grid.

The site itself performs no analytics, tracking, external asset loading, or runtime network requests. Fonts, iconography, and all five simulator captures are local. Three ordinary HTTPS anchors lead to primary research/criteria pages only when a visitor selects them; the JavaScript does not call `fetch`, XHR, WebSocket, EventSource, or beacon APIs.

## Platform boundary

- **macOS:** confirmed clinician-plan and age-scoped public evidence can enter the bounded local retrieval pipeline.
- **iPhone:** evidence search uses seven bundled curated public-source summaries only. It does not index clinician PDFs and does not perform clinician-plan RAG.
- Both are unvalidated research prototypes that support care and never diagnose, treat, predict recovery, prescribe, or issue school, work, driving, exercise, or sport clearance.

## iPhone trust setup shown on the site

The interactive Download → Verify → Ready offline receipt mirrors the implemented iOS contract:

- four frozen artifacts—BGE-small-en-v1.5 and MiniLM-L6-v2 ONNX weights plus their tokenizers;
- exact pack size `157,716,998` bytes (about 151 MiB);
- conservative working-space preflight of `357,919,352` bytes;
- user-selected foreground transfer from immutable-revision HTTPS URLs on allowlisted hosts;
- bundled Ed25519 public-key verification of the signed manifest;
- exact expected-size and SHA-256 verification for every artifact;
- staging followed by atomic activation, with partial packs kept inactive;
- no profile, health, symptom, query, or care-plan fields in artifact requests;
- offline inference after activation, with no cloud fallback.

The 388 ms local result shown on the page is one captured simulator execution—not a latency benchmark. Its source locator proves only excerpt-to-bundled-passage locatability, not medical correctness.

## Local visual evidence

The self-contained assets were copied from `output/ios/` without modification:

| Site asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `assets/paceback-ios-setup-top.jpg` | 62,333 | `c3faf850df2eb3c82733040d30d0fa98bc008d34c2a77acd8248df41395541df` |
| `assets/paceback-ios-setup-privacy.jpg` | 71,530 | `913b38e2d028257d659a24852373e72c8f6d6df5b871371ea01a1ec565207738` |
| `assets/paceback-ios-today.jpg` | 54,164 | `56b4d120cb11ced044c74cbde3e8032210901ba37807546f3166e5ed42b8faa8` |
| `assets/paceback-ios-evidence-query.jpg` | 73,620 | `23e6eb62515294c76ea62e855070c9de998f651dd74a774b79456ba8d4c7aa1d` |
| `assets/paceback-ios-evidence-result.jpg` | 64,567 | `1374d1cf6124eb75f44f52aa4b9c13281b47782b5d34052352542d2e9272c7c2` |

## Preview

From the PaceBack repository root, so local documentation links remain reachable:

```sh
python3 -m http.server 4173
```

Then open `http://127.0.0.1:4173/site/`.

## Validate

The structural checker uses only Python’s standard library. It checks local links and assets, the five simulator-capture hashes, an explicit allowlist for the three external design-input links, landmark and heading structure, duplicate IDs, image dimensions and size budgets, button contracts, truthfulness markers, responsive breakpoints, reduced-motion/forced-colors support, and absence of runtime network APIs.

```sh
python3 scripts/check_site.py
node --check app.js
```

Recommended real-browser pass: 375 × 812, 768 × 1024, 1024 × 768, and 1440 × 1000. Verify no horizontal overflow, keyboard order and focus rings, the skip link, route/persona/setup receipts, light and dark appearance, reduced motion, and 200% browser zoom.

## External design inputs, not validation

- [2019 JMIR Human Factors pediatric concussion app study](https://humanfactors.jmir.org/2019/2/e12135)
- [2025 JMIR Human Factors adult persistent-symptom app study](https://humanfactors.jmir.org/2025/1/e75323)
- [Official Hack for Humanity Summer 2026 rules and judging criteria](https://hack-for-humanity-summer-26.devpost.com/rules)

These sources shaped usability questions and proof priorities. They did not test PaceBack, its AI system, its safety, its accessibility, or health outcomes.

## Benchmark evidence boundary

The benchmark ledger is intentionally explicit. The frozen 100-item real-model v2 diagnostic uses the signed BGE + MiniLM pack and compares it with the frozen deterministic-fallback v3 run. Recall@20 / nDCG@20 / mean latency are `0.9767 / 0.954886 / 51.53 ms` and `0.9667 / 0.894214 / 7.09 ms`, respectively. Because both the dense retriever and reranker change together, the observed ranking difference cannot be attributed to either component individually. Human answer correctness, citation precision, and unsupported-claim rate remain unmeasured; promotion gates remain closed.

The linked source summaries are `full_real_models_unreviewed_unmeasured_2026-08-25-v2.summary.json` and `full_fallback_unreviewed_unmeasured_2026-08-25-v3.summary.json`; their metadata siblings contain frozen runtime-input hashes.
