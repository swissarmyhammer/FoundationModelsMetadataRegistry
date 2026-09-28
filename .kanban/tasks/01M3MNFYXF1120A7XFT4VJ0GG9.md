---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtwp37v2s74v0xmvysvfsz
  text: |-
    ### Facts from swissarmyhammer-05 about FoundationModelsExtras (2026-09-28)
    Extras OTel A-D are done locally but are not on Extras origin/main yet. Do not start this task until they are on origin/main.
    1. TelemetryCapture (TelemetryTestSupport) uses task-local withMetricsFactory. A test process that uses it must NOT call LoggingSystem.bootstrap itself.
    2. A metric that is made before the first capture does not go to the capture. A `static let` metric (Timer, Gauge, Counter) that a test uses before the capture starts is lost. Make metrics per call or per instance, or make sure that the capture starts first.
  timestamp: 2026-09-28T20:21:52.359443+00:00
- actor: claude-code
  id: 01m3n0qjd739k680qcxyp8662f
  text: |-
    ### Research (implement)
    - `search(intent:limit:)` is in `MetadataSearcher+Search.swift`. It opens the search span and calls `answer(intent:limit:recordingIn:)`, which calls `tierAnswer(intent:limit:)`. The span gets `search.tier` from `TierAnswer.tier`. On the error path there is no `TierAnswer`, so the metric needs the tier from the same switch. Plan: move the switch on `mode` into one `TierRoute` value (retrieval, selection, unavailable). `tierAnswer` uses it, and the error path reads `route.tier` (nil gives `none`). The success path uses `answer.tier`, the same value as the span.
    - The HybridRanker call is in `retrievalSearch(intent:limit:)` in `MetadataSearcher+RetrievalTier.swift`, inside the `rank` span. The selection tier call is in `selectionSearch(_:intent:limit:)`, inside `withTracedSpan`. Use `Timer.measure(body:)` of swift-metrics (2.11.0) around each call.
    - The designated `init(index:mode:weights:embedder:sharedEmbedding:selection:onDiagnostic:)` is in `MetadataSearcher.swift`. `reload(items:recordingIn:)` assigns `index = baseline` after the hash guard.
    - `TelemetryCapture.Context.metricsFactory` is a `TestMetrics` (MetricsTestKit). `TestMetrics` keeps one handler for each label and dimension set, so `expectTimer(label, dimensions).values` gives each recorded value. A `Gauge` is a `TestRecorder` (`expectGauge`). The test target must link `Metrics` and `MetricsTestKit` from swift-metrics.
    - Reuse `RegistryTelemetry.Tier` and `RegistryTelemetry.Ranker` for the dimension values. Add a new `Outcome` enum (`success`, `error`) and a `none` value for no tier.
  timestamp: 2026-09-28T22:03:56.199362+00:00
