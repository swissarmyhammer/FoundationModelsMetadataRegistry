---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m173dt5ad24adkp9txb8r0km
  text: |-
    Research done. What I found:

    - The sibling task ^x0qr1ap already landed for the embedder side. `Examples/SemanticSearchCore/SemanticSearchCore.swift` and `Examples/HotReload/main.swift` at HEAD have no gate, no `import LiveRouterSupport`, one GPU-free path, and `main.swift` is imports + doc comment + top-level statements only. I follow that shape.
    - `SelectionConfig.model` in FoundationModelsRanker is still `@Sendable (String, Grammar) -> any AgentSession`. `Examples/HotReloadCore/HotReloadCore.swift` already builds one with `SelectionConfig(model: { _, _ in ScriptedSelectionSession() })` and imports no Router. I copy that: parameter types stay inferred, `Grammar` is never named.
    - `AgentSession` gives a default `fork()` that returns `self`, so a demo double needs only `respond(to:)`.
    - `Librarian` and `BigCatalog` are the LAST two users of `ExamplesSupport.isMetadataRegistryIntegrationEnabled` / `metadataRegistryIntegrationEnvVar`. After this task both symbols are dead, so I delete them from `Examples/ExamplesSupport/ExamplesSupport.swift` too. Nothing in `IntegrationTests/` reads them (only doc-comment mentions of the env var name).
    - `LibrarianCore` is NOT a dependency of the unit test target today. The card asks for an `ExamplesSmokeTests` test over `LibrarianCore`'s selection entry function, so I add `.target(name: "LibrarianCore")` to the test target only. I do not touch the package-level `dependencies:` entries.
    - `printCatalog()` in `LibrarianCore` is only called from the deleted `else` branch. To leave no dead code I call it unconditionally in the single GPU-free path.
  timestamp: 2026-08-29T15:50:16.490820+00:00
- actor: claude-code
  id: 01m175n3t23vnrtrhekx5ps8wr
  text: |-
    Implementation landed. What I did, and two decisions worth knowing:

    1. **Shared the demo double, not just the session.** The card asked for `DemoAgentSession` in `Examples/ExamplesSupport/`. Both demos also needed the same `SelectionConfig` around it (same `preamble: .librarianDefault`, differing only in scripted ids and capacity), so `Examples/ExamplesSupport/DemoAgentSession.swift` also carries `demoSelectionConfig(selectedIds:capacityCharacterLimit:)`. That keeps one source of truth instead of two near-identical `SelectionConfig` literals in `LibrarianCore` and `BigCatalogCore`.

    2. **`respond(to:)` encodes with `JSONEncoder`, it does not interpolate a string.** `BigCatalog`'s ids are URIs, so hand-built JSON would be a latent escaping bug.

    3. **`runBigCatalogOverBudgetSelection` gained an `onDiagnostic` parameter.** Without it the diagnostic only reached stdout and no test could assert it. Shape copied from `runSemanticSearch(query:embedder:onDiagnostic:)`: required parameter, and `BigCatalog/main.swift` passes `printDiagnostic`. Its one caller is updated in the same diff.

    4. **Deleted `metadataRegistryIntegrationEnvVar` and `isMetadataRegistryIntegrationEnabled`** from `Examples/ExamplesSupport/ExamplesSupport.swift`. `Librarian` and `BigCatalog` were their last two readers, so this change made them dead, and dead code is a blocker. Nothing in `IntegrationTests/` reads them.

    5. **`.target(name: "LibrarianCore")` added to the unit test target** so `ExamplesSmokeTests` can drive the selection entry function, as the card's Tests section requires. The package-level `dependencies:` entries are untouched; task `^b2487hc` owns those.

    Verified: `swift run Librarian` prints the catalog then the two selected verbatim blocks; `swift run BigCatalog` prints the retrieval timing, then `[diagnostic] retrievalCut: considered 1000 candidates, kept the top 24 ...`, then the needle. Both exit 0, no network, no GPU.

    **Pre-existing flaky test found, recorded as `^b8sg2pk`.** `ExamplesSmokeTests.bigCatalogRetrievalFindsTheNeedleAndReportsTiming()` asserts `result.elapsed < 5.0`, a wall-clock claim over a ~10^3-entry catalog. I stashed my whole change and ran the 106-test suite 4 times at HEAD (`aa7aa78`): 2 failed on that exact assertion, 2 passed. So it is not mine. I did NOT raise the threshold -- the `test-integrity` validator names that as cheating. I did shrink my own new over-budget test from the 1,000-entry default to 40 entries so it adds no parallel load to that timed test; 40 still exceeds both the capacity limit and the default candidate limit, so the cut it asserts is real.
  timestamp: 2026-08-29T16:29:12.898958+00:00
