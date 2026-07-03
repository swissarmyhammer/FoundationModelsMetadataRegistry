---
position_column: todo
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