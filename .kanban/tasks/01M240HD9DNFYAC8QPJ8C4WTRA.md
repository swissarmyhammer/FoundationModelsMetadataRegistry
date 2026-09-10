---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m242a4z6fwpsq42hf1ckqmd2
  text: |-
    ### Research

    - `MetadataSearcher.search(intent:limit:)` goes to `retrievalSearch` or `Self.selectionSearch`. Both paths call `computeCosineScores`, which emits `.embeddingUnavailable` when no catalog entry has an embedding. The selection tier's `retrievalRanking` closure reads the `snapshot` lock, so a merge into `selectionTier?.snapshot` reaches it.
    - `update(items:)` owns the catch-up now: `MetadataIndex.incrementalBaseline` gives the pending ids and texts, then `embedder.embed`, then `MetadataIndex.mergingEmbeddings(ids:vectors:embeddedFrom:into:)` merges into the live `index` and refreshes the tier snapshot. The first-search catch-up must reuse that tail, not copy it.
    - `MetadataIndex` has no accessor for "entries with no embedding". `incrementalBaseline` collects them in its loop. A new `pendingEmbeddings()` accessor on the index can serve both the loop and the first search.
    - Actor reentrancy: a concurrent search during an in-flight `update(items:)` embed must stay keyword-only (test `concurrentSearchDuringUpdateServesKeywordOnlyForTheNotYetEmbeddedItem` gates every embed call and awaits the search before it releases the gate). So the first-search catch-up must not run when `update(items:)` has already taken the catch-up. `update(items:)` will mark the first-search catch-up as done.
    - Two concurrent first searches: the second search must wait for the first search's embed, or it would emit `.embeddingUnavailable`. A stored single-flight `Task` on the actor gives that.
    - Test doubles: `FakeEmbedder` counts texts only, `GatedEmbedder` counts nothing. The card asks for a recording embedder. Plan: `EmbedCallCounter` records each batch; both doubles expose `embeddedBatches`.
    - No `.swift-format`, `.swiftformat`, or `.swiftlint` config exists in the repo. No format tool run is possible; the code follows the style of the files around it.
    - No ARCHITECTURE.md exists.
    - All Examples build a searcher with `init(items:...)`; none uses `init(index:...)` with an embedder. IntegrationTests build with no embedder. No caller outside the unit tests changes behavior.
  timestamp: 2026-09-09T21:48:46.438991+00:00
- actor: claude-code
  id: 01m24z792nsp1hjbqpbeeap1tb
  text: |-
    ### implement — changed
    - files: `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`, `Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift`, `Tests/FoundationModelsMetadataRegistryTests/EmbeddingTests.swift`, `Tests/FoundationModelsMetadataRegistryTests/TestSupport/FakeEmbedder.swift`, `Tests/FoundationModelsMetadataRegistryTests/TestSupport/GatedEmbedder.swift`, `plan.md`
    - TDD: RED — six new tests in `EmbeddingTests` (the `First-search embed catch-up` section) failed for the correct cause: the first search embedded nothing, emitted `.embeddingUnavailable`, and ranked with cosine `0.0`. GREEN — all pass.
    - Design: `MetadataSearcher` gets a private `FirstSearchCatchUp` enum (`.pending` / `.running(Task)` / `.done`). `search(intent:limit:)` awaits `catchUpEmbeddingsBeforeFirstSearch()` before it selects a tier. The first search creates one stored `Task`; a search that arrives while it runs awaits the same task, so two concurrent first searches embed the catalog one time. The initializer sets `.done` when no embedder is configured, so a keyword-only searcher is unchanged. `update(items:)` sets `.done` at its start: a reload owns the catch-up, and a search in its interim window stays keyword-only (the existing gated hot-reload test proves this; a first-search embed there would deadlock the test).
    - Reuse: the merge tail of `update(items:)` moved to `catchUpEmbeddings(ids:texts:embeddedFrom:with:)`, shared by both catch-ups. `MetadataIndex.pendingEmbeddings()` gives the pending ids and texts; `incrementalBaseline` now reads them from that accessor instead of its own loop.
    - Test doubles: `EmbedCallCounter` records each batch; `FakeEmbedder` and `GatedEmbedder` expose `embeddedBatches`. `EmbedGate.waitForStart()` is now cancellation-aware, because a `.timeLimit` cannot end a test that waits in a plain continuation; the concurrent test carries `.timeLimit(.minutes(1))` so a searcher that never starts the catch-up fails the test instead of hanging the run.
    - Environment: the local `.build` state was from Jul 24 and pinned a `FoundationModelsRouter` revision that does not compile against the installed Xcode 27 beta SDK (`Transcript.CustomSegment` is gone). `Package.resolved` is gitignored, so `swift package update` re-resolved to the single `FoundationModelsRanker` main dependency the manifest describes. No tracked file changed by that step. `swift package reset` was not run.
    - `swift test` — 121 tests in 12 suites, passed. `swift build --build-tests` — 0 warnings. `swift build --package-path IntegrationTests --build-tests` — build complete.
    - Format: no `.swift-format`, `.swiftformat`, or `.swiftlint` config exists in the repo, so no format tool ran.
    - Consumer note (card criterion 4): FoundationModelsMultitool can delete `CatalogSearcher` and `CatalogEmbedding` and pass its embedder to `MetadataSearcher.init(index:mode:weights:embedder:selection:onDiagnostic:)` directly. The first `search` embeds the catalog one time; `update(items:)` keeps its role for reloads.
    - next: `/review`
  timestamp: 2026-09-10T06:14:01.045441+00:00
