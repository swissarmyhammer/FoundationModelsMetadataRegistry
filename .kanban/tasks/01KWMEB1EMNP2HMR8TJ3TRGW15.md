---
comments:
- actor: claude-code
  id: 01kwmrm0pjn9gjvqfmhna5z2bx
  text: 'Picked up by /finish scoped-batch loop (iteration 1). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T19:52:18.386743+00:00
- actor: claude-code
  id: 01kwmrrmd07sn0yqke4bqb02x7
  text: 'Picked up. Research done. Key discovery: the family reusable workflow `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main` (used by Multitool/Router/OperationTool ci.yml) only checks out the calling repo — it cannot resolve a `.package(path: "../FoundationModelsRouter")` dependency. That is why CodeContextKit (which uses the path dep per Package.swift:61) has NO .github/workflows at all. Since this task requires BOTH the path dep and a working ci.yml, I will write a standalone ci.yml on [self-hosted, macOS] (family runner label) that checks out this repo and swissarmyhammer/FoundationModelsRouter as siblings via actions/checkout `path:`, then runs swift build/test with working-directory. TDD: writing the failing placeholder test first.'
  timestamp: 2026-07-03T19:54:49.632406+00:00
- actor: claude-code
  id: 01kwms6kdkcegc876f5h6rzth6
  text: |-
    Implementation complete and green. TDD: wrote Tests/FoundationModelsMetadataRegistryTests/PackageTests.swift first, watched `swift test` fail ("Could not find Package.swift"), then added Package.swift (tools 6.1, .macOS("27.0"), path dep ../FoundationModelsRouter wired like CodeContextKit), Sources placeholder, and .github/workflows/ci.yml (standalone [self-hosted, macOS] job: checks out this repo + swissarmyhammer/FoundationModelsRouter as siblings so the path dep resolves, then swift build --build-tests && swift test — reproducing the family reusable workflow's steps, which itself cannot handle path deps).

    Verification: `swift build` exit 0; `swift test` exit 0, 1 Swift Testing test passed. The single "missing creator for mutated node ... mlx-swift_Cmlx.bundle" warning is pre-existing — CodeContextKit and Router emit it identically; zero warnings from this package's own sources.

    Double-check agent: REVISE with one finding — Package.resolved must be COMMITTED (family convention; Router's .gitignore documents why: with a path dep, only the root package's Package.resolved pins the mlx-swift-lm BRANCH dependency, so untracked = non-reproducible CI). Addressed within my no-commit constraint: Package.resolved is in the working tree (untracked, not ignored) and .gitignore now carries the mirrored "committed, not ignored" comment. ORCHESTRATOR: include Package.resolved in the commit. Task left in doing for /review.
  timestamp: 2026-07-03T20:02:27.379197+00:00
position_column: doing
position_ordinal: '80'
title: Scaffold SwiftPM package with Router dependency
---
## What
Create the SwiftPM package skeleton per plan.md §10:
- `Package.swift`: swift-tools 6.x, `platforms: [.macOS("27.0")]` (match `../FoundationModelsMultitool/Package.swift:131-133`), one library target `FoundationModelsMetadataRegistry`, one test target `FoundationModelsMetadataRegistryTests` (Swift Testing), dependency `.package(path: "../FoundationModelsRouter")` wired the same way `../CodeContextKit/Package.swift:61,96` does it.
- `Sources/FoundationModelsMetadataRegistry/` with a placeholder file so the target builds.
- **CI workflow** `.github/workflows/ci.yml`: macOS runner with the OS 27 SDK, `swift build && swift test` on push/PR — this is what later keeps the `Examples/` executables compiling (plan.md §13 "kept compiling in CI").
- `.gitignore` already covers `.build/`.

The core must compile and unit-test without exercising Router at runtime (fakes conform to seams); Router link is for production conformers added by later tasks.

## Acceptance Criteria
- [ ] `swift build` succeeds on macOS 27 SDK
- [ ] `swift test` runs and passes with at least one placeholder Swift Testing test
- [ ] `Package.swift` declares the `../FoundationModelsRouter` path dependency and macOS 27 platform floor
- [ ] `.github/workflows/ci.yml` exists and runs `swift build && swift test` on a macOS runner

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/PackageTests.swift` — a trivial `@Test` that imports the module and asserts truth (replaced by real tests later)
- [ ] Run `swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.