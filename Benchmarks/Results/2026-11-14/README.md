# Ranking benchmark run of 2026-11-14

This folder holds the result of one real run of the `RankingBenchmark`
executable. `report.json` holds the full measurement. `report.md` holds the
same values as a markdown table.

## Command

```sh
swift run -c release --package-path Benchmarks RankingBenchmark \
  --output Benchmarks/Results/2026-11-14 --repeats 3
```

The command started at 10:23:55 CST and stopped at 10:34:39 CST (644.5 s of
wall time). This time includes the release build of the package (143.2 s).
The command stopped with exit code 0.

## Machine

| Item | Value |
| --- | --- |
| Chip | Apple M5 Max |
| Memory | 137438953472 bytes (128 GiB) |
| OS | macOS 27.2, build 26B123 |

## Code under test

- Commit of this repository: `65dc2a03c3f6cb771a667221cc18cbc2ed028bde`.
- `Benchmarks/Package.resolved` gives these revisions of the model packages:

| Package | Revision |
| --- | --- |
| FoundationModelsDecision | `20c0f80` |
| FoundationModelsExtras | `5914a80` |
| FoundationModelsLlamaCpp | `be74448` |
| FoundationModelsRanker | `ddb39a1` |
| mlx-swift | `7ede4fd` (0.33.0) |
| mlx-swift-lm | `6dc1e4e` |
| llama-cpp-swift | `6b273d6` |

## Models

| Model | Configurations that use it |
| --- | --- |
| `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` | each configuration except `retrieval-keyword` |
| `mlx-community/Qwen3-4B-4bit` | `selection-qwen3-4b`, `decision-qwen3-4b` |
| Apple system language model | `selection-apple` |
| `Mapika/decider-4b-GGUF/decider-4b-v3-Q4_K_M.gguf` | `decision-decider-4b` |

## Configurations

All six configurations ran, and each has a measurement in the report:

- `retrieval-keyword`
- `retrieval-semantic`
- `selection-qwen3-4b`
- `selection-apple`
- `decision-qwen3-4b`
- `decision-decider-4b`

No configuration is unavailable. The Apple system language model was
available on this machine. The GGUF model loaded with llama.cpp. No search
threw an error: the `errors` column is 0 in each row.

## How to read the values

- Each kind of intent has 30 searches in each row: the 10 intents of the
  kind, each one 3 times (`--repeats 3`).
- The recall cutoff is 5, the same as the search `limit`.
- p50 and p95 do not include the first search. The first search includes the
  time to load the models and to embed the catalog.