- actor: claude-code
  id: 01m3n1797x6g6cc8zfzf4g7jcp
  text: |-
    ### Implementation notes
    - TDD: I wrote `RegistryMetricsTests.swift` first. All 9 tests failed because no metric was recorded (RED). Then I added the metrics (GREEN).
    - New file `Telemetry/RegistryTelemetry+Metrics.swift`: `recordSearchDuration(_:tier:outcome:)`, `rankTimer(for:)` and `recordCatalogSize(_:)`. Each helper makes its metric at the call, never in a `static let`, so `TelemetryCapture` (task-local `withMetricsFactory`) sees it.
    - `RegistryTelemetry.swift`: `MetricName` now has `searchDuration`, `rankDuration` and `catalogSize`, each with unit and dimensions in its doc comment. New `DimensionKey` (`tier`, `outcome`, `ranker`), `Outcome` (`success`, `error`) and `noTier = "none"`. The dimension values reuse `Tier` and `Ranker`. The `// periphery:ignore` marker on `MetricName` is gone, because the names now have callers.
    - `MetadataSearcher+Search.swift`: new `TierRoute` enum (retrieval, selection, unavailable). `tierAnswer(_:intent:limit:)` switches on it. `answer(intent:limit:recordingIn:)` measures with `ContinuousClock`. On success the `tier` dimension is `answer.tier`, the same value as the `search.tier` span attribute. On error it is `route.tier` (`nil` gives `none`). The selection tier call is inside `rankTimer(for: .selection).measure`, so a session that throws also records a rank duration.
    - `MetadataSearcher+RetrievalTier.swift`: the `HybridRanker.topMatches` call is inside `rankTimer(for: .hybrid).measure`, inside the rank span. `limit <= 0` or an empty catalog records no rank duration.
    - `MetadataSearcher.swift`: the designated init records `index.count` in the gauge. `reload(items:recordingIn:)` records `baseline.count` after `index = baseline`, after the hash guard.
    - `Package.swift`: the test target links `MetricsTestKit` (swift-metrics) to read `TestMetrics` values.
    - Discovery: a searcher with no embedder never takes the hash-guarded no-op path of `update(items:)`, because its entries stay pending an embed. The no-op gauge test uses an embedded searcher (the same setup as the tracing no-op test).
    - SwiftLint `file_length` (400) fired on `MetadataSearcher.swift` at 402 lines after my first doc edit. I shortened the doc comment; the file is now 399 lines.
    - The `swift test` output shows "disk I/O error" warnings for the SwiftPM manifest cache of pathkit and spectre. These come from the local cache, not from the code.
  timestamp: 2026-09-28T22:12:31.101714+00:00
- actor: claude-code
  id: 01m3n17c47sr5bqesrvka0wexg
  text: |-
    ### implement — changed
    - evidence: `swift test` 199 tests in 22 suites passed (9 new in RegistryMetricsTests); `swiftlint lint` 0 violations; `swiftformat . --lint` 0/82 files need formatting. Files: Package.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry+Metrics.swift (new), Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+RetrievalTier.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Tests/FoundationModelsMetadataRegistryTests/RegistryMetricsTests.swift (new).
    - next: /review
  timestamp: 2026-09-28T22:12:34.055213+00:00
- actor: claude-code
  id: 01m3n1g3hszgjex8x6815x9tc1
  text: |-
    ### test — green
    - command: swift test — 199 tests, 22 suites, 0 fail, 0 skip.
    - command: swiftlint — 0 rule breaks in 82 files.
    - command: swiftformat . --lint — 0 of 82 files need a change.
    - command: swift build — build is clean. The only messages are lines like "failed loading cached manifest for 'yams': disk I/O error" for yams, swift-argument-parser, swift-libgit2, pathkit, spectre, and "failed storing manifest ... in cache" for the same set plus ulid.swift and stencil. These come from a damaged global SwiftPM manifest cache on this machine, not from this code. Per instruction, the cache is not deleted.
    - No skipped or disabled tests found in the test files.
    - next: none. The build is clean.
  timestamp: 2026-09-28T22:17:20.185492+00:00
- actor: claude-code
  id: 01m3n1hbnbs8xy4k2kxhcec0pz
  text: |-
    ### commit — changed
    - evidence: 99a4fac feat(telemetry): add metrics for search time, rank time, and catalog size
    - next: none. The commit is a local commit only. It is not pushed.
  timestamp: 2026-09-28T22:18:01.259748+00:00
- actor: claude-code
  id: 01m3n1trtpsxve2nrhv25t53m5
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 99a4fac). 7 files reviewed. 0 findings, 0 confirmed, 0 refuted, 0 failed. The task has no earlier review findings.
    - next: none. The task is in done.
  timestamp: 2026-09-28T22:23:09.654392+00:00
