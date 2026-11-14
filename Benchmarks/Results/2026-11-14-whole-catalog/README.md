# Ranking benchmark run of 2026-11-14: whole-catalog decision tier

This folder holds the result of the second real run of the `RankingBenchmark`
executable. `report.json` holds the full measurement. `report.md` holds the
same values as a markdown table.

This run is different from the first run (`../2026-11-14/`) in two ways:

1. The decision tier scores the whole catalog. The decision model asks one
   yes-or-no question for each of the 62 catalog items, in batches of 64. In
   the first run, it asked only about the first 20 retrieval candidates.
2. The run has a seventh configuration, `decision-h2o-lightning-4b`.

The first run stays unchanged. It is the result of the rerank design.

## Command

```sh
swift run -c release --package-path Benchmarks RankingBenchmark \
  --output Benchmarks/Results/2026-11-14-whole-catalog --repeats 3
```

The command started at 11:21:55 CST and stopped at 11:48:21 CST (26 min 26 s
of wall time). This time includes the release build of the package and the
first download of the H2O-Lightning model. The command stopped with exit
code 0.

## Machine

| Item | Value |
| --- | --- |
| Chip | Apple M5 Max |
| Memory | 137438953472 bytes (128 GiB) |
| OS | macOS 27.2, build 26B123 |

## Code under test

- Commit of this repository: `465c15b`, plus the `decision-h2o-lightning-4b`
  configuration, which the commit that adds this folder also adds.
- The model package revisions are the same as in the first run
  (`../2026-11-14/README.md`). `Package.resolved` did not change between the
  two runs.

## Models

| Model | Configurations that use it |
| --- | --- |
| `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` | each configuration except `retrieval-keyword` |
| `mlx-community/Qwen3-4B-4bit` | `selection-qwen3-4b`, `decision-qwen3-4b` |
| Apple system language model | `selection-apple` |
| `Mapika/decider-4b-GGUF/decider-4b-v3-Q4_K_M.gguf` | `decision-decider-4b` |
| `h2oai/h2o-lightning-4b-gguf/h2o-lightning-4b-Q4_K_M.gguf`, revision `61f8d8b7a8c2d84426d0d143ca187f65d235934b` | `decision-h2o-lightning-4b` (native decision path of llama.cpp) |

## Configurations

All seven configurations ran, and each has a measurement in the report. No
configuration is unavailable. No search threw an error: the `errors` column is
0 in each row.

## How to read the values

- Each kind of intent has 30 searches in each row: the 10 intents of the
  kind, each one 3 times (`--repeats 3`).
- The recall cutoff is 5, the same as the search `limit`.
- p50 and p95 do not include the first search. The first search includes the
  time to load the models and to embed the catalog.
- The retrieval and selection rows measure the same code as in the first run.
  Their small changes in time come from the machine, not from the code.
