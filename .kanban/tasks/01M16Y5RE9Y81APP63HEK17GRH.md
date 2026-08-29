---
assignees:
- claude-code
depends_on:
- 01M16Y5CNB3P7E5ESF43AEAKQ4
position_column: todo
position_ordinal: '8880'
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

- [ ] No comment in `Package.swift` or `Sources/` claims this package depends on FoundationModelsRouter.
- [ ] `FoundationModelsRankerReexport.swift`'s type list matches what FoundationModelsRanker actually exports.
- [ ] `plan.md` records the Router removal decision.
- [ ] The `README.md` usage example compiles.

## Tests

- [ ] Add a test in `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` that asserts `Package.swift` and every file in `Sources/` contain no `FoundationModelsRouter`, `RoutedEmbedderAdapter`, or `RoutedAgentSession` string.
- [ ] Extract the `README.md` usage example into a test in `Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift` and assert it produces the ranked output the README shows.
- [ ] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.