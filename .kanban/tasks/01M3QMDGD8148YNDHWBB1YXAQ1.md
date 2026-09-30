---
comments:
- actor: claude-code
  id: 01m3sdjfpdmr0m1syb549rkdhm
  text: |-
    Implementation notes.

    - Pins: root `swift package update` gives Ranker 39e3717 (it descends from 798503b) and Extras c5ca65a. Extras went from b553bdf to 42ca5b5 and then to c5ca65a while this work ran. `Package.resolved` is in `.gitignore` in all three packages, so the pins are local only, and CI resolves the newest `main`.
    - The baseline build failed at one location only: `PooledTextEmbedding.dimension` read `PooledEmbedder.dimension`, and that property does not exist now. The async selection factory and the `logRecords` change of Extras 42ca5b5 did not break the build, so `DiagnosticsTests` and `TelemetryContentSafetyTests` did not need a change for them.
    - Doubles: new `TestSupport/VectorTable.swift` holds the text-to-vector table for `FakeEmbedder` and `GatedEmbedder`. A text that is not registered embeds to a zero vector with the length of the registered vectors. When no vector is registered, the length is `VectorTable.defaultVectorLength` (2). An empty vector is not a correct fallback: `CosineScoring` of the Ranker gives nil for length 0, so the search reports `.embeddingUnavailable`, and that changes behavior (for example `HotReloadCoalescingTests`, whose `GatedEmbedder` registers no vector).
    - New tests: `EmbeddingTestDoubleTests` (3 tests). RED was a compile failure, because `FakeEmbedder()` and `GatedEmbedder(vectorsByText:gate:)` with no `dimension:` did not exist.
    - Constants removed because the only use was `dimension:`: `embeddingDimension` in EmbedPendingEntriesTests and SharedCatalogEmbeddingTests, `catchUpEmbeddingDimension`, and `burstEmbeddingDimension`. In RegistryTracingTests and TelemetryContentSafetyTests the constant also builds the fixture vectors, so it is now `vectorLength`.
    - No registry source read an embedder `dimension` other than `PooledTextEmbedding` itself. I removed that property. `Examples/HotReload/CoalescedBurst.swift` `HeldFirstEmbedder.dimension` forwarded to it, so I removed that property also.
    - Build fix outside this task: in `Examples/`, `swift package update` also moved FoundationModelsRouter from c49e453 to 4f2a5c5. In that revision, `LiveModelLoader` has only `init(reporting:)`. The smallest change was in `Examples/ExamplesSupport/ExampleEmbedding.swift`: `LiveModelLoader(downloader: #hubDownloader(), tokenizerLoader: #huggingFaceTokenizerLoader())` became `LiveModelLoader()`, and I removed the 4 imports that became unused (HuggingFace, MLXHuggingFace, MLXLMCommon, Tokenizers). CI does not build `Examples/`. The Examples package dependencies on HuggingFace, MLXHuggingFace and Tokenizers can now be unused. Task ^1y9gj7b or the Examples Qwen task can remove them.

    BLOCKER (conflict with a documented contract): acceptance criterion 1 says "No registry source or test names an embedder `dimension`". `Tests/.../TestSupport/PooledModelStubs.swift` `StubEmbeddingModel.dimension` (and `PooledTextEmbeddingTests.dimension`, which feeds it) must stay. `StubEmbeddingModel` conforms to `PooledEmbedding` of FoundationModelsExtras, and at c5ca65a that protocol still declares `var dimension: Int { get }`. If I remove the property, the test target does not compile. The card does not list this stub, and task ^1y9gj7b deletes `PooledModelStubs.swift` and `PooledTextEmbeddingTests.swift`. A person must decide one of these: (a) the criterion applies to `TextEmbedding` doubles only, and the stub stays until ^1y9gj7b, or (b) Extras removes `PooledEmbedding.dimension` first.
  timestamp: 2026-09-30T15:05:18.797279+00:00
- actor: claude-code
  id: 01m3sdjp34h23fjhdxxfy8ns38
  text: |-
    ### implement — stuck
    - evidence: 19 files. Changed: Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift, Examples/HotReload/CoalescedBurst.swift, Examples/ExamplesSupport/ExampleEmbedding.swift (build fix for the Router API, outside this task), Tests/.../TestSupport/FakeEmbedder.swift, TestSupport/GatedEmbedder.swift, EmbeddingTests, HotReloadTests, HotReloadBurstTests, HotReloadCoalescingTests, SearchableMetadataTextsTests, EmbedPendingEntriesTests, SharedCatalogEmbeddingTests, EmbeddingCatchUpTests, RegistryTracingTests, TelemetryContentSafetyTests. New: TestSupport/VectorTable.swift, EmbeddingTestDoubleTests.swift. Root `swift build --build-tests`: exit 0, no warning outside the mlx-swift checkout. Root `swift test`: 181 tests in 22 suites passed. `swift build --build-tests` in Examples/ and IntegrationTests/: exit 0. I did not run the real-model integration tests.
    - gap: acceptance criterion 1. `StubEmbeddingModel.dimension` in PooledModelStubs.swift stays, because the Extras `PooledEmbedding` protocol requires it. Refer to the BLOCKER in the comment above. Criterion 2 (CI green on the pushed commit) is not examined, because this step does not commit or push.
    - next: a person decides on the stub (a or b). Then /review.
  timestamp: 2026-09-30T15:05:25.348551+00:00
