---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mtwh7jz1p53cxkrbhbmmpk
  text: |-
    ### Facts from swissarmyhammer-05 about FoundationModelsExtras (2026-09-28)
    Extras OTel A-D are done locally but are not on Extras origin/main yet. Do not start this task until they are on origin/main.
    1. TelemetryCapture (TelemetryTestSupport) uses task-local withTracer and withMetricsFactory. It bootstraps logging one time only. A test process that uses it must NOT call LoggingSystem.bootstrap itself.
    2. A logger or metric that is made before the first capture does not go to the capture. A `static let` logger or metric that a test uses before the capture starts is lost. Make loggers and metrics per call or per instance, or make sure that the capture starts first.
    3. TracedCall.run (the span plus "enter" log helper) gets the trace id and the span id from the traceparent that the tracer injects. InMemoryTracer does not inject, so its records have no ids. A test that checks the ids needs a tracer that injects.
  timestamp: 2026-09-28T20:21:47.378075+00:00
- actor: claude-code
  id: 01m3mwcen68ke4tz101d708mbs
  text: |-
    ### Fact from swissarmyhammer-05 about FoundationModelsExtras (2026-09-28)
    Extras OTel E (^wts388b) is on Extras origin/main (6c399a4). Run `swift package update FoundationModelsExtras` to get it.
    - TelemetryCapture.Context.tracer is now a W3CInMemoryTracer. This tracer injects a traceparent, so a test can check the trace id and the span id that TracedCall.run records.
    - Code that needs the InMemoryTracer type must use `context.tracer.inMemoryTracer`. Code that uses the tracer as `any Tracer`, or reads `finishedSpans`, still compiles.
  timestamp: 2026-09-28T20:47:57.606388+00:00
- actor: claude-code
  id: 01m3my5t4x6m8mpy7ngynb9qbs
  text: |-
    ### Research and implementation notes (implement step)
    - Extras origin/main is 6c399a4 (checked with `git ls-remote`). `swift package update FoundationModelsExtras` moved Package.resolved from 70ad74d to 6c399a4. Package.resolved is in .gitignore, so git shows no change for it.
    - The code changed after this card was written. Commit 1ee5675 removed `catchUpEmbeddings(ids:texts:embeddedFrom:with:)`, `checkedVectors(for:)` and the private `SharedCatalogEmbedding.embeddingPendingEntries`. Now each catalog embed (build, first search, reload loop, shared) goes through one function: `MetadataIndex.embedPendingEntries(with:source:onDiagnostic:)`. The embed span is in that function. Each caller gives its `embed.source`: build -> `.build`, `runFirstSearchCatchUp` -> `.firstSearch`, `runReloadEmbedLoop` -> `.reload`, `SharedCatalogEmbedding.embeddedBatch` -> `.shared`. A new private `checkedVectors(for:with:in:)` sets `embed.outcome`. No span opens when nothing is pending.
    - The span helper is `RegistryTelemetry.withTracedSpan(_:attributes:_:)` in the new file `Telemetry/RegistryTelemetry+Spans.swift`. It calls `TracedCall.run` (rule 8) with `tracer(explicit: nil)` and a new logger for each call (`makeLogger()`), so the capture always gets the records. On a throw it sets `SpanStatus(code: .error)` with no message and `error.type` = the type name. `withSpan` also records the error object itself (swift-distributed-tracing does this). Search, selection rank and embed spans use this helper. The hybrid rank span (synchronous, cannot hang) and the update span (non-throwing) use `tracer.withSpan` directly.
    - `TracedCall.run` is `throws`, not `rethrows`. Thus a non-throwing caller cannot use it without a catch that never runs. The embed path is correct: its body throws on a real embed failure, and the caller catches it (graceful degradation).
    - The retrieval tier moved to the new file `MetadataSearcher+RetrievalTier.swift`, because `MetadataSearcher+Search.swift` went over the swiftlint file length (400). `retrievalSearch` is now internal and returns `TierAnswer` (tier, signals, matches).
    - `embedPendingEntries` got a required `source:` parameter. The 4 call sites in `EmbedPendingEntriesTests.swift` now pass `source: .reload`.
    - Discovery: `TracedCall.enterLevel` is `.info`. A host that does not bootstrap swift-log gets the default StreamLogHandler, so each search and embed prints one "enter" line to stderr. Tests outside a capture show these lines. This is the Extras design, not a change here.
    - periphery could not find the index store with this build system (`.build/index-build/...`). I checked by hand that each new symbol has a caller.
  timestamp: 2026-09-28T21:19:17.149138+00:00
