---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m170502m393137tvcv8rcczb
  text: |-
    Picked up the card and moved it to `doing`.

    Research: `grep files` for `import\s+FoundationModelsRouter` over `Sources/` returns no match. The library target does not use Router. It gets its external types from `@_exported import FoundationModelsRanker` in `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift`. This confirms the product link is dead.

    State of the edit: the change was already in the working tree, uncommitted. `git diff -- Package.swift` shows exactly one deleted line — `.product(name: routerDependencyName, package: routerDependencyName)` from the `packageName` target dependency list — and nothing else. That is what the card asks for, so I verified it instead of making it again.

    Kept, as the card says: the package-level `.package(url: "...FoundationModelsRouter.git", branch: "main")` entry, because `liveRouterProductDependencies` still uses it for `LiveRouterSupport` and the four live-Router example cores. A later card removes it.

    TDD note: the card names `/tdd`, but this change removes a manifest dependency edge. There is no new behavior and no symbol to drive with a failing unit test — a Swift test target cannot assert on the link graph of its own manifest. The verification is the existing suite plus the two builds the Tests section names. All were run.

    Warnings seen in the build output are pre-existing and come from outside this repository's sources: C++17-extension diagnostics in the generated Metal headers of the `mlx-swift` checkout, and one llbuild "missing creator for mutated node" message for the `mlx-swift_Cmlx.bundle` product directory. Neither mentions FoundationModelsRouter, and no SwiftPM "unused dependency" warning appeared.

    Did not commit. The finish loop commits separately.
  timestamp: 2026-08-29T14:53:01.908783+00:00
- actor: claude-code
  id: 01m170549cmggbr4pe8f1gj9wb
  text: |-
    ### implement — no-change
    - evidence: 1 file already correct in the working tree — /Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Package.swift (uncommitted, verified by `git diff`, one line deleted). `swift build` exit 0. `swift test` exit 0 — 102 tests in 9 suites passed. `swift build --package-path IntegrationTests` exit 0. No SwiftPM "unused dependency" warning.
    - next: /review
  timestamp: 2026-08-29T14:53:06.220583+00:00
position_column: doing
position_ordinal: '80'
title: Remove the unused Router product link from the main library target
---
## What

`Package.swift` links the `FoundationModelsRouter` product into the main library target. No file in `Sources/FoundationModelsMetadataRegistry/` imports Router. The library gets all of its external types from `@_exported import FoundationModelsRanker` (`Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift:12`).

Remove that product entry. This is the first step of the full Router removal. It does not depend on the FoundationModelsRanker changes.

Files to change:
- `Package.swift` — delete `.product(name: routerDependencyName, package: routerDependencyName)` from the `packageName` target dependency list.

Keep the package-level `.package(url: ...FoundationModelsRouter.git ...)` entry. `liveRouterProductDependencies` still uses it. Later tasks remove that entry.

Note: this edit is already made in the working tree and is not committed. Confirm it is still correct, then commit it.

## Acceptance Criteria

- [x] The `packageName` target in `Package.swift` lists only the `FoundationModelsRanker` product.
- [x] `swift build` completes with no error.
- [x] SwiftPM prints no "unused dependency" warning for FoundationModelsRouter.

## Tests

- [x] Run `swift test`. All 102 tests in 9 suites pass.
- [x] Run `swift build --package-path IntegrationTests`. The build completes with no error.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.