---
assignees:
- claude-code
position_column: done
position_ordinal: c080
title: 'Decision tier: score the whole catalog with the decision model, in batches'
---
## What

The user decided (2026-11-14) that the decision model selects from the whole catalog, not only from the retrieval candidates. Today `MetadataSearcher+DecisionTier.swift` asks P(yes) only for the top `DecisionConfig.candidateCount` (20) retrieval candidates, so the decision model cannot find an entry that retrieval missed. In the first benchmark, retrieval recall@5 on paraphrase intents was 0.20.

Change:
- `Sources/FoundationModelsMetadataRegistry/DecisionConfig.swift`: delete `candidateCount` and `defaultCandidateCount`, with no alias (ARCHITECTURE.md). Add `batchSize: Int` (default `DecisionConfig.defaultBatchSize = 64`, clamped to at least 1): the largest count of questions in one `DecisionSession.decide` call.
- `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+DecisionTier.swift`: take the index snapshot, make one `DecisionSession(model:state: .text(intent))`, and ask one binary question (`config.question(id, block)`) for EVERY catalog item, in batches of `batchSize`, in catalog order, in one session (so the state prefix is reused). Keep `minimumProbability`, the sort by P(yes), and the `limit`. Run the retrieval tier over the same snapshot with `limit = snapshot.count` only to attach `Match.signals` and to order equal scores (retrieval order first, then catalog order for items that retrieval did not rank). An item that retrieval did not rank gets the `Signals` value that the retrieval tier uses for "no signal" (read the code; do not invent one).
- Telemetry: the decision `rank` span's `rank.candidate_count` is now the catalog size; the questions of all batches go in that one span. Update the doc comments.
- `README.md`, `plan.md` section 6a and decision #17: describe the whole-catalog scope, `batchSize`, and that `candidateCount` is gone. Add one dated line to decision #17: the user chose the whole-catalog scope after the first benchmark.
- `Benchmarks/`: if any code uses `candidateCount`, update it.

## Acceptance Criteria
- [ ] A `.decision` search asks one question for each catalog item, also for an item that retrieval does not find.
- [ ] An item with no keyword and no cosine match, but a high P(yes), is a match.
- [ ] With 150 items and `batchSize` 64, the model gets 3 `decide` calls (64, 64, 22) in one session.
- [ ] `candidateCount` does not exist anywhere in the repository.
- [ ] Root `swift test` and `swift test --package-path Benchmarks` pass.

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/DecisionTierTests.swift`: update the tests that used `candidateCount`; add the tests for the three criteria above with `ScriptedDecisionModel`.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/DecisionConfigTests.swift`: `batchSize` default and clamp.
- [ ] Telemetry tests: `rank.candidate_count` equals the catalog size.
- [ ] Run `swift test` and `swift test --package-path Benchmarks`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.