- actor: claude-code
  id: 01m3my6rwg205q8mgsn419rhgj
  text: |-
    ### implement — changed
    - evidence: `swift test` 187 tests in 20 suites passed, 0 warnings from the build. `swiftlint lint` 0 violations. `swiftformat . --lint` 0/79 files need formatting. RED was seen first: 18 of 19 new RegistryTracingTests failed before the implementation.
    - files: Sources/.../Telemetry/RegistryTelemetry.swift, Sources/.../Telemetry/RegistryTelemetry+Spans.swift (new), Sources/.../MetadataSearcher+Search.swift, Sources/.../MetadataSearcher+RetrievalTier.swift (new), Sources/.../Catalog/MetadataIndex+Embedding.swift, Sources/.../SharedCatalogEmbedding.swift, Sources/.../MetadataSearcher+ReloadEmbedLoop.swift, Sources/.../MetadataSearcher+FirstSearchCatchUp.swift, Sources/.../MetadataSearcher.swift (doc only), Tests/.../RegistryTracingTests.swift (new, 19 tests), Tests/.../TelemetryContentSafetyTests.swift, Tests/.../EmbedPendingEntriesTests.swift.
    - next: /review. Task stays in doing. Not committed.
  timestamp: 2026-09-28T21:19:48.624976+00:00
- actor: claude-code
  id: 01m3myfx9m0y9wp27bzt8zxpgg
  text: |-
    ### test — green
    - evidence: swift test — 187 tests passed, 0 failed, 0 skipped, 20 suites, in 12.63 s. swiftlint — 0 violations in 79 files. swiftformat . --lint — 0 of 79 files need format, 2 files skipped.
    - note: swift build shows warning lines for 'failed loading cached manifest' and 'failed storing manifest ... disk I/O error' for every dependency (swift-metrics, swift-log, foundationmodelsextras, foundationmodelsranker, swift-distributed-tracing, swift-service-context, swift-libgit2, swift-syntax, ulid.swift, yams, stencil, swift-argument-parser, spectre, pathkit). This comes from a damaged global SwiftPM manifest cache on this machine, not from package code. The cache was not deleted. The build still completes and all tests pass.
    - next: none. The build is clean.
  timestamp: 2026-09-28T21:24:48.052273+00:00
- actor: claude-code
  id: 01m3myh8dkb4zgx4qqxsd1zwan
  text: |-
    ### commit — changed
    - evidence: d0cb65a feat(telemetry): add spans for search, rank, catalog update, and catalog embed. 16 files. Local commit only, not pushed.
    - next: none. The task is ready for review.
  timestamp: 2026-09-28T21:25:32.211988+00:00
- actor: claude-code
  id: 01m3mywzhpz0cwphqt261vx5fz
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (commit d0cb65a). 1 finding, 1 confirmed, 0 refuted. Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift:185 (code-hygiene/data-driven).
    - next: Do the open item in "Review Findings (2026-09-28 16:25)". Remove this cause from the full file. Then commit and review again. The task stays in review.
  timestamp: 2026-09-28T21:31:56.342212+00:00
- actor: claude-code
  id: 01m3myx97kbced563cxs2jd9sg
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files (3 new); Extras updated to 6c399a4
    - test: green — swift test, 187 passed, 0 failed, 0 skipped; swiftlint 0 in 79 files; swiftformat 0/79
    - commit: d0cb65a
    - review: findings — Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift:185
  timestamp: 2026-09-28T21:32:06.259569+00:00
