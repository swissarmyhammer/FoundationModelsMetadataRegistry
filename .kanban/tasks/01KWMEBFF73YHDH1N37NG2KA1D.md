---
depends_on:
- 01KWMEB1EMNP2HMR8TJ3TRGW15
position_column: todo
position_ordinal: '8180'
title: Port retrieval primitives from CodeContextKit (Tokenizer, BM25, Trigram, RRF, Hit)
---
## What
Port five small self-contained files from `../CodeContextKit/Sources/CodeContextKit/Search/` into `Sources/FoundationModelsMetadataRegistry/Search/`, with attribution comments noting the CodeContextKit origin (which itself ports the Rust `swissarmyhammer-search` crate). Plan.md §5 "Port, don't depend":
- `Tokenizer.swift` (~133 lines) — tokenize + `charTrigrams`
- `BM25.swift` (~103 lines) — field-weighted BM25F-lite; keep the ×5 id-field / ×1 body weighting constants (rename `symbolPathFieldWeight` → id-field naming for this domain)
- `Trigram.swift` (~70 lines) — character-trigram Sørensen-Dice over canonicalized trigram sets
- `RRF.swift` (~67 lines) — `fuse` (k=60, 0-based ranks, absent-signal-contributes-nothing) + `normalize` (divide by best-possible: rank 0 in every weighted signal)
- `Hit.swift` (~70 lines) — `Hit(id, score, signals)` + `Signals(bm25, trigram, cosine)` explainability

Adapt namespaces/visibility for this package; no behavior changes.

## Acceptance Criteria
- [ ] All five files compile in the new package with attribution headers
- [ ] RRF semantics verified: k=60, 0-based ranks, absent signal contributes nothing (never zero-filled), normalized scores in [0,1]
- [ ] BM25 indexes two weighted fields (id ×5, block ×1)

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/RRFTests.swift` — table-driven: fusion ordering, absent-signal handling, normalization bounds, weight=0 exclusion
- [ ] `Tests/FoundationModelsMetadataRegistryTests/BM25Tests.swift` — field weighting: id-field match outranks body-only match
- [ ] `Tests/FoundationModelsMetadataRegistryTests/TrigramTests.swift` — typo tolerance ("kuberntes deploy" scores against "deploy-k8s"), dice bounds
- [ ] Run `swift test` — all pass, no GPU/Router needed

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.