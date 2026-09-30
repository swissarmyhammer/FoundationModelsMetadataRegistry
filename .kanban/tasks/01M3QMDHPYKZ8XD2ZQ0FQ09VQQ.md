---
depends_on:
- 01M3QMDH61DM9VH8581H9QQTZY
position_column: todo
position_ordinal: '8380'
title: 'Examples: select with a real Qwen3-4B PooledModel, no scripted session'
---
**Wait for:** FoundationModelsRanker tasks 01M3QMD9X40XA640Z9CXCREQAM ("Async session factory…") and 01M3QMDA82DXPZNEASMVXTP31M ("Depend on Extras; PooledSession is an AgentSession…") on the Ranker board: done and pushed.

## What
```swift
let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")
let searcher = MetadataSearcher(items: catalog, mode: .selection,
                                selection: SelectionConfig(model: { try await qwen.session(instructions: $0) }))
```

- Delete `Examples/ExamplesSupport/ExampleSelection.swift` (the Apple on-device model helper).
- `Librarian/main.swift`, `BigCatalog/main.swift` and `HotReload/main.swift` part 3 (count the factory calls): select with `PooledModel(ref: "mlx-community/Qwen3-4B-4bit")`. No scripted session, no Apple on-device model.
- `BigCatalog`: set `capacityCharacterLimit` so one run fits the context of Qwen3-4B with space for the answer; the comment gives the number and why.
- `README.md`: the examples paragraph names the two models and the first-run download.
- No tests for examples: the build and the runs are the check.

## Acceptance Criteria
- [ ] No example defines a session type or a selection helper.
- [ ] `swift build --package-path Examples` succeeds with no warnings from `Examples/`.
- [ ] `swift run --package-path Examples Librarian`, `BigCatalog` and `HotReload` run to completion with the real model; record the output in a task comment. #model-pool