- actor: claude-code
  id: 01m175nayynfrs3jx0yay90mfb
  text: |-
    ### implement — changed
    - evidence: 8 files. New: Examples/ExamplesSupport/DemoAgentSession.swift. Changed: Examples/LibrarianCore/LibrarianCore.swift, Examples/BigCatalogCore/BigCatalogCore.swift, Examples/Librarian/main.swift, Examples/BigCatalog/main.swift, Examples/ExamplesSupport/ExamplesSupport.swift, Package.swift, Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift, Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift. `swift build --build-tests` clean, 0 errors 0 warnings. `swift test` = 109 tests in 9 suites (was 106); the 3 new tests pass in 0.012s. One failure appears intermittently -- `ExamplesSmokeTests.bigCatalogRetrievalFindsTheNeedleAndReportsTiming()`'s `result.elapsed < 5.0` -- reproduced 2 of 4 runs at HEAD with my change stashed, so it is pre-existing; filed as ^b8sg2pk. `swift run Librarian` and `swift run BigCatalog` each exit 0, GPU-free, and BigCatalog prints the `.retrievalCut` diagnostic.
    - next: /review
  timestamp: 2026-08-29T16:29:20.222263+00:00
depends_on:
- 01M16Y2V1034PDVAN8Z0GK3T9F
position_column: doing
position_ordinal: '80'
title: Remove the live-Router selection path from LibrarianCore and BigCatalogCore
---
## What

`LibrarianCore` and `BigCatalogCore` each build a `SelectionConfig` from a live Router model. Both call `buildSelectionConfig(demoLabel:name:description:capacityCharacterLimit:)` in `Examples/LiveRouterSupport/`. That is the last selection-tier use of Router in this package.

Replace the live model with a scripted, GPU-free `AgentSession`. `AgentSession` stays public in FoundationModelsRanker and needs only `respond(to:)` and `fork()`, so a demo double is about 15 lines. Put the double in `Examples/ExamplesSupport/` so both demos share it.

Files to change:
- `Examples/ExamplesSupport/DemoAgentSession.swift` — new file. A public `AgentSession` that returns a fixed, ids-only JSON response built from the ids it is given. Model it on `Tests/FoundationModelsMetadataRegistryTests/TestSupport/SelectionFixtures.swift`'s `ScriptedAgentSession`, but public and demo-shaped.
- `Examples/LibrarianCore/LibrarianCore.swift` — delete `resolveLiveSelectionConfig()` (line 94) and `import LiveRouterSupport` (line 4). Build the `SelectionConfig` from `DemoAgentSession`.
- `Examples/BigCatalogCore/BigCatalogCore.swift` — delete the `buildSelectionConfig(...)` call (line 144) and `import LiveRouterSupport` (line 4). Keep the over-budget `capacityCharacterLimit`, so the `.retrievalCut` diagnostic still fires.
- `Examples/Librarian/main.swift` and `Examples/BigCatalog/main.swift` — delete the `METADATA_REGISTRY_INTEGRATION_TESTS` gate and its branch. Both demos now run one GPU-free path always.

## Acceptance Criteria

- [x] Neither core imports `LiveRouterSupport`.
- [x] Neither core names `Router`, `buildSelectionConfig`, or `RoutedAgentSession`.
- [x] `swift run Librarian` prints selected verbatim blocks, with no network and no GPU.
- [x] `swift run BigCatalog` prints retrieval timings and the over-budget `.retrievalCut` diagnostic, with no network and no GPU.

## Tests

- [x] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — add a test that runs `LibrarianCore`'s selection entry function and asserts the returned matches are the ids the `DemoAgentSession` named.
- [x] `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` — add a test that runs `BigCatalogCore`'s over-budget path and asserts a `.retrievalCut` diagnostic is emitted.
- [x] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Notes carried forward

- The scripted double also carries `demoSelectionConfig(selectedIds:capacityCharacterLimit:)`, so both demos share one `SelectionConfig` shape instead of two near-identical copies.
- `runBigCatalogOverBudgetSelection` gained a required `onDiagnostic` parameter, matching `runSemanticSearch`'s shape, so a test can assert the `.retrievalCut` diagnostic.
- `ExamplesSupport.metadataRegistryIntegrationEnvVar` and `isMetadataRegistryIntegrationEnabled` were deleted: this change removed their last two readers.
- `swift test` also surfaces a PRE-EXISTING flaky assertion, `result.elapsed < 5.0` in `ExamplesSmokeTests.bigCatalogRetrievalFindsTheNeedleAndReportsTiming()`. Reproduced 2 of 4 runs at HEAD with this change stashed. Filed as `^b8sg2pk`; it is not this card's work.