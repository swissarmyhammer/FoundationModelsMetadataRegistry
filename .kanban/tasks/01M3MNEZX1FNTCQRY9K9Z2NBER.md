---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtwkkw343exa9jqb6yk7jh
  text: |-
    ### Facts from swissarmyhammer-05 about FoundationModelsExtras (2026-09-28)
    Extras OTel A-D are done locally but are not on Extras origin/main yet. Do not start this task until they are on origin/main.
    1. TelemetryCapture (TelemetryTestSupport) bootstraps logging one time only. A test process that uses it must NOT call LoggingSystem.bootstrap itself.
    2. A logger that is made before the first capture does not go to the capture. A `static let` logger that a test uses before the capture starts is lost. Make the logger per call or per instance, or make sure that the capture starts first. This applies to MetadataDiagnostic.log.
  timestamp: 2026-09-28T20:21:49.820409+00:00
- actor: claude-code
  id: 01m3mzknxbtnw73qyg52kj32za
  text: |-
    ### Research (implement)
    - Extras is at 6c399a4 in .build/checkouts. TelemetryTestSupport is in `Tests/TelemetryTestSupport` of Extras. `TelemetryCapture.Context.logRecords` gives `[InMemoryLogHandler.Entry]` with `level`, `message`, `metadata` only.
    - A captured record does not hold the logger label. The routing handler of the capture ignores the label. Thus the test checks the label through `RegistryTelemetry.makeLogger().label`, the same pattern as `ExtrasTelemetryTests` ("the logger has the module name as its label"). `log(_:)` uses `makeLogger()`.
    - `RegistryTelemetry.loggerLabel` (value `FoundationModelsMetadataRegistry.MetadataDiagnostic`) and `RegistryTelemetry.makeLogger()` (a new logger for each call) already exist from task D / OTel A. Reuse them. Do not add a second label constant.
    - `RegistryTelemetry.MetadataKey` is an empty enum with a `periphery:ignore` comment. This task adds the keys, so remove that comment.
    - No ARCHITECTURE.md. No PlanDocumentTests text pins "os.Logger".
    - If no capture bootstrapped swift-log, the default StreamLogHandler writes to stdout. Its line starts with a timestamp, so it never starts with "[diagnostic] ".
  timestamp: 2026-09-28T21:44:20.139370+00:00
- actor: claude-code
  id: 01m3n03kk14fg71v263e7kg3sk
  text: |-
    ### Implementation landed
    - RED: the new `DiagnosticsTests` log tests failed before the change with `records.count → 0` (no swift-log record).
    - `Diagnostics.swift`: `import Logging`. The `static let` os.Logger is gone. `log(_:)` calls `RegistryTelemetry.makeLogger()` for each call (the existing helper of OTel A; no second helper). One private `LogRecord` struct holds case name, message and metadata values. The switch has no `default`.
    - `RegistryTelemetry.swift`: `MetadataKey` now holds `diagnosticCase`, `catalogId`, `retrievalConsidered`, `retrievalKept`, `embedPendingCount`, `catalogSize`. The `periphery:ignore` marker on `MetadataKey` is removed, because the keys are now used. A new `DiagnosticCase: String` enum gives the value of `diagnostic.case` (the Swift case name), in the same pattern as `Tier`, `Signal`, `Ranker`.
    - Counts go in as `.stringConvertible(Int)`, ids as `.string`.
    - `Package.swift`: the test target now names the `Logging` product, because `DiagnosticsTests` imports `Logging`.
    - `TelemetryContentSafetyTests.loggingADiagnosticKeepsContentOutOfTheTelemetry` now also expects one log record in the capture.
    - Discovery: `TelemetryCapture` records do not hold the logger label (the routing handler of the capture ignores it). Thus the label is checked with `RegistryTelemetry.makeLogger().label` in `registryLoggerHasTheDiagnosticsLabel()`, the same pattern as `ExtrasTelemetryTests`.
    - First swiftlint run gave `large_tuple` (Diagnostics.swift, DiagnosticsTests.swift x2) and `line_length` (DiagnosticsTests.swift). Replaced the tuples with named structs (`LogRecord`, `ExpectedRecord`, `CapturedRecord`) and wrapped the lines. Now clean.
    - SwiftPM prints "failed loading cached manifest ... disk I/O error" warnings. They come from the SwiftPM manifest cache of this machine, not from the code.
  timestamp: 2026-09-28T21:53:02.049422+00:00
- actor: claude-code
  id: 01m3n03pex36d8jh0bqg8z417y
  text: |-
    ### implement — changed
    - evidence: `swift test` 190 tests in 21 suites passed, 0 compiler warnings; `swiftlint lint` 0 violations; `swiftformat . --lint` 0/80 files need formatting. Files: Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift, Package.swift, Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift, Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift, Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests+DiagnosticPrinting.swift, plan.md
    - next: /review
  timestamp: 2026-09-28T21:53:04.989662+00:00
- actor: claude-code
  id: 01m3n08rpgws9xc77wy4agk0dp
  text: |-
    ### test — green
    - evidence: swift test — 190 tests passed, 0 failed, 0 skipped, in 21 test groups. swiftlint — 0 rule breaks in 80 files. swiftformat . --lint — 0 of 80 files need a format change.
    - note: swift build shows warning lines about a bad global manifest cache, for example "warning: 'swift-log': failed loading cached manifest for 'swift-log': disk I/O error". This is a known fault on this machine's cache, not a code fault. Per instruction, the cache stays as is.
    - next: no action needed. The build is clean.
  timestamp: 2026-09-28T21:55:51.120395+00:00
