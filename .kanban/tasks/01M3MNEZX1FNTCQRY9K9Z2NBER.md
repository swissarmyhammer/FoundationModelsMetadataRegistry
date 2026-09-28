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
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
position_column: todo
position_ordinal: '8280'
title: 'OTel B: replace the os.Logger in MetadataDiagnostic.log with swift-log'
---
## What

Part B of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Rule 2: remove all `os.Logger` use and use `Logging.Logger` (swift-log) in its place. Do not keep unified-logging output. The library uses only the swift-log API and never bootstraps a log handler.

The one `os.Logger` site of the library is in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift`: `import os` (line 1), `private static let logger = Logger(subsystem: "FoundationModelsMetadataRegistry", category: "MetadataDiagnostic")` (line 62), and `public static func log(_ diagnostic: MetadataDiagnostic)`, which writes each case at `.notice` with `privacy: .public` interpolation. `import os` in `Examples/HotReloadCore/HotReloadCore.swift` and in `Tests/.../TestSupport/ScriptedAgentSession.swift` / `SelectionFixtures.swift` is for `OSAllocatedUnfairLock` only. It is not logging, so do not change it.

External dependency (FoundationModelsExtras board, so not in `depends_on`): Extras OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV), "add swift-log and swift-metrics to the core target as API only". Task D (vd487dv) of this board adds swift-log to `Package.swift` with the same version floor, so this task depends on D.

Rule 4 (no content): a log message and a log metadata value must never hold query text or item content. The catalog id in `.duplicateId(id:)` and `.unknownSelectedId(id:)` is an identifier, so it is safe. Counts are safe.

Subtasks:
- [ ] In `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D), add the logger label `FoundationModelsMetadataRegistry.MetadataDiagnostic` and the log metadata keys: `diagnostic.case` (the case name), `catalog.id`, `retrieval.considered`, `retrieval.kept`, `embed.pending_count`, `catalog.size`. Give each key a doc comment.
- [ ] In `Diagnostics.swift`, replace `import os` with `import Logging`, and replace the `os.Logger` with `Logging.Logger(label:)` that uses the label above. Keep `log(_:)` public, with the same signature. Write each case at `.notice`. Keep the current message text (tests match parts of it), with no `privacy:` interpolation. Also put each value in the log metadata with the keys above, so that a backend can query the values without a parse of the message.
- [ ] Update `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/DiagnosticsTests.swift`: remove `import OSLog`, `logSubsystem`, `logCategory` and `messagesInLogStore(since:)`. Change `logWritesEachCaseToTheLogStore()` so that it runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product and reads the recorded log records. It checks, for each case: the logger label, the level `.notice`, the message text in `loggedMessages`, and the metadata values. Update the doc comments that say `os.Logger`.
- [ ] Update the comment at line 75 of `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests+DiagnosticPrinting.swift` ("writes to os.Logger, not to stdout"). Note: when no process bootstraps swift-log, the default handler writes to stdout. `capturedDiagnosticLines(_:)` keeps only the lines with `diagnosticPrefix`, so `printExampleDiagnosticPrintsNothingWhenDescribeGivesNoMessage()` must still pass. Make sure that the log line never starts with that prefix.
- [ ] Update `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/plan.md` lines 305 and 523, which say "`os.Logger` sink", to say swift-log. Run `PlanDocumentTests` to make sure that no pinned text breaks.

## Acceptance Criteria
- [ ] `rg -n "os\.Logger|import OSLog|OSSignposter" Sources Tests Examples` finds no code (only `OSAllocatedUnfairLock` users still import `os`).
- [ ] `MetadataDiagnostic.log(_:)` writes one `.notice` record for each case through the logger with label `FoundationModelsMetadataRegistry.MetadataDiagnostic`, with the metadata keys above.
- [ ] The public API of `MetadataDiagnostic` does not change.
- [ ] `DiagnosticsTests`, `ExamplesSmokeTests` and `TelemetryContentSafetyTests` pass.

## Tests
- [ ] `DiagnosticsTests.logWritesEachCaseToTheLogStore()` (rename it to fit, for example `logWritesEachCaseToTheLogger()`) as above. It fails before the change, because no swift-log record exists.
- [ ] Add a test in `DiagnosticsTests.swift` that checks the metadata values of `.embedCatchUp(pending:total:)` and `.duplicateId(id:)`.
- [ ] `TelemetryContentSafetyTests` (made by task D) already calls `MetadataDiagnostic.log(_:)` for each case. Make sure it now sees the log records and reports no issue.
- [ ] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #metadata