- actor: claude-code
  id: 01m3mz710bc8t3gmyjx424gbxx
  text: |-
    ### Fix for finding code-hygiene/data-driven (RegistryTelemetry.swift)
    - SearchMode is in this package (Sources/.../SearchMode.swift). It has no associated values. Thus the fix compiles, and there is no conflict.
    - I did not use a `Dictionary<SearchMode, String>`. The carve-out of the data-driven rule says that a map lookup gives an optional, so a new case compiles and makes a missing row at run time. The rule accepts a fix only when the lookup is total, for example a raw value.
    - Change: `public enum SearchMode: String, Sendable`. The implicit raw values are `retrieval`, `selection`, `auto`, the same names as before. The switch `RegistryTelemetry.modeName(of:)` is deleted. `search(intent:limit:)` now sets `search.mode` to `mode.rawValue`, the same pattern as `Tier`, `Ranker`, `EmbedSource` and `EmbedOutcome`. The doc of `AttributeKey.searchMode` and of `SearchMode` tell this.
    - Public API note: `SearchMode` now also conforms to `RawRepresentable` (it has `rawValue` and `init?(rawValue:)`). This is an addition, not a break.
    - No other switch that is a table was in the diff of this task. The `switch mode` in `tierAnswer(intent:limit:)` calls different code in each arm, so it is control flow.
    - TDD: the new test `Tests/.../SearchModeRawValueTests.swift` failed first with "value of type 'SearchMode' has no member 'rawValue'". It passes now.
  timestamp: 2026-09-28T21:37:25.515323+00:00
- actor: claude-code
  id: 01m3mz73meyc3d3er2nj03me09
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMetadataRegistry/SearchMode.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, Tests/FoundationModelsMetadataRegistryTests/SearchModeRawValueTests.swift (new). `swift test`: 188 tests in 21 suites passed, 0 warnings. `swiftlint lint`: 0 violations. `swiftformat . --lint`: 0/80 files need formatting.
    - next: /review. The task stays in doing. Not committed.
  timestamp: 2026-09-28T21:37:28.206381+00:00
- actor: claude-code
  id: 01m3mzbngymevjn50w961tewh7
  text: |-
    ### test — green
    - evidence: `swift test` — 188 tests in 21 suites passed, 0 failed, 0 skipped. `swiftlint` — 0 violations in 80 files. `swiftformat . --lint` — 0 of 80 files need format changes, 2 files skipped by config.
    - note: The run showed no "failed loading cached manifest ... disk I/O error" lines this time. This message comes from a damaged global SwiftPM manifest cache on this machine. The agent did not delete that cache.
    - next: none. The build is clean.
  timestamp: 2026-09-28T21:39:57.598780+00:00
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
position_column: doing
position_ordinal: '80'
title: 'OTel A: add a span for each search and for each catalog build, update and embed'
---
## What

Part A of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Use only the `Tracing` API (swift-distributed-tracing). Get the tracer with `RegistryTelemetry.tracer(explicit: nil)` (resolve late), so a host that bootstraps a backend after it makes a searcher still traces. Do not add a public init parameter.

Rule 4 (no content): a span attribute must never hold the query text (`intent`), a rendered block, an embedded text or a vector. Counts, sizes, mode names and ranker names are safe. Rule 9: FoundationModelsRanker gets no telemetry, so this package measures its calls to the Ranker (`HybridRanker.topMatches(...)` and `SelectionTier.search(intent:limit:)`).

Rule 8 (hang detection): a search in `.selection` mode waits on a model session, and an embed waits on an embedder. Both can suspend for a long time. Open these spans through the shared helper of FoundationModelsExtras task OTel C, short id ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA), "add a shared helper that opens a span and writes one enter log record". It uses swift-log, from Extras task OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV). These tasks are on the FoundationModelsExtras board, so they are not in `depends_on`. Do not start this task until both are done and pushed to `main` of FoundationModelsExtras.

