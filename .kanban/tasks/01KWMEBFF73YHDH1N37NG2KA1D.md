---
comments:
- actor: claude-code
  id: 01kwmted7tx0ysanke0tn52gmz
  text: 'Picked up by /finish scoped-batch loop (iteration 1, task 2 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T20:24:11.770437+00:00
- actor: claude-code
  id: 01kwmtst46s7dcmnh8r977nxes
  text: |-
    Implementation complete via TDD.

    Ported 5 files from ../CodeContextKit/Sources/CodeContextKit/Search/ into Sources/FoundationModelsMetadataRegistry/Search/: Tokenizer.swift, Trigram.swift, RRF.swift, Hit.swift, BM25.swift. Each has an attribution header comment noting CodeContextKit origin (which itself ports the Rust swissarmyhammer-search crate). No behavior changes except the required rename: BM25.symbolPathFieldWeight -> BM25.idFieldWeight and BM25.bodyFieldWeight -> BM25.blockFieldWeight, matching this domain's SearchableMetadata id/block (renderBlock()) fields per plan.md's Catalog contract section.

    Wrote failing tests first (RED verified: compile errors "cannot find 'Trigram'/'Tokenizer'/etc in scope" before Source files existed), then added the Source files to make them pass (GREEN):
    - Tests/FoundationModelsMetadataRegistryTests/RRFTests.swift — table-driven fusion-ordering cases plus focused tests for k=60 default, 0-based ranks, absent-signal-contributes-nothing, weight=0 exclusion, normalization bounds (rank-0-everywhere == 1.0, all-zero-weights == 0.0, general [0,1] bounds), and Hit/Signals plumbing.
    - Tests/FoundationModelsMetadataRegistryTests/BM25Tests.swift — hand-computed Okapi BM25 reference checks plus the id-field (x5) vs block-field (x1) weighting acceptance test and a constants-match-spec test.
    - Tests/FoundationModelsMetadataRegistryTests/TrigramTests.swift — Tokenizer tests (camelCase/snake_case/kebab-case/digit-boundary/duplicates) since Trigram canonicalizes through Tokenizer, plus Dice bounds and the "kuberntes deploy" vs "deploy-k8s" typo/delimiter-style tolerance case (hand-verified Dice = 8/22 ≈ 0.364 from the shared "deploy" word's 4 trigrams).

    swift build: clean (only a pre-existing unrelated mlx-swift bundle warning, not from this change).
    swift test: 34 tests in 3 suites (BM25Tests, RRFTests, TrigramTests) + the existing PackageTests.moduleImportsAndBuilds, all green, 0 failures.

    Left in `doing` per /implement workflow — ready for /review.
  timestamp: 2026-07-03T20:30:25.414440+00:00
depends_on:
- 01KWMEB1EMNP2HMR8TJ3TRGW15
position_column: doing
position_ordinal: '80'
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