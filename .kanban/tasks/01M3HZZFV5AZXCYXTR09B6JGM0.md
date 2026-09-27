---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3j1022022bc3nx7b5jja8ht
  text: 'Research: `MetadataDiagnostic.log(_:)` (Diagnostics.swift:70-94) has an exhaustive switch over 5 cases. Each case calls `logger.notice` on a private `Logger(subsystem: "FoundationModelsMetadataRegistry", category: "MetadataDiagnostic")`. The function returns `Void`. The test-integrity rule flags a test with no assertion. Thus the plan is to read the entries back from `OSLogStore(scope: .currentProcessIdentifier)` and assert that each case writes a message that holds its values. A second test uses an exhaustive switch over a local `CaseName` enum, so a new case in `MetadataDiagnostic` stops the compile until the fixture list holds it.'
  timestamp: 2026-09-27T18:10:51.072151+00:00
- actor: claude-code
  id: 01m3j1ejpcty3q4vy59h12dqd1
  text: |-
    What did not work: a parameterized `@Test(arguments:)` over the 5 cases, with one `OSLogStore` read for each case. Each read takes about 4 seconds. In parallel, the first run crashed the test process with no issue line. With `.serialized`, the test was stable but took 17 to 21 seconds. Result: one test writes all 5 cases, reads the store one time, and does one `#expect` for each case (5 to 9 seconds). A second test `loggedMessagesHoldEachCaseOneTime` keeps the "each case is in the list" check: it maps the fixture list through an exhaustive switch into `CaseName` and compares with `CaseName.allCases`.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift (swift test --filter DiagnosticsTests: 3 tests pass, 3 runs of 3)
    - next: test
  timestamp: 2026-09-27T18:18:46.860770+00:00
- actor: claude-code
  id: 01m3j1fzc232e8shpp73cp0chz
  text: |-
    ### test — green
    - evidence: swift test — 145 tests in 15 suites passed, 0 failed, 0 skipped; swiftformat . --lint — 0/68 files require formatting; swiftlint --strict — 0 violations in 68 files
    - next: commit
  timestamp: 2026-09-27T18:19:32.610079+00:00
- actor: claude-code
  id: 01m3j1k65gmrdna6avagvjd1rk
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings, 0 confirmed, 0 refuted (7 validators attempted, 0 failed); .kanban/ files not reviewed (.reviewignore)
    - next: done
  timestamp: 2026-09-27T18:21:17.872770+00:00
- actor: claude-code
  id: 01m3j1k9mn5m5j2jwcjcgjes58
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift (log(_:) writes each of 5 cases, then one OSLogStore read checks each message; exhaustive-switch check that the fixture list holds each case)
    - test: green — swift test 145 tests in 15 suites passed, 0 failed, 0 skipped; swiftformat --lint 0/68; swiftlint --strict 0 violations
    - commit: 700d6d4
    - review: clean — review sha HEAD~1..HEAD, 0 findings; task moved to done
  timestamp: 2026-09-27T18:21:21.429890+00:00
position_column: done
position_ordinal: aa80
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