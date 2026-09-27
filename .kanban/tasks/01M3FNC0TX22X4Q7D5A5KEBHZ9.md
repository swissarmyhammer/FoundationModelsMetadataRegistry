---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3hdcg4afwwtxaw5t5swz4ff
  text: |-
    Research done. The Extras API (resolved checkout, ModelPool/) gives all that the task needs:
    - The embed protocol on the container is `PooledEmbedding` (`dimension`, `embed(texts:)`).
    - The handle is `PooledEmbedder(hold:)`. It keeps the `ModelHold`, and sends each `embed(texts:)` call through `hold.queue` (the one `GenerationQueue` of the key). It finds the container through `as? any PooledEmbedding` only, and throws `PooledEmbedderError.notAnEmbedding` when the container does not conform.
    - `ModelPool.init()` is public (a private pool for each test). `ModelPool.isResident(_:)` is public (the residency query).
    - `ModelPool.acquire(_:footprintBytes:sessionBytes:loader:)` needs the bytes of the weights. Thus the new searcher initializer also takes `footprintBytes`. An embedding hold opens no session, so `sessionBytes` is 0.
    - The key is `ModelPoolKey(ref:role: .embedding)`. The loader protocol is `PooledModelLoader` (`load(_:)`, `evict(_:)`).
    - Eviction runs in a detached admission job after the last hold goes. The pool removes the entry before it calls `loader.evict`, so a test can wait for the evict call and then read `isResident`.
    README.md does not list the initializers. It only says "Add a `TextEmbedding` conformer". I will add one short sentence there about the pooled initializer.
  timestamp: 2026-09-27T12:28:07.178769+00:00
- actor: claude-code
  id: 01m3hdr0wjmc69jdppkx9vk5b4
  text: |-
    Implementation landed.
    - New `PooledTextEmbedding` (public struct, `TextEmbedding`): keeps one `PooledEmbedder`, forwards `embed(_:)` to `embed(texts:)` of the handle. No cast, no second queue. `static func acquire(_:footprintBytes:loader:from:)` acquires the `.embedding` key with `sessionBytes` 0.
    - New `MetadataSearcher.init(items:mode:weights:embeddingModel:footprintBytes:loader:pool:selection:onDiagnostic:) async throws` (pool defaults to `ModelPool.shared`). The three current initializers do not change.
    - Tests: `PooledTextEmbeddingTests` (the four tests of the card), with stubs in `TestSupport/PooledModelStubs.swift`. Each test uses its own `ModelPool()`.
    - Check of the concurrency test: with a temporary change that calls the container directly (no queue), `concurrentUpdatesRunOneAtATime` failed (`maximumCallsInFlight` > 1). With the real code it passes. The temporary change is reverted.
    - Docs: plan.md §5 (the pooled embedder paragraph) and §12 (the fourth initializer), both refer to decision #16 and say that the first loader of a key wins. README.md: one sentence.
    - Environment note: the disk was full (about 100 MB free), and `swift build` failed with I/O error 28. The cause was nested `.build` directories inside `.build/checkouts/*` (for example `swift-distributed-tracing/Samples/*/.build/index-build`, about 9 GB), which an index build makes. I deleted those nested build directories (regenerable, not source). A process still writes there, so the disk can fill again.

    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Tests/FoundationModelsMetadataRegistryTests/PooledTextEmbeddingTests.swift, Tests/FoundationModelsMetadataRegistryTests/TestSupport/PooledModelStubs.swift, plan.md, README.md
    - next: /test
  timestamp: 2026-09-27T12:34:24.786758+00:00
- actor: claude-code
  id: 01m3hdtn53m13ptgqsec4t9x54
  text: |-
    ### test — green
    - evidence: `swift test` — 137 tests in 14 suites passed, 0 failed, 0 skipped; `swift build --build-tests` after touch of all sources — 0 warnings; `swiftformat --lint` — 0/54 files; `swiftlint lint` — 0 violations. SwiftFormat first found `unusedArguments` in `PooledModelStubs.swift` (the `load`/`evict` parameters); fixed with `_`.
    - next: /commit
  timestamp: 2026-09-27T12:35:51.075356+00:00
- actor: claude-code
  id: 01m3hdtxb614tszm3d0tay9nec
  text: |-
    ### commit — changed
    - evidence: 73cc532 feat(searcher): add PooledTextEmbedding and a pooled embedding ModelRef initializer
    - next: /review 01M3FNC0TX22X4Q7D5A5KEBHZ9 HEAD~1..HEAD
  timestamp: 2026-09-27T12:35:59.462641+00:00