- actor: claude-code
  id: 01m3n1tzjdr34zmsg4700dsk9h
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (2 new)
    - test: green — swift test, 199 passed, 0 failed, 0 skipped; swiftlint 0 in 82 files; swiftformat 0/82
    - commit: 99a4fac
    - review: clean — 7 files, 0 findings
  timestamp: 2026-09-28T22:23:16.557461+00:00
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
- 01M3MNDY0Q77SYFCYWP376QRQP
position_column: done
position_ordinal: b180
title: 'OTel C: add metrics for search duration, ranker duration and catalog size'
---
## What

Part C of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Use only the `Metrics` API (swift-metrics). The library never calls `MetricsSystem.bootstrap`. Until a host bootstraps a backend, each metric is a no-op.

Rule 4 (no content): a metric dimension must never hold query text or item content. Use only the small fixed value sets below. Do not use a catalog id, a searcher id or any other value with no fixed limit as a dimension. Rule 9: FoundationModelsRanker gets no telemetry, so this package measures its calls to the Ranker.

External dependency (FoundationModelsExtras board, so not in `depends_on`): Extras OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV), "add swift-log and swift-metrics to the core target as API only". Task D (vd487dv) of this board adds swift-metrics to `Package.swift` with the same version floor. This task also depends on task A (376qrqp), because both tasks change `search(intent:limit:)`. Use the tier value that task A computes for `search.tier`, so the span and the metric agree.

Add the names to `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D), in `RegistryTelemetry.MetricName`, with a doc comment for each name that gives the unit and the dimensions.

Subtasks:
- [x] Search duration: a `Metrics.Timer` named `FoundationModelsMetadataRegistry.search.duration` (nanoseconds). Record it one time for each `MetadataSearcher.search(intent:limit:)` call in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift`, also when the call throws. Dimensions: `tier` (`retrieval` or `selection`; `none` when `.selection` mode throws `SelectionTierUnavailable`) and `outcome` (`success` or `error`). Use `ContinuousClock` to measure.
- [x] Ranker duration: a `Metrics.Timer` named `FoundationModelsMetadataRegistry.rank.duration` around the `HybridRanker.topMatches(...)` call in `retrievalSearch(intent:limit:)` and around `selection.tier.search(intent:limit:)` in `selectionSearch(_:intent:limit:)`. Dimension: `ranker` (`hybrid` or `selection`).
- [x] Catalog size: a `Metrics.Gauge` named `FoundationModelsMetadataRegistry.catalog.size` (count of items). Record `index.count` in the internal designated `MetadataSearcher.init(index:...)` at `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` line 328 (each public init goes through it), and in `MetadataSearcher.update(items:)` after it assigns the new baseline. The hash-guarded no-op path of `update(items:)` does not record. No dimensions. Write in the doc comment that with two or more searchers the gauge holds the last value that any searcher recorded.
- [x] New test file `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/RegistryMetricsTests.swift` (see Tests). Each test runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product (task z6jqd9g on the Extras board), with the query text and the item content as forbidden strings.

## Acceptance Criteria
- [x] Each `search(intent:limit:)` call records exactly one `search.duration` value with the correct `tier` and `outcome` dimensions, and one `rank.duration` value when a ranker ran.
- [x] A `.selection` search with no selection tier records `search.duration` with `tier = none` and `outcome = error`, and no `rank.duration`.
- [x] Making a searcher over N items sets `catalog.size` to N. `update(items:)` with M different items sets it to M. A no-op `update(items:)` records nothing.
- [x] Each metric dimension value is in its fixed set, and `TelemetryCapture` reports no issue.

## Tests
- [x] In `RegistryMetricsTests.swift`: one test for each tier (`.retrieval`, `.selection` with `TestSupport/ScriptedAgentSession.swift`, `.auto`) that checks the recorded timers and their dimensions; one test for the `SelectionTierUnavailable` path; tests for the `catalog.size` gauge at init, after `update(items:)`, and after a no-op `update(items:)`.
- [x] Do not check the duration values. Check only that one value was recorded and that it is not negative, so that the tests are stable.
- [x] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #search-tools #catalog