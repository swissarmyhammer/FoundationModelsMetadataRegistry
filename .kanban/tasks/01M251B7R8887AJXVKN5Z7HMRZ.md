---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'MetadataSearcher: move to SelectionTier.init(catalog:config:onDiagnostic:) and drop candidateLimit from the tests'
---
## What

The FoundationModelsRanker package changed. `SelectionTier` now sends one prompt that picks. It runs no retrieval before the prompt and no retrieval after the answer. Three uses in this package must change before the ranker dependency moves to that revision.

The ranker commits, on its branch `main`:

- `aac493a` — one prompt that picks. No retrieval steps.
- `dbda1ae` — new words for the default preamble.

## The three uses

1. `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` line 332 calls `SelectionTier(catalog:config:onDiagnostic:retrievalRanking:)`. That initializer is deprecated and it ignores the closure. Move the call to `SelectionTier(catalog:config:onDiagnostic:)`. Delete the `rankEntireCatalog` ranking that fills the closure, and the weights and the embedder that only that ranking uses. Correct the doc comments at lines 92, 287, 294, 310, 312, 315, 630 and 633, which tell about the closure and about `candidateLimit`.
2. `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` gives `candidateLimit:` to `SelectionConfig` at lines 60, 89 and 106. That parameter does not exist now. `HotReloadTests.swift` does the same. Remove the parameter. Write the over-budget tests again for the new design: the tier divides the catalog into runs, every id gets to one prompt, and no `.retrievalCut` is sent.
3. `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift` lines 21, 22, 49 and 76 map `RankDiagnostic.retrievalCut`. The ranker keeps that case, but it never sends it. Keep the mapping, or remove it with this package's own `.retrievalCut` case.

## Also

The ranker changed the words of `String.selectionDefault`. A measurement on the system model and on `mlx-community/Qwen3-4B-4bit` gave 30 of 30 answers with the new words, against 27 of 30 and 0 of 30 with the old words. If this package gives its own preamble only to correct the old default, it can use the default now.

## Where this card came from

The ranker board holds the same record as card `^6kd63xc`. This card is the copy that this package's own board can work.

## Acceptance Criteria

- [ ] `MetadataSearcher` builds the tier with `SelectionTier(catalog:config:onDiagnostic:)`.
- [ ] No test gives `candidateLimit:` to `SelectionConfig`.
- [ ] `swift build` and `swift test` pass against the ranker `main`, with no deprecation warning.