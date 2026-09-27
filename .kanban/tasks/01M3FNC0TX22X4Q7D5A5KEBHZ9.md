---
assignees:
- claude-code
depends_on:
- 01M3FNBKG7PTTAGCQNN3CRNN69
position_column: todo
position_ordinal: '8180'
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