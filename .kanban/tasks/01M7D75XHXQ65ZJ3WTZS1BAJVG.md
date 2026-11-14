---
assignees:
- claude-code
depends_on:
- 01M7D75MMFBRTFTF72Y6RAE39K
position_column: done
position_ordinal: bb80
title: 'Add telemetry for the decision tier: tier, signal, ranker, rank span and rank duration'
---
## What

The benchmark compares the tiers by time, so the decision tier must record the same telemetry as the selection tier.

- `Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift`: add `Tier.decision`, `Signal.decision` and `Ranker.decision` (raw value `"decision"` for each), with doc comments.
- `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+DecisionTier.swift`: run the model call in one `RegistryTelemetry.SpanName.rank` span through `RegistryTelemetry.withTracedSpan(_:attributes:_:)` (rule 8, the model can wait for a long time). Attributes: `rankRanker = "decision"` and `rankCandidateCount` = the count of questions in the batch. Record one `rankDuration` value with `rankTimer(for: .decision)`, also when the model throws. The retrieval step inside the tier keeps its own `hybrid` rank span.
- `MetadataSearcher+Search.swift`: `TierRoute.tier` and the `TierAnswer` of the decision tier use `.decision`. `searchRankers` of a decision search is the retrieval signals that ranked the candidates, then `decision`.
- No span, log record or metric holds the intent, a block, or a question text (rule 4).

## Acceptance Criteria
- [ ] A `.decision` search records `search.tier = "decision"` and a `rank` span with `rank.ranker = "decision"`.
- [ ] `rankDuration` has a value with the `decision` ranker after a decision search that returns and after one that throws.
- [ ] `searchDuration` of a failed decision search has the `decision` tier.
- [ ] The content-safety test passes for the decision path.

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/RegistryTracingTests.swift`: tests for the span attributes of a decision search, with `ScriptedDecisionModel`.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/RegistryMetricsTests.swift`: tests for `rankDuration` and `searchDuration` with the `decision` values, for success and for a thrown error.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift`: add a decision search (success and failure) inside a `TelemetryCapture`.
- [ ] Run `swift test` at the root. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.