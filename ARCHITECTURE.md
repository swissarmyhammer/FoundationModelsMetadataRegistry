# Architecture

## No backward compatibility

This package has not shipped, and none of the swissarmyhammer packages has. We do not keep backward compatibility, and we do not write code for it.

- When a file format or an on-disk layout changes, write and read only the new one. Do not keep a reader for the old format, and do not write migration code. Data on disk in the old format may simply stop working.
- When an API changes, change every caller in the same change, or in the packages that depend on it. Do not keep deprecated aliases, shims, or old overloads.
- Do not keep a schema version only so that an old file can still be read.

This rule holds until we ship. When we ship, this section will say what we promise from then on.

## Nested packages

- `Benchmarks/` is a separate SwiftPM package. The root manifest does not name it and CI does not build or run it.
  - The `BenchmarkSupport` library holds the labeled relevance fixture, the ranking metrics, the benchmark report, the runner and the argument parser. It links no model runtime. Use `swift test --package-path Benchmarks` to run its tests.
  - The `RankingBenchmark` executable holds the real configurations. It is the only target that links model runtime products (MLX and llama.cpp). Use `swift run -c release --package-path Benchmarks RankingBenchmark --output <dir>` to run it.
