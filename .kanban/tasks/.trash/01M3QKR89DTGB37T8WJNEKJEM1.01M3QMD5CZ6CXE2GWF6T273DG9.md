---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8480'
title: 'Registry: take PooledEmbedder directly; delete PooledTextEmbedding and the embeddingModel initializer'
---
**Wait for:** the FoundationModelsRanker task "Depend on Extras, drop TextEmbedding.dimension, async session factory, pooled conformances" (01M3QKX8AA2V38S7ET93PV40YM, Ranker board) must be done and pushed first. It waits for the FoundationModelsExtras tasks 01M3QKWR26HVCVNR8KWWRQCCDQ and 01M3QKWR7DD80PS72KHT2H3THF (Extras board).

#model-pool #embedding

## What
After the Ranker makes `PooledEmbedder` a `TextEmbedding`, the registry needs no adapter:

```swift
let searcher = MetadataSearcher(items: catalog,
                                embedder: PooledEmbedder("mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"))
// sync init; the first search embeds the catalog (existing catch-up path)
```

- Delete `Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift`.
- Delete `MetadataSearcher.init(items:mode:weights:embeddingModel:footprintBytes:loader:pool:selection:onDiagnostic:)` in `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` (around line 253).
- Make sure a synchronous `MetadataSearcher(items:mode:weights:embedder:selection:onDiagnostic:)` exists and embeds at the first search (the catch-up path of `MetadataSearcher+FirstSearchCatchUp.swift`). If only the async init takes `embedder:`, add the synchronous one and document it as the default.
- Remove `dimension` from the test doubles (`TestSupport/FakeEmbedder.swift`, `TestSupport/GatedEmbedder.swift`, and the others that declare it).
- Delete `Tests/.../PooledTextEmbeddingTests.swift` and `TestSupport/PooledModelStubs.swift`, or change them to test a searcher with a `PooledEmbedder` on an injected Extras test loader.
- `README.md`: the paragraph that names `init(items:embeddingModel:footprintBytes:loader:)` now shows `PooledEmbedder("…")`.
- Update the Ranker and Extras pins (`Package.resolved`).

## Acceptance Criteria
- [ ] `PooledTextEmbedding` and the `embeddingModel:` initializer no longer exist.
- [ ] `MetadataSearcher(items:, embedder: PooledEmbedder("…"))` compiles synchronously and the first search reports cosine signals.
- [ ] Two searchers with the same embedder name share one resident model.
- [ ] No test double declares `dimension`.

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/EmbeddingTests.swift` (or a new `PooledEmbedderSearchTests.swift`): a searcher with a `PooledEmbedder` on an Extras test loader embeds at the first search; two searchers share one load.
- [ ] `IntegrationTests/`: one real test with `PooledEmbedder("mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")` where the cosine signal ranks a paraphrase.
- [ ] `swift test` passes (all suites).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.