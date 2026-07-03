---
depends_on:
- 01KWMEBFF73YHDH1N37NG2KA1D
position_column: todo
position_ordinal: '8280'
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
- [ ] A test-fixture type conforms to `SearchableMetadata` with only `id` + `renderBlock()` (summary default kicks in)
- [ ] `MetadataIndex` builds tokenized fields and trigram sets for a fixture catalog
- [ ] Duplicate id: first item retained, duplicate dropped, `.duplicateId` emitted through `onDiagnostic`
- [ ] `Match.block` is the catalog's rendered text by identity, never re-derived

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/CatalogTests.swift` — index build from fixtures, id-field vs block-field token separation, `renderSummaryBlock` default, duplicate-id first-wins + diagnostic capture via a recording `onDiagnostic`
- [ ] Run `swift test` — all pass, no GPU/Router

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.