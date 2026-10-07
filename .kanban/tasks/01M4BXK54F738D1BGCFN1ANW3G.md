---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4c06m64mqhjsah7h7hngtxn
  text: FoundationModelsExtras is on origin main at 2c37a78. It contains a91911d (`PooledEmbedder` conforms to `PooledEmbedding`, and `PooledEmbedding` has no `dimension`), 5993e14 (`PooledModel` conforms to FoundationModels `LanguageModel`) and 2c37a78 (`OperationEventKind.message`). The task is still blocked until the FoundationModelsRanker SHA arrives.
  timestamp: 2026-10-07T20:17:12.900676+00:00
- actor: claude-code
  id: 01m4c07c2szrv7x49s8pgrw7r0
  text: |-
    ### finish iteration 1 — stuck
    - implement: not started — the task is blocked by work in a different repository.
    - evidence: FoundationModelsRanker origin/main is at d75a67c. It still contains `TextEmbedding.swift`, `PooledEmbedderSupport.swift`, `Selection/AgentSession.swift`, `Selection/LanguageModelSessionSupport.swift` and `Selection/PooledSessionSupport.swift`. `SelectionConfig` still takes a session, not `any LanguageModel`, so the session half of this task cannot compile against the current Ranker. The Ranker session (foundationmodelsranker-35) asked that nothing that depends on the new shape is pushed before it sends its SHA.
    - next: start `/finish ^n1anw3g` when the Ranker session sends the commit SHA of the Ranker change on main.
  timestamp: 2026-10-07T20:17:37.369043+00:00
- actor: claude-code
  id: 01m4c0m6ekvj5671vh54k2m9qw
  text: |-
    Unblocked. FoundationModelsRanker origin/main is at 6156346. The API change is 1c4cf12 "feat!: take FoundationModels LanguageModel and Extras PooledEmbedding". It requires Extras 2c37a78.

    New Ranker API:
    - `Searcher(items, embedder: (any PooledEmbedding)? = nil, model: (any LanguageModel)? = SystemLanguageModel.default, weights:, preamble:, mode:, onDiagnostic:)`
    - `SelectionConfig(model: any LanguageModel, preamble:, capacityCharacterLimit:)`
    - `SelectionTier(catalog:config:onDiagnostic:)`
    - Removed: `AgentSession`, `TextEmbedding`, `SessionSource`, `idEnumSchema(ids:)`, `SelectionSchemaShapeError`, `fork`.

    A scripted `LanguageModel` double to copy: FoundationModelsRanker `Tests/FoundationModelsRankerTests/Support/ScriptedLanguageModel.swift` (at ../FoundationModelsRanker).

    Start with `swift package update` in the root package, `Examples` and `IntegrationTests`. Also delete any test that checks `idEnumSchema(ids:)` or `SelectionSchemaShapeError`.
  timestamp: 2026-10-07T20:24:37.587434+00:00
- actor: claude-code
  id: 01m4c12arskp5xdm3s6e9dd2y7
  text: |-
    Research done. `swift package update` ran in the root, in `Examples` and in `IntegrationTests`. All three Package.resolved files now hold FoundationModelsRanker 6156346 and FoundationModelsExtras 2c37a78 (the Package.resolved files are not tracked by git).

    Discoveries:
    - The new `SelectionTier` makes one `LanguageModelSession(model:instructions:)` for each run. The instructions are the assembled prefix. The prompt is `<request>\n<intent>\n</request>\nAnswer with the exact ids of the chosen candidates. Choose only from these ids: a, b.`
    - The prefix now has one `<candidate>` block for each id, with an `id:` line and a `description:` line. Tests that look for `## <id>\n<summary>` must look for `id: <id>\ndescription: <summary>`.
    - Over budget, the tier splits the catalog into runs and prompts each run. Under budget (prefix count <= limit), one prompt.
    - `PooledEmbedding` is in FoundationModelsExtras, so each library file that names it needs `import FoundationModelsExtras`.
    - `TestSupport/SelectionSchema.swift` exists only for the `idEnumSchema(ids:)` tests, so it goes away with them.
    - The guard tests in `PackageManifestTests` and `PlanDocumentTests` name the removed Router type `RoutedAgentSession`. That is a different type from `AgentSession`, and the guard must keep its name.
    - The sah `files` edit tool ignores `replace_all`. It replaces one match for each call.
  timestamp: 2026-10-07T20:32:20.761778+00:00
- actor: claude-code
  id: 01m4c1qw0xnr0q58fe4fa5m7f0
  text: Library sources migrated. Each `TextEmbedding` is now `PooledEmbedding` (with `import FoundationModelsExtras`), the calls use `embed(texts:)`, and the comments about the cached root session, fork and the id-enum grammar now state the current behavior (Sources, root Package.swift comments, README, the re-export comment, and the `unknownSelectedId` doc in Diagnostics.swift). `swift build` at the root passes. Added `Tests/.../TestSupport/ScriptedLanguageModel.swift`, copied from the Ranker double with 2-space indent. The test migration, and the Examples and IntegrationTests migration, are next.
  timestamp: 2026-10-07T20:44:06.557608+00:00