Add the names to `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D, vd487dv), with a doc comment for each name.

Subtasks:
- [x] Search span `FoundationModelsMetadataRegistry.search` in `MetadataSearcher.search(intent:limit:)` in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift`. The span covers `catchUpEmbeddingsBeforeFirstSearch()` and the tier call. Attributes: `search.mode` (the configured `SearchMode`: `retrieval`, `selection`, `auto`), `search.tier` (the tier that answered: `retrieval` or `selection`), `search.limit`, `search.result_count` (the count of returned matches), `catalog.size` (`index.count`), and `search.rankers` (a string array of the rankers that ran). For `retrievalSearch(intent:limit:)`: `bm25` and `trigram` when their `Weights` value is greater than 0, and `cosine` only when `computeCosineScores(...)` returned non-nil. For `selectionSearch(_:intent:limit:)`: `selection`. When the call throws, record the error on the span and set the span status to error. Also record the error type only, never the error message.
- [x] Ranker child span `FoundationModelsMetadataRegistry.rank` around the `HybridRanker.topMatches(...)` call in `retrievalSearch(intent:limit:)` and around `selection.tier.search(intent:limit:)` in `selectionSearch(_:intent:limit:)`. Attributes: `rank.ranker` (`hybrid` or `selection`), `rank.candidate_count` (`index.ids.count` for hybrid, the snapshot count for selection).
- [x] Catalog update span `FoundationModelsMetadataRegistry.catalog.update` in `MetadataSearcher.update(items:)`. Attributes: `catalog.item_count` (`items.count`), `catalog.size` (the count of the new baseline), `catalog.content_changed` (bool), `catalog.pending_embed_count` (`result.pendingEmbedIDs.count`). The hash-guarded no-op path also ends the span, with `catalog.content_changed = false` and `catalog.pending_embed_count = 0`.
- [x] Catalog embed span `FoundationModelsMetadataRegistry.catalog.embed` in `MetadataSearcher.catchUpEmbeddings(ids:texts:embeddedFrom:with:)` (this covers each pass of `runReloadEmbedLoop(with:)` in `MetadataSearcher+ReloadEmbedLoop.swift` and `runFirstSearchCatchUp()` in `MetadataSearcher+FirstSearchCatchUp.swift`), in the private `SharedCatalogEmbedding.embeddingPendingEntries(of:with:onDiagnostic:)` in `SharedCatalogEmbedding.swift`, and in `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` in `Catalog/MetadataIndex+Embedding.swift`. Attributes: `embed.pending_count`, `catalog.size`, `embed.source` (`reload`, `first_search`, `shared`, `build`), `embed.outcome` (`embedded` or `failed`, from the result of `checkedVectors(for:)`). (Implemented in the one shared step `MetadataIndex.embedPendingEntries(with:source:onDiagnostic:)`, which each of these paths now calls after commit 1ee5675. See the comment of the implement step.)
- [x] New test file `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/RegistryTracingTests.swift` (see Tests). Each test runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product, with the query text and the item content as forbidden strings, so it also proves rule 4 for the new spans.

## Acceptance Criteria
- [x] Each `search(intent:limit:)` call ends exactly one `FoundationModelsMetadataRegistry.search` span, with one `FoundationModelsMetadataRegistry.rank` child, and with the attributes above. The values of `search.result_count`, `catalog.size` and `search.rankers` agree with the call.
- [x] A `.retrieval` search with no embedder has `search.rankers == ["bm25", "trigram"]`. With `FakeEmbedder` and an embedded catalog, it has `["bm25", "trigram", "cosine"]`. A `.selection` search has `["selection"]`.
- [x] A `.selection` search with no selection tier ends its span with error status, and the span has no error message text.
- [x] Each `update(items:)` call ends one `catalog.update` span. Each embed pass ends one `catalog.embed` span with the correct `embed.source` and `embed.outcome`.
- [x] No span attribute holds the query text or item content (`TelemetryCapture` reports no issue).

## Tests
- [x] In `RegistryTracingTests.swift`: one test for each tier (`.retrieval` with no embedder, `.retrieval` with `TestSupport/FakeEmbedder.swift`, `.selection` with `TestSupport/ScriptedAgentSession.swift`, `.auto`), which checks the span names, parent/child link and attributes.
- [x] A test for the `SelectionTierUnavailable` throw path (error status, no message text).
- [x] Tests for `update(items:)` (content changed, no-op), for a failed embed (use a throwing embedder, see `TestSupport/GatedEmbedder.swift` / `FakeEmbedder.swift`), for `SharedCatalogEmbedding` (`embed.source = shared`, one embed span for two sharing searchers), and for `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`.
- [x] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #search-tools #catalog #embedding

## Review Findings (2026-09-28 16:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift:185` `code-hygiene/data-driven` — A switch statement over a closed enum (`SearchMode`) where each arm returns only a different string constant. This is a table written as control flow. The same logic can be expressed as a data-driven lookup (e.g., a static dictionary or a rawValue property), which is easier to read, extend, and verify correct. Replace the switch with a static `Dictionary<SearchMode, String>` or, if `SearchMode` has a `rawValue` property matching the output strings, use `mode.rawValue` directly.
