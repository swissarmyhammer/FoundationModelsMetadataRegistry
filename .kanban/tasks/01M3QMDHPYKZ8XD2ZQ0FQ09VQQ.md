---
comments:
- actor: claude-code
  id: 01m3smsbwbcz5cs71r571ny5p1
  text: |-
    Implementation and real runs (2026-09-30).

    Changes:
    - Deleted Examples/ExamplesSupport/ExampleSelection.swift.
    - Librarian, BigCatalog and HotReload part 3 select with `PooledModel(ref: "mlx-community/Qwen3-4B-4bit")` through `SelectionConfig(model: { try await qwen.session(instructions: $0) })`. They use the default preamble `.selectionDefault` (the Ranker measured it on Qwen3-4B). The old helper used `.librarianDefault`.
    - HotReload part 3: the factory closure counts each call, then calls `qwen.session(instructions:)`. `CallCounter` is now an actor, because the factory is async. The report line also prints the selected ids.
    - BigCatalog: `selectionCapacityCharacterLimit = 48_000`. Measured with the Qwen3 tokenizer.json (Python `tokenizers`): the full prefix of 1,000 entries is 116,126 chars = 29,505 tokens (3.94 chars/token). 48,000 chars is about 12,200 tokens of the 32,768-token context, which gives three runs.
    - Package.swift comments and the README examples paragraph name both models and the first-run download.

    Runs (swift run --package-path Examples, all exit 0):
    - CatalogSearch (32 s): 1. commit, 2. push, 3. stash, 4. branch.
    - SemanticSearch (28 s): 1. status 0.969 (cosine 0.494), 2. stash, 3. branch, 4. commit, 5. push.
    - SemanticSearch --no-embedder (27 s): [diagnostic] embeddingUnavailable; 1. status.
    - Librarian (33 s): 1. tripCities, 2. weather, 3. packingList.
    - BigCatalog (51 s): retrieval 0.24 s, needle is rank 1. Selection gave no match: Qwen answered the short id "quantum-flux-capacitor", and the tier dropped it with `unknownSelectedId` (seen in the log). Ids are not constrained to the catalog (decision), so this output is expected.
    - HotReload (35 s): 4 update(items:) calls -> 2 embed calls; root session built 1 time for ["toolA"], selected ["toolA"]; after the change, built 2 times total, selected ["toolA"].

    Build: `swift build --package-path Examples` exit 0. The only warning is the SwiftPM "missing creator for mutated node" on the mlx-swift_Cmlx.bundle in .build. It is not from Examples/ sources.
    Root `swift test`: 180 tests in 22 suites passed.
  timestamp: 2026-09-30T17:11:24.299245+00:00
- actor: claude-code
  id: 01m3smsdxxk0bk9dy91ny40rek
  text: |-
    ### implement — changed
    - evidence: 6 files — Examples/ExamplesSupport/ExampleSelection.swift (deleted), Examples/Librarian/main.swift, Examples/BigCatalog/main.swift, Examples/HotReload/main.swift, Examples/Package.swift, README.md. Examples build exit 0, no warning from Examples/. Six example runs, each exit 0. Root swift test: 180 tests passed.
    - next: /review
  timestamp: 2026-09-30T17:11:26.397264+00:00
depends_on:
- 01M3QMDH61DM9VH8581H9QQTZY
position_column: doing
position_ordinal: '80'
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
- [x] No example defines a session type or a selection helper.
- [x] `swift build --package-path Examples` succeeds with no warnings from `Examples/`.
- [x] `swift run --package-path Examples Librarian`, `BigCatalog` and `HotReload` run to completion with the real model; record the output in a task comment. #model-pool