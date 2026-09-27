---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3hcdk98f4x4wm3xhs2jq8hm
  text: |-
    Research done.
    - The Extras manifest (tools 6.2) has five products: FoundationModelsExtras, Operations, OperationsCLI, Marketplace, MarketplaceFixtures. The core target needs Stencil, Yams, ULID.swift and swift-distributed-tracing (product `Tracing`) only.
    - `PackageManifestTests.declaredProductNames()` reads literal product names only. The Ranker entry uses constants. The new check must expand the manifest constants in each `.product(name:package:)` entry, or it cannot see an entry that uses a constant.
    - plan.md: decision #14 is at line 469, decision #15 at line 515, §10 at line 371. The top status block also says "depends on FoundationModelsRanker alone"; it gets a dated marker too.
  timestamp: 2026-09-27T12:11:14.600216+00:00
- actor: claude-code
  id: 01m3hcrzf9r8hvqrstmbhdr77j
  text: |-
    Implementation landed.
    - Package.swift: new constant `foundationModelsExtrasPackage`, a `.package(url: "\(swissArmyHammerOrg)\(foundationModelsExtrasPackage).git", branch: "main")` entry, and the `FoundationModelsExtras` product on the library target. `swift package update` resolved Extras at main (f4bd503).
    - Build check: a clean `swift build` in a scratch build path compiled Yams (with CYaml), Stencil (with PathKit), ULID, Tracing (with swift-service-context), FoundationModelsRanker and FoundationModelsExtras. It compiled no swift-syntax, swift-argument-parser or libgit2 module. SwiftPM downloads the swift-syntax prebuilts into `.build/prebuilts/` because swift-syntax is in the resolved graph, but it does not compile them.
    - PackageManifestTests: `dependsOnTheRankerAndExtrasAlone` replaces `dependsOnTheRankerAlone`. The new test `namesOnlyTheCoreExtrasProduct` checks the Extras product. The manifest reader moved to `TestSupport/ManifestEntries.swift`, because swiftlint file_length (400) failed at 428 lines. It now resolves manifest constants in `.product(name:package:)` entries. Before, it read literal names only.
    - plan.md: decision #16 comes after #15. Dated markers are on the top status block, on decision #14, and in §10. §10 has a new `FoundationModelsExtras` bullet.

    ### implement — changed
    - evidence: 4 files — Package.swift, Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift, Tests/FoundationModelsMetadataRegistryTests/TestSupport/ManifestEntries.swift, plan.md; `swift test --filter "PackageManifestTests|PlanDocumentTests|PackageTests"` 7/7 pass
    - next: /test
  timestamp: 2026-09-27T12:17:27.529362+00:00
position_column: doing
position_ordinal: '80'
title: 'Add the FoundationModelsExtras dependency for the model pool and record decision #16'
---
## Goal
Add a dependency on the core `FoundationModelsExtras` product, so the registry can use the model pool. Record this change as decision #16 in `plan.md`.

## Context
- The user decided on 2026-09-26: `FoundationModelsExtras` owns one process-wide model pool. In one process, each model loads one time only, and all users share it. The router and the registry both use the pool.
- User decision (2026-09-26, sent by the router session): these changes add no new targets, products or packages in any repo. There is no separate `ModelPool` product or package. The pool, the work queue and the embedder handle go into the existing core `FoundationModelsExtras` product. Use `.product(name: "FoundationModelsExtras", package: "FoundationModelsExtras")` and `import FoundationModelsExtras`.
- Decision #14 (`plan.md:469`) says that this package has exactly one dependency, `FoundationModelsRanker`. `PackageManifestTests.dependsOnTheRankerAlone` (`Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift:117`) pins this.
- The rule of decision #14 that stays true: no MLX product and no Hugging Face product. The core `FoundationModelsExtras` target has no MLX. The MLX loader stays in the router or in the application.
- Accepted cost (user decision, 2026-09-26, sent by the router session): the registry build also compiles what the core `FoundationModelsExtras` target needs: Stencil, Yams, ULID.swift, and swift-distributed-tracing (Extras adds it for tool hosting). SwiftPM also resolves the other package dependencies of the Extras manifest (swift-argument-parser, swift-syntax, swift-libgit2), but the registry build must not compile them. If the build compiles a package that is not in this list, stop and tell the user.

## Blocked by (other board)
- Extras task `01M3FN8WD0G0NJ7QAAKSPZ9RW1` (the pool types in the core Extras target). This work must be done and pushed before this task can start.

## Steps
1. In `Package.swift`, add the `FoundationModelsExtras` package and add the `FoundationModelsExtras` product to the `FoundationModelsMetadataRegistry` target.
2. Change `PackageManifestTests` to agree with decision #16: the allowed dependency set is `FoundationModelsRanker` and `FoundationModelsExtras`, and no other. Keep the MLX and Hugging Face product checks as they are. Add a check that the only product of the `FoundationModelsExtras` package that the manifest names is `FoundationModelsExtras` (not `Operations`, `OperationsCLI` or `Marketplace`). Update the doc comment of the suite, which says that the one entry is the whole resolved graph.
3. In `plan.md` §11, add decision #16 after decision #15. Give the date 2026-09-26. Say that the registry now gets `FoundationModelsExtras`. Record the accepted cost: Stencil, Yams, ULID.swift and swift-distributed-tracing compile with the registry, and SwiftPM also resolves the other dependencies of the Extras manifest. Say that the user accepted this cost on 2026-09-26. Say why: one load for each model in a process, and a work queue for each model. Say which parts of decision #14 and §10 it changes, and put a dated marker on each of those parts. Say that the rule "no MLX and no Hugging Face product" stays true.
4. Update §10 (dependencies) to show the two packages.

## Acceptance criteria
- [ ] `swift build` passes. The build compiles no package other than FoundationModelsRanker, FoundationModelsExtras, Stencil (and its own dependencies), Yams, ULID.swift and swift-distributed-tracing (and its own dependencies).
- [ ] `PackageManifestTests` pass and agree with decision #16.
- [ ] `plan.md` has decision #16, with the accepted cost, and dated markers on the parts that it changes.

## Tests
- `PackageManifestTests`: add a test that `Package.swift` names `FoundationModelsExtras` as the only product of the `FoundationModelsExtras` package.
- Run `swift test`. All tests must pass.