---
assignees:
- claude-code
depends_on:
- 01M7D7571BRCEWVV1DHZQKG6ZE
position_column: todo
position_ordinal: '8180'
title: 'Implement the decision tier: rerank retrieval candidates by P(yes) from a DecisionModel'
---
## What

Add the search path of `SearchMode.decision`. The tier is a two-stage reranker:

1. The retrieval tier gives the top `DecisionConfig.candidateCount` candidates (BM25 + trigram + cosine, as today).
2. One `DecisionSession(model: config.model, state: .text(intent))` asks one batch of binary questions, one question for each candidate, made with `config.question(id, block)`. The state is the intent, so a local model reads the intent prefix one time and reuses it for each question.
3. Each candidate gets `score = P(yes)`. The tier drops each candidate below `config.minimumProbability`, sorts by score (descending; on equal scores, the retrieval order), and returns at most `limit` matches. Thus an off-topic intent can give an empty result, as the selection tier can.

Files:
- New `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+DecisionTier.swift`: `func decisionSearch(_ config: DecisionConfig, intent: String, limit: Int) async throws -> TierAnswer`. Take the `index` snapshot before the first `await`, and attach `Match.item` from that snapshot, the same as `selectionSearch` does. Keep the retrieval `Signals` of each candidate in `Match.signals`.
- `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift`: add `TierRoute.decision(DecisionConfig)`. `.decision` with no config throws a new public `DecisionTierUnavailable` error (in `DecisionConfig.swift`). `.auto` order: decision, then selection, then retrieval. For this task only, `TierRoute.tier` and `TierAnswer.tier` use the existing telemetry values (`.retrieval` tier, no new signal); the next task adds the decision telemetry values. `limit <= 0` gives `[]` and asks the model nothing. An error from the model goes to the caller, the same as a selection error.
- `update(items:)` needs no rebuild: the tier reads the live `index` at each search.
- New `Tests/FoundationModelsMetadataRegistryTests/TestSupport/ScriptedDecisionModel.swift`: a `DecisionModel` stub whose executor returns a P(yes) for each question from a closure `(Question) -> Double`, records each batch it gets, and can throw.

## Acceptance Criteria
- [ ] A `.decision` search over a catalog returns matches ordered by the P(yes) that the model gave, not by the retrieval order.
- [ ] The model gets one batch with at most `candidateCount` questions for each search, and the state of the session is `.text(intent)`.
- [ ] Candidates below `minimumProbability` are not in the result. When the model gives every candidate a low P(yes), the result is empty.
- [ ] `.decision` with no `DecisionConfig` throws `DecisionTierUnavailable`.
- [ ] `.auto` uses the decision tier when it is configured, also when a selection tier is configured.
- [ ] An error that the model throws goes to the caller of `search(intent:limit:)`.

## Tests
- [ ] New `Tests/FoundationModelsMetadataRegistryTests/DecisionTierTests.swift` with `ScriptedDecisionModel`, one test for each acceptance criterion, and a test that a concurrent `update(items:)` during the model call does not mix the items of two catalogs.
- [ ] Run `swift test` at the root. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.