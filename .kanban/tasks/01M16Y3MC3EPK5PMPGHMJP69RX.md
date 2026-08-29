---
assignees:
- claude-code
depends_on:
- 01M16Y2V1034PDVAN8Z0GK3T9F
position_column: todo
position_ordinal: '8380'
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

- [ ] Neither core imports `LiveRouterSupport`.
- [ ] Neither core names `Router`, `buildSelectionConfig`, or `RoutedAgentSession`.
- [ ] `swift run Librarian` prints selected verbatim blocks, with no network and no GPU.
- [ ] `swift run BigCatalog` prints retrieval timings and the over-budget `.retrievalCut` diagnostic, with no network and no GPU.

## Tests

- [ ] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — add a test that runs `LibrarianCore`'s selection entry function and asserts the returned matches are the ids the `DemoAgentSession` named.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` — add a test that runs `BigCatalogCore`'s over-budget path and asserts a `.retrievalCut` diagnostic is emitted.
- [ ] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.