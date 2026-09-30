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
- actor: claude-code
  id: 01m3snh7jf425ztdk4xptczjj4
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit 1745237); 2 findings (2 confirmed, 4 refuted) — Examples/BigCatalog/main.swift:91, Examples/HotReload/main.swift:124
    - next: implement the 2 open items in the "Review Findings (2026-09-30 11:18)" section. Remove each cause from the whole file: all print(…) calls in the changed example lines, and the qwen constant in BigCatalog, Librarian and HotReload (move it to ExamplesSupport as one shared constant).
  timestamp: 2026-09-30T17:24:26.319437+00:00
- actor: claude-code
  id: 01m3snhsjy6x13ajy6cym8y9w3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — ExampleSelection.swift deleted; Librarian, BigCatalog, HotReload part 3 select with PooledModel(ref: "mlx-community/Qwen3-4B-4bit"); BigCatalog capacity 48,000 chars; six runs exit 0
    - test: green — root 180 tests / 22 suites; Examples build clean (forced recompile)
    - commit: 1745237 feat(examples): select with a real Qwen3-4B PooledModel
    - review: findings — Examples/BigCatalog/main.swift:91 (no_direct_standard_out_logs), Examples/HotReload/main.swift:124 (duplication: qwen constant also in BigCatalog:89, Librarian:57)
    - next: implement iteration 2 — shared output writer in ExamplesSupport used by every example in place of print; shared model constants (selection model and embedder) in ExamplesSupport
  timestamp: 2026-09-30T17:24:44.766912+00:00
- actor: claude-code
  id: 01m3sp140wneckfyvax5a3ejfw
  text: |-
    Iteration 2: both review findings are done.

    - ExamplesSupport now has `public enum Report { public static func write(_:) }` (it writes through `FileHandle.standardOutput`), `public let exampleEmbedder` (PooledEmbedder, Qwen3 Embedding 0.6B 4-bit DWQ) and `public let exampleSelectionModel` (PooledModel, Qwen3 4B 4-bit). Each has a doc comment. The ExamplesSupport target now depends on the FoundationModelsExtras product (Package.swift).
    - HotReload: the local `Report` and `embedder` are deleted, and `qwen` is deleted. It uses the shared values. `import Foundation` is removed, because nothing in main.swift uses it now.
    - CatalogSearch, SemanticSearch, Librarian and BigCatalog: each `print(` is now `Report.write(`. SemanticSearch uses `noEmbedder ? nil : exampleEmbedder`. Librarian and BigCatalog use `exampleSelectionModel`. The header comments name the shared constants.
    - `grep -rn "print(" Examples --include=*.swift --exclude-dir=.build`: no match. The two model ref strings occur only in ExamplesSupport.swift.
    - The output did not change: `Report.write` adds one "\n", the same as `print`.
  timestamp: 2026-09-30T17:33:06.972215+00:00
- actor: claude-code
  id: 01m3sp17y22cyz4xaxrbk5mwdb
  text: |-
    ### implement — changed
    - evidence: 6 files — Examples/ExamplesSupport/ExamplesSupport.swift, Examples/Package.swift, Examples/CatalogSearch/main.swift, Examples/SemanticSearch/main.swift, Examples/Librarian/main.swift, Examples/BigCatalog/main.swift, Examples/HotReload/main.swift (7 with Package.swift). `grep -rn "print(" Examples --include=*.swift` (with .build excluded): 0 matches. `swift build --package-path Examples`: exit 0. The only warning is the SwiftPM "missing creator for mutated node" on mlx-swift_Cmlx.bundle, and it is not from Examples/. Runs: CatalogSearch 0, SemanticSearch 0, SemanticSearch --no-embedder 0, Librarian 0 (tripCities, weather, packingList), BigCatalog 0 (needle rank 1 in retrieval; selection empty, as before), HotReload 0 (4 updates -> 2 embed calls; root session built 1 then 2 times). Root swift test: 180 tests in 22 suites passed. Both findings are flipped to [x].
    - next: /review
  timestamp: 2026-09-30T17:33:10.978471+00:00
- actor: claude-code
  id: 01m3spjs7xhpexk1ey1616vx1z
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (958d88a): 0 findings (7 files attempted, 0 failed, 0 skipped; 2 .kanban files excluded by .reviewignore). The 2 prior findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-09-30T17:42:45.757209+00:00
- actor: claude-code
  id: 01m3spk1xm22w6g324h519bz4n
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — shared `Report.write` in ExamplesSupport replaces every `print(`; shared `exampleSelectionModel` and `exampleEmbedder`; six runs exit 0
    - test: green — root 180 tests / 22 suites; Examples build clean (forced recompile); no `print(` in Examples
    - commit: 958d88a refactor(examples): share report output and model names
    - review: clean — 0 findings; task moved to done
    - next: push; final run of all examples
  timestamp: 2026-09-30T17:42:54.644558+00:00
depends_on:
- 01M3QMDH61DM9VH8581H9QQTZY
position_column: done
position_ordinal: b680
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

## Review Findings (2026-09-30 11:18)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Examples/ExamplesSupport/ExampleSelection.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Examples/ExamplesSupport/ExampleSelection.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Examples/ExamplesSupport/ExampleSelection.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Examples/ExamplesSupport/ExampleSelection.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Examples/ExamplesSupport/ExampleSelection.swift, so its declarations are unread

- [x] `Examples/BigCatalog/main.swift:91` `code-hygiene/disallowed-constructs-swift` — no_direct_standard_out_logs: Do not commit print(…), debugPrint(…), dump(…) or _printChanges(), which write to standard out in release. Log to a dedicated logging system, or silence one debug-only line with // swiftlint:disable:next no_direct_standard_out_logs and the reason after it.
- [x] `Examples/HotReload/main.swift:124` `duplication/duplication` — Verbatim duplicate of qwen constant declared in BigCatalog:89 and Librarian:57. All three examples initialize the same model constant; changes to the model reference must be replicated in all three locations. Extract qwen initialization to ExamplesSupport as a shared constant; import and use in all three examples.
