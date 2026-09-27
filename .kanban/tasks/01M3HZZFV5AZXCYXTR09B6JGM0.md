---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Add tests for MetadataDiagnostic.log(_:)
---
Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift:70-94

Coverage (file): 74.3% (26/35 lines)

Uncovered lines in this function: 81, 83-88

```swift
public static func log(_ diagnostic: MetadataDiagnostic)
```

This function is the default `onDiagnostic` conformer. It writes each diagnostic to the `os.Logger` of the package. The tests do not call it with `.unknownSelectedId` or with `.retrievalCut`.

Tests to add:
- Call `MetadataDiagnostic.log(_:)` one time for each case: `.duplicateId`, `.embeddingUnavailable`, `.unknownSelectedId`, `.retrievalCut`, `.embedCatchUp`. The function returns `Void` and writes only to `os.Logger`. Thus the test shows that each case runs and does not crash.
- A parameterized `@Test(arguments:)` over all cases is a good shape. Make sure that the argument list holds each case, so a new case that the list does not hold is easy to see.

Do not change the code under test. #coverage-gap