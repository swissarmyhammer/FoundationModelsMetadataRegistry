---
depends_on:
- 01M7SZZHFEQV2AGWW3HQMBFQGX
position_column: done
position_ordinal: c580
title: 'Cost gate at 100,000 items: search, update of 20 items, start, memory'
---
D207, brief `mdr-brief.md` item 4.

## Change
- A `ScaleBenchmark` executable in the `Benchmarks/` package (not in the unit suite). It makes 100,000 items of up to 2,000 characters and vectors of 768 dimensions (embeddinggemma-300m) with a fast deterministic embedder.
- It measures: a `.retrieval` search with a limit of the catalog size; an update of 20 items (`update(upserting:removing:)`, no model embed); a start from the stored catalog; the resident memory.
- The limits: a search at most 300 ms, an update of 20 items at most 100 ms, a start at most 5 s. The executable exits with a failure when a limit is not met.
- The report goes to `Benchmarks/Results/<date>-scale/`.

## Acceptance
- The run passes the three limits, and the report is committed. If a limit is not met, send the numbers to the TestudoApp session.