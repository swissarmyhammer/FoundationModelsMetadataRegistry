---
comments:
- actor: claude-code
  id: 01m3mm50s66kjr0jkfr78xpe4k
  text: |-
    Research done. Findings:
    - `MetadataSearcher.init(index:...)` is the synchronous seam. It sets `firstSearchCatchUp = .pending` when an embedder is given. `runFirstSearchCatchUp()` (in MetadataSearcher+Search.swift) embeds `index.pendingEmbeddings()` through `catchUpEmbeddings(ids:texts:embeddedFrom:with:)` and merges with the hash-checked `MetadataIndex.mergingEmbeddings(ids:vectors:embeddedFrom:into:)`.
    - `update(items:)` sets `firstSearchCatchUp = .done`, so it takes over the catch-up. A merge from a shared embed after a reload is safe because the merge is hash-checked.
    - The "embed, then check the vector count" guard occurs in `MetadataIndex.build` and in `catchUpEmbeddings`. The shared embed needs it a third time, so I extract one helper.
    - `MetadataIndex` and `SearchableMetadata` are `Sendable`. `TextEmbedding` comes from FoundationModelsRanker.
    Plan: add `public actor SharedCatalogEmbedding<Item>` (sync init from index + embedder + onDiagnostic, single-flight embed stored as a `Task`), and `MetadataSearcher.init(sharing:mode:weights:selection:onDiagnostic:)`. At the first search, the searcher awaits the shared embed and merges its vectors into its own `index`.
  timestamp: 2026-09-28T18:24:05.414918+00:00
- actor: claude-code
  id: 01m3mmwbjwz53hp5kgsc4wyygp
  text: |-
    Implementation landed (TDD: I wrote 6 tests first, and 4 of them failed for the correct cause against a stub `init(sharing:)` that ran its own catch-up; parity and update isolation passed as guards).
    - New `public actor SharedCatalogEmbedding<Item>` (Sources/.../SharedCatalogEmbedding.swift). Its init is synchronous: `index`, `embedder`, `onDiagnostic`. Its `embeddedIndex()` is single flight through a stored `Task` in a `CatalogEmbed` enum (`pending` / `started`). A failed embed returns the index with no change, and the task is never run again. The shared value reports `.embedCatchUp` one time through its own `onDiagnostic`.
    - New `public extension MetadataSearcher { init(sharing:mode:weights:selection:onDiagnostic:) }`. A new internal designated init takes `sharedEmbedding:`, and the public `init(index:...)` now delegates to it (the signature is the same).
    - The first-search catch-up moved to the new `MetadataSearcher+FirstSearchCatchUp.swift` (the same pattern as `+ReloadEmbedLoop.swift`). With a shared value, the first search awaits `embeddedIndex()` and merges `storedEmbeddings()` through the hash-checked `mergingEmbeddings`.
    - Extracted `TextEmbedding.checkedVectors(for:)` (embed + count check). `MetadataIndex.build`, `catchUpEmbeddings`, and the shared embed use it, so the guard is not copied a third time.
    - Discovery: with the new code, swiftlint `file_length` (400) failed on MetadataSearcher.swift and MetadataSearcher+Search.swift. The moves above fixed it. swiftlint and swiftformat `--lint` are now clean.
    - Note: `update(items:)` on a sharing searcher embeds its own reload through the shared embedder. The shared value is not used for reloads.
  timestamp: 2026-09-28T18:36:50.140647+00:00
- actor: claude-code
  id: 01m3mmwepkwj2krsv5gqyrt9mg
  text: |-
    ### implement — changed
    - evidence: `swift test` 157 tests in 16 suites passed, 0 warnings; swiftlint 0, swiftformat --lint 0/49. Files: Sources/FoundationModelsMetadataRegistry/SharedCatalogEmbedding.swift (new), Sources/FoundationModelsMetadataRegistry/MetadataSearcher+FirstSearchCatchUp.swift (new), Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex+Embedding.swift, Tests/FoundationModelsMetadataRegistryTests/SharedCatalogEmbeddingTests.swift (new)
    - next: /review
  timestamp: 2026-09-28T18:36:53.331938+00:00
- actor: claude-code
  id: 01m3mn2d7a3daf6j7vr08a2mg7
  text: |-
    ### test — green
    - evidence: `swift test` — 157 tests passed, 0 failed, 0 skipped, 0 warnings. `swiftformat . --lint` — 0 of 72 files need a change. `swiftlint` — 0 rule breaks, 0 serious rule breaks, in 72 files.
    - next: The code can go to review.
  timestamp: 2026-09-28T18:40:08.426716+00:00
position_column: doing
position_ordinal: '80'
title: Let two synchronously built MetadataSearchers share one catalog embed
---
## What
A consumer (FoundationModelsMultitool `RegistryBundle`) builds two `MetadataSearcher<Item>` over the same items and the same embedder, with different `Weights` and `SearchMode`. It must build them synchronously, so it uses `init(index:mode:weights:embedder:selection:onDiagnostic:)` over an unembedded `MetadataIndex`. Each searcher then runs its own `FirstSearchCatchUp` and embeds the whole catalog. The catalog is embedded two times for each bundle, and again after each registry swap. (`PooledTextEmbedding` keeps no vector cache, so it does not help.)

Add a public, synchronous API that lets two or more searchers share one first-search embed of one index. One possible shape (the implementer can choose a different shape with the same effect):
- A public reference type, for example `public final class SharedCatalogEmbedding<Item>: Sendable` (or an `actor`), made synchronously from a `MetadataIndex<Item>` and an embedder. It runs the catch-up one time (single flight), and gives the embedded vectors to each searcher that uses it.
- A new synchronous `MetadataSearcher.init(sharing: SharedCatalogEmbedding<Item>, mode:weights:selection:onDiagnostic:)`. At its first search, the searcher awaits the shared catch-up and merges the shared vectors into its own `index` (through the existing hash-checked `mergingEmbeddings`), in place of a catch-up of its own.

Keep these behaviors the same as now: the catalog embed occurs at the first search of any sharing searcher, not at init; a failed embed leaves each sharing searcher keyword-only and marks the catch-up done; `update(items:)` on one searcher does not change the other searchers.

Requested by the FoundationModelsMultitool session on 2026-09-28 (added by the router session, because no registry session was running).

## Acceptance Criteria
- [x] Two searchers made synchronously through the new API over one index call the embedder over the catalog one time in total, at the first search of either searcher.
- [x] Two concurrent first searches (one on each searcher) cause one catalog embed call, not two.
- [x] The rankings of each searcher are the same as the rankings of a searcher made with `init(index:...)` with the same weights and mode.
- [x] A catalog embed that fails leaves both searchers answering keyword-only, with no second catalog embed for the life of the shared value.

## Tests
- [x] A counting stub `TextEmbedding` records each batch. Two sharing searchers, one search each: exactly one catalog batch plus one query batch per search.
- [x] The concurrency case with `async let` on the two searchers: one catalog batch.
- [x] Ranking parity with the per-searcher catch-up for three fixed queries and two different `Weights`.
- [x] The failing-embedder case.
- [x] Run `swift test`. Expected result: all tests pass, and the output shows the full count of tests run.

## Consumer
FoundationModelsMultitool task ^57bedj6 (01M3FPF7XG14A2MKW8457BEDJ6) waits on this card. After it lands, that task changes `RegistryBundle.init(registry:shape:)` to build one shared embedding and give it to `hintSearcher` and `discoverySearcher`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #cross-repo #embedding