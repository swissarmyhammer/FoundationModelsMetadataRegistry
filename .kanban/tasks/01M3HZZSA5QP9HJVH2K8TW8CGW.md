---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: Add tests for SemanticSearchCore.printDiagnostic(_:) and printExampleDiagnostic(_:describingSpecialCase:)
---
Examples/SemanticSearchCore/SemanticSearchCore.swift:84-89
Examples/ExamplesSupport/ExamplesSupport.swift:110-119

Coverage:
- SemanticSearchCore.swift: 60.0% (9/15 lines). Uncovered lines: 84-89.
- ExamplesSupport.swift: 69.6% (16/23 lines). Uncovered lines: 113-119.

```swift
public func printDiagnostic(_ diagnostic: MetadataDiagnostic)
public func printExampleDiagnostic(
    _ diagnostic: MetadataDiagnostic,
    describingSpecialCase describe: (MetadataDiagnostic) -> String?,
)
```

`printExampleDiagnostic` prints `[diagnostic] <message>` when `describe` returns a message. When `describe` returns `nil`, it calls `MetadataDiagnostic.log(_:)`. `printDiagnostic` calls it with a closure that gives a message only for `.embeddingUnavailable`. No test calls these functions.

Tests to add (in `ExamplesSmokeTests.swift`):
- `printExampleDiagnostic(.embeddingUnavailable) { _ in "msg" }`: make sure that the closure gets the diagnostic. The branch that prints must run.
- `printExampleDiagnostic(.duplicateId(id: "x")) { _ in nil }`: the branch that calls `MetadataDiagnostic.log(_:)` must run.
- `printDiagnostic(.embeddingUnavailable)` and `printDiagnostic(.duplicateId(id: "x"))`: the two branches of the closure must run.
- If the tests must examine the printed text, capture stdout, or give the print function as a parameter only in the test. Do not change the code under test. #coverage-gap