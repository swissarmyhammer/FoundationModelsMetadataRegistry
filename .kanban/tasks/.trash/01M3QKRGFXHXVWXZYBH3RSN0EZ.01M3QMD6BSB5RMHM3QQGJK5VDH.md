---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8580'
title: 'Examples: real Qwen embedder and real Qwen selection through Extras pooled models, no Router'
---
#model-pool

## What
The nested `Examples/` package (uncommitted work in this repository) uses real models through Extras only.

```swift
let embedder = PooledEmbedder("mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
let qwen = PooledModel("mlx-community/Qwen3-4B-4bit")
MetadataSearcher(items: catalog, embedder: embedder)
MetadataSearcher(items: catalog, mode: .selection,
                 selection: SelectionConfig(model: { try await qwen.session(instructions: $0) }))
```

- `Examples/Package.swift`: remove `FoundationModelsRouter`, `mlx-swift-lm`, `swift-huggingface`, `swift-transformers`. Keep the path dependency on `..` and `FoundationModelsExtras`.
- Delete `Examples/ExamplesSupport/ExampleEmbedding.swift` and `Examples/ExamplesSupport/ExampleSelection.swift`.
- `SemanticSearch/main.swift`, `HotReload/main.swift` (part 1) and `HotReload/CoalescedBurst.swift` (part 2, the held embedder wraps a `PooledEmbedder`): embed with `PooledEmbedder`.
- `Librarian/main.swift`, `BigCatalog/main.swift` and `HotReload/main.swift` (part 3, count the session factory calls): select with `PooledModel("mlx-community/Qwen3-4B-4bit")`. No scripted session and no Apple on-device model.
- `BigCatalog`: set `capacityCharacterLimit` so that one run fits the context of Qwen3-4B with space for the answer; the comment gives the number and why.
- Comments describe each example stand-alone (no plan references), as now. Print the model output as it is; do not claim a fixed answer.
- `README.md`: the examples paragraph names the two models and the first-run download.

## Acceptance Criteria
- [ ] `Examples/Package.swift` names no Router and no MLX package.
- [ ] No example defines a loader, an embedding type or a session type.
- [ ] `swift build --package-path Examples` succeeds with no warnings from `Examples/`.
- [ ] Each of the five examples runs to completion on this machine with the real models.

## Tests
- [ ] `swift build --package-path Examples` — build succeeds.
- [ ] Run each example once (`swift run --package-path Examples <name>` for the five names) and record the output in the task comment; exit code 0 for each.
- [ ] `swift test` at the root passes (the root package does not include the examples).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.