- actor: claude-code
  id: 01m3n0akpqr4m536j35r22ctqr
  text: |-
    ### commit — changed
    - evidence: bb9e230 feat(telemetry): use swift-log in MetadataDiagnostic.log, not os.Logger
    - next: none
  timestamp: 2026-09-28T21:56:51.543890+00:00
- actor: claude-code
  id: 01m3n0htbf38xeq5bd851ea279
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (bb9e230). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 6 files reviewed. An ignore rule excluded 4 .kanban files. No validator matched plan.md. The task has no earlier Review Findings sections.
    - next: None. The task moved to done.
  timestamp: 2026-09-28T22:00:47.727916+00:00
- actor: claude-code
  id: 01m3n0j1peahpprkyk87ztsbwn
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files
    - test: green — swift test, 190 passed, 0 failed, 0 skipped; swiftlint 0 in 80 files; swiftformat 0/80
    - commit: bb9e230
    - review: clean — 6 files, 0 findings
  timestamp: 2026-09-28T22:00:55.246142+00:00
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
position_column: done
position_ordinal: b080
title: 'OTel B: replace the os.Logger in MetadataDiagnostic.log with swift-log'
---
## What

Part B of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Rule 2: remove all `os.Logger` use and use `Logging.Logger` (swift-log) in its place. Do not keep unified-logging output. The library uses only the swift-log API and never bootstraps a log handler.

The one `os.Logger` site of the library is in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift`: `import os` (line 1), `private static let logger = Logger(subsystem: "FoundationModelsMetadataRegistry", category: "MetadataDiagnostic")` (line 62), and `public static func log(_ diagnostic: MetadataDiagnostic)`, which writes each case at `.notice` with `privacy: .public` interpolation. `import os` in `Examples/HotReloadCore/HotReloadCore.swift` and in `Tests/.../TestSupport/ScriptedAgentSession.swift` / `SelectionFixtures.swift` is for `OSAllocatedUnfairLock` only. It is not logging, so do not change it.

External dependency (FoundationModelsExtras board, so not in `depends_on`): Extras OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV), "add swift-log and swift-metrics to the core target as API only". Task D (vd487dv) of this board adds swift-log to `Package.swift` with the same version floor, so this task depends on D.

Rule 4 (no content): a log message and a log metadata value must never hold query text or item content. The catalog id in `.duplicateId(id:)` and `.unknownSelectedId(id:)` is an identifier, so it is safe. Counts are safe.

Subtasks:
- [x] In `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D), add the logger label `FoundationModelsMetadataRegistry.MetadataDiagnostic` and the log metadata keys: `diagnostic.case` (the case name), `catalog.id`, `retrieval.considered`, `retrieval.kept`, `embed.pending_count`, `catalog.size`. Give each key a doc comment.
- [x] In `Diagnostics.swift`, replace `import os` with `import Logging`, and replace the `os.Logger` with `Logging.Logger(label:)` that uses the label above. Keep `log(_:)` public, with the same signature. Write each case at `.notice`. Keep the current message text (tests match parts of it), with no `privacy:` interpolation. Also put each value in the log metadata with the keys above, so that a backend can query the values without a parse of the message.
- [x] Update `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift`: remove `import OSLog`, `logSubsystem`, `logCategory` and `messagesInLogStore(since:)`. Change `logWritesEachCaseToTheLogStore()` so that it runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product and reads the recorded log records. It checks, for each case: the logger label, the level `.notice`, the message text in `loggedMessages`, and the metadata values. Update the doc comments that say `os.Logger`.
- [x] Update the comment at line 75 of `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests+DiagnosticPrinting.swift` ("writes to os.Logger, not to stdout"). Note: when no process bootstraps swift-log, the default handler writes to stdout. `capturedDiagnosticLines(_:)` keeps only the lines with `diagnosticPrefix`, so `printExampleDiagnosticPrintsNothingWhenDescribeGivesNoMessage()` must still pass. Make sure that the log line never starts with that prefix.
- [x] Update `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/plan.md` lines 305 and 523, which say "`os.Logger` sink", to say swift-log. Run `PlanDocumentTests` to make sure that no pinned text breaks.

## Acceptance Criteria
- [x] `rg -n "os\.Logger|import OSLog|OSSignposter" Sources Tests Examples` finds no code (only `OSAllocatedUnfairLock` users still import `os`).
- [x] `MetadataDiagnostic.log(_:)` writes one `.notice` record for each case through the logger with label `FoundationModelsMetadataRegistry.MetadataDiagnostic`, with the metadata keys above.
- [x] The public API of `MetadataDiagnostic` does not change.
- [x] `DiagnosticsTests`, `ExamplesSmokeTests` and `TelemetryContentSafetyTests` pass.

## Tests
- [x] `DiagnosticsTests.logWritesEachCaseToTheLogStore()` (rename it to fit, for example `logWritesEachCaseToTheLogger()`) as above. It fails before the change, because no swift-log record exists.
- [x] Add a test in `DiagnosticsTests.swift` that checks the metadata values of `.embedCatchUp(pending:total:)` and `.duplicateId(id:)`.
- [x] `TelemetryContentSafetyTests` (made by task D) already calls `MetadataDiagnostic.log(_:)` for each case. Make sure it now sees the log records and reports no issue.
- [x] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #metadata