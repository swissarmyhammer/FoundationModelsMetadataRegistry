---
assignees:
- claude-code
depends_on:
- 01M7D75XHXQ65ZJ3WTZS1BAJVG
position_column: todo
position_ordinal: '8580'
title: Document the decision tier in README.md and plan.md
---
## What

- `plan.md`: add a new numbered decision (the next number after the last one) with the date: the registry gets a decision tier that reranks retrieval candidates by P(yes) from a FoundationModelsDecision `DecisionModel`. The tier stays beside the selection tier until the benchmark compares them, then the tier that loses is deleted (ARCHITECTURE.md, no backward compatibility). Add a section for the decision tier after §6: the two stages, `DecisionConfig` (candidate count, minimum probability, question), the `.auto` order (decision, selection, retrieval), the telemetry values, and why the library links only the core `FoundationModelsDecision` product.
- `plan.md:32-41` (the "Update 2026-08-30 — decision #15" note): the note says that the integration package uses "no MLX, no tiny `mlx-community` model". `PooledEmbedderRealModelTests` now loads an MLX embedding model. Add one sentence that says this, so the history note does not mislead.
- `README.md`: add a short paragraph and code sample after the `SelectionConfig` sentence, with `DecisionConfig(model: PooledDecisionModel(ref: "mlx-community/Qwen3-4B-4bit"))` and `mode: .decision`. Say that the caller adds the `FoundationModelsDecisionPooled` product for `PooledDecisionModel`. Name the `Benchmarks/` package and its run command.
- Write all new text in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] `plan.md` has the new decision and the decision tier section.
- [ ] `README.md` shows the decision tier sample and the benchmark command.
- [ ] The decision #15 note no longer says that no test loads an MLX model.

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift`: add a test that `plan.md` names `DecisionConfig` and `SearchMode.decision`.
- [ ] `Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift`: add a test that `README.md` names `DecisionConfig`, `.decision` and `swift run --package-path Benchmarks RankingBenchmark`. Make the existing README tests pass with the new text.
- [ ] Run `swift test` at the root. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.