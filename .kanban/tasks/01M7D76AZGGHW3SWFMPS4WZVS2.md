---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: 'Create the Benchmarks package: labeled relevance fixture and ranking metrics'
---
## What

The comparison needs intents with known correct answers. The existing integration fixture (`IntegrationTests/.../Support/IntegrationCatalog.swift`) has six entries and no labels, so it cannot measure ranking quality.

Make a new nested SwiftPM package `Benchmarks/`. The root manifest does not name it, the same as `Examples/` and `IntegrationTests/`. Thus a bare `swift test` at the root does not run it, and CI does not download its models. This adds a new top-level component: add one line about it to `ARCHITECTURE.md`.

This task makes the library and its unit tests only. It loads no model and uses only the public API of the registry (`MetadataSearcher`, `Match`), thus it does not wait for the decision tier tasks.

Files:
- `Benchmarks/Package.swift`: platform macOS 27, dependency `.package(path: "..")`. Target `BenchmarkSupport` (library), test target `BenchmarkSupportTests`.
- `Benchmarks/Sources/BenchmarkSupport/BenchmarkCatalog.swift`: about 60 items (`SearchableMetadata`) in about 8 domains (git, file system, cooking, gardening, music, finance, travel, health). Some items in different domains share words, so that keyword match alone gives wrong answers.
- `Benchmarks/Sources/BenchmarkSupport/BenchmarkIntents.swift`: about 40 labeled intents: `struct LabeledIntent { let text: String; let relevantIDs: Set<String>; let kind: Kind }` with `Kind` = `.lexical` (shares words with the answer), `.paraphrase` (no shared content words), `.multiStep` (more than one relevant id), `.offTopic` (no relevant id, `relevantIDs` empty). At least 8 intents of each kind.
- `Benchmarks/Sources/BenchmarkSupport/RankingMetrics.swift`: pure functions over `[String]` (ranked ids) and `Set<String>` (relevant ids): `hitAt1`, `recall(at:)`, `reciprocalRank`, `isEmpty` for off-topic, `falsePositiveCount` for off-topic. Aggregates: mean of each metric for each `Kind`, latency p50 and p95 from `[Duration]`.
- `Benchmarks/Sources/BenchmarkSupport/BenchmarkReport.swift`: `struct BenchmarkReport: Codable` (one row for each configuration: name, metrics for each kind, p50, p95, first-search duration) with `markdownTable() -> String` and JSON encoding.

## Acceptance Criteria
- [ ] `swift build --package-path Benchmarks` passes.
- [ ] Each `relevantIDs` value names an id that `BenchmarkCatalog` holds, and the catalog has no duplicate ids.
- [ ] Each `Kind` has at least 8 intents.
- [ ] The metric functions give the correct values for hand-computed cases.
- [ ] `ARCHITECTURE.md` names the `Benchmarks/` package and says that the root manifest and CI do not use it.

## Tests
- [ ] `Benchmarks/Tests/BenchmarkSupportTests/BenchmarkFixtureTests.swift`: unique ids, every label resolves, the count of each kind, off-topic intents have no labels.
- [ ] `Benchmarks/Tests/BenchmarkSupportTests/RankingMetricsTests.swift`: hit@1, recall@k, reciprocal rank, p50 and p95 on hand-computed inputs, empty inputs, and k larger than the list.
- [ ] `Benchmarks/Tests/BenchmarkSupportTests/BenchmarkReportTests.swift`: JSON round trip, and the markdown table has one row for each configuration.
- [ ] Run `swift test --package-path Benchmarks`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.