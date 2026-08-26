# Benchmark result artifacts

`full_real_models_unreviewed_unmeasured_2026-08-25-v2.*` is the current primary
automated run. It activates the signed local BGE/MiniLM model pack and evaluates
each question inside a concrete selected profile, permitting only `allAges` plus
that profile's selected age band. The `age_ambiguous` label is a question
stratum; it is not an age-less runtime mode.

`full_fallback_unreviewed_unmeasured_2026-08-25-v3.*` is the matching deterministic
fallback comparison. BGE and MiniLM changed together, so the comparison cannot
attribute any difference to either component independently. The 60-item
`dev_real_models_unreviewed_unmeasured_2026-08-25.*` artifact is retained as a
pre-full-run development record.

The current pair records SHA-256 values for the product policy, evidence seed,
synthetic clinician plans, and engine Python source tree. Earlier artifacts are
retained as immutable provenance but are superseded: the original unsuffixed
fallback treated age-ambiguous questions as requiring an all-ages-only runtime
scope, and later pre-provenance runs did not freeze every runtime corpus input.

All files are unreviewed engineering outputs. Human correctness, citation
precision, unsupported-claim rate, clinical validity, and promotion gates remain
unmeasured or not evaluated. Retrieval/routing metrics do not establish medical
effectiveness.
