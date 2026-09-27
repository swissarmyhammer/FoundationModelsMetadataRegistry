---
assignees:
- claude-code
position_column: todo
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