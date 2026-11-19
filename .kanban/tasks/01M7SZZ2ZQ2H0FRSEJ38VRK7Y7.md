---
assignees:
- claude-code
position_column: done
position_ordinal: c280
title: 'Scale: compact catalog storage and an exact columnar retrieval scorer'
---
D207 (TestudoApp `features/decisions.md`), brief `swissarmyhammer/.briefs/search/mdr-brief.md` item 3.

## Why
At 100,000 items of up to 2,000 characters, each `RankedDocument` keeps three `Set<String>` and one `[String: Double]`. The memory is some GB, and `HybridRanker.topMatches` builds a `BM25Corpus` over each document at each search. `update(items:)` tokenizes each item again.

## Change
- `MetadataIndex` keeps each entry in a slot: the item, the block, the digests, and compact features (sorted term ids with weighted term frequency, sorted trigram ids for the id field and the body field, the document length). Two interned vocabularies (terms, trigrams). Document frequencies and the total length are kept as counters.
- The vectors go into a contiguous row-major matrix in blocks of rows, with the squared magnitude of each row. A vector of a different dimension goes into a side table.
- A `RetrievalScorer` computes the same three signals, the same RRF fusion and normalization, and the same order (ties by catalog position) as `HybridRanker.topMatches`. It scans the slots in parallel. The cosine of each row uses the same sequential float arithmetic as `CosineScoring.cosineSimilarity`.
- `EmbeddedBatch` keeps the embedded-text digest of each id, not the source index, so that an embed does not keep a copy of the index.
- The search embeds the query first, then ranks the live index with no suspension.
- The catch-up embeds pending entries in chunks; each chunk merges into the live index.

## Acceptance
- An equivalence test: over random catalogs and queries, the scorer gives the same ids, scores and signals as `HybridRanker.topMatches` (tolerance 1e-9 for the BM25 sum order).
- All current unit tests stay green; `rankedDocument(forID:)` stays public.