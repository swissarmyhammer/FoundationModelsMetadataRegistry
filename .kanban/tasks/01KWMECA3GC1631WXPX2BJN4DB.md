---
depends_on:
- 01KWMEBWC11D5XHXEJB6HW6325
position_column: todo
position_ordinal: '8380'
title: MetadataSearcher actor with keyword-only .retrieval mode
---
## What
Implement the searcher core per plan.md §3/§5/§7, in `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` + `SearchMode.swift`:
- `enum SearchMode: Sendable { case retrieval, selection, auto }`
- `actor MetadataSearcher<Item: SearchableMetadata>` holding a `MetadataIndex`, per-signal `Weights` config (bm25/trigram/cosine, default 1.0 each), and the **`onDiagnostic` callback** (the shared `MetadataDiagnostic` surface from the catalog task) threaded through to the index and later tiers
- `search(intent: String, limit: Int) -> [Match<Item>]` for `.retrieval`: run BM25 (two fields) + trigram Dice rankings → `RRF.fuse(k: 60)` → `normalize` → map ids back through the catalog to `Match`es carrying verbatim blocks + per-signal `Signals`
- No session, no tokens, no embedder yet — cosine slot simply absent (absent-signal rule: contributes nothing)
- `.selection`/`.auto` stubs throw/fall back to retrieval until the selection tasks land

## Acceptance Criteria
- [ ] Fixture query "deploy" ranks the `deploy` item first via id-field weighting even when its block never says "deploy"
- [ ] Returned `Match.score` in [0,1], `signals` populated with raw bm25/trigram values, cosine nil
- [ ] Zero-weight signal is excluded from fusion and from the normalization ceiling
- [ ] Searcher init accepts `onDiagnostic` and forwards index-build diagnostics through it

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift` — golden rankings over a fixture catalog (~20 items), limit handling, empty-query and no-hits behavior, weights configuration, diagnostic forwarding
- [ ] Run `swift test` — all pass, no GPU/Router

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.