- actor: claude-code
  id: 01m24z87f7jyqw60j518jcwxr0
  text: |-
    ### test — green
    - evidence: `swift test` — 121 tests, 12 suites, all passed. 0 failures, 0 warnings, 0 skipped.
    - next: proceed to review.
  timestamp: 2026-09-10T06:14:32.167948+00:00
position_column: doing
position_ordinal: '80'
title: 'MetadataSearcher: embed the catalog at the first search when the searcher was built synchronously with an embedder'
---
## What

`MetadataSearcher` has two initializers that take an embedder. The `async` one (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` lines 179-195 in the checkout of 2026-09-09) embeds every block in `MetadataIndex.build`. The synchronous one, `init(index:mode:weights:embedder:selection:onDiagnostic:)` (lines 217-234), takes an unembedded index and an embedder. After the synchronous one, `search` ranks keyword-only and emits `.embeddingUnavailable` ("no embedder configured or catalog not yet embedded") on every call until a caller runs `update(items:)` (lines 346-395), which does the embed catch-up.

A consumer that must build its searcher synchronously cannot use the async initializer. FoundationModelsMultitool is such a consumer: `RegistryBundle.init` is synchronous and `makeSessionToolsAndStaging` must start no task. It now wraps the searcher in `CatalogSearcher` (`Sources/FoundationModelsMultitool/Discovery/CatalogSearcher.swift`), whose actor calls `update(items:)` one time before the first search. That is a copy of a behavior the searcher can own (card ^zqz1zan, direction part 4).

## What to change

`search(intent:limit:)` on a searcher built with an embedder and with pending embeddings runs the catch-up itself, one time, before it ranks. Then a searcher built synchronously with an embedder never reports `.embeddingUnavailable`, and the consumer can delete `CatalogSearcher` and `CatalogEmbedding`.

## Acceptance Criteria

- [ ] A searcher built with `init(index:mode:weights:embedder:selection:onDiagnostic:)` over an unembedded index embeds every block at its first `search`, and only then.
- [ ] Such a searcher emits no `.embeddingUnavailable` diagnostic; the `embedding catch-up: N/N item(s) pending` diagnostic is emitted one time.
- [ ] A searcher built with no embedder is unchanged.
- [ ] Tell the consumer: FoundationModelsMultitool can then delete `CatalogSearcher`/`CatalogEmbedding` and pass the embedder to the searcher directly.

## Tests

- [ ] Unit test with a recording `TextEmbedding`: the first search embeds `[every block]` then `[query]`; the second search embeds `[query]` only.
- [ ] Unit test: two concurrent first searches embed the catalog one time.
