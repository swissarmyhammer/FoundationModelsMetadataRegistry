---
assignees:
- claude-code
position_column: todo
position_ordinal: '8480'
title: Clear the four periphery warnings in files outside the OTel work
---
## What

`periphery scan --retain-public --quiet --relative-results --index-store-path .build/out` (run on 2026-09-28, during ^vd487dv) reports four warnings. They are in files that ^vd487dv did not change:

- `Examples/ExamplesSupport/DemoAgentSession.swift`: "Assign-only property 'ids' is assigned, but never used".
- `Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift`: "Superfluous ignore comment for property 'block' (declaration is referenced and should not be ignored)".
- `Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift`: "Superfluous ignore comment for property 'indexedText' (declaration is referenced and should not be ignored)".
- `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift`: "Unused imported module 'BigCatalogCore'".

Note: this toolchain writes the index store to `.build/out`, not to `.build/debug/index/store`. Thus give `--index-store-path .build/out` to periphery.

## Subtasks
- [ ] Remove or use the assign-only `ids` property of `DemoAgentSession`.
- [ ] Remove the two superfluous `// periphery:ignore` comments in `RenderedTextDigests.swift`.
- [ ] Remove the unused `BigCatalogCore` import from `OverBudgetTests.swift`, or use it.

## Acceptance Criteria
- [ ] The periphery scan above reports no warning.
- [ ] `swift test` passes with no new warning. swiftlint and `swiftformat . --lint` are clean.