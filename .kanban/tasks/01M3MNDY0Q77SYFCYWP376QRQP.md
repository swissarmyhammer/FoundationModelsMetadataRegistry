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
depends_on:
- 01M3MNBPPECY20MSET2VD487DV
position_column: todo
position_ordinal: '8180'
title: 'OTel A: add a span for each search and for each catalog build, update and embed'
---
## What

Part A of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Use only the `Tracing` API (swift-distributed-tracing). Get the tracer with `RegistryTelemetry.tracer(explicit: nil)` (resolve late), so a host that bootstraps a backend after it makes a searcher still traces. Do not add a public init parameter.

Rule 4 (no content): a span attribute must never hold the query text (`intent`), a rendered block, an embedded text or a vector. Counts, sizes, mode names and ranker names are safe. Rule 9: FoundationModelsRanker gets no telemetry, so this package measures its calls to the Ranker (`HybridRanker.topMatches(...)` and `SelectionTier.search(intent:limit:)`).

Rule 8 (hang detection): a search in `.selection` mode waits on a model session, and an embed waits on an embedder. Both can suspend for a long time. Open these spans through the shared helper of FoundationModelsExtras task OTel C, short id ykgz2aa (01M3MN91YK71YVJ9C7WYKGZ2AA), "add a shared helper that opens a span and writes one enter log record". It uses swift-log, from Extras task OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV). These tasks are on the FoundationModelsExtras board, so they are not in `depends_on`. Do not start this task until both are done and pushed to `main` of FoundationModelsExtras.

Add the names to `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift` (made by task D, vd487dv), with a doc comment for each name.

Subtasks:
- [ ] Search span `FoundationModelsMetadataRegistry.search` in `MetadataSearcher.search(intent:limit:)` in `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift`. The span covers `catchUpEmbeddingsBeforeFirstSearch()` and the tier call. Attributes: `search.mode` (the configured `SearchMode`: `retrieval`, `selection`, `auto`), `search.tier` (the tier that answered: `retrieval` or `selection`), `search.limit`, `search.result_count` (the count of returned matches), `catalog.size` (`index.count`), and `search.rankers` (a string array of the rankers that ran). For `retrievalSearch(intent:limit:)`: `bm25` and `trigram` when their `Weights` value is greater than 0, and `cosine` only when `computeCosineScores(...)` returned non-nil. For `selectionSearch(_:intent:limit:)`: `selection`. When the call throws, record the error on the span and set the span status to error. Also record the error type only, never the error message.
- [ ] Ranker child span `FoundationModelsMetadataRegistry.rank` around the `HybridRanker.topMatches(...)` call in `retrievalSearch(intent:limit:)` and around `selection.tier.search(intent:limit:)` in `selectionSearch(_:intent:limit:)`. Attributes: `rank.ranker` (`hybrid` or `selection`), `rank.candidate_count` (`index.ids.count` for hybrid, the snapshot count for selection).
- [ ] Catalog update span `FoundationModelsMetadataRegistry.catalog.update` in `MetadataSearcher.update(items:)`. Attributes: `catalog.item_count` (`items.count`), `catalog.size` (the count of the new baseline), `catalog.content_changed` (bool), `catalog.pending_embed_count` (`result.pendingEmbedIDs.count`). The hash-guarded no-op path also ends the span, with `catalog.content_changed = false` and `catalog.pending_embed_count = 0`.
- [ ] Catalog embed span `FoundationModelsMetadataRegistry.catalog.embed` in `MetadataSearcher.catchUpEmbeddings(ids:texts:embeddedFrom:with:)` (this covers each pass of `runReloadEmbedLoop(with:)` in `MetadataSearcher+ReloadEmbedLoop.swift` and `runFirstSearchCatchUp()` in `MetadataSearcher+FirstSearchCatchUp.swift`), in the private `SharedCatalogEmbedding.embeddingPendingEntries(of:with:onDiagnostic:)` in `SharedCatalogEmbedding.swift`, and in `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` in `Catalog/MetadataIndex+Embedding.swift`. Attributes: `embed.pending_count`, `catalog.size`, `embed.source` (`reload`, `first_search`, `shared`, `build`), `embed.outcome` (`embedded` or `failed`, from the result of `checkedVectors(for:)`).
- [ ] New test file `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/RegistryTracingTests.swift` (see Tests). Each test runs inside `TelemetryCapture.run(forbidding:)` from the Extras `TelemetryTestSupport` product, with the query text and the item content as forbidden strings, so it also proves rule 4 for the new spans.

## Acceptance Criteria
- [ ] Each `search(intent:limit:)` call ends exactly one `FoundationModelsMetadataRegistry.search` span, with one `FoundationModelsMetadataRegistry.rank` child, and with the attributes above. The values of `search.result_count`, `catalog.size` and `search.rankers` agree with the call.
- [ ] A `.retrieval` search with no embedder has `search.rankers == ["bm25", "trigram"]`. With `FakeEmbedder` and an embedded catalog, it has `["bm25", "trigram", "cosine"]`. A `.selection` search has `["selection"]`.
- [ ] A `.selection` search with no selection tier ends its span with error status, and the span has no error message text.
- [ ] Each `update(items:)` call ends one `catalog.update` span. Each embed pass ends one `catalog.embed` span with the correct `embed.source` and `embed.outcome`.
- [ ] No span attribute holds the query text or item content (`TelemetryCapture` reports no issue).

## Tests
- [ ] In `RegistryTracingTests.swift`: one test for each tier (`.retrieval` with no embedder, `.retrieval` with `TestSupport/FakeEmbedder.swift`, `.selection` with `TestSupport/ScriptedAgentSession.swift`, `.auto`), which checks the span names, parent/child link and attributes.
- [ ] A test for the `SelectionTierUnavailable` throw path (error status, no message text).
- [ ] Tests for `update(items:)` (content changed, no-op), for a failed embed (use a throwing embedder, see `TestSupport/GatedEmbedder.swift` / `FakeEmbedder.swift`), for `SharedCatalogEmbedding` (`embed.source = shared`, one embed span for two sharing searchers), and for `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`.
- [ ] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #search-tools #catalog #embedding