---
depends_on:
- 01KWMECA3GC1631WXPX2BJN4DB
position_column: todo
position_ordinal: '8480'
title: 'Embedding signal: TextEmbedding seam, RoutedEmbedderAdapter, cosine in fusion'
---
## What
Add the third signal per plan.md §5 (M2), in `Sources/FoundationModelsMetadataRegistry/Embedding/`:
- Port `TextEmbedding.swift` (~19-line protocol seam) and `RoutedEmbedderAdapter.swift` (~45 lines, wraps Router's `RoutedEmbedder`) from `../CodeContextKit/Sources/CodeContextKit/Embedding/`, with attribution
- `MetadataIndex` stores per-item embeddings keyed by `(id, block-hash)`; embedding happens at index-build/update time, never at query time (only the query itself is embedded per search)
- Cosine ranking joins RRF fusion in `MetadataSearcher.search`; items without embeddings contribute nothing to cosine (absent-signal rule)
- No embedder configured → keyword-only, surfaced as the shared `MetadataDiagnostic.embeddingUnavailable` case through `onDiagnostic` (never silent)
- Brute-force per-row dot products — in-memory, no vector store (decision #10)

## Acceptance Criteria
- [ ] With a `FakeEmbedder`, a paraphrase query ranks the semantically-close item above keyword-only ranking
- [ ] Omitting the embedder degrades to keyword-only and emits `.embeddingUnavailable` via `onDiagnostic`
- [ ] Un-embedded items still rank via BM25 + trigram
- [ ] Embed count is proportional to changed blocks only (hash-keyed), verified by a counting fake

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/EmbeddingTests.swift` — `FakeEmbedder` (deterministic vectors + call counter): cosine fusion, degradation diagnostic capture, absent-signal, hash-keyed incremental embed
- [ ] Run `swift test` — all pass, no GPU (RoutedEmbedderAdapter compiles but is not exercised)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.