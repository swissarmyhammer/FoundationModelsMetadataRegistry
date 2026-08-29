---
assignees:
- claude-code
depends_on:
- 01M16Y2V1034PDVAN8Z0GK3T9F
position_column: todo
position_ordinal: '8280'
title: Remove the live-Router embedder path from SemanticSearchCore and HotReloadCore
---
## What

`SemanticSearchCore` and `HotReloadCore` each have one function that resolves a real embedder through a live Router. Both call `buildLiveEmbedder(demoLabel:name:description:)` in `Examples/LiveRouterSupport/`. Replace that path with the GPU-free `DeterministicEmbedder`.

Files to change:
- `Examples/SemanticSearchCore/SemanticSearchCore.swift` — delete `resolveLiveEmbedder()` (line 81) and its `import LiveRouterSupport` (line 4). Add `import ExamplesSupport`. Make the demo use `DeterministicEmbedder()` as its embedder. Keep the `--no-embedder` flag and its keyword-only diagnostic; that path does not change.
- `Examples/HotReloadCore/HotReloadCore.swift` — delete `resolveLiveEmbedder()` (line 320) and its `import LiveRouterSupport` (line 4). The `embedder` parameter already defaults to `DeterministicEmbedder()` (line 154), so the burst keeps working.
- `Examples/SemanticSearch/main.swift` and `Examples/HotReload/main.swift` — delete the `METADATA_REGISTRY_INTEGRATION_TESTS` gate and the branch that calls the deleted function. Both demos now run one GPU-free path always.

Update every doc comment that names Router, `LiveModelLoader`, or "live-Router-resolved embedder".

## Acceptance Criteria

- [ ] Neither file imports `LiveRouterSupport`.
- [ ] Neither file names `Router`, `buildLiveEmbedder`, or `RoutedEmbedderAdapter`.
- [ ] `swift run SemanticSearch` prints ranked matches with a cosine signal, with no network and no GPU.
- [ ] `swift run HotReload` prints the burst as before, with no network and no GPU.

## Tests

- [ ] `Tests/FoundationModelsMetadataRegistryTests/HotReloadTests.swift` — the existing burst tests pass unchanged.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — add a test that calls `SemanticSearchCore`'s entry function with the default embedder and asserts the cosine signal is present in the returned `Signals`, and a second test that asserts the `--no-embedder` path still emits its keyword-only diagnostic.
- [ ] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.