---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3j1ydw781vgh49bfbz3fhhv
  text: 'Research: `printExampleDiagnostic` (Examples/ExamplesSupport/ExamplesSupport.swift:110-119) prints `[diagnostic] <message>` or calls `MetadataDiagnostic.log(_:)`, which writes to os.Logger and not to stdout. `printDiagnostic` (Examples/SemanticSearchCore/SemanticSearchCore.swift:84-89) gives a message only for `.embeddingUnavailable`. No other code in the test process prints lines with the `[diagnostic] ` prefix, so the tests filter captured stdout on that prefix. Discovery: `StandardOutputCapture.capture` moves `STDOUT_FILENO` for the whole process. Two captures that overlap in parallel tests can save the pipe of the other capture as the "original" descriptor, and then a reader never gets end of file (a hang). This task adds more captures, so the plan isolates `capture` to one global actor. The redirect window has no suspension point, so the actor makes each window exclusive.'
  timestamp: 2026-09-27T18:27:26.215442+00:00
- actor: claude-code
  id: 01m3j28kzb4v5rg98evhxdwa5e
  text: |-
    ### finish iteration 1 — clean
    - implement: changed. New file Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests+DiagnosticPrinting.swift (an extension of the `Examples smoke tests` suite) with 4 tests for the two branches of printExampleDiagnostic and printDiagnostic. The tests are in an extension file because swiftlint file_length (400 lines) stopped them in ExamplesSmokeTests.swift. StandardOutputCapture.capture is now @MainActor, so two captures cannot overlap and hang.
    - test: green. swift test — 151 tests in 15 suites passed, 0 failed, 0 skipped; swiftformat . --lint 0/69 files; swiftlint --strict 0 violations.
    - commit: 92dc44a test(examples): add tests for printDiagnostic and printExampleDiagnostic
    - review: clean. review sha HEAD~1..HEAD — 0 findings (7 attempted, 0 failed); task moved to done.
  timestamp: 2026-09-27T18:33:00.139221+00:00
position_column: done
position_ordinal: ac80
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