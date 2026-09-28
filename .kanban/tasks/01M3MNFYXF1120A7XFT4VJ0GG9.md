---
assignees:
- claude-code
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
- 01M3MNDY0Q77SYFCYWP376QRQP
position_column: todo
position_ordinal: '8380'
title: 'OTel C: add metrics for search duration, ranker duration and catalog size'
---
## What

Part C of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Use only the `Metrics` API (swift-metrics). The library never calls `MetricsSystem.bootstrap`. Until a host bootstraps a backend, each metric is a no-op.

Rule 4 (no content): a metric dimension must never hold query text or item content. Use only the small fixed value sets below. Do not use a catalog id, a searcher id or any other value with no fixed limit as a dimension. Rule 9: FoundationModelsRanker gets no telemetry, so this package measures its calls to the Ranker.

External dependency (FoundationModelsExtras board, so not in `depends_on`): Extras OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV), "add swift-log and swift-metrics to the core target as API only". Task D (vd487dv) of this board adds swift-metrics to `Package.swift` with the same version floor. This task also depends on task A (376qrqp), because both tasks change `search(intent:limit:)`. Use the tier value that task A computes for `search.tier`, so the span and the metric agree.

Add the names to `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D), in `RegistryTelemetry.MetricName`, with a doc comment for each name that gives the unit and the dimensions.

Subtasks:
- [ ] Search duration: a `Metrics.Timer` named `FoundationModelsMetadataRegistry.search.duration` (nanoseconds). Record it one time for each `MetadataSearcher.search(intent:limit:)` call in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift`, also when the call throws. Dimensions: `tier` (`retrieval` or `selection`; `none` when `.selection` mode throws `SelectionTierUnavailable`) and `outcome` (`success` or `error`). Use `ContinuousClock` to measure.
- [ ] Ranker duration: a `Metrics.Timer` named `FoundationModelsMetadataRegistry.rank.duration` around the `HybridRanker.topMatches(...)` call in `retrievalSearch(intent:limit:)` and around `selection.tier.search(intent:limit:)` in `selectionSearch(_:intent:limit:)`. Dimension: `ranker` (`hybrid` or `selection`).
- [ ] Catalog size: a `Metrics.Gauge` named `FoundationModelsMetadataRegistry.catalog.size` (count of items). Record `index.count` in the internal designated `MetadataSearcher.init(index:...)` at `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` line 328 (each public init goes through it), and in `MetadataSearcher.update(items:)` after it assigns the new baseline. The hash-guarded no-op path of `update(items:)` does not record. No dimensions. Write in the doc comment that with two or more searchers the gauge holds the last value that any searcher recorded.
- [ ] New test file `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/RegistryMetricsTests.swift` (see Tests). Each test runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product (task z6jqd9g on the Extras board), with the query text and the item content as forbidden strings.

## Acceptance Criteria
- [ ] Each `search(intent:limit:)` call records exactly one `search.duration` value with the correct `tier` and `outcome` dimensions, and one `rank.duration` value when a ranker ran.
- [ ] A `.selection` search with no selection tier records `search.duration` with `tier = none` and `outcome = error`, and no `rank.duration`.
- [ ] Making a searcher over N items sets `catalog.size` to N. `update(items:)` with M different items sets it to M. A no-op `update(items:)` records nothing.
- [ ] Each metric dimension value is in its fixed set, and `TelemetryCapture` reports no issue.

## Tests
- [ ] In `RegistryMetricsTests.swift`: one test for each tier (`.retrieval`, `.selection` with `TestSupport/ScriptedAgentSession.swift`, `.auto`) that checks the recorded timers and their dimensions; one test for the `SelectionTierUnavailable` path; tests for the `catalog.size` gauge at init, after `update(items:)`, and after a no-op `update(items:)`.
- [ ] Do not check the duration values. Check only that one value was recorded and that it is not negative, so that the tests are stable.
- [ ] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #search-tools #catalog