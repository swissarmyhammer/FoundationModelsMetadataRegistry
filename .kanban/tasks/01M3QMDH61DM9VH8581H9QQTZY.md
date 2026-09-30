---
depends_on:
- 01M3QMDGR3PSYQ5PMM41Y9GJ7B
position_column: todo
position_ordinal: '8280'
title: 'Examples: embed with a real Qwen PooledEmbedder, no Router'
---
## What
The nested `Examples/` package embeds through Extras only.

```swift
let embedder = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
let searcher = MetadataSearcher(items: catalog, mode: .retrieval, embedder: embedder)
```

- `Examples/Package.swift`: remove `FoundationModelsRouter`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`; keep the path dependency on `..` and `FoundationModelsExtras`.
- Delete `Examples/ExamplesSupport/ExampleEmbedding.swift`.
- `SemanticSearch/main.swift`, `HotReload/main.swift` (part 1) and `HotReload/CoalescedBurst.swift` (part 2: the held embedder wraps a `PooledEmbedder`): embed with `PooledEmbedder`.
- Comments describe each example stand-alone (no plan references). Print the model output as it is; do not claim a fixed answer.
- No tests for examples: the build and the runs are the check.

## Acceptance Criteria
- [ ] No example defines a loader or an embedding type.
- [ ] `swift build --package-path Examples` succeeds with no warnings from `Examples/`.
- [ ] `swift run --package-path Examples SemanticSearch` (with and without `--no-embedder`) and `HotReload` parts 1–2 run to completion with the real model; record the output in a task comment. #model-pool