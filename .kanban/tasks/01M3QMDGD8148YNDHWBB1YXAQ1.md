---
position_column: todo
position_ordinal: '80'
title: Remove dimension from the registry test doubles
---
**Wait for:** FoundationModelsRanker task 01M3QMD9KJ8T723R02085BEFYY ("Remove dimension from TextEmbedding") on the Ranker board: done and pushed.

## What
- `swift package update`, confirm the new Ranker revision.
- Remove `dimension` from each test double in `Tests/FoundationModelsMetadataRegistryTests/` that declares it (`TestSupport/FakeEmbedder.swift`, `TestSupport/GatedEmbedder.swift`, and the doubles in `EmbeddingTests`, `EmbeddingCatchUpTests`, `EmbedPendingEntriesTests`, `HotReload*Tests`, `SharedCatalogEmbeddingTests`, `RegistryMetricsTests`, `RegistryTracingTests`, `TelemetryContentSafetyTests`, `SearchableMetadataTextsTests`), and from `PooledTextEmbedding.dimension`.
- Each registry source that read an embedder `dimension` uses the length of a returned vector.

## Acceptance Criteria
- [ ] No registry source or test names an embedder `dimension`.
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `swift test` passes with no change of behavior.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool