---
assignees:
- claude-code
depends_on:
- 01M7D77383S3CZC298PG6T01GM
- 01M7D75XHXQ65ZJ3WTZS1BAJVG
position_column: done
position_ordinal: bf80
title: Run the ranking benchmark on real models and commit the report
---
## What

Run the comparison and keep the data, so that the user can select the tier to keep. This task does NOT select the winner and does NOT delete a tier. The user makes that decision from the report.

1. Run `swift run -c release --package-path Benchmarks RankingBenchmark --output Benchmarks/Results/<YYYY-MM-DD> --repeats 3` on this machine (Apple silicon, macOS 27). The first run downloads the models into the Hugging Face cache.
2. Commit `Benchmarks/Results/<YYYY-MM-DD>/report.json` and `report.md`.
3. Add a `Benchmarks/Results/<YYYY-MM-DD>/README.md` with the machine (chip, memory), the OS build, the commit SHA of the code under test, the configurations that ran, and each configuration that did not run with the reason (for example, Apple Intelligence not available).
4. In `plan.md`, under the decision of the decision tier, add one paragraph with the table of the main values (hit@1 and MRR for each intent kind, the off-topic empty rate, p50, p95) and a link to the report. Do not write a conclusion about which tier wins.

## Acceptance Criteria
- [ ] `Benchmarks/Results/<YYYY-MM-DD>/report.json` has one row for each of the six configurations. Each row has metrics or a reason why it did not run.
- [ ] `report.md` and the run `README.md` are committed beside it.
- [ ] `plan.md` holds the table of values and the link.

## Tests
- [ ] New `Benchmarks/Tests/BenchmarkSupportTests/CommittedReportTests.swift`: decode the newest `Benchmarks/Results/*/report.json` with `BenchmarkReport`, and check that it has a row for each configuration name in `RankingBenchmark/Configurations.swift` (move the list of names into `BenchmarkSupport` so that the test can read it), and that each row has metrics or a skip reason.
- [ ] Run `swift test --package-path Benchmarks`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.