- actor: claude-code
  id: 01m4c32m0mkyxwnrhy1jhp1d2b
  text: |-
    Tests, Examples and IntegrationTests migrated.

    Discovery: after the update to Extras 2c37a78, `TracedCall.run` writes `error.type` itself, as the type name with its module, then the enum case name when reflection shows one (for example `FoundationModelsRanker.SelectionTierUnavailable`). It wrote over the short name that the registry's own `recordFailure(_:on:)` wrote, so two `RegistryTracingTests` failed. Fix: the registry's `run(_:recordingFailureOn:)` and `recordFailure(_:on:)` in `RegistryTelemetry+Spans.swift` are deleted, because `TracedCall.run` now gives the error status and `error.type`. The doc of `AttributeKey.errorType` names the new format, and the two tests expect the literal values.

    Test changes: `AgentSessionTests.swift`, `ScriptedAgentSession.swift`, `SelectionSchema.swift` and `SelectionFixtures.swift` are deleted. `ExpectedSelectionPrompt.swift` is new (a literal of the prompt text). `OverBudgetTests` counts prompts on `ScriptedLanguageModel.calls`, checks that the prompt is only the `<request>` block and the exact-ids line and that the prefix is the instructions, and keeps the two boundary tests driven by `capacityCharacterLimit`. `HotReloadTests` checks the prefix of the prompts before and after an update, in place of the fork count.

    Not changed: `plan.md` still names the removed types, because it is the design history and not source, test or comment. The guard lists in `PackageManifestTests` and `PlanDocumentTests` still name the removed Router type `RoutedAgentSession`.

    ### implement — changed
    - evidence: 46 paths (42 modified, 4 deleted, 2 added, by `git status`). `swift build`: Build complete. `swift build --build-tests`: Build complete, no warning from a project file. `swift test`: 172 tests in 21 suites passed. `swift build --package-path Examples`: Build complete. `swift build --package-path IntegrationTests --build-tests`: Build complete. The only build warning is the SwiftPM "missing creator for mutated node" message for the mlx-swift bundle, which comes from the dependency.
    - next: `/review ^n1anw3g`
  timestamp: 2026-10-07T21:07:27.380099+00:00
position_column: doing
position_ordinal: '80'
title: Move the registry to PooledEmbedding and any LanguageModel
---
## Goal

Move the registry to the new FoundationModelsRanker and FoundationModelsExtras interfaces:

- Embedding: Extras `PooledEmbedding` (only `embed(texts:) async throws -> [[Float]]`). The Ranker deletes `TextEmbedding` and `PooledEmbedderSupport.swift`.
- Selection: `SelectionConfig`, `SelectionTier` and `Searcher` take `model: any LanguageModel`. The Ranker deletes `AgentSession`, `fork()`, `SelectionConfig.SessionSource` and the root-session cache. The tier makes a new `LanguageModelSession(model:instructions:)` for each prompt. `PooledModel` conforms to `LanguageModel`.

Do not add a registry-level embedding or session protocol or typealias.

## Blocked

Do not start this task before the FoundationModelsRanker session (foundationmodelsranker-35) sends the commit SHAs of Extras and of the Ranker on `main`. Then run `swift package update`.

## Embedding changes

- [x] `FoundationModelsRankerReexport.swift`: remove the `TextEmbedding` mention.
- [x] Change `any TextEmbedding` to `any PooledEmbedding` in `MetadataSearcher.swift` (78, 214, 260, 284), `SharedCatalogEmbedding.swift` (46, 72), `MetadataSearcher+RetrievalTier.swift` (142), `MetadataSearcher+ReloadEmbedLoop.swift` (44, 68), `MetadataSearcher+Search.swift` (162), `Catalog/MetadataIndex+Embedding.swift` (97, 334, 373).
- [x] Change the calls from `embed(_:)` to `embed(texts:)`.
- [x] Make `FakeEmbedder`, `GatedEmbedder`, `EmptyResultEmbedder` (EmbeddingTests:80) and `HeldFirstEmbedder` (Examples/HotReload/CoalescedBurst.swift:127) conform to `PooledEmbedding`.
- [x] Remove `dimension` from `TableEmbeddingModel` (PooledEmbedderSearchTests).
- [x] Do not wrap `GatedEmbedder` in a `PooledEmbedder`. `GenerationQueue` runs one job at a time, so a held call stops the next call, and the gated tests can deadlock (SharedCatalogEmbeddingTests:109, EmbeddingCatchUpTests:115, HotReloadCoalescingTests:66, HotReloadBurstTests:29).

## Session changes

- [x] `FoundationModelsRankerReexport.swift`: remove the `AgentSession` mentions.
- [x] Delete `AgentSessionTests.swift`.
- [x] Replace `TestSupport/ScriptedAgentSession.swift` with a scripted FoundationModels `LanguageModel` double that records each prompt and its instructions.
- [x] Update `SelectionFixtures.swift`, `SelectionTests.swift`, `PlanDocumentTests.swift` and `PackageManifestTests.swift`.
- [x] `OverBudgetTests.swift`: count prompts on the double, not factory calls. Delete the fork tests and the cached-root test. Keep the boundary tests (limit `== prefix.count` is under budget, `prefix.count - 1` is over budget). Make sure that the prefix goes to the double as instructions, and that the prompt is only the `<request>` block and the id line.
- [x] Examples HotReload, Librarian and BigCatalog: give `PooledModel(ref:)` as `model:`, not `qwen.session(instructions:)`.
- [x] IntegrationTests: update `ColdSelectionRealModelTests.swift` and `IntegrationTests/Package.swift`.

## Done when

- [x] `swift build` and `swift test` pass in the root package.
- [x] `swift build --package-path Examples` passes.
- [x] `swift build --package-path IntegrationTests --build-tests` passes.
- [x] No source, test or comment mentions `TextEmbedding`, `AgentSession`, `SessionSource`, `fork()` or `ScriptedAgentSession`.