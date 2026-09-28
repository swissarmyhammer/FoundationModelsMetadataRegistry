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
- actor: claude-code
  id: 01m3mn3ht3j700d67dzb7x0hgh
  text: |-
    ### commit — changed
    - evidence: bf058c6 feat(searcher): add SharedCatalogEmbedding for two searchers
    - next: run review
  timestamp: 2026-09-28T18:40:45.891259+00:00
- actor: claude-code
  id: 01m3mnfm1encsrbfmgqfdyvp7c
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (bf058c6). 1 finding (1 confirmed, 2 refuted). Sources/FoundationModelsMetadataRegistry/SharedCatalogEmbedding.swift:118 duplication/duplication.
    - next: Extract the embed-and-merge logic into one shared function. Make embeddingPendingEntries() and catchUpEmbeddings() use it. Then do the review again.
  timestamp: 2026-09-28T18:47:21.390424+00:00
- actor: claude-code
  id: 01m3mnfwn94vw3smev86rjcz8c
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 157 passed, 0 failed, 0 skipped, 0 warnings; swiftlint 0; swiftformat 0/72
    - commit: bf058c6
    - review: findings — Sources/FoundationModelsMetadataRegistry/SharedCatalogEmbedding.swift:118
  timestamp: 2026-09-28T18:47:30.217410+00:00
- actor: claude-code
  id: 01m3mnjmdaz4rfxtvngz222eef
  text: |-
    Picked up the review finding again. Research:
    - Four sites do "get the pending entries, stop when there are none, report `.embedCatchUp`, call `checkedVectors`, stop when it fails, merge": `SharedCatalogEmbedding.embeddingPendingEntries`, `MetadataIndex.build`, `runFirstSearchCatchUp` (MetadataSearcher+FirstSearchCatchUp.swift) with `catchUpEmbeddings`, and `runReloadEmbedLoop` (MetadataSearcher+ReloadEmbedLoop.swift) with `catchUpEmbeddings`.
    - The merge target is different: build and the shared embed merge into the index that they embedded; the searcher merges into its live `index` after the `await`, because an `update(items:)` can change it.
    - `build` does not report `.embedCatchUp`. The other three sites do.
    Plan: add `MetadataIndex.embedPendingEntries(with:onDiagnostic:) async -> EmbeddedBatch?` and `EmbeddedBatch.merged(into:)`. All four sites use it. `catchUpEmbeddings` loses its `ids`/`texts`/`embeddedFrom` parameters and reads the pending entries itself. `IncrementalBaseline.textsToEmbed` then has no reader, so I remove it.
  timestamp: 2026-09-28T18:49:00.074663+00:00
- actor: claude-code
  id: 01m3mp1xyzv8rv8314jmw8v3pe
  text: |-
    Fix for the duplication finding landed (TDD: I wrote 4 tests in the new EmbedPendingEntriesTests.swift first; they did not compile because `embedPendingEntries` did not exist).
    - New `MetadataIndex.embedPendingEntries(with:onDiagnostic:) async -> EmbeddedBatch?`: it reads the pending entries, stops when there are none, reports `.embedCatchUp`, embeds in one batch, and checks the vector count. The default `onDiagnostic` reports nothing, so `build` keeps its old behavior (no `.embedCatchUp`).
    - New `MetadataIndex.EmbeddedBatch` (ids, vectors, source) with `merged(into:)`, the one caller of the hash-checked `mergingEmbeddings`.
    - All catalog embeds now use these two functions: `MetadataIndex.build`, `SharedCatalogEmbedding.embeddedBatch()` (was `embeddedIndex()`; it now keeps the batch, not a merged index), `MetadataSearcher.catchUpEmbeddings(with:)` (lost its `ids`/`texts`/`embeddedFrom` parameters), and the shared path of `runFirstSearchCatchUp`.
    - Removed code with no callers after the change: `TextEmbedding.checkedVectors(for:)`, `MetadataIndex.storedEmbeddings()`, `IncrementalBaseline.textsToEmbed`, `SharedCatalogEmbedding.embeddingPendingEntries`, `MetadataSearcher.mergeSharedEmbeddings(from:)`, and the pending guards in `runReloadEmbedLoop` and `runFirstSearchCatchUp`.
    - Note: `swift build`/`swift test` print SwiftPM "failed loading cached manifest ... disk I/O error" warnings. These come from the SwiftPM manifest cache, not from the code. The compiler gave 0 warnings.
  timestamp: 2026-09-28T18:57:21.375161+00:00
- actor: claude-code
  id: 01m3mp215ndrh7zjethnjhd4bn
  text: |-
    ### implement — changed
    - evidence: `swift test` 161 tests in 17 suites passed, 0 compiler warnings; swiftlint 0 violations in 73 files; `swiftformat . --lint` 0/73 files. Files: Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex+Embedding.swift, Sources/FoundationModelsMetadataRegistry/SharedCatalogEmbedding.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+FirstSearchCatchUp.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+ReloadEmbedLoop.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Tests/FoundationModelsMetadataRegistryTests/EmbedPendingEntriesTests.swift (new)
    - next: /review
  timestamp: 2026-09-28T18:57:24.661122+00:00
- actor: claude-code
  id: 01m3mp8fzx7yn17pkqhv080186
  text: |-
    ### test — green
    - evidence: `swift test` — 161 tests passed, 0 failed, 0 skipped, in 17 suites. `swiftlint` — 0 violations in 73 files. `swiftformat . --lint` — 0 of 73 files need a change, 2 files skipped by rule.
    - no code fix was needed. all tests, lint, and format checks were clean on this run.
    - note on the "failed loading cached manifest ... disk I/O error" warning from the last run: it does persist, and it is not caused by this package's code. `sqlite3 ~/Library/Caches/org.swift.swiftpm/manifests/manifest.db "PRAGMA integrity_check;"` fails with "disk I/O error (10)" even run from an unrelated directory, with no swift process active. this proves the shared, global SwiftPM manifest cache database is corrupt in this environment. a `swift package plugin --list` run reproduced the same "failed loading cached manifest" and "failed storing manifest" warnings for every package in the graph, including this one. this is an environment fault in the local manifest cache, not a defect in this repository's code. it did not fail the build or the tests; SwiftPM falls back to reparsing the manifest when the cache read fails. a person or CI job can clear it by deleting `~/Library/Caches/org.swift.swiftpm/manifests` to force a fresh cache.
    - next: none. board can move this task forward.
  timestamp: 2026-09-28T19:00:56.445905+00:00
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

## Review Findings (2026-09-28 13:41)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsMetadataRegistry/SharedCatalogEmbedding.swift:118` `duplication/duplication` — `embeddingPendingEntries()` duplicates the embed-and-merge pattern already in `build()` (MetadataIndex+Embedding.swift:64) and `catchUpEmbeddings()` (MetadataSearcher+Search.swift:132). All three get pending embeddings, guard, report diagnostic, call `checkedVectors`, guard result, and merge. Extract the embed-and-merge logic into a shared function. Both `embeddingPendingEntries()` and `catchUpEmbeddings()` can delegate to it, parameterizing how the pending entries are obtained and how the result is returned.
