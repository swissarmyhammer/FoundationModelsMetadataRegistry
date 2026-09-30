---
depends_on:
- 01M3QMDGD8148YNDHWBB1YXAQ1
position_column: todo
position_ordinal: '8180'
title: Take PooledEmbedder directly; delete PooledTextEmbedding and the embeddingModel initializer
---
**Wait for:** FoundationModelsRanker task 01M3QMDA82DXPZNEASMVXTP31M ("Depend on Extras; PooledSession is an AgentSession and PooledEmbedder is a TextEmbedding") on the Ranker board: done and pushed.

## What
```swift
let searcher = MetadataSearcher(items: catalog,
                                embedder: PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"))
// sync init; the first search embeds the catalog (existing catch-up path)
```

- `swift package update`, confirm the new Ranker and Extras revisions.
- Delete `Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift` and `MetadataSearcher.init(items:mode:weights:embeddingModel:footprintBytes:loader:pool:selection:onDiagnostic:)` (`MetadataSearcher.swift` ~line 253).
- A synchronous `MetadataSearcher(items:mode:weights:embedder:selection:onDiagnostic:)` embeds at the first search (`MetadataSearcher+FirstSearchCatchUp.swift`). If only the async init takes `embedder:`, add the synchronous one.
- Delete `Tests/.../PooledTextEmbeddingTests.swift` and `TestSupport/PooledModelStubs.swift`; new tests use `PooledEmbedder(ref: "…", pool: ModelPool(loader: fake))`.
- `.github/workflows/ci.yml` and `Tests/.../CIWorkflowTests.swift`: MLX is now in the graph through Extras; give the shared workflow `integration-metallib-glob` for the real-model test; update the workflow comment and the test that pins "no MLX".
- `README.md`: the `init(items:embeddingModel:footprintBytes:loader:)` paragraph shows `PooledEmbedder(ref: "…")`.

## Acceptance Criteria
- [ ] `PooledTextEmbedding` and the `embeddingModel:` initializer do not exist.
- [ ] `MetadataSearcher(items:, embedder: PooledEmbedder(ref: "…"))` is synchronous and the first search reports cosine signals.
- [ ] Two searchers with one embedder name share one resident model.
- [ ] CI (unit and integration jobs) is green on the pushed commit.

## Tests
- [ ] New `Tests/FoundationModelsMetadataRegistryTests/PooledEmbedderSearchTests.swift`: with `ModelPool(loader:)` and a test loader: embed at the first search; two searchers, one load.
- [ ] `IntegrationTests/`: one real test with `PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")` where the cosine signal ranks a paraphrase first.
- [ ] `CIWorkflowTests` pins the metallib input.
- [ ] `swift test` and `swift test --package-path IntegrationTests` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool