---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8380'
title: 'Ranker: depend on Extras, drop TextEmbedding.dimension, async session factory, pooled conformances'
---
**Repository:** commit to `/Users/wballard/github/swissarmyhammer/FoundationModelsRanker`. #cross-repo #model-pool

## What
- `Package.swift`: depend on the core `FoundationModelsExtras` product (`git@github.com:swissarmyhammer/FoundationModelsExtras.git`, branch `main`).
- `Sources/FoundationModelsRanker/TextEmbedding.swift`: remove `var dimension: Int { get }`. The contract is `func embed(_ texts: [String]) async throws -> [[Float]]`. Fix each use of `dimension` in the Ranker (the vectors carry their length).
- `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`: the factory becomes async: `init(model: @escaping @Sendable (String) async throws -> any AgentSession, …)` and `SelectionSessionSource.factory` stores that type. Update the three call sites: `Selection/SelectionTier.swift:213`, `Selection/SelectionTier.swift:304`, `Searcher.swift:300` (`try await makeSession(…)`).
- New `Sources/FoundationModelsRanker/Selection/PooledSessionSupport.swift`: `extension PooledSession: AgentSession` (forward `respond(to:)`, `respond(to:generating:)`, `fork()`), next to the `LanguageModelSession` conformance.
- New `Sources/FoundationModelsRanker/PooledEmbedderSupport.swift`: `extension PooledEmbedder: TextEmbedding` (forward `embed`).

```swift
let qwen = PooledModel("mlx-community/Qwen3-4B-4bit")
SelectionConfig(model: { instructions in try await qwen.session(instructions: instructions) })
MetadataSearcher(items: catalog, embedder: PooledEmbedder("mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"))
```

## Acceptance Criteria
- [ ] `TextEmbedding` has no `dimension`.
- [ ] A `SelectionConfig` factory can `await` and `throw`; an error from the factory surfaces from `search`.
- [ ] `PooledSession` is an `AgentSession` and `PooledEmbedder` is a `TextEmbedding` with no code in the consumer.
- [ ] The cached-root path forks the pooled session (it does not re-send the prefix).

## Tests
- [ ] Update the Ranker test doubles that declare `dimension` (remove it).
- [ ] `Tests/FoundationModelsRankerTests/SelectionConfigTests.swift` (or the existing selection tests): an async factory is awaited for the root and for each over-budget run; a throwing factory makes `search` throw.
- [ ] A test that `PooledSession` and `PooledEmbedder` satisfy the protocols (compile-level use through `any AgentSession` / `any TextEmbedding` with injected Extras test loaders).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.