---
comments:
- actor: claude-code
  id: 01kwmv9rrpdw0rgb2ak4ephy6w
  text: 'Picked up by /finish scoped-batch loop (task 3 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T20:39:08.310551+00:00
- actor: claude-code
  id: 01kwmvwgr1cf5ndvshk1478y2r
  text: |-
    Implemented via TDD. Read Search/{Tokenizer,BM25,Trigram,RRF,Hit}.swift (prior task) and CodeContextKit's SearchCorpusSnapshot/SearchCode.swift as the precedent for how a two-field weighted index + BM25/trigram precomputation should be structured, then wrote Tests/FoundationModelsMetadataRegistryTests/CatalogTests.swift first (watched it fail to compile — missing SearchableMetadata/Match/MetadataIndex/MetadataDiagnostic types — before implementing).

    Created:
    - Sources/FoundationModelsMetadataRegistry/Catalog/SearchableMetadata.swift — protocol with id/renderBlock(), default renderSummaryBlock() = renderBlock()
    - Sources/FoundationModelsMetadataRegistry/Catalog/Match.swift — generic struct per plan.md §4 verbatim (id, block, score, signals: Signals?, item)
    - Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift — in-memory value-type index, entries keyed by id, BM25 field-weighted term frequency (id ×BM25.idFieldWeight, block ×BM25.blockFieldWeight, summed for tokens present in both fields), per-entry id/block trigram sets via Trigram.canonicalTrigramSet, embedding storage slot (nil, for the follow-on embedding task), duplicate-id first-wins policy emitting .duplicateId via onDiagnostic
    - Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift — MetadataDiagnostic enum (duplicateId, embeddingUnavailable, unknownSelectedId, retrievalCut, embedCatchUp) + MetadataDiagnostic.log(_:) default os.Logger conformer

    Ran the double-check agent (adversarial) against the diff: verdict REVISE on test-coverage grounds only (no functional bugs) — flagged missing coverage for (1) a token shared by both id and block fields (weight-summing), (2) 3-way duplicate ids (one diagnostic per dropped duplicate, not deduped by id), (3) empty catalog. Added all three tests. For the two correctness-bearing ones, did a red-green-red regression proof: temporarily broke the weight-summing (`=` instead of `+=`) and the duplicate-diagnostic-per-item behavior (added a "warn once per id" set) — confirmed each broke exactly the corresponding new test and no others, then restored.

    Final: `swift test` → 49/49 tests pass (4 suites: PackageTests, BM25Tests, RRFTests, TrigramTests, CatalogTests), exit 0, no warnings from our code. Left in `doing` per workflow — ready for /review.
  timestamp: 2026-07-03T20:49:22.689815+00:00
depends_on:
- 01KWMEBFF73YHDH1N37NG2KA1D
position_column: doing
position_ordinal: '80'
title: 'Catalog contract: SearchableMetadata, Match, MetadataIndex'
---
## What
Implement the catalog layer per plan.md §4, in `Sources/FoundationModelsMetadataRegistry/Catalog/`:
- `SearchableMetadata.swift` — `protocol SearchableMetadata: Sendable { var id: String; func renderBlock() -> String }` plus `renderSummaryBlock()` with default = `renderBlock()` (consumed by the selection tier for the session prefix — see selection tasks)
- `Match.swift` — `struct Match<Item: SearchableMetadata>: Sendable { id, block (verbatim from catalog), score ([0,1]; 1.0 for pure-selection), signals: Signals? (nil in pure-selection), item }`
- `MetadataIndex.swift` — in-memory only (plan.md §1/§5, decision #10: no persistence, no DB): entries keyed by id, tokenized two-field index (id ×5, block ×1), per-entry trigram sets, embedding storage slots (filled by the embedding task). Built from generic items; rebuildable.
- `Diagnostics.swift` — **the single shared diagnostics surface** all later tasks emit through: `enum MetadataDiagnostic: Sendable` with payload-carrying cases (`duplicateId(id:)`, `embeddingUnavailable`, `unknownSelectedId(id:)`, `retrievalCut(considered:kept:)`, `embedCatchUp(pending:total:)`) delivered via one `onDiagnostic: @Sendable (MetadataDiagnostic) -> Void` callback (Multitool's `onPrefilterCut` callback pattern generalized; default implementation logs). Later tasks add cases here rather than inventing parallel mechanisms.

Duplicate-id policy (definite, since `id` is the join key for grammar and lookup): **first item wins; the duplicate is dropped and surfaced as `.duplicateId`** — never a crash, never silent.

The package never interprets block contents — blocks are opaque text.

## Acceptance Criteria
- [x] A test-fixture type conforms to `SearchableMetadata` with only `id` + `renderBlock()` (summary default kicks in)
- [x] `MetadataIndex` builds tokenized fields and trigram sets for a fixture catalog
- [x] Duplicate id: first item retained, duplicate dropped, `.duplicateId` emitted through `onDiagnostic`
- [x] `Match.block` is the catalog's rendered text by identity, never re-derived

## Tests
- [x] `Tests/FoundationModelsMetadataRegistryTests/CatalogTests.swift` — index build from fixtures, id-field vs block-field token separation, `renderSummaryBlock` default, duplicate-id first-wins + diagnostic capture via a recording `onDiagnostic`
- [x] Run `swift test` — all pass, no GPU/Router

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.