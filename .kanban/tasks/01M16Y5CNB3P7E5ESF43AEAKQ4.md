---
assignees:
- claude-code
depends_on:
- 01M16Y50NXQE1M24P457E74Y0R
- 01M16Y4H2X4AWJD59C89M7Y43T
position_column: todo
position_ordinal: '8780'
title: Reduce Package.swift to the single FoundationModelsRanker dependency
---
## What

After the preceding tasks, nothing in this package uses Router, MLX, or Hugging Face. Remove every dependency entry except FoundationModelsRanker. FoundationModelsRanker itself now has zero dependencies, so this package's whole dependency tree becomes one package.

Files to change:
- `Package.swift` — delete these `dependencies:` entries (lines 209-223):
  - `FoundationModelsRouter`
  - `mlx-swift-lm`
  - `swift-huggingface`
  - `swift-transformers`
  - the `swift-jinja` `"2.0.0"..<"2.4.0"` pin and its long comment
- `Package.swift` — delete the now-unused constants: `routerDependencyName` (line 24), `mlxPackage` (line 48), `huggingFacePackage` (line 57), `transformersPackage` (line 65), `huggingFaceOrg` (line 77).
- `Package.swift` — delete the `.product(name: "Jinja", package: "swift-jinja")` entry from the test target (line 262) and its comment block (lines 249-261). That entry existed only to mark the jinja pin as used.
- `Package.resolved` — regenerate with `swift package resolve`. It should list FoundationModelsRanker only.

This also removes both `git@github.com:` SSH URLs from the manifest, so CI no longer needs a deploy key for this repository.

## Acceptance Criteria

- [ ] `Package.swift` `dependencies:` has exactly one entry: FoundationModelsRanker.
- [ ] `Package.swift` contains no `git@github.com:` URL and no `huggingface` URL.
- [ ] `Package.resolved` lists FoundationModelsRanker and nothing else.
- [ ] `swift build` completes with no warning about an unused dependency.

## Tests

- [ ] `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` — extend the test added earlier. Assert `Package.swift` contains no `FoundationModelsRouter`, no `mlx-swift-lm`, no `swift-huggingface`, no `swift-transformers`, and no `swift-jinja`.
- [ ] Add a test that reads `Package.resolved` and asserts it names exactly one pin.
- [ ] Run `swift test`. All tests pass.
- [ ] Run `rm -rf .build && swift build` to prove a clean checkout resolves with no SSH access.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.