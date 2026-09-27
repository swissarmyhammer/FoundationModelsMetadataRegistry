---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3j0pb88cc53kr0byd1z4c2y
  text: 'Research: `MetadataDiagnostic.init(_:)` is internal, so the tests use `@testable import`. `RankDiagnostic` is `Sendable, Equatable` and the module re-exports it. I added a new file `Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift` with one parameterized `@Test(arguments:)` over the three cases. This removes duplicate test bodies. The retrievalCut case uses considered = 40 and kept = 12, so a swap of the two values makes the test fail. The code under test did not change.'
  timestamp: 2026-09-27T18:05:32.808533+00:00
- actor: claude-code
  id: 01m3j0x8rd5285826ddkterhs6
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file, Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift (one parameterized test with 3 cases: retrievalCut(40, 12), embeddingUnavailable, unknownSelectedId("x"))
    - test: green — swift test: 143 tests in 15 suites passed, 0 failed, 0 skipped; swiftformat . --lint: 0/68 files need formatting; swiftlint --strict: 0 violations. SwiftPM also wrote "failed loading cached manifest ... disk I/O error" lines. These come from the SwiftPM manifest cache, not from the code.
    - commit: 89410ab test(catalog): add tests for MetadataDiagnostic.init(_: RankDiagnostic)
    - review: clean — review sha HEAD~1..HEAD: 0 findings, 7 validators ran, 0 failed. Task moved to done.
  timestamp: 2026-09-27T18:09:19.629644+00:00
position_column: done
position_ordinal: a980
title: 'Add tests for MetadataDiagnostic.init(_: RankDiagnostic)'
---
Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift:19-28

Coverage (file): 74.3% (26/35 lines)

Uncovered lines in this function: 22, 26

```swift
init(_ diagnostic: RankDiagnostic)
```

This initializer maps each `RankDiagnostic` case to the case of `MetadataDiagnostic` that has the same name. The tests use only the `.unknownSelectedId` mapping. The `.retrievalCut` and `.embeddingUnavailable` mappings do not run.

Tests to add (in `CatalogTests.swift` or a new `DiagnosticsTests.swift`):
- `MetadataDiagnostic(RankDiagnostic.retrievalCut(considered: 40, kept: 12))` is equal to `.retrievalCut(considered: 40, kept: 12)`. Use different values for `considered` and `kept`, so that a swap of the two values makes the test fail.
- `MetadataDiagnostic(RankDiagnostic.embeddingUnavailable)` is equal to `.embeddingUnavailable`.
- `MetadataDiagnostic(RankDiagnostic.unknownSelectedId(id: "x"))` is equal to `.unknownSelectedId(id: "x")`. Add this for full coverage of the switch.

Do not change the code under test. #coverage-gap