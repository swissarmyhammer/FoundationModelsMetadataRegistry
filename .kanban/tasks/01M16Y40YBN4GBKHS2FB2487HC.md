---
assignees:
- claude-code
depends_on:
- 01M16Y37AEYBQ1JEY02X0QR1AP
- 01M16Y3MC3EPK5PMPGHMJP69RX
position_column: todo
position_ordinal: '8480'
title: Delete the LiveRouterSupport target
---
## What

`Examples/LiveRouterSupport/` exists only to resolve a live `Router` + `LiveModelLoader` for the four demo cores. After the two preceding tasks, nothing imports it. Delete it and the manifest scaffolding that carries the Router, MLX, and Hugging Face products into the demo targets.

Files to change:
- `Examples/LiveRouterSupport/LiveRouterSupport.swift` — delete the file and its directory (128 lines).
- `Package.swift` — delete:
  - the `LiveRouterSupport` target (line 287-291),
  - `liveRouterProductDependencies` (line 99-105),
  - `liveRouterCoreDependencies` (line 116-120),
  - the `exampleCoreTarget(name:)` helper (line 165-171), because every demo core now has the same GPU-free shape as `CatalogSearchCore`.
- `Package.swift` — declare `SemanticSearchCore`, `LibrarianCore`, `BigCatalogCore`, and `HotReloadCore` the same way `CatalogSearchCore` is declared: `.target(name: packageName)` plus `.target(name: examplesSupportName)` only. Consider one new helper that builds that shape, so the five declarations stay a single source of truth.

Do not touch the package-level dependency entries yet. A later task removes them.

## Acceptance Criteria

- [ ] `Examples/LiveRouterSupport/` does not exist.
- [ ] No target in `Package.swift` names `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, or `Tokenizers`.
- [ ] Every `Examples/*Core` target depends only on the main library target and `ExamplesSupport`.
- [ ] `swift build` completes with no error.

## Tests

- [ ] Run `swift test`. All tests pass, including the `ExamplesSmokeTests` added by the two preceding tasks.
- [ ] Run `swift run CatalogSearch`, `swift run SemanticSearch`, `swift run Librarian`, `swift run BigCatalog`, and `swift run HotReload`. Each exits 0.
- [ ] Add a test in `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` (new file) that reads `Package.swift` and asserts it contains no `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, or `Tokenizers` product entry. Model it on `CIWorkflowTests.swift`'s `#filePath`-relative file read.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.