- actor: claude-code
  id: 01m3sdkkq5c1rmvbhssxz036ss
  text: |-
    ### finish iteration 1 — implement: changed (block resolved)
    - implement: stuck reported, but the block is a wording fault of the task, not a real conflict. Resolution by the plan author: option (a). The Extras `PooledEmbedding` protocol keeps `dimension` by design; only `TextEmbedding` / `PooledEmbedder` lose it. Acceptance criterion 1 is corrected on the task: `StubEmbeddingModel.dimension` stays until ^1y9gj7b deletes `PooledModelStubs.swift`.
    - implement evidence: 19 files (PooledTextEmbedding.dimension removed; FakeEmbedder/GatedEmbedder share new TestSupport/VectorTable.swift; new EmbeddingTestDoubleTests; dimension arguments removed from the test files; build fix outside the task in Examples/ExamplesSupport/ExampleEmbedding.swift for the Router `LiveModelLoader()` API). Root `swift test`: 181 tests in 22 suites passed. Pins: Ranker 39e3717, Extras c5ca65a.
    - next: test
  timestamp: 2026-09-30T15:05:55.685393+00:00
- actor: claude-code
  id: 01m3se5rg72akfqje67gv8w15p
  text: |-
    ### review — stuck
    - evidence: `review sha HEAD~1..HEAD` (2ae7dff): 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsMetadataRegistryTests/HotReloadCoalescingTests.swift:62 `completeness/invariant-propagation`. The finding requires code that cannot type-check: `gatedTexts: Set<String>?` and `vectorsByText: [String: [Float]]` are different parameters of `GatedEmbedder.init`.
    - next: A person must correct the rule or refute the finding, then run `/review 01M3QMDGD8148YNDHWBB1YXAQ1 HEAD~1..HEAD` again. The task stays in `review`.
  timestamp: 2026-09-30T15:15:50.407610+00:00
- actor: claude-code
  id: 01m3se6q5vhqy2gxej406qg6am
  text: |-
    ### finish iteration 1 — review: stuck → resolved, not a true conflict
    - test: green — swift test 181 tests / 22 suites, 0 failures; IntegrationTests build complete
    - commit: 2ae7dff refactor(embedding): remove dimension from the registry test doubles
    - review: 1 finding — Tests/FoundationModelsMetadataRegistryTests/HotReloadCoalescingTests.swift:62 completeness/invariant-propagation. The reviewer marked it a true conflict, because the literal label change `gatedTexts:` → `vectorsByText:` does not type-check.
    - resolution (orchestrator): the cause of the finding is that this one call leaves out `vectorsByText:`, while every other `GatedEmbedder(...)` call gives `vectorsByText:` first. A fix that type-checks removes that cause: `GatedEmbedder(vectorsByText: [:], gate: gate, gatedTexts: [firstBurstItem.block])`. Same gate behavior. The finding is in scope; the blocker note is obsolete.
    - next: implement (iteration 2) with that fix, then test, commit, review
  timestamp: 2026-09-30T15:16:21.819229+00:00
- actor: claude-code
  id: 01m3se9vpm2a7hv1bv69fx1gew
  text: |-
    ### implement — changed
    - evidence: 1 source file: Tests/FoundationModelsMetadataRegistryTests/HotReloadCoalescingTests.swift. `startBlockedBurst` now calls `GatedEmbedder(vectorsByText: [:], gate: gate, gatedTexts: [firstBurstItem.block])`, with one argument on each line, the same as the other calls. `[:]` is the default of `vectorsByText`, so the gate behavior does not change. A search of Tests/ for `GatedEmbedder(` found 6 calls. The other 5 calls (EmbeddingCatchUpTests, EmbeddingTestDoubleTests, HotReloadBurstTests, SharedCatalogEmbeddingTests, HotReloadTests) already give `vectorsByText:` first. I removed the obsolete blocker section from the description and set the finding to `- [x]`. Root `swift test`: exit 0, 181 tests in 22 suites passed. The one build warning is "missing creator for mutated node" on the mlx-swift_Cmlx.bundle, which is dependency build output, not project code.
    - next: test, commit, review
  timestamp: 2026-09-30T15:18:04.756319+00:00
position_column: doing
position_ordinal: '80'
title: Remove dimension from the registry test doubles
---
**Wait for:** FoundationModelsRanker task 01M3QMD9KJ8T723R02085BEFYY ("Remove dimension from TextEmbedding") on the Ranker board: done and pushed.

## What
- `swift package update`, confirm the new Ranker revision.
- Remove `dimension` from each test double in `Tests/FoundationModelsMetadataRegistryTests/` that declares it (`TestSupport/FakeEmbedder.swift`, `TestSupport/GatedEmbedder.swift`, and the doubles in `EmbeddingTests`, `EmbeddingCatchUpTests`, `EmbedPendingEntriesTests`, `HotReload*Tests`, `SharedCatalogEmbeddingTests`, `RegistryMetricsTests`, `RegistryTracingTests`, `TelemetryContentSafetyTests`, `SearchableMetadataTextsTests`), and from `PooledTextEmbedding.dimension`.
- Each registry source that read an embedder `dimension` uses the length of a returned vector.

## Acceptance Criteria
- [ ] No `TextEmbedding` conformer or test double in the registry names `dimension`. (Clarified by the plan author: the Extras `PooledEmbedding` protocol keeps `dimension` on purpose, because a loaded container knows it. So `StubEmbeddingModel.dimension` in `TestSupport/PooledModelStubs.swift` stays; task ^1y9gj7b deletes that file.)
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `swift test` passes with no change of behavior.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool

## Review Findings (2026-09-30 09:08)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsMetadataRegistryTests/HotReloadCoalescingTests.swift:62` `completeness/invariant-propagation` — Parameter name mismatch in GatedEmbedder instantiation—uses `gatedTexts:` while other calls in the same commit use `vectorsByText:`. All calls to the same API should use consistent parameter names to avoid confusion and potential API mismatches. Change `gatedTexts:` to `vectorsByText:` on line 62 to match the parameter naming convention established elsewhere in the same commit.