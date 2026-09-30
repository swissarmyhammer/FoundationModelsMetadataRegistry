---
comments:
- actor: claude-code
  id: 01m3shkxj15r8htejyk5skycse
  text: 'Research: The examples at main 0b55573 do not compile. SemanticSearch, HotReload part 1 and CoalescedBurst still call the removed `embeddingModel:footprintBytes:loader:` initializer and `PooledTextEmbedding`. `PooledEmbedder: TextEmbedding` comes from FoundationModelsRanker, and the registry re-exports that module (`@_exported import FoundationModelsRanker`). `ModelPool.shared` loads with the built-in `MLXModelLoader`, so the examples need no loader. After ExampleEmbedding.swift is deleted, ExamplesSupport imports only the registry and FoundationModels. Thus it does not need Extras. Plan: HotReload makes one `PooledEmbedder` and gives it to part 1 and to `runCoalescedBurst`, so the two searchers share one hold and the model name is in one place.'
  timestamp: 2026-09-30T16:16:00.065740+00:00
- actor: claude-code
  id: 01m3sja3gqp54gz09qts112160
  text: |-
    Implementation landed. Examples/Package.swift now depends on `..` and FoundationModelsExtras only; ExamplesSupport depends on the registry only. ExampleEmbedding.swift is deleted. SemanticSearch, HotReload part 1 and CoalescedBurst embed with `PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")`. HotReload makes one embedder and gives it to `runCoalescedBurst(_:embeddingWith:query:limit:)`, where `HeldFirstEmbedder.base` is a `PooledEmbedder`.

    Build: `swift build --package-path Examples` -> Build complete, no warning from Examples/ (after touching every Examples source). SwiftPM prints one build-system line that is not from Examples/: `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`.

    Runs (model was already in the Hugging Face cache):
    - SemanticSearch, exit 0:
      1. status  score=0.969  [bm25=0.000 trigram=0.122 cosine=0.494]
      2. stash  score=0.500  [bm25=0.000 trigram=0.000 cosine=0.562]
      3. branch  score=0.492  [bm25=0.000 trigram=0.000 cosine=0.535]
      4. commit  score=0.484  [bm25=0.000 trigram=0.000 cosine=0.526]
      5. push  score=0.476  [bm25=0.000 trigram=0.000 cosine=0.521]
    - SemanticSearch --no-embedder, exit 0: `[diagnostic] embeddingUnavailable ...`, then `1. status  score=1.000  [bm25=0.000 trigram=0.122 cosine=0.000]`.
    - HotReload, exit 0: step 1 = ["toolA"] embedCatchUp(pending: 1, total: 1); step 2 = ["toolA", "toolB"] embedCatchUp(pending: 1, total: 2); step 3 no diagnostic; step 4 = ["toolB", "toolC"] embedCatchUp(pending: 1, total: 2). Coalesced: 4 update(items:) calls -> 2 embed calls; call 1 ["reads a file from disk"], call 2 ["writes a file to disk", "deletes a file from disk"]; after the burst = ["toolB", "toolC"]. Part 3: root session built 1, then 2 time(s).
    - CatalogSearch, exit 0: 1. commit score=1.000, 2. push 0.976, 3. stash 0.976, 4. branch 0.476.

    Root `swift test`: 180 tests in 22 suites passed.
  timestamp: 2026-09-30T16:28:07.063969+00:00
- actor: claude-code
  id: 01m3sja5ggcb5bcsy0hexycfhz
  text: |-
    ### implement — changed
    - evidence: 5 files — Examples/Package.swift, Examples/ExamplesSupport/ExampleEmbedding.swift (deleted), Examples/SemanticSearch/main.swift, Examples/HotReload/main.swift, Examples/HotReload/CoalescedBurst.swift. Examples build clean for Examples/; SemanticSearch, SemanticSearch --no-embedder, HotReload, CatalogSearch each exit 0; root swift test 180/180 pass.
    - next: /review
  timestamp: 2026-09-30T16:28:09.104483+00:00
depends_on:
- 01M3QMDGR3PSYQ5PMM41Y9GJ7B
position_column: doing
position_ordinal: '80'
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