---
assignees:
- claude-code
depends_on:
- 01M7DG8WM8E7M08JZKB4AH74CN
position_column: done
position_ordinal: c180
title: Add h2o-lightning-4b to the benchmark and run it again on the whole-catalog decision tier
---
## What

The user asked (2026-11-14) to try `h2o-lightning-4b` as a decision model. The decision tier also changes to score the whole catalog (task 01M7DG8WM8E7M08JZKB4AH74CN), so the first report (`Benchmarks/Results/2026-11-14/`) no longer measures the current code.

Already done in the main checkout (not committed):
- `Benchmarks/Sources/BenchmarkSupport/BenchmarkConfiguration.swift`: new name `decision-h2o-lightning-4b`.
- `Benchmarks/Sources/RankingBenchmark/Configurations.swift`: `PooledNativeDecisionModel(ref: h2oLightningRef, pool: ggufPool)`, with the revision `61f8d8b7a8c2d84426d0d143ca187f65d235934b` that the FoundationModelsDecision model matrix tests.
- `Benchmarks/Tests/BenchmarkSupportTests/ArgumentParsingTests.swift`: the names test expects seven names.

To do:
1. After the whole-catalog task is merged, run `swift run -c release --package-path Benchmarks RankingBenchmark --output Benchmarks/Results/2026-11-14-whole-catalog --repeats 3` in the main checkout. The new folder name sorts after `2026-11-14`, so `CommittedReportTests` reads the new report. Keep the first report: it is the result of the rerank design.
2. Write the run `README.md` as for the first run, and say that the decision tier now scores the whole catalog.
3. `plan.md` decision #17: add a second table and a link. Do not write which tier wins.

## Acceptance Criteria
- [ ] `Benchmarks/Results/2026-11-14-whole-catalog/report.json` has 7 rows, each with metrics or a real unavailable reason.
- [ ] The first report stays unchanged.
- [ ] `swift test --package-path Benchmarks` and root `swift test` pass.

## Tests
- [ ] `CommittedReportTests` passes on the new report (7 names).
- [ ] `ArgumentParsingTests` expects the seven names.
- [ ] Run `swift test --package-path Benchmarks`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.