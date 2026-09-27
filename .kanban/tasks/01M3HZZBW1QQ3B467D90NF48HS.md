---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3j0pb88cc53kr0byd1z4c2y
  text: 'Research: `MetadataDiagnostic.init(_:)` is internal, so the tests use `@testable import`. `RankDiagnostic` is `Sendable, Equatable` and the module re-exports it. I added a new file `Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift` with one parameterized `@Test(arguments:)` over the three cases. This removes duplicate test bodies. The retrievalCut case uses considered = 40 and kept = 12, so a swap of the two values makes the test fail. The code under test did not change.'
  timestamp: 2026-09-27T18:05:32.808533+00:00
position_column: doing
position_ordinal: '80'
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