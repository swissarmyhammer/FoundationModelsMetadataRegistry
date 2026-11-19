# Scale benchmark run of 2026-11-19

This folder holds the result of one run of the `ScaleBenchmark` executable:
the cost gate of D207 (TestudoApp, session search) at 100,000 items.
`scale-report.json` holds the values, and `scale-report.md` holds the same
values as a markdown table.

## Command

```sh
swift run -c release --package-path Benchmarks ScaleBenchmark Benchmarks/Results/2026-11-19-scale
```

The run took 54 s of wall time after the release build, and it stopped with
exit code 0 (each limit is met).

## What it measures

- The corpus: 100,000 chunks of 500 to 2,000 characters (Zipf words, with
  identifiers, paths and numbers), 20 chunks for each session id.
- The vectors: 768 dimensions, the dimension of embeddinggemma-300m, from a
  stub embedder that costs almost nothing. The times are thus the times of the
  registry, with no model embed.
- The search: a `.retrieval` search with a limit of the catalog size, for 14
  queries of one to four words.
- The update: `update(upserting:removing:)` with 19 new chunks and one changed
  item, 10 times. The time includes the embed of the 20 texts by the stub and
  the merge. The save runs after it in the background; the run waits for it
  before the next update.
- The start: a new searcher over the stored catalog, in a fresh process.
- The memory: the resident memory of that fresh process after the start, and
  of the build process after the build.

## Limits

| Measurement | Limit |
|---|---:|
| search, limit = catalog size | 300 ms |
| update of 20 items | 100 ms |
| start from the stored catalog | 5 s |
