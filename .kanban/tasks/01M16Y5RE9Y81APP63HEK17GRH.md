---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19bsbshj9fhvjf9rw32stb8
  text: |-
    Research done. Current state of each named file, verified against the code:

    **`Package.swift`** — three stale spots remain (line numbers have shifted from the card's):
    - `packageName`'s doc comment: "following the pattern established by the sibling FoundationModelsRouter and CodeContextKit packages."
    - `foundationModelsRankerPackage`'s doc comment: lists `RoutedEmbedderAdapter` among Ranker's exports (deleted upstream); says "for the same CI reason as `routerDependencyName` above" (that constant no longer exists, so the cross-reference dangles); claims "FoundationModelsRanker itself depends on FoundationModelsRouter `main`, so SwiftPM unifies it with the existing pin" (false — Ranker at `35447e4` declares `dependencies: []`).
    - `platforms:`: "floor inherited from FoundationModelsRouter".
    - `exampleCoreTarget`'s doc comment narrates the removal ("Router-free", "once resolved ... through a live `Router`", "no core needs a Router product") rather than describing the shape as it now is.
    - The manifest header (`let package = Package(`) already says "over the FoundationModelsRanker sibling" and already describes the GPU-free examples — correct as written.

    **`Sources/.../FoundationModelsRankerReexport.swift`** — already correct. Its list is `HybridRanker`, `RankedDocument`, `SignalWeights`, `CosineScoring`, `Hit`, `Signals`, the BM25/trigram/tokenizer primitives, `TextEmbedding`, `SelectionTier`, `SelectionConfig`, `SelectionSessionSource`, `SelectionCatalog`, `SelectionMatch`, `Selection`, `RankDiagnostic`, `AgentSession`, and the selection-unavailable error. Every one of those is a `public` declaration in the Ranker checkout at `35447e4`. Neither `RoutedEmbedderAdapter` nor `RoutedAgentSession` appears. No change needed.

    Ranker's full public surface at `35447e4`: `BM25`, `BM25Corpus`, `CosineScoring`, `Hit`, `Signals`, `HybridRanker`, `SignalWeights`, `RankedDocument`, `RRF`, `SearchCorpus`, `StreamingSearchCorpus`, `Searcher`, `SelectionTierUnavailable`, `Searchable`, `SearchItem`, `TextEmbedding`, `Tokenizer`, `Trigram`, `AgentSession`, `RankDiagnostic`, `Selection`, `SelectionCatalog`, `SelectionConfig`, `SelectionSessionSource`, `SelectionMatch`, `SelectionTier`, `SelectionSchemaShapeError`.

    **`plan.md`** — stale in §1, §2, §3, §5, §6, §9, §10, §12, §13, §14 (M7/M8) and §15. §11 "Resolved decisions" is a numbered list ending at 13, and is the file's own home for a recorded decision, so the dated note goes there and the affected sections point at it.

    **`README.md`** — no Router/MLX/Hugging Face mention. The usage example type-checks against the current API: `MetadataSearcher` is a `public actor`, `init(items:mode:weights:selection:onDiagnostic:)` is sync and non-throwing, `search(intent:limit:)` is `async throws -> [Match<Item>]`, and `Match` has `id` and `score`. One prose claim still to verify empirically: "`commit` gets the first rank although its block does not contain the query's words" — the `commit` block reads "Record staged **changes** as a new snapshot..." and the query is "commit **changes** to git", so the block does share a query word.

    **Test precedent:** `CIWorkflowTests.swift` and `PackageManifestTests.swift` both resolve the repository root from `#filePath` by stripping two path components. New tests follow that pattern.
  timestamp: 2026-08-30T12:54:52.465490+00:00
- actor: claude-code
  id: 01m19c907p5fz9apvgrskg4vgw
  text: |-
    Implementation landed. TDD notes, including where the red-green cycle was and was not available:

    **Genuine RED → GREEN (the manifest test).** Wrote `spellsNoRemovedRouterName()` first and ran it. It failed for exactly the right reason: `["Package.swift: FoundationModelsRouter, RoutedEmbedderAdapter"]`. `Sources/` was already clean, which independently confirms `FoundationModelsRankerReexport.swift` needed no edit. Then fixed `Package.swift` and it went green.

    **Passed on first run (the README tests), so each was proven able to fail by perturbation.** The README's ranking claim was already true, so there was no failing state to observe. Rather than accept two assertions I had never seen fail, I perturbed each and re-ran:
    - `topRankedID` set to `"stash"` → failed, and reported the real ranking: `["commit", "push", "stash"]`. Restored.
    - One fixture block edited to `"...history, drifted."` → the drift guard failed naming that exact line. Restored.

    **A false claim found in `README.md`, and corrected.** The README said `commit` ranks first "although its block does not contain the query's words". That is not true: the `commit` block is "Record staged **changes** as a new snapshot..." and the query is "commit **changes** to git", so the block does share a query word. The true statement is that the block never says `commit` — the id field, weighted ×5, carries that term. Verified in the Ranker checkout: `BM25.primaryFieldWeight = 5.0`, `BM25.bodyFieldWeight = 1.0`, so the README's "(id field ×5, block ×1)" was already correct. Reworded that one sentence only.

    **A duplication trap avoided.** `ReadmeExampleTests` needs the repository root, and `PackageManifestTests` already had the `#filePath` walk — a third copy would have been a real near-duplicate (`CIWorkflowTests` holds the second). Extracted `TestSupport/RepositoryFiles.swift` and pointed the new code and the file I was already changing at it. `CIWorkflowTests` is untouched: the duplication rule says the fix goes in the changed code, never in the untouched counterpart.

    **A name collision avoided.** `ExamplesSupport` exports its own `GitCommand`, and the test target depends on it. A file-scope `GitCommand` in the new test file would have shadowed it for every other test file in the target — the local module wins. The README's type is nested inside the suite instead, and the doc comment says why.

    **`Package.swift` — every stale statement, and what replaced it:**
    - "the sibling FoundationModelsRouter and CodeContextKit packages" → "the sibling FoundationModelsRanker package's manifest", which I verified carries the identical constant-extraction convention.
    - `RoutedEmbedderAdapter` dropped from Ranker's export list; the selection tier added, matching the re-export file.
    - The dangling "same CI reason as `routerDependencyName` above" replaced with the actual reason, stated without reference to a deleted constant: a `../FoundationModelsRanker` path resolves only beside a checked-out sibling.
    - "FoundationModelsRanker itself depends on FoundationModelsRouter `main`" (false) → "declares `dependencies: []`, so this single entry is also the whole resolved graph", verified at `35447e4`.
    - "floor inherited from FoundationModelsRouter" → Ranker declares the same `.macOS("27.0")` floor, verified in its manifest.
    - `exampleCoreTarget`'s comment narrated the removal ("Router-free", "once resolved ... through a live `Router`"). Rewritten to describe the shape as it stands, with no reference to what it used to be.

    **`plan.md`** — history untouched. Added decision #14 (dated 2026-08-30) recording what was removed and why, plus the two API changes Ranker's Router-free release brought (`SelectionConfig`'s one-argument factory and `sessionSource`; `idEnumSchema(ids:) throws -> String` for `idEnumGrammar(ids:) -> Grammar`). Every section a reader could be misled by now carries a dated superseded marker pointing at it: the top status blockquote, §10, §12, §13, §14/M7 and §15. The markers use the file's own `*(Superseded ...)*` idiom.

    **Not changed, deliberately:** the existing `#expect` messages in `PackageManifestTests`. Reformatting user-facing output the card did not ask to change is what the `public-output-contract` rule forbids.

    Verification: `swift build` clean, `swift build --build-tests` reports zero warnings and zero errors, `swift test` is 113 tests in 11 suites passed (was 110 in 10 — three added). `Package.swift`, `Sources/` and `Examples/` now contain no occurrence of Router, Routed, MLX or Hugging Face at all. `stash@{0}` untouched.
  timestamp: 2026-08-30T13:03:24.918479+00:00
- actor: claude-code
  id: 01m19c9f3eraakyfx96nmap1wr
  text: |-
    ### implement — changed
    - evidence: 6 files — Package.swift, README.md, plan.md, Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift, Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift (new), Tests/FoundationModelsMetadataRegistryTests/TestSupport/RepositoryFiles.swift (new). `swift test` 113 passed / 0 failed in 11 suites (was 110 in 10). `swift build --build-tests` 0 warnings, 0 errors. `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` needed no change — its list already matches Ranker's public surface at `35447e4`, which the new manifest test independently confirms.
    - next: ready for `/review`. Not committed.
  timestamp: 2026-08-30T13:03:40.142383+00:00
depends_on:
- 01M16Y5CNB3P7E5ESF43AEAKQ4
position_column: doing
position_ordinal: '80'
title: Update the docs that describe the Router dependency
---
## What

Many doc comments and design notes still say this package is built over FoundationModelsRouter. After the dependency is gone, those statements are wrong. Correct them.

Files to change:
- `Package.swift` — rewrite the manifest header comment (lines 173-185), which says "A single library target over the FoundationModelsRouter sibling" and describes the live-Router examples. Rewrite the `foundationModelsRankerPackage` comment (lines 26-37), which explains the Router pin unification that no longer applies. Rewrite every remaining target comment that names Router, MLX, or a gated real-model path.
- `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` — the comment lists `RoutedEmbedderAdapter` and `RoutedAgentSession` (lines 6, 9) among the re-exported types. Both are deleted. Correct the list.
- `plan.md` — §10 and §13 describe the Router dependency and the live-Router examples. Add a note that records the decision and the new state. Do not rewrite the history; record what changed and why.
- `README.md` — check it. A grep for Router, MLX, and Hugging Face currently finds nothing, so it may need no change. Confirm the usage example still compiles against the current API.

## Acceptance Criteria

- [x] No comment in `Package.swift` or `Sources/` claims this package depends on FoundationModelsRouter.
- [x] `FoundationModelsRankerReexport.swift`'s type list matches what FoundationModelsRanker actually exports.
- [x] `plan.md` records the Router removal decision.
- [x] The `README.md` usage example compiles.

## Tests

- [x] Add a test in `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` that asserts `Package.swift` and every file in `Sources/` contain no `FoundationModelsRouter`, `RoutedEmbedderAdapter`, or `RoutedAgentSession` string.
- [x] Extract the `README.md` usage example into a test in `Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift` and assert it produces the ranked output the README shows.
- [x] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.