- actor: claude-code
  id: 01m3hdyngap9ctwx408gq1mm8s
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings, 0 confirmed, 0 refuted (7 attempted, 0 failed); 4 Swift files reviewed; README.md and plan.md matched no validator; .kanban/ excluded by .reviewignore. The task moved review → done.
    - next: none

    ### finish iteration 1 — clean
    - implement: changed (PooledTextEmbedding.swift, MetadataSearcher.swift, PooledTextEmbeddingTests.swift, TestSupport/PooledModelStubs.swift, plan.md, README.md)
    - test: green (swift test — 137 passed, 0 failed, 0 skipped; 0 warnings; swiftformat and swiftlint clean)
    - commit: 73cc532
    - review: clean (0 findings); task in done
  timestamp: 2026-09-27T12:38:02.506203+00:00
depends_on:
- 01M3FNBKG7PTTAGCQNN3CRNN69
position_column: done
position_ordinal: a680
title: Add PooledTextEmbedding and a MetadataSearcher initializer that takes a pooled embedding ModelRef
---
## Goal
Let a `MetadataSearcher` get its embedder from the process-wide `ModelPool` by `ModelRef`. Two searchers with the same `ModelRef` must share one loaded model, and all embed calls for that model must go through one queue.

## Context
- The embedder enters as `any TextEmbedding` on `MetadataSearcher` (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:73`, initializers at `:211` and `:257`) and on `MetadataIndex.build` (`Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex+Embedding.swift:64`).
- Problem now: two searchers built with two embedders can hold two copies of one model. Concurrent `update(items:)` calls each start an embed call at the same time (`MetadataSearcher+Search.swift:46`, `catchUpEmbeddings` at `:114`). There is no backpressure.
- Extras gives a pool actor keyed by `ModelRef` + role (one load and one hold for each key), and an embedder handle (`dimension`, `embed(texts:)`) that sends each call through the queue of the model. The handle keeps the hold, so the model stays resident while the handle exists. The pool, the queue and the handle are in the core `FoundationModelsExtras` product.
- IMPORTANT: the pool uses the loader of the FIRST caller of a key. If the router (or a different application loader) loads the embedding key first, the registry gets the container that THAT loader made, not the container of the registry's loader. Thus `PooledTextEmbedding` must use only the Extras embed protocol on the container (the Extras task `01M3FN95AM98RJSTCVQ8G1Z7KE` names this protocol). It must not cast the container to a registry type or to the type of its own loader.
- Do not change the `AgentSession` side (`SelectionConfig.sessionSource`). A caller that gives a router session already gets a pooled model through the router.
- The MLX loader does not come into this package. The caller gives the loader. (The router tasks will make the router's live loader public, so that an application can give it to the registry.)

## Blocked by (other board)
- Extras task `01M3FN95AM98RJSTCVQ8G1Z7KE` (the pool actor and the embed protocol on the container).
- Extras task `01M3FN9BTXNPBWE6VVBQEXK4W2` (the pool entry owns the work queue, and the embedder handle).
Both must be done and pushed before this task starts. The Extras API must also give a public `ModelPool.init()` (a private pool for each test) and a public way to ask if a key is resident.

## Steps
1. Add `PooledTextEmbedding`, a `TextEmbedding` adapter over the pooled embedder handle. It keeps the handle, so the searcher keeps the hold. It forwards `embed(_:)` to the handle, through the Extras embed protocol only. Do not cast to a concrete container type. Do not add a second queue in the registry.
2. Add a `MetadataSearcher` initializer that takes an embedding `ModelRef`, a loader, and a pool (default `ModelPool.shared`). It acquires the handle from the pool and wraps it in `PooledTextEmbedding`. Keep the other parameters (`mode`, `weights`, `selection`, `onDiagnostic`) the same as the current async initializer.
3. Update `plan.md` §5 (the `TextEmbedding` seam) and §12 (Public API) to show the new initializer. Refer to decision #16. Say that the first loader of a key wins.
4. Add a short note to `README.md` if it lists the initializers.

## Acceptance criteria
- [ ] Two searchers with the same `ModelRef` cause exactly one call to the loader.
- [ ] Concurrent `update(items:)` calls on one searcher, and on two searchers that share one `ModelRef`, reach the model one at a time.
- [ ] When both searchers are released, the pool evicts the model.
- [ ] When a different loader loaded the key first, the searcher embeds through that container, with no cast.
- [ ] The current initializers that take `any TextEmbedding` do not change.

## Tests
Use stub loaders and stub embedders. Do not load a real model. Use a private pool instance in each test (`ModelPool.init()`), not `ModelPool.shared`, so that tests do not share state.
- `twoSearchersShareOneLoad`: build two searchers with one `ModelRef`; the stub loader counts one load.
- `concurrentUpdatesRunOneAtATime`: the stub embedder records the maximum number of calls in flight; start many `update(items:)` calls at the same time; the maximum is 1.
- `releasingBothSearchersEvictsTheModel`: release both searchers; the pool reports that the key is not resident.
- `firstLoaderWinsAndSearcherEmbedsThroughProtocol`: stub loader A acquires the key first and keeps its hold. Then build a searcher for the same key with stub loader B. Expect: loader B is never called; the searcher's embed calls reach the container of loader A (loader A's container records the texts); the searcher gets correct vectors.
- Run `swift test`